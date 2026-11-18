#!/usr/bin/env python3
"""Download vulnerability databases serially; never scan a target or start a service."""
import argparse
from datetime import datetime, timezone
import json
import shlex
import subprocess
import sys

sys.dont_write_bytecode = True
import quality


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--include-java", action="store_true",
                        help="also prepare Trivy's separate Java artifact index; unnecessary for Dart/Python sources")
    args = parser.parse_args()
    # Current databases expand to several GiB; leave room for archives and staging.
    quality.require_space(6)
    home = quality.TOOL_HOME
    config = home / "config/database-preparation.yaml"
    for path in (home / "cache/trivy", home / "cache/grype/db", home / "tmp",
                 home / "logs", home / "receipts", config):
        if not path.resolve().is_relative_to(home):
            raise RuntimeError(f"Database preparation path escapes tool storage: {path}")
    for tool in ("trivy", "grype"):
        if not (home / "bin" / tool).is_file():
            raise RuntimeError(f"Install the pinned native {tool} executable first.")
    quality.prepare_directories()
    (home / "receipts").mkdir(parents=True, exist_ok=True)
    # An explicit empty configuration avoids unrelated user/project scanner settings.
    config.write_text("{}\n")
    env = quality.environment()
    for key in list(env):
        if key.startswith(("TRIVY_", "GRYPE_")):
            del env[key]
    env.update({
        "TRIVY_CACHE_DIR": str(home / "cache/trivy"),
        "GRYPE_DB_CACHE_DIR": str(home / "cache/grype/db"),
        "GRYPE_DB_UPDATE_URL": "https://grype.anchore.io/databases",
        "GRYPE_DB_AUTO_UPDATE": "false",
        "GRYPE_CHECK_FOR_APP_UPDATE": "false",
        "GRYPE_LOG_LEVEL": "debug",
        "GRYPE_DB_UPDATE_AVAILABLE_TIMEOUT": "120s",
        "GRYPE_DB_UPDATE_DOWNLOAD_TIMEOUT": "30m",
    })
    trivy = [str(home / "bin/trivy"), "--config", str(config), "image",
             "--scanners", "vuln", "--no-progress", "--skip-version-check",
             "--disable-telemetry", "--timeout", "30m"]
    jobs = [
        ("trivy-vulnerabilities", trivy + ["--download-db-only"], 6),
        ("grype-vulnerabilities", [str(home / "bin/grype"), "--config", str(config), "db", "update"], 6),
    ]
    if args.include_java:
        jobs.append(("trivy-java", trivy + ["--download-java-db-only"], 8))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    receipt = home / "receipts" / f"databases-{stamp}.json"
    evidence = {"started_at": datetime.now(timezone.utc).isoformat(), "tool_home": str(home),
                "application_tests_or_scans_run": False, "include_java": args.include_java, "steps": []}
    for name, command, free_gib in jobs:
        # Recheck both the mounted image and its backing drive before each large update.
        quality.require_space(free_gib)
        log = home / "logs" / f"databases-{stamp}-{name}.log"
        print(shlex.join(command), flush=True)
        print(f"Download/install log: {log}", flush=True)
        result = {"name": name, "command": command, "log": str(log)}
        with log.open("w") as output:
            try:
                completed = subprocess.run(command, cwd=home, env=env, stdout=output,
                                           stderr=subprocess.STDOUT, check=False, timeout=3600)
                result["exit_code"] = completed.returncode
            except (OSError, subprocess.TimeoutExpired) as error:
                result.update({"exit_code": 1, "error": str(error)})
        result["status"] = "prepared" if result["exit_code"] == 0 else "failed"
        result["finished_at"] = datetime.now(timezone.utc).isoformat()
        evidence["steps"].append(result)
        receipt.write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"{name}: {result['status']}", flush=True)
    print(f"Database preparation receipt: {receipt}", flush=True)
    return int(any(step["exit_code"] != 0 for step in evidence["steps"]))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
