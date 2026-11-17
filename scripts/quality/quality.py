#!/usr/bin/env python3
"""Prepare tooling and explicitly run synthetic-only checks after user approval."""
import argparse
from datetime import datetime, timezone
import importlib.metadata
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "infrastructure/erpnext/quality"
LOCATION = ROOT / ".local/quality/location.json"
STORAGE = json.loads(LOCATION.read_text()) if LOCATION.is_file() else {}
TOOL_HOME = Path(os.environ.get("ERP_QUALITY_HOME", STORAGE.get("tool_home", ROOT / ".local/quality"))).expanduser().resolve()
TARGET = "http://127.0.0.1:8081"
GROUPS = ("unit", "flutter", "metadata", "backend", "security", "dependencies", "sbom", "infrastructure", "web", "api", "load", "discovery", "zap", "mobile", "licenses", "supply-chain", "release")
MANIFEST = json.loads((CONFIG / "tools.json").read_text())


def venv(name, command):
    return str(TOOL_HOME / "venvs" / name / "bin" / command)


def node_bin(name):
    return str(TOOL_HOME / "node/node_modules/.bin" / name)


def environment():
    env = os.environ.copy()
    # Keep the local suite independent of saved ERP origins, proxies and scanner cloud accounts.
    for key in list(env):
        if (key.upper().endswith("_PROXY") or key.startswith(("ERP_", "FRAPPE_"))
                or key in {"SEMGREP_APP_TOKEN", "BC_API_KEY"}):
            env.pop(key, None)
    env.update({
        "ERP_QUALITY_HOME": str(TOOL_HOME), "NATIVE_TEST_SITE": "native-test.localhost",
        "DOCKER_CONTEXT": "colima-erp", "NO_PROXY": "*", "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONPATH": str(ROOT / "apps/erp_extensions"),
        "PATH": os.pathsep.join((str(TOOL_HOME / "bin"), str(TOOL_HOME / "pub-cache/bin"), env.get("PATH", ""))),
        "TMPDIR": str(TOOL_HOME / "tmp"), "UV_CACHE_DIR": str(TOOL_HOME / "cache/uv"),
        "UV_CONCURRENT_DOWNLOADS": "2", "UV_CONCURRENT_INSTALLS": "1", "UV_CONCURRENT_BUILDS": "1",
        "npm_config_maxsockets": "2", "UV_THREADPOOL_SIZE": "4",
        "XDG_CACHE_HOME": str(TOOL_HOME / "cache"), "XDG_CONFIG_HOME": str(TOOL_HOME / "config"),
        "XDG_DATA_HOME": str(TOOL_HOME / "data"), "TRIVY_CACHE_DIR": str(TOOL_HOME / "cache/trivy"),
        "GRYPE_DB_CACHE_DIR": str(TOOL_HOME / "cache/grype/db"), "npm_config_cache": str(TOOL_HOME / "cache/npm"),
        "TOX_WORK_DIR": str(TOOL_HOME / "tox"), "HYPOTHESIS_STORAGE_DIRECTORY": str(TOOL_HOME / "hypothesis"),
        "ANALYZER_STATE_LOCATION_OVERRIDE": str(TOOL_HOME / "cache/analyzer"),
        "SEMGREP_SEND_METRICS": "off", "SEMGREP_ENABLE_VERSION_CHECK": "0",
        "SEMGREP_SETTINGS_FILE": str(TOOL_HOME / "config/semgrep/settings.yml"),
        "SEMGREP_LOG_FILE": str(TOOL_HOME / "logs/semgrep.log"),
        "SEMGREP_VERSION_CACHE_PATH": str(TOOL_HOME / "cache/semgrep/version"),
        "CHECKOV_SEND_CRASH_REPORTS": "False", "PLAYWRIGHT_BROWSERS_PATH": str(TOOL_HOME / "browsers"),
        "CHECKOV_WORKERS_NUMBER": "1",
        "SYFT_PARALLELISM": "1",
        "PUB_CACHE": str(TOOL_HOME / "pub-cache"), "HOMEBREW_NO_AUTO_UPDATE": "1",
        "PATROL_ANALYTICS_ENABLED": "false",
        "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_ANALYTICS": "1",
    })
    # Testcontainers must never use another project's default Docker context.
    env["DOCKER_HOST"] = f"unix://{Path.home()}/.colima/erp/docker.sock"
    return env


