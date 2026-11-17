#!/usr/bin/env python3
"""Prepare native MobSF and its local database; never start a service or scan."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import stat
import subprocess
import sys
import zipfile

from install_containers import require_storage
from install_native import plain_path, safe_member

VERSION = "4.6.6"
JAVA_HOME = Path("/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home")
WHEEL = "mobsf-4.6.6-py3-none-any.whl"
WHEEL_URL = "https://files.pythonhosted.org/packages/cc/ea/b5fe211761a154ee53115eba1c13aee7e936876cc1795b8171a8b848ee89/" + WHEEL
WHEEL_SHA256 = "ea2ef07a18b5992d8c684acb889b1a21a37aaa34a63d4ddf1f5790263d8a8c34"
JADX_VERSION = "1.5.6"
JADX_URL = f"https://github.com/skylot/jadx/releases/download/v{JADX_VERSION}/jadx-{JADX_VERSION}.zip"
JADX_SHA256 = "545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974"
ANDROID_SDK = Path('/opt/homebrew/share/android-commandlinetools')


def android_aapt_paths():
    result = {}
    for name in ('aapt', 'aapt2'):
        path = ANDROID_SDK / 'build-tools/36.0.0' / name
        if path.exists() or path.is_symlink():
            if not path.resolve().is_relative_to(ANDROID_SDK.resolve()) or not path.is_file() or not os.access(path, os.X_OK):
                raise RuntimeError('Android inspection tool is outside the known SDK or is not executable')
            result['MOBSF_' + name.upper() + '_BINARY'] = str(path)
    return result if len(result) == 2 else {}


def environment(home):
    env = os.environ.copy()
    for key in list(env):
        if (key.startswith(("ERP_", "FRAPPE_", "MOBSF_", "DJANGO_", "POSTGRES_", "PYTHON", "UV_", "PIP_", "GUNICORN_"))
                or key.upper().endswith("_PROXY") or key in {"VIRTUAL_ENV", "DATABASE_URL", "WEB_CONCURRENCY"}):
            env.pop(key, None)
    env.update({
        "MOBSF_HOME_DIR": str(home / "state/mobsf"),
        "MOBSF_JAVA_DIRECTORY": str(JAVA_HOME / "bin"), "JAVA_HOME": str(JAVA_HOME),
        "MOBSF_DISABLE_AUTHENTICATION": "0", "DJANGO_SETTINGS_MODULE": "mobsf.MobSF.settings",
        "TMPDIR": str(home / "tmp/mobsf"), "UV_CACHE_DIR": str(home / "cache/uv"),
        "UV_CONCURRENT_DOWNLOADS": "1", "UV_CONCURRENT_INSTALLS": "1", "UV_CONCURRENT_BUILDS": "1",
        "UV_PYTHON_DOWNLOADS": "never", "PIP_CACHE_DIR": str(home / "cache/pip"),
        "XDG_CACHE_HOME": str(home / "cache"), "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_DATA_HOME": str(home / "data"), "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1", "NO_PROXY": "*",
        "PATH": os.pathsep.join((str(home / "venvs/mobsf/bin"), str(JAVA_HOME / "bin"), env.get("PATH", ""))),
    })
    # MobSF needs both tools, even when it uses aapt2 for badging; invocation is read-only.
    env.update(android_aapt_paths())
    return env


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(url, target, expected, env):
    plain_path(target)
    pending = plain_path(target.with_suffix(target.suffix + ".part"))
    if not target.exists():
        print(f"Downloading {target.name}", flush=True)
        subprocess.run(["/usr/bin/curl", "--disable", "--fail", "--silent", "--show-error", "--location",
                        "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15",
                        "--max-time", "1800", "--retry", "3", "--max-filesize", str(130 * 1024**2),
                        "--output", str(pending), url], env=env, check=True)
        if digest(pending) != expected:
            raise RuntimeError(f"Publisher checksum mismatch: {target.name}")
        pending.replace(target)
    elif digest(target) != expected:
        raise RuntimeError(f"Cached publisher checksum mismatch: {target.name}")
    print(f"Verified publisher checksum: {target.name}", flush=True)


def install_jadx(archive, state):
    target = plain_path(state / "tools/jadx" / f"jadx-{JADX_VERSION}")
    marker = plain_path(target / ".erp-quality-sha256")
    if marker.is_file() and marker.read_text().strip() == JADX_SHA256 and (target / "bin/jadx").is_file():
        return
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            safe_member(member.filename)
            kind = stat.S_IFMT(member.external_attr >> 16)
            if kind and kind not in (stat.S_IFREG, stat.S_IFDIR):
                raise RuntimeError("JADX archive contains a non-regular entry")
        for member in package.infolist():
            output = plain_path(target / member.filename)
            if member.is_dir():
                output.mkdir(parents=True, exist_ok=True)
            else:
                output.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as source, output.open("wb") as copied:
                    shutil.copyfileobj(source, copied, 1024**2)
                output.chmod(0o755 if member.filename.startswith("bin/") else 0o644)
    if not (target / "bin/jadx").is_file():
        raise RuntimeError("Verified JADX archive did not contain its expected launcher")
    marker.write_text(JADX_SHA256 + "\n")


def install(home):
    home = plain_path(home.expanduser().absolute())
    if ".." in home.parts:
        raise RuntimeError("Tool home must not contain '..'")
    require_storage(home)
    if platform.system() != "Darwin" or platform.machine() != "arm64" or not ((3, 12) <= sys.version_info[:2] <= (3, 13)):
        raise RuntimeError("This native installation requires macOS ARM64 and Python 3.12 or 3.13")
    if not (JAVA_HOME / "bin/java").is_file():
        raise RuntimeError("The existing Homebrew OpenJDK21 runtime is required")
    uv = shutil.which("uv")
    if not uv:
        raise RuntimeError("The existing uv package installer is required")
    for folder in ("downloads/mobsf", "locks", "venvs", "state/mobsf", "tmp/mobsf", "cache/uv", "cache/pip", "logs", "receipts"):
        plain_path(home / folder).mkdir(mode=0o700, parents=True, exist_ok=True)
    state = home / "state/mobsf"
    venv = plain_path(home / "venvs/mobsf")
    env = environment(home)
    log = plain_path(home / "logs/mobsf-installation.log")

    def run(command, label):
        print(label, flush=True)
        with log.open("a") as output:
            log.chmod(0o600)
            subprocess.run(command, cwd=home, env=env, stdout=output, stderr=subprocess.STDOUT,
                           check=True, umask=0o077)

    wheel = home / "downloads/mobsf" / WHEEL
    jadx = home / "downloads/mobsf" / f"jadx-{JADX_VERSION}.zip"
    download(WHEEL_URL, wheel, WHEEL_SHA256, env)
    download(JADX_URL, jadx, JADX_SHA256, env)
    if not (venv / "pyvenv.cfg").is_file():
        run([uv, "--no-config", "venv", "--python", sys.executable, str(venv)], "Creating isolated MobSF environment")
    python = venv / "bin/python"
    seed = plain_path(home / "locks/mobsf.in")
    lock = plain_path(home / "locks/requirements-mobsf.lock.txt")
    seed.write_text(f"mobsf @ {wheel.as_uri()}\n")
    if not lock.is_file():
        pending = plain_path(lock.with_name("requirements-mobsf.pending.txt"))
        run([uv, "--no-config", "pip", "compile", "--python", str(python), "--generate-hashes",
             "--only-binary", ":all:", "--no-binary", "frida-tools",
             "--default-index", "https://pypi.org/simple", "--output-file", str(pending), str(seed)],
            "Resolving and hashing MobSF dependencies")
        pending.replace(lock)
    if WHEEL_SHA256 not in lock.read_text():
        raise RuntimeError("Dependency lock does not include the verified MobSF wheel hash")
    run([uv, "--no-config", "pip", "sync", "--python", str(python), "--require-hashes",
         "--only-binary", ":all:", "--no-binary", "frida-tools",
         "--default-index", "https://pypi.org/simple", str(lock)], "Installing pinned MobSF dependencies")
    install_jadx(jadx, state)
    credentials = plain_path(state / "local-credentials.json")
    if not credentials.exists():
        with credentials.open("x") as stream:
            credentials.chmod(0o600)
            json.dump({"username": "erp-quality", "password": secrets.token_urlsafe(32)}, stream)
            stream.write("\n")
    login = json.loads(credentials.read_text())
    env["DJANGO_SUPERUSER_USERNAME"] = login["username"]
    env["DJANGO_SUPERUSER_PASSWORD"] = login["password"]
    run([str(venv / "bin/mobsf"), "db"], "Initializing the isolated MobSF database (no server or scans)")
    create_user = """import os, django
