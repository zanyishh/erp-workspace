#!/usr/bin/env python3
"""Download pinned OCI images without touching Docker or launching containers."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
PLATFORM = "linux/arm64"
DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")
IMAGES = json.loads((ROOT / "infrastructure/erpnext/quality/tools.json").read_text())["containers"]


def require_storage(tool_home):
    storage = json.loads((ROOT / ".local/quality/location.json").read_text())
    mount = Path("/Volumes/ERPQuality")
    if storage.get("mountpoint") != str(mount) or not storage.get("volume_uuid"):
        raise RuntimeError("The selected external volume and its UUID must be recorded before installation")
    if not os.path.ismount(mount):
        raise RuntimeError("External tool storage is not mounted; no files were created")
    if tool_home == mount or not tool_home.is_relative_to(mount):
        raise RuntimeError("Tool home must resolve strictly inside /Volumes/ERPQuality")
    details = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/diskutil", "info", "-plist", str(mount)], timeout=120))
    if details.get("VolumeUUID") != storage["volume_uuid"]:
        raise RuntimeError("The mounted external volume does not match the recorded UUID")
    backing = Path(storage["disk_image"]).expanduser().resolve().parent
    for label, path in (("selected external volume", mount), ("backing drive", backing)):
        if shutil.disk_usage(path).free < 6 * 1024**3:
            raise RuntimeError(f"Tool preparation requires at least 6 GiB free on the {label}")


def verify_layout(folder, digest):
    index = json.loads((folder / "index.json").read_text())
    if not any(item["digest"] == digest for item in index["manifests"]):
        raise RuntimeError("OCI index does not contain the pinned platform manifest")
    artifacts = []
    for file in sorted((folder / "blobs/sha256").iterdir()):
        if file.is_symlink() or not file.is_file():
            raise RuntimeError(f"Unexpected OCI blob: {file.name}")
        with file.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != file.name:
            raise RuntimeError(f"OCI blob checksum mismatch: {file.name}")
        artifacts.append({"path": str(file.relative_to(folder)), "sha256": actual,
                          "bytes": file.stat().st_size})

    def blob(reference):
        if not DIGEST.fullmatch(reference):
            raise RuntimeError(f"Unsupported OCI digest: {reference}")
        return folder / "blobs/sha256" / reference.removeprefix("sha256:")

    manifest = json.loads(blob(digest).read_text())
    config = json.loads(blob(manifest["config"]["digest"]).read_text())
    if (config.get("os"), config.get("architecture")) != ("linux", "arm64"):
        raise RuntimeError("Downloaded image is not Linux arm64")
    for entry in [manifest["config"], *manifest["layers"]]:
        if blob(entry["digest"]).stat().st_size != entry["size"]:
            raise RuntimeError("OCI manifest references an incomplete blob")
    for name in ("index.json", "oci-layout"):
        file = folder / name
        artifacts.append({"path": name, "sha256": hashlib.sha256(file.read_bytes()).hexdigest(),
                          "bytes": file.stat().st_size})
    return artifacts


def pull_registry(source, folder, env):
    """Docker Hub fallback using Apple's existing curl, with no new executable launch."""
    repository, source_digest = source.rsplit("@", 1)
    if not re.fullmatch(r"[a-z0-9_-]+/[a-z0-9_.-]+", repository):
        raise RuntimeError("The registry fallback supports the pinned Docker Hub repositories only")
    accept = ",".join(("application/vnd.oci.image.index.v1+json",
                       "application/vnd.oci.image.manifest.v1+json",
                       "application/vnd.docker.distribution.manifest.list.v2+json",
                       "application/vnd.docker.distribution.manifest.v2+json"))

    def request(url, token=None, output=None):
        command = ["/usr/bin/curl", "--disable", "--fail", "--silent", "--show-error", "--location",
                   "--proto", "=https", "--proto-redir", "=https",
                   "--connect-timeout", "15", "--max-time", "3600" if output else "90", "--retry", "3",
                   "--config", "-", "--header", f"Accept: {accept}"]
        if output:
            command.extend(["--output", str(output)])
        else:
            command.extend(["--max-filesize", str(4 * 1024**2)])
        # The short-lived public pull token stays out of process arguments and logs.
        config = f"header = {json.dumps('Authorization: Bearer ' + token)}\n" if token else ""
        return subprocess.run(command + [url], input=config.encode(), stdout=subprocess.PIPE,
                              check=True, env=env).stdout

    def authenticate():
        query = urlencode({"service": "registry.docker.io", "scope": f"repository:{repository}:pull"})
        result = json.loads(request(f"https://auth.docker.io/token?{query}"))
        return result.get("token") or result["access_token"]

    token = authenticate()

    def get(kind, digest, output=None):
        nonlocal token
        if not DIGEST.fullmatch(digest):
            raise RuntimeError("Registry returned an unsupported digest")
        url = f"https://registry-1.docker.io/v2/{repository}/{kind}/{digest}"
        try:
            return request(url, token, output)
        except subprocess.CalledProcessError as error:
            if error.returncode != 22:
                raise
            token = authenticate()
            return request(url, token, output)

    def manifest(digest):
        content = get("manifests", digest)
        if hashlib.sha256(content).hexdigest() != digest[7:]:
            raise RuntimeError("Registry manifest does not match its pinned SHA256")
        return content, json.loads(content)

    source_bytes, document = manifest(source_digest)
    selected, content = source_digest, source_bytes
    if "manifests" in document:
        candidates = [item for item in document["manifests"]
                      if item.get("platform", {}).get("os") == "linux"
                      and item["platform"].get("architecture") == "arm64"
                      and item["platform"].get("variant", "v8") == "v8"]
        if len(candidates) != 1:
            raise RuntimeError("Expected exactly one Linux arm64 manifest in the pinned image index")
        selected = candidates[0]["digest"]
        content, document = manifest(selected)
    blobs = folder / "blobs/sha256"
    if not blobs.resolve().is_relative_to(folder.resolve()):
        raise RuntimeError("OCI blob directory resolves outside the archive")
    blobs.mkdir(parents=True, exist_ok=True)
    for digest, data in ((source_digest, source_bytes), (selected, content)):
        target = blobs / digest[7:]
        if target.is_symlink():
            raise RuntimeError("Refusing to replace a symbolic link in the OCI archive")
        target.write_bytes(data)
    for entry in [document["config"], *document["layers"]]:
        digest = entry["digest"]
        if not DIGEST.fullmatch(digest):
            raise RuntimeError("Registry returned an unsupported blob digest")
        target = blobs / digest[7:]
        temporary = target.with_suffix(".part")
        if target.is_symlink() or temporary.is_symlink():
            raise RuntimeError("Refusing a symbolic link in the OCI blob store")
        if not target.exists():
            print(f"Downloading OCI blob {digest[7:19]} ({entry['size']:,} bytes)", flush=True)
            get("blobs", digest, temporary)
            temporary.rename(target)
    (folder / "oci-layout").write_text('{"imageLayoutVersion":"1.0.0"}\n')
    index = {"schemaVersion": 2, "manifests": [{"mediaType": document["mediaType"],
             "digest": selected, "size": len(content), "platform": {"os": "linux", "architecture": "arm64"},
             "annotations": {"org.opencontainers.image.ref.name": source}}]}
    (folder / "index.json").write_text(json.dumps(index) + "\n")
    return selected