def commands(group, report):
    source = report / "source"
    groups = {
        "unit": [([venv("core", "python"), "-m", "unittest", "discover", "-s", "scripts", "-p", "test_*.py", "-v"], ROOT),
                 ([venv("core", "python"), "-m", "unittest", "discover", "-s", "scripts/migration", "-p", "test_*.py", "-v"], ROOT),
                 ([venv("core", "python"), "-m", "unittest", "discover", "-s", "scripts/quality", "-p", "test_*.py", "-v"], ROOT),
                 ([venv("core", "python"), "-m", "unittest", "discover", "-s", "infrastructure/erpnext/security", "-p", "test_*.py", "-v"], ROOT),
                 ([venv("core", "python"), str(ROOT / "apps/erp_client/android/test_security_config.py"), "-v"], ROOT)],
        "flutter": [([sys.executable, str(ROOT / "scripts/flutter_toolchain.py"), "--suppress-analytics", "pub", "get", "--enforce-lockfile"], ROOT / "apps/erp_client"),
                    ([sys.executable, str(ROOT / "scripts/flutter_toolchain.py"), "--suppress-analytics", "analyze", "--no-pub"], ROOT / "apps/erp_client"),
                    ([sys.executable, str(ROOT / "scripts/flutter_toolchain.py"), "--suppress-analytics", "test", "--no-pub", "--concurrency=1", "--coverage",
                      "--coverage-path", str(report / "lcov.info"), "test/"], ROOT / "apps/erp_client")],
        "metadata": [(["node", "--test", "extract.test.mjs", "conditions.test.mjs"], ROOT / "tools/native_metadata")],
        "backend": [([sys.executable, str(ROOT / "scripts/quality/native_target.py"), "--site", "native-test.localhost"], ROOT)],
        "security": [(["gitleaks", "dir", str(source), "--redact", "--report-format", "json", "--report-path", str(report / "gitleaks.json")], ROOT),
                     ([venv("semgrep", "semgrep"), "scan", "--jobs", "1", "--config", str(CONFIG / "semgrep.yml"), "--metrics=off", "--disable-version-check", "--error", "--json", "--output", str(report / "semgrep.json"), str(source)], ROOT)],
        "dependencies": [([sys.executable, str(ROOT / "scripts/quality/dependency_scan.py"), "--report", str(report)], ROOT)],
        "sbom": [(["syft", f"dir:{source}", "-o", f"cyclonedx-json={report / 'sbom.cdx.json'}"], ROOT),
                     (["grype", f"sbom:{report / 'sbom.cdx.json'}", "--fail-on", "high", "-o", "json", "--file", str(report / "grype.json")], ROOT)],
        "infrastructure": [([venv("checkov", "checkov"), "--directory", str(source / "infrastructure"), "--compact", "--output", "json"], ROOT),
                           (["trivy", "config", "--exit-code", "1", "--severity", "HIGH,CRITICAL", str(source / "infrastructure")], ROOT)],
        "web": [([node_bin("playwright"), "test", "--config", str(TOOL_HOME / "node/playwright.config.cjs")], TOOL_HOME / "node")],
        "api": [([node_bin("bru"), "run", "--env", "native-test", "--reporter-json", str(report / "bruno.json")], CONFIG / "bruno"),
                ([venv("core", "pytest"), str(CONFIG / "api/test_schema.py"), "-q", "-o", f"cache_dir={TOOL_HOME / 'cache/pytest'}", f"--junitxml={report / 'schemathesis.xml'}"], ROOT)],
        "load": [(["k6", "run", "--summary-export", str(report / "k6.json"), str(CONFIG / "k6.js")], ROOT)],
        "discovery": [(["ffuf", "-u", TARGET + "/FUZZ", "-w", str(CONFIG / "endpoints.txt"), "-rate", "2", "-t", "1", "-maxtime", "30", "-noninteractive", "-of", "json", "-o", str(report / "ffuf.json")], ROOT)],
        "licenses": [([str(TOOL_HOME / "bin/scancode"), "--license", "--copyright", "--package",
                       "--processes", "1", "--timeout", "120", "--no-check-version",
                       "--json-pp", str(report / "scancode.json"), str(source)], ROOT)],
        "zap": [(["docker", "--context", "colima-erp", "run", "--rm", "--pull=never", "--memory=1g", "--cpus=1", "--network", "erp-baseline_frappe_network", "-v", f"{CONFIG / 'zap.yaml'}:/zap/wrk/plan.yaml:ro", "-v", f"{report}:/zap/wrk/reports", MANIFEST["containers"]["zap"], "zap.sh", "-cmd", "-autorun", "/zap/wrk/plan.yaml"], ROOT)],
    }
    if group == "zap" and (TOOL_HOME / "bin/zap").is_file():
        return [([str(TOOL_HOME / "bin/zap"), "-autorun", str(report / "zap-plan.yaml")], ROOT)]
    return groups.get(group, [])


