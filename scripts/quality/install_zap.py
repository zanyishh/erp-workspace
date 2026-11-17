#!/usr/bin/env python3
"""Install the pinned native ZAP bundle externally without launching it."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import tempfile

from install_containers import require_storage
from install_native import plain_path, sha256

VERSION = "2.17.0"
DMG = "ZAP_2.17.0_aarch64.dmg"
URL = f"https://github.com/zaproxy/zaproxy/releases/download/v{VERSION}/{DMG}"
SIZE = 276518308
SHA256 = "3b3c6c8b105a33cb2a7d718e7f9aa41418a6d8aae3887d94a42523b5eeac723b"
JAVA = "jre-jdk-17.0.17+10-jre"
# Recorded from the successfully copied, publisher-checksummed official bundle.
FILES = {
    "Contents/Info.plist": "e2a00b7e44e845e35dc00b76b307dd8cf4ed5924a5c0a8a9890b52e2eca9cd31",
    "Contents/Java/zap.sh": "14cbae7c389e1b9fdbfe43dab82163f44e486a391792f1fc74e77e7092f38999",
    "Contents/Java/zap-2.17.0.jar": "d0b58c941836deec8193ad68b56cef573109cbb52d649b7162384cc9b090e32a",
    f"Contents/PlugIns/{JAVA}/Contents/Home/bin/java": "b66b363acef8221916a2cd1438cbd00367a9fe93b31b11a0609b5e37bfb511a7",
}
WRAPPER = '''#!/bin/sh
set -eu
quality_root=$(cd "$(dirname "$0")/.." && pwd -P)
unset JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS JAVADEBUG
export TMPDIR="$quality_root/tmp"
exec "$quality_root/apps/ZAP.app/Contents/Java/zap.sh" -Xmx512m -cmd -host 127.0.0.1 -port 8095 -dir "$quality_root/state/zap" "$@"
'''


def verify_download(archive):
    plain_path(archive)
    if not archive.is_file() or archive.stat().st_size != SIZE or sha256(archive) != SHA256:
        raise RuntimeError(f"ZAP installer failed its pinned size/SHA256 check: {archive}")


def download(archive, env, log):
    if archive.exists():
        verify_download(archive)
        print("Reusing the verified ZAP installer download", flush=True)
        return
    with tempfile.NamedTemporaryFile(prefix=".zap-download-", suffix=".dmg", dir=archive.parent, delete=False) as stream:
        pending = Path(stream.name)
    try:
        with log.open("a") as output:
            subprocess.run([
                "/usr/bin/curl", "--disable", "--fail", "--silent", "--show-error", "--location",
                "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "20",
                "--max-time", "1800", "--retry", "3", "--max-filesize", str(SIZE),
                "--output", str(pending), URL,
            ], check=True, env=env, stdout=output, stderr=subprocess.STDOUT)
        verify_download(pending)
        # Exclusive publication preserves any destination created concurrently.
        os.link(pending, archive)
    finally:
        pending.unlink(missing_ok=True)


def verify_bundle(app):
    plain_path(app)
    for relative, expected in FILES.items():
        file = plain_path(app / relative)
        if not file.is_file() or sha256(file) != expected:
            raise RuntimeError(f"ZAP bundle verification failed: {file}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleShortVersionString") != VERSION:
        raise RuntimeError("ZAP application metadata does not match the pinned version")


def copy_bundle(archive, app, env, log):
    # Only this empty mountpoint is internal. App files, downloads and logs stay external.
    mount = Path(tempfile.mkdtemp(prefix="erp-quality-zap-", dir="/private/tmp"))
    try:
        with log.open("a") as output:
            subprocess.run([
                "/usr/bin/hdiutil", "attach", str(archive), "-readonly", "-nobrowse",
                "-noautoopen", "-noverify", "-mountpoint", str(mount),
            ], check=True, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180)
        if not os.path.ismount(mount):
            raise RuntimeError("The verified ZAP installer was not mounted at its private mountpoint")
        source = mount / "ZAP.app"
        verify_bundle(source)
        # Reserve a new directory exclusively; never merge into or replace a user's bundle.
        app.mkdir(exist_ok=False)
        with log.open("a") as output:
            subprocess.run(["/usr/bin/ditto", str(source), str(app)], check=True, env=env,
                           stdout=output, stderr=subprocess.STDOUT, timeout=1800)
        verify_bundle(app)
    finally:
        if os.path.ismount(mount):
            with log.open("a") as output:
                subprocess.run(["/usr/bin/hdiutil", "detach", str(mount)], check=True, env=env,
                               stdout=output, stderr=subprocess.STDOUT, timeout=180)
        # Remove only our empty mountpoint after a clean detach; partial app copies are retained.
        if not os.path.ismount(mount):
            mount.rmdir()


def install(home):
    home = plain_path(home.expanduser().absolute())
    if ".." in home.parts:
        raise RuntimeError("Tool home must not contain '..'")
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("This pinned ZAP bundle requires macOS ARM64")
    require_storage(home)
    app = plain_path(home / "apps/ZAP.app")
    wrapper = plain_path(home / "bin/zap")
    receipt = plain_path(home / "receipts/zap-native.json")
    previous = json.loads(receipt.read_text()) if receipt.exists() else None
    if previous is not None and any(previous.get(key) != value for key, value in {
        "tool": "zap", "version": VERSION, "path": str(app), "installer_sha256": SHA256,
    }.items()):
        raise RuntimeError("Existing ZAP receipt differs from this installation; nothing was replaced")
    if wrapper.exists() and (not wrapper.is_file() or wrapper.read_text() != WRAPPER):
        raise RuntimeError("Existing ZAP launcher differs; nothing was replaced")
    if app.exists():
        if previous is None:
            raise RuntimeError("Existing ZAP bundle has no matching installation receipt; inspect it before retrying")
        verify_bundle(app)
    for name in ("apps", "bin", "downloads", "logs", "receipts", "state/zap", "tmp"):
        plain_path(home / name).mkdir(mode=0o700, parents=True, exist_ok=True)
    log = plain_path(home / "logs/zap-installation.log")
    log.touch(mode=0o600, exist_ok=True)
    log.chmod(0o600)
    env = os.environ.copy()
    env["TMPDIR"] = str(home / "tmp")
    archive = plain_path(home / "downloads" / DMG)
    download(archive, env, log)
    if not app.exists():
        copy_bundle(archive, app, env, log)
    if not wrapper.exists():
        with wrapper.open("x") as stream:
            stream.write(WRAPPER)
    wrapper.chmod(0o755)
    now = datetime.now(timezone.utc).isoformat()
    record = {
        "tool": "zap", "version": VERSION, "status": "installed-native-bundle",
        "platform": "darwin-arm64", "installed_at": previous.get("installed_at", now) if previous else now,
        "verified_at": now, "path": str(app), "executable": str(wrapper),
        "source_url": URL, "installer_path": str(archive), "installer_sha256": SHA256,
        "copied_file_sha256": FILES, "bundled_java": JAVA,
        "version_evidence": "Copied Info.plist; application was not launched",
        "listen_when_started": "127.0.0.1:8095", "maximum_heap_mib": 512,
        "services_started": False, "tests_or_scans_run": False,
        "launcher_sha256": hashlib.sha256(WRAPPER.encode()).hexdigest(),
        "inherited_jvm_overrides_removed": True,
        "notices": "Complete official application bundle copied with ditto, preserving bundled notices",
    }
    if previous is None:
        with receipt.open("x") as stream:
            stream.write(json.dumps(record, indent=2) + "\n")
    else:
        with tempfile.NamedTemporaryFile(mode="w", prefix=".zap-receipt-", dir=receipt.parent, delete=False) as stream:
            pending = Path(stream.name)
            json.dump(record, stream, indent=2)
            stream.write("\n")
        try:
            pending.replace(receipt)
        finally:
            pending.unlink(missing_ok=True)
    print(f"Prepared native ZAP {VERSION}; no application launch, tests or scans. Receipt: {receipt}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", type=Path, required=True)
    args = parser.parse_args()
    try:
        install(args.tool_home)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print(f"ZAP preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