def install(tool_home, tool=None, crane=None, transport="crane"):
    tool_home = tool_home.expanduser().resolve()
    require_storage(tool_home)
    crane = crane or tool_home / "bin/crane"
    if transport == "crane" and not crane.is_file():
        raise RuntimeError(f"Install the verified native crane binary first: {crane}")
    images = {tool: IMAGES[tool]} if tool else IMAGES
    archive_root = tool_home / "container-archives"
    receipt_root = tool_home / "receipts"
    log_root = tool_home / "logs"
    temporary = tool_home / "tmp"
    for folder in (archive_root, receipt_root, log_root, temporary):
        if not folder.resolve().is_relative_to(tool_home):
            raise RuntimeError("An output directory resolves outside the selected tool home")
    for folder in (archive_root, receipt_root, log_root, temporary):
        folder.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(temporary))
    for name, source in images.items():
        repository, source_digest = source.rsplit("@", 1)
        if not re.fullmatch(r"[a-z0-9_-]+", name) or not DIGEST.fullmatch(source_digest):
            raise RuntimeError("Container names and source references must be pinned")
        folder = archive_root / f"{name}-{source_digest[7:19]}-linux-arm64.oci"
        partial = folder.with_suffix(".oci.partial")
        for output in (folder, partial, log_root / f"container-{name}.log",
                       receipt_root / f"container-{name}.json", receipt_root / f"container-{name}.json.partial"):
            if not output.resolve().is_relative_to(tool_home):
                raise RuntimeError("An output path resolves outside the selected tool home")
        for destination in (folder, partial):
            for entry in ("blobs", "blobs/sha256", "index.json", "oci-layout"):
                if not (destination / entry).resolve().is_relative_to(destination.resolve()):
                    raise RuntimeError("An OCI path resolves outside its archive directory")
        print(f"Preparing {name} ({PLATFORM}); Docker remains unchanged", flush=True)
        if transport == "registry":
            destination = folder if folder.exists() else partial
            selected = pull_registry(source, destination, env)
            artifacts = verify_layout(destination, selected)
            if destination == partial:
                partial.rename(folder)
        else:
            selected = subprocess.check_output(
                [str(crane), "digest", "--platform", PLATFORM, source], text=True, env=env, timeout=90).strip()
            if not DIGEST.fullmatch(selected):
                raise RuntimeError("Registry returned an invalid platform digest")
        if transport == "crane" and not folder.exists():
            with (log_root / f"container-{name}.log").open("a") as output:
                subprocess.run([str(crane), "pull", "--platform", PLATFORM, "--format", "oci",
                                "--annotate-ref", f"{repository}@{selected}", str(partial)],
                               stdout=output, stderr=subprocess.STDOUT, check=True, env=env)
            artifacts = verify_layout(partial, selected)
            partial.rename(folder)
        elif transport == "crane":
            artifacts = verify_layout(folder, selected)
        receipt = {"tool": name, "status": "prepared-oci-layout", "source": source,
                   "source_digest": source_digest, "platform": PLATFORM,
                   "platform_digest": selected, "path": str(folder), "artifacts": artifacts,
                   "transport": transport,
                   "prepared_at": datetime.now(timezone.utc).isoformat(),
                   "loaded_into_docker": False, "containers_started": False,
                   "tests_or_scans_run": False}
        receipt_path = receipt_root / f"container-{name}.json"
        receipt_temp = receipt_path.with_suffix(".json.partial")
        receipt_temp.write_text(json.dumps(receipt, indent=2) + "\n")
        receipt_temp.replace(receipt_path)
        print(f"Prepared {name}: {sum(item['bytes'] for item in artifacts):,} bytes; {folder}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", type=Path, required=True)
    parser.add_argument("--tool", choices=list(IMAGES), help="Prepare one image; defaults to all pinned images")
    parser.add_argument("--crane", type=Path, help="Use an explicitly verified crane executable")
    parser.add_argument("--transport", choices=("crane", "registry"), default="crane",
                        help="Registry mode uses existing system curl when crane cannot launch")
    args = parser.parse_args()
    try:
        install(args.tool_home.expanduser().resolve(), args.tool, args.crane, args.transport)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Container preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