def source_snapshot(report):
    """Restrict scanners to product source/config; never include local customer data."""
    # A fresh per-run directory avoids deleting a user's existing external-drive folder.
    target = report / "source"
    target.mkdir(parents=True, exist_ok=False)
    entries = ["apps/erp_client/lib", "apps/erp_client/test", "apps/erp_client/assets",
               "apps/erp_client/android", "apps/erp_client/ios", "apps/erp_client/macos", "apps/erp_client/windows",
               "apps/erp_client/pubspec.yaml", "apps/erp_client/pubspec.lock", "apps/erp_client/LICENSE",
               "apps/erp_extensions", "infrastructure/erpnext", "scripts", "tools/native_metadata",
               "licenses", "NOTICE.md", "LICENSE", "upstream.lock.json"]
    excluded = {".git", ".local", ".env", "__pycache__", "node_modules", "build", ".dart_tool", ".venv",
                "Pods", ".gradle", "ephemeral", "key.properties", "local.properties"}

    def ignore(directory, names):
        return [n for n in names if n in excluded or (Path(directory) / n).is_symlink() or n.endswith((".log", ".pyc", ".jks", ".keystore"))]

    for entry in entries:
        original, copy = ROOT / entry, target / entry
        if original.is_symlink() or not original.exists():
            continue
        copy.parent.mkdir(parents=True, exist_ok=True)
        if original.is_dir():
            shutil.copytree(original, copy, ignore=ignore)
        else:
            shutil.copy2(original, copy)


def require_space(gib):
    volume = STORAGE.get("mountpoint")
    if not volume or not STORAGE.get("volume_uuid") or not STORAGE.get("disk_image"):
        raise RuntimeError("External storage selection is missing; restore .local/quality/location.json before installing or running checks.")
    mount = Path(volume).resolve()
    if TOOL_HOME == mount or not TOOL_HOME.is_relative_to(mount):
        raise RuntimeError("Tool home must stay inside the selected external volume.")
    if not os.path.ismount(volume):
        raise RuntimeError("External tool storage is not mounted. Run scripts/quality-storage.command mount.")
    details = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", volume], timeout=120))
    if details.get("VolumeUUID") != STORAGE["volume_uuid"]:
        raise RuntimeError("A different volume is mounted at the tool-storage path; refusing to write.")
    existing = TOOL_HOME
    while not existing.exists():
        existing = existing.parent
    free = shutil.disk_usage(existing).free / 1024 ** 3
    if free < gib:
        raise RuntimeError(f"Only {free:.2f} GiB free; this step requires at least {gib} GiB. No files were deleted.")
    backing = Path(STORAGE["disk_image"]).parent
    backing_free = shutil.disk_usage(backing).free / 1024 ** 3
    if backing_free < gib:
        raise RuntimeError(f"The external drive has only {backing_free:.2f} GiB free for image growth; at least {gib} GiB is required.")


def run_command(argv, cwd=ROOT, log=None, extra_env=None):
    print(shlex.join(map(str, argv)), flush=True)
    env = environment()
    env.update(extra_env or {})
    if log:
        with log.open("w") as output:
            return subprocess.run(argv, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, check=False).returncode
    return subprocess.run(argv, cwd=cwd, env=env, check=False).returncode


def prepare_directories():
    # Some tools honor XDG paths only when those directories already exist.
    for name in ("tmp", "cache", "cache/semgrep", "cache/analyzer", "config", "config/semgrep", "data", "logs"):
        (TOOL_HOME / name).mkdir(mode=0o700, parents=True, exist_ok=True)