django.setup()
from django.contrib.auth import get_user_model
User = get_user_model()
name = os.environ['DJANGO_SUPERUSER_USERNAME']
password = os.environ['DJANGO_SUPERUSER_PASSWORD']
user = User.objects.filter(**{User.USERNAME_FIELD: name}).first()
if user is None:
    User.objects.create_superuser(**{User.USERNAME_FIELD: name, 'email': '', 'password': password})
elif not user.is_superuser or not user.check_password(password):
    raise SystemExit('Existing MobSF operator does not match the installation credential file; no account was changed')
"""
    run([str(python), "-c", create_user], "Preparing the local MobSF operator")
    packages = {}
    for site in (venv / "lib").glob("python*/site-packages"):
        packages.update({item.metadata["Name"]: item.version for item in importlib.metadata.distributions(path=[str(site)])})
    if packages.get("mobsf") != VERSION or not (state / "db.sqlite3").is_file():
        raise RuntimeError("MobSF package/database installation evidence is incomplete")
    receipt = {"tool": "mobsf", "version": VERSION, "status": "installed-native-static-preparation",
               "prepared_at": datetime.now(timezone.utc).isoformat(), "platform": "darwin-arm64",
               "path": str(venv), "home": str(state), "wheel_sha256": WHEEL_SHA256,
               "wheel_url": WHEEL_URL, "jadx_url": JADX_URL,
               "jadx_version": JADX_VERSION, "jadx_sha256": JADX_SHA256, "lock_path": str(lock),
               "lock_sha256": digest(lock), "packages": dict(sorted(packages.items())),
               "credentials_path": str(credentials), "listen_when_started": "127.0.0.1:8009",
               "services_started": False, "tests_or_scans_run": False,
               "runtime_limit": "Official general requirement is 80GB+ free disk and 8GB+ RAM; this host does not meet the free-disk recommendation. Dynamic analysis is not configured."}
    destination = plain_path(home / "receipts/mobsf-native.json")
    destination.write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Prepared native MobSF {VERSION}; service remains stopped. Receipt: {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", type=Path, required=True)
    args = parser.parse_args()
    try:
        install(args.tool_home)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f"MobSF preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
