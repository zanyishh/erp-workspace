#!/usr/bin/env python3
"""Install pinned license tools on the external drive; never scan application files."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile

WORKSPACE = Path(__file__).resolve().parents[2]
LOCK = WORKSPACE / "infrastructure/erpnext/quality/license-tools.lock.json"
INTEL_PYTHON = Path("/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13-intel64")


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(root, spec):
    archive = root / "downloads/license-tools" / spec["url"].rsplit("/", 1)[1]
    if not archive.exists():
        partial = archive.with_name(archive.name + ".part")
        if not partial.exists() or partial.stat().st_size != spec["size"]:
            subprocess.run([
                "/usr/bin/curl", "--fail", "--location", "--show-error", "--silent",
                "--connect-timeout", "20", "--max-time", "1800", "--retry", "2",
                "--continue-at", "-", "--output", str(partial), spec["url"],
            ], check=True)
        if partial.stat().st_size != spec["size"] or checksum(partial) != spec["sha256"]:
            raise RuntimeError(f"Archive verification failed: {partial}")
        partial.rename(archive)
        return archive
    if archive.stat().st_size != spec["size"] or checksum(archive) != spec["sha256"]:
        raise RuntimeError(f"Archive verification failed: {archive}")
    return archive


def extract(root, archive, spec):
    destination = root / spec["destination"]
    marker = destination / ".erp-quality-archive.sha256"
    if destination.exists():
        if not marker.is_file() or marker.read_text().strip() != spec["sha256"]:
            raise RuntimeError(f"Existing installation requires inspection: {destination}")
        return destination
    staging = root / "tmp/license-tools" / (destination.name + ".extracting")
    staging.mkdir(exist_ok=False)
    with tarfile.open(archive) as bundle:
        bundle.extractall(staging, filter="data")
    folders = list(staging.iterdir())
    if len(folders) != 1 or not folders[0].is_dir():
        raise RuntimeError(f"Expected one archive root directory: {staging}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    folders[0].rename(destination)
    staging.rmdir()
    marker.write_text(spec["sha256"] + "\n")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", type=Path, default=Path("/Volumes/ERPQuality/erp-quality"))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--download-only", action="store_true")
    mode.add_argument("--extract-only", action="store_true")
    args = parser.parse_args()
    root = args.tool_home.resolve()
    if not Path("/Volumes/ERPQuality").is_mount() or not root.is_relative_to("/Volumes/ERPQuality"):
        parser.error("The approved external tool volume must be mounted; tool-home must be inside it.")
    try:
        location = json.loads((WORKSPACE / ".local/quality/location.json").read_text())
        if location.get("mountpoint") != "/Volumes/ERPQuality" or not location.get("volume_uuid"):
            parser.error("The external storage record is missing its approved mountpoint or UUID.")
        volume = plistlib.loads(subprocess.check_output([
            "/usr/sbin/diskutil", "info", "-plist", "/Volumes/ERPQuality",
        ], timeout=120))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.error(f"Cannot verify external storage identity: {error}")
    if str(volume.get("VolumeUUID", "")).upper() != str(location["volume_uuid"]).upper():
        parser.error("The mounted tool volume does not match the recorded UUID; no files were written.")
    if not location.get("disk_image"):
        parser.error("The external storage record is missing its backing disk image path.")
    for storage in (root, Path(location["disk_image"]).parent):
        if shutil.disk_usage(storage).free < 4 * 1024**3:
            parser.error(f"At least 4 GiB free is required on {storage}; no files were removed.")
    for folder in ("downloads/license-tools", "tmp/license-tools", "receipts/license-tools", "logs/license-tools", "cache/license-tools", "bin"):
        (root / folder).mkdir(parents=True, exist_ok=True)
    specs = json.loads(LOCK.read_text())["archives"]
    installed = {}
    for name, spec in specs.items():
        print(f"Verifying {name} {spec['version']}", flush=True)
        archive = download(root, spec)
        if not args.download_only:
            print(f"Extracting {name}", flush=True)
            installed[name] = extract(root, archive, spec)
    if args.download_only:
        return
    if args.extract_only:
        print("Archives verified and extracted; configuration and version checks are pending.")
        return
    env = os.environ.copy()
    env.update({
        "TMPDIR": str(root / "tmp/license-tools"),
        "XDG_CACHE_HOME": str(root / "cache/license-tools"),
        "PIP_CACHE_DIR": str(root / "cache/license-tools/pip"),
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONNOUSERSITE": "1",
        "VIRTUALENV_APP_DATA": str(root / "cache/license-tools/virtualenv"),
        "PYTHON_EXECUTABLE": str(INTEL_PYTHON),
        "SCANCODE_CACHE": str(root / "cache/license-tools/scancode"),
        "SCANCODE_TEMP": str(root / "tmp/license-tools"),
    })
    if not INTEL_PYTHON.is_file():
        raise RuntimeError(f"ScanCode requires the existing x86_64 Python 3.13: {INTEL_PYTHON}")
    python_version = subprocess.check_output(["/usr/bin/arch", "-x86_64", str(INTEL_PYTHON), "--version"], env=env, text=True).strip()
    print(python_version, flush=True)
    scan = installed["scancode"]
    if not (scan / ".erp-quality-configured").is_file():
        if not (scan / "etc/thirdparty/virtualenv.pyz").is_file() or not any((scan / "thirdparty").glob("*.whl")):
            raise RuntimeError("ScanCode archive lacks its offline bootstrap or wheels; refusing an unpinned network fallback.")
        print("Configuring ScanCode from its bundled offline wheels", flush=True)
        with (root / "logs/license-tools/scancode-configure.log").open("w") as output:
            subprocess.run(["/usr/bin/arch", "-x86_64", "/bin/bash", str(scan / "configure")], cwd=scan, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)
        (scan / ".erp-quality-configured").write_text(specs["scancode"]["sha256"] + "\n")
    java = next(installed["java"].glob("**/Contents/Home"))
    quote = shlex.quote
    java_flags = shlex.join([f"-Duser.home={root / 'cache/license-tools/java-home'}", f"-Djava.io.tmpdir={env['TMPDIR']}"])
    wrappers = {
        "scancode": "#!/bin/sh\n" + f"export TMPDIR={quote(env['TMPDIR'])}\nexport XDG_CACHE_HOME={quote(env['XDG_CACHE_HOME'])}\nexport SCANCODE_CACHE={quote(env['SCANCODE_CACHE'])}\nexport SCANCODE_TEMP={quote(env['SCANCODE_TEMP'])}\nexport PYTHONDONTWRITEBYTECODE=1\nexec /usr/bin/arch -x86_64 {quote(str(scan / 'venv/bin/scancode'))} \"$@\"\n",
        "ort": "#!/bin/sh\n" + f"export JAVA_HOME={quote(str(java))}\nexport TMPDIR={quote(env['TMPDIR'])}\nexport ORT_DATA_DIR={quote(str(root / 'cache/license-tools/ort'))}\nexport ORT_CONFIG_DIR={quote(str(root / 'cache/license-tools/ort/config'))}\nexport JAVA_OPTS=\"${{JAVA_OPTS:--Xmx512m}} \"{quote(java_flags)}\nexec {quote(str(installed['ort'] / 'bin/ort'))} \"$@\"\n",
    }
    for name, content in wrappers.items():
        target = root / "bin" / name
        if target.is_symlink() or (target.exists() and target.read_text() != content):
            raise RuntimeError(f"Refusing to replace an existing different launcher: {target}")
        target.write_text(content)
        target.chmod(0o755)
    versions = {}
    for name, command in {"java": [str(java / "bin/java"), "-version"], "scancode": [str(root / "bin/scancode"), "--version"], "ort": [str(root / "bin/ort"), "--version"]}.items():
        result = subprocess.run(command, cwd=root / "tmp/license-tools", env={**env, "JAVA_OPTS": "-Xms32m -Xmx256m"}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
        (root / "logs/license-tools" / f"{name}-version.log").write_text(result.stdout)
        result.check_returncode()
        versions[name] = result.stdout.strip()
        print(versions[name], flush=True)
    receipt = {"prepared_at": datetime.now(timezone.utc).isoformat(), "installations": {k: str(v) for k, v in installed.items()}, "archives": specs, "version_checks": versions, "existing_python": {"path": str(INTEL_PYTHON), "version": python_version, "architecture": "x86_64"}, "application_tests_or_scans_run": False}
    (root / "receipts/license-tools/install.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Installed license tools; no application tests or scans were run.")


if __name__ == "__main__":
    main()