def install(group):
    # Installation never launches application suites or services; tool self-checks stay local.
    steps = []
    if group in MANIFEST["python"]:
        spec = MANIFEST["python"][group]
        require_space(spec["minimum_free_gib"])
        folder = TOOL_HOME / "venvs" / group
        if not (folder / "pyvenv.cfg").exists():
            steps.append(["uv", "--no-cache", "venv", "--python", sys.executable, str(folder)])
        locked = CONFIG / f"requirements-{group}.lock.txt"
        if group == "checkov":
            if not locked.is_file():
                raise RuntimeError("Checkov requires its reviewed security dependency lock.")
            steps.append([sys.executable, str(ROOT / "scripts/quality/patch_checkov.py"), "--tool-home", str(TOOL_HOME)])
        if locked.is_file():
            requirements = [str(locked)] if group == "checkov" else ["-r", str(locked)]
        else:
            requirements = ["-r", str(CONFIG / spec["requirements"])] if "requirements" in spec else spec["packages"]
        action = "sync" if group == "checkov" else "install"
        local_wheels = ["--find-links", str(TOOL_HOME / "wheels")] if group == "checkov" else []
        steps.append(["uv", "--no-cache", "pip", action, "--only-binary", ":all:", "--python", str(folder / "bin/python")] + local_wheels + requirements)
        if group == "checkov":
            steps.append([str(folder / "bin/python"), str(ROOT / "scripts/quality/check_checkov_patch.py"), "-v"])
    elif group == "node":
        require_space(3)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_node.py")])
    elif group == "browsers":
        require_space(3)
        steps.append([node_bin("playwright"), "install", "chromium", "--only-shell"])
    elif group == "native":
        require_space(5)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_native.py"), "--tool-home", str(TOOL_HOME)])
    elif group == "containers":
        require_space(15)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_containers.py"), "--tool-home", str(TOOL_HOME), "--tool", "mobsf", "--transport", "registry"])
    elif group == "mobsf":
        require_space(6)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_mobsf.py"), "--tool-home", str(TOOL_HOME)])
    elif group == "zap":
        require_space(6)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_zap.py"), "--tool-home", str(TOOL_HOME)])
    elif group == "databases":
        require_space(6)
        steps.append([sys.executable, str(ROOT / "scripts/quality/prepare_databases.py")])
    elif group == "mobile":
        require_space(3)
        dart = [sys.executable, str(ROOT / "scripts/flutter_toolchain.py"), "--dart"]
        steps.append(dart + ["pub", "global", "activate", "patrol_cli", MANIFEST["patrol_cli"]])
        steps.append(dart + ["pub", "cache", "add", "patrol", "--version", MANIFEST["patrol_package"]])
    elif group == "licenses":
        require_space(5)
        steps.append([sys.executable, str(ROOT / "scripts/quality/install_license_tools.py"), "--tool-home", str(TOOL_HOME)])
    prepare_directories()
    for command in steps:
        result = run_command(command)
        if result:
            return result
    if group == "node":
        for name in ("playwright.config.cjs", "web.spec.cjs"):
            shutil.copy2(CONFIG / name, TOOL_HOME / "node" / name)
    return 0


