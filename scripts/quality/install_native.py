#!/usr/bin/env python3
"""Install pinned macOS ARM64 quality tools on the mounted external volume only.

This installs files and collects version output. It never starts a scan or test.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "infrastructure/erpnext/quality/native-tools.lock.json"
MOUNT = Path("/Volumes/ERPQuality")
MAX_DOWNLOAD_BYTES = 64 * 1024 * 1024


def plain_path(path):
    """Do not follow existing symlinks in any installation path."""
    for item in (path, *path.parents):
        if item.is_symlink():
            raise RuntimeError(f"Refusing a symlink in installation path: {item}")
    return path


def sha256(path):
    with path.open("rb") as source:
        digest = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
        return digest.hexdigest()


def download(url, target, expected):
    plain_path(target)
    if not url.startswith(("https://github.com/", "https://raw.githubusercontent.com/")):
        raise RuntimeError(f"Unexpected publisher URL: {url}")
    if target.exists():
        if target.stat().st_size > MAX_DOWNLOAD_BYTES:
            raise RuntimeError(f"Cached file exceeds the pinned archive size limit: {target}")
        data = target.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Cached file failed SHA-256 verification: {target}")
        return data
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".native-download-", dir=target.parent, delete=False) as temporary:
        pending = Path(temporary.name)
    try:
        subprocess.run([
            "/usr/bin/curl", "--fail", "--silent", "--show-error", "--location",
            "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2",
            "--retry", "3", "--connect-timeout", "30", "--max-time", "600",
            "--max-filesize", str(MAX_DOWNLOAD_BYTES),
            "--output", str(pending), url,
        ], check=True)
        if pending.stat().st_size > MAX_DOWNLOAD_BYTES:
            raise RuntimeError(f"Download exceeds the pinned archive size limit: {url}")
        data = pending.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Downloaded file failed SHA-256 verification: {url}")
        pending.replace(target)
        return data
    finally:
        pending.unlink(missing_ok=True)


def safe_member(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name:
        raise RuntimeError(f"Unsafe archive member: {name!r}")


def copy_member(source, destination, executable=False):
    plain_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".native-install-", dir=destination.parent, delete=False) as temporary:
        pending = Path(temporary.name)
        digest = hashlib.sha256()
        try:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                temporary.write(block)
                digest.update(block)
        except BaseException:
            pending.unlink(missing_ok=True)
            raise
    try:
        mode = 0o755 if executable else 0o644
        pending.chmod(mode)
        if destination.exists() and sha256(destination) == digest.hexdigest():
            if stat.S_IMODE(destination.stat().st_mode) != mode:
                destination.chmod(mode)
            return digest.hexdigest()
        pending.replace(destination)
        return digest.hexdigest()
    finally:
        pending.unlink(missing_ok=True)


def install_archive(archive, data, tool, home):
    selected = {tool["binary_member"]: (home / "bin" / tool["name"], True)}
    for member in tool["notice_members"]:
        selected[member] = (home / "licenses" / tool["name"] / PurePosixPath(member).name, False)
    seen = set()
    digests = {}
    # Only explicitly selected regular files are copied; archive extraction is never used.
    # The largest pinned archive is 50 MB; reuse it in memory instead of rereading the slow drive.
    if archive.suffix == ".zip":
        with zipfile.ZipFile(io.BytesIO(data)) as package:
            for member in package.infolist():
                safe_member(member.filename)
                if member.filename in seen:
                    raise RuntimeError(f"Duplicate archive member: {member.filename}")
                seen.add(member.filename)
                mode = member.external_attr >> 16
                if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
                    raise RuntimeError(f"Non-regular archive member: {member.filename}")
            if not selected.keys() <= seen:
                raise RuntimeError(f"Missing expected files in {archive.name}")
            for member, (destination, executable) in selected.items():
                if package.getinfo(member).is_dir():
                    raise RuntimeError(f"Expected a file: {member}")
                with package.open(member) as source:
                    digests[member] = copy_member(source, destination, executable)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as package:
            for member in package.getmembers():
                safe_member(member.name)
                if member.name in seen:
                    raise RuntimeError(f"Duplicate archive member: {member.name}")
                seen.add(member.name)
                if not (member.isfile() or member.isdir()):
                    raise RuntimeError(f"Non-regular archive member: {member.name}")
            if not selected.keys() <= seen:
                raise RuntimeError(f"Missing expected files in {archive.name}")
            for member, (destination, executable) in selected.items():
                if not package.getmember(member).isfile():
                    raise RuntimeError(f"Expected a file: {member}")
                with package.extractfile(member) as source:
                    digests[member] = copy_member(source, destination, executable)
    return digests[tool["binary_member"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", "--home", dest="home",
                        default=os.environ.get("ERP_QUALITY_HOME", str(MOUNT / "erp-quality")))
    args = parser.parse_args()
    home = plain_path(Path(args.home).expanduser().absolute())
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("These pinned tools require macOS ARM64.")
    if not MOUNT.is_mount() or not home.is_relative_to(MOUNT) or home == MOUNT:
        raise RuntimeError(f"Installation requires the mounted external volume {MOUNT}.")
    if ".." in home.parts:
        raise RuntimeError("Installation path must not contain '..'.")
    location_path = ROOT / ".local/quality/location.json"
    if not location_path.is_file():
        raise RuntimeError("External tool storage has not been configured for this workspace.")
    location = json.loads(location_path.read_text())
    if location.get("mountpoint") != str(MOUNT) or not location.get("volume_uuid"):
        raise RuntimeError("The workspace storage record does not identify the approved tool volume.")
    volume = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/diskutil", "info", "-plist", str(MOUNT)], timeout=120))
    if volume.get("VolumeUUID") != location["volume_uuid"]:
        raise RuntimeError("A different volume is mounted at the tool storage path; no files were written.")
    disk_image = location.get("disk_image")
    if not isinstance(disk_image, str) or not Path(disk_image).is_absolute():
        raise RuntimeError("The workspace storage record does not identify the backing disk image.")
    for storage in (MOUNT, Path(disk_image).parent):
        if shutil.disk_usage(storage).free < 1024 ** 3:
            raise RuntimeError(f"Native installation needs at least 1 GiB free on {storage}.")
    lock = json.loads(LOCK.read_text())
    for folder in ("bin", "downloads/native", "licenses", "logs", "tmp", "cache/trivy", "cache/grype", "cache/syft"):
        plain_path(home / folder).mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "TMPDIR": str(home / "tmp"), "XDG_CACHE_HOME": str(home / "cache"),
        "TRIVY_CACHE_DIR": str(home / "cache/trivy"),
        "GRYPE_DB_CACHE_DIR": str(home / "cache/grype"), "GRYPE_DB_AUTO_UPDATE": "false",
        "GRYPE_CHECK_FOR_APP_UPDATE": "false", "SYFT_CHECK_FOR_APP_UPDATE": "false",
    })
    evidence = {"installed_at": datetime.now(timezone.utc).isoformat(), "platform": "darwin-arm64", "tool_home": str(home), "tools": []}
    for tool in lock["tools"]:
        cache = home / "downloads/native" / tool["repository"].split("/")[-1] / tool["tag"]
        checksums = cache / tool["checksums"]["filename"]
        archive = cache / tool["archive"]["filename"]
        checksum_data = download(tool["checksums"]["url"], checksums, tool["checksums"]["sha256"])
        published = [line.split()[0] for line in checksum_data.decode().splitlines()
                     if len(line.split()) == 2 and line.split()[1].lstrip("*") == archive.name]
        if published != [tool["archive"]["sha256"]]:
            raise RuntimeError(f"Publisher checksum disagrees with lock: {tool['name']}")
        archive_data = download(tool["archive"]["url"], archive, tool["archive"]["sha256"])
        binary_digest = install_archive(archive, archive_data, tool, home)
        del archive_data
        for notice in tool.get("additional_notices", []):
            download(notice["url"], home / "licenses" / tool["name"] / notice["filename"], notice["sha256"])
        binary = home / "bin" / tool["name"]
        architecture = subprocess.check_output(["/usr/bin/file", str(binary)], text=True).strip()
        if "Mach-O 64-bit executable arm64" not in architecture:
            raise RuntimeError(f"Unexpected installed executable architecture: {architecture}")
        evidence["tools"].append({"name": tool["name"], "version": tool["version"], "path": str(binary),
                                  "binary_sha256": binary_digest, "architecture": architecture,
                                  "version_status": "pending", "archive_sha256": tool["archive"]["sha256"]})
        plain_path(home / "logs/native-installation.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Installed {tool['name']} {tool['version']} (SHA-256 verified; ARM64).", flush=True)
    failures = []
    # Place every binary before probing launches, so an OS launch delay cannot block installation.
    for tool, receipt in zip(lock["tools"], evidence["tools"]):
        try:
            result = subprocess.run([receipt["path"], *tool["version_args"]], cwd=home, env=env,
                                    capture_output=True, text=True, check=True, timeout=60)
            output = (result.stdout + result.stderr).strip()
            if tool["version"] not in output:
                raise RuntimeError(f"Unexpected installed version: {output}")
            receipt.update({"version_status": "verified", "version_output": output})
            print(f"Version verified: {tool['name']} {tool['version']}.", flush=True)
        except (subprocess.SubprocessError, RuntimeError) as error:
            receipt.update({"version_status": "failed", "version_error": str(error)})
            failures.append(tool["name"])
            print(f"Version check failed for {tool['name']}: {error}", flush=True)
        plain_path(home / "logs/native-installation.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Installation evidence: {home / 'logs/native-installation.json'}")
    if failures:
        raise SystemExit("Installed files, but version checks need attention: " + ", ".join(failures))


if __name__ == "__main__":
    main()