def inventory():
    mount = STORAGE.get("mountpoint")
    mounted = bool(mount and os.path.ismount(mount))
    installed = {}
    for name in MANIFEST["python"]:
        site = TOOL_HOME / "venvs" / name / "lib"
        distributions = {}
        for folder in site.glob("python*/site-packages"):
            for item in importlib.metadata.distributions(path=[str(folder)]):
                distributions[item.metadata["Name"]] = item.version
        installed[name] = distributions
    node = {}
    for package in ("@playwright/test", "@usebruno/cli"):
        file = TOOL_HOME / "node/node_modules" / package / "package.json"
        node[package] = json.loads(file.read_text())["version"] if file.is_file() else None
    receipts = {}
    for relative in ("logs/native-installation.json", "receipts/python-security.json", "receipts/zap-native.json", "receipts/mobsf-native.json",
                     "receipts/license-tools/install.json", "receipts/root-installation.json"):
        file = TOOL_HOME / relative
        receipts[relative] = json.loads(file.read_text()) if file.is_file() else None
    database_receipts = sorted((TOOL_HOME / "receipts").glob("databases-*.json"))
    if database_receipts:
        file = database_receipts[-1]
        receipts[str(file.relative_to(TOOL_HOME))] = json.loads(file.read_text())
    return {"checked_at": datetime.now(timezone.utc).isoformat(), "mode": "installation-inventory-only",
            "tests_executed_by_status": False,
            "recorded_run_reports": len(list((TOOL_HOME / "reports").glob("*/results.json"))), "tool_home": str(TOOL_HOME),
            "storage_mounted": mounted, "storage_image": STORAGE.get("disk_image"),
            "free_gib": round(shutil.disk_usage(mount).free / 1024 ** 3, 2) if mounted else None,
            "python_packages": installed, "node_packages": node,
            "installation_receipts": receipts,
            "project_flutter_toolchain": {"selector": str(ROOT / "scripts/flutter_toolchain.py"),
                "pin": json.loads((CONFIG / "flutter-toolchain.json").read_text()),
                "selection": json.loads((ROOT / ".local/quality/flutter-sdk.json").read_text())
                    if (ROOT / ".local/quality/flutter-sdk.json").is_file() else None,
                "validation": "The selector verifies the drive and SDK before executing; global SDK paths below are unchanged."},
            "executables": {name: shutil.which(name, path=environment()["PATH"]) for name in ["flutter", "dart", "uv", "node", "docker", "colima"] + MANIFEST["brew"]},
            "containers": "No tool images loaded into Docker; native ZAP/MobSF status is recorded in receipts. Existing ERP Docker data is unchanged.",
            "manual_requirements": MANIFEST["manual"]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("status", help="Read-only installation metadata; no tests or service probes")
    sub.add_parser("plan", help="Show staged groups; runs nothing")
    prepare = sub.add_parser("install", help="Install tools only; never run tests")
    prepare.add_argument("group", choices=list(MANIFEST["python"]) + ["node", "native", "browsers", "containers", "zap", "mobsf", "mobile", "licenses", "databases"])
    run = sub.add_parser("run", help="Print planned commands unless --execute is supplied")
    run.add_argument("group", choices=["all"] + list(GROUPS))
    run.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    if args.action == "status":
        print(json.dumps(inventory(), indent=2))
        return 0
    if args.action == "plan":
        print("Prepared groups: " + ", ".join(GROUPS))
        print("Run syntax: scripts/quality.command run GROUP --execute")
        print("Mobile, supply-chain and release need additional evidence/harnesses; all cannot pass while they remain blocked.")
        print("License scans inventory the selected source; ORT policy and legal review are separate release gates.")
        return 0
    if args.action == "install":
        return install(args.group)
    groups = GROUPS if args.group == "all" else (args.group,)
    report = TOOL_HOME / "reports" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    if not args.execute:
        print("PLAN ONLY. No tests, scans or target requests have started.")
        for group in groups:
            for command, cwd in commands(group, report):
                print(f"[{group}] ({cwd}) {shlex.join(command)}")
            if not commands(group, report):
                print(f"[{group}] BLOCKED: see docs/setup/QUALITY_COVERAGE.md")
        return 0
    require_space(2)
    prepare_directories()
    report.mkdir(parents=True)
    if any(g in groups for g in ("security", "dependencies", "sbom", "infrastructure", "licenses")):
        source_snapshot(report)
    results = []
    for group in groups:
        if group == "web" and (TOOL_HOME / "node").is_dir():
            for name in ("playwright.config.cjs", "web.spec.cjs"):
                shutil.copy2(CONFIG / name, TOOL_HOME / "node" / name)
        if group == "zap" and (TOOL_HOME / "bin/zap").is_file():
            plan = (CONFIG / "zap.yaml").read_text()
            # Quoted origin strings belong to regex scope rules; ordinary URLs remain literal.
            plan = plan.replace("'http://native-test-frontend:8080", "'" + re.escape(TARGET))
            plan = plan.replace("http://native-test-frontend:8080", TARGET)
            plan = plan.replace("/zap/wrk/reports", str(report))
            (report / "zap-plan.yaml").write_text(plan)
        jobs = commands(group, report)
        if not jobs:
            results.append({"group": group, "status": "blocked", "reason": "Additional harness/manual evidence required"})
        for number, (command, cwd) in enumerate(jobs):
            log = report / f"{group}-{number}.log"
            try:
                code = run_command(command, cwd, log, {"ERP_QUALITY_REPORT_DIR": str(report)})
                result = {"group": group, "status": "passed" if code == 0 else "failed", "exit_code": code, "log": str(log)}
            except OSError as error:
                result = {"group": group, "status": "blocked", "reason": str(error)}
            results.append(result)
            # These jobs consume the first job's output; other checks are independent.
            prerequisite = ("The SBOM prerequisite failed" if group == "sbom" else
                            "Flutter dependency resolution failed" if group == "flutter" and number == 0 else None)
            if prerequisite and result["status"] != "passed":
                for remaining in range(number + 1, len(jobs)):
                    results.append({"group": group, "job": remaining, "status": "blocked",
                                    "reason": prerequisite})
                break
        (report / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"Results: {report / 'results.json'}")
    print("Tool execution results are not release approval; manual gates remain required.")
    return int(any(result["status"] != "passed" for result in results))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
