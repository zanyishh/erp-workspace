#!/usr/bin/env python3
"""Cache pinned quality-tool archives first, then install without network access."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
import quality


DEPENDENCY_FIELDS = ("dependencies", "devDependencies", "optionalDependencies")
CACHE_INSPECTION = r"""
const fs = require('node:fs');
const path = require('node:path');
const cacachePath = process.argv[1];
const cacache = require(cacachePath);
const ssri = require(require.resolve('ssri', { paths: [cacachePath] }));
const cache = path.join(process.argv[2], '_cacache');
const lock = JSON.parse(fs.readFileSync(0, 'utf8'));
function matches(value, allowed) {
  if (!allowed) return true;
  const values = Array.isArray(allowed) ? allowed : [allowed];
  return !values.includes('!' + value) &&
    (values.includes('any') || values.every(v => v.startsWith('!')) || values.includes(value));
}
(async () => {
  const required = new Map();
  let skipped = 0;
  for (const [name, entry] of Object.entries(lock.packages)) {
    if (!name || entry.link) continue;
    if (entry.optional && (!matches(process.platform, entry.os) ||
                           !matches(process.arch, entry.cpu))) {
      skipped++;
      continue;
    }
    const url = new URL(entry.resolved);
    if (url.protocol !== 'https:' || url.hostname !== 'registry.npmjs.org' ||
        url.port || url.username || url.password || url.search || url.hash ||
        !url.pathname.endsWith('.tgz')) {
      throw new Error(`Unexpected registry archive for ${name}: ${entry.resolved}`);
    }
    const integrity = typeof entry.integrity === 'string' && ssri.parse(entry.integrity);
    if (!integrity || !Object.keys(integrity).some(algorithm =>
        ['sha512', 'sha384', 'sha256', 'sha1'].includes(algorithm))) {
      throw new Error(`Missing or invalid npm integrity for ${name}`);
    }
    required.set(entry.integrity, { name, url: entry.resolved, integrity: entry.integrity });
  }
  const missing = [];
  for (const entry of required.values()) {
    if (!await cacache.get.hasContent(cache, entry.integrity)) missing.push(entry);
  }
  console.log(JSON.stringify({ platform: process.platform, arch: process.arch,
    required: required.size, skipped, missing }));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
"""


def read_lock(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def matches_manifest(lock, manifest):
    if not isinstance(lock, dict) or lock.get("lockfileVersion") not in (2, 3):
        return False
    packages = lock.get("packages", {})
    root = packages.get("", {})
    for field in DEPENDENCY_FIELDS:
        if root.get(field, {}) != manifest.get(field, {}):
            return False
        for name, version in manifest.get(field, {}).items():
            if packages.get("node_modules/" + name, {}).get("version") != version:
                return False
    # Root tool versions alone cannot detect stale vulnerable transitive pins.
    for name, version in manifest.get("overrides", {}).items():
        entries = [entry for path, entry in packages.items()
                   if path and path.rsplit("node_modules/", 1)[-1] == name]
        if not entries or any(entry.get("version") != version for entry in entries):
            return False
    return True


def main():
    manifest = json.loads((quality.CONFIG / "package.json").read_text())
    for field in (*DEPENDENCY_FIELDS, "overrides"):
        for name, version in manifest.get(field, {}).items():
            if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?", version):
                raise RuntimeError(f"Quality tool must have an exact version: {name}={version}")
    quality.require_space(3)
    env = quality.environment()
    quality.prepare_directories()
    folder = quality.TOOL_HOME / "node"
    # Reuse the cache populated by the original installer, rather than cache/npm.
    cache = quality.TOOL_HOME / "npm-cache"
    for destination in (folder, cache, folder / "package.json", folder / "package-lock.json"):
        if not destination.resolve().is_relative_to(quality.TOOL_HOME):
            raise RuntimeError(f"Installation path escapes external tool storage: {destination}")
    folder.mkdir(parents=True, exist_ok=True)
    env["npm_config_cache"] = str(cache)
    env["npm_config_maxsockets"] = "1"
    env["npm_config_registry"] = "https://registry.npmjs.org/"
    env["npm_config_include"] = "dev"
    npm = shutil.which("npm", path=env["PATH"])
    node = shutil.which("node", path=env["PATH"])
    if not npm or not node:
        raise RuntimeError("Node.js and npm must already be installed.")
    cacache = Path(npm).resolve().parent.parent / "node_modules/cacache"
    if not (cacache / "package.json").is_file():
        raise RuntimeError(f"Cannot locate npm's public cacache API: {cacache}")
    common = ["--cache", str(cache), "--ignore-scripts", "--no-audit", "--no-fund"]

    def run(arguments, timeout=None):
        command = [npm, *arguments, *common]
        print(shlex.join(command), flush=True)
        subprocess.run(command, cwd=folder, env=env, check=True, timeout=timeout)

    shutil.copy2(quality.CONFIG / "package.json", folder / "package.json")
    lock_path = folder / "package-lock.json"
    if (quality.CONFIG / "package-lock.json").is_file():
        shutil.copy2(quality.CONFIG / "package-lock.json", lock_path)
    lock = read_lock(lock_path)
    if not matches_manifest(lock, manifest):
        if lock is None and lock_path.exists():
            descriptor, backup = tempfile.mkstemp(prefix=".previous-package-lock-", suffix=".json", dir=folder)
            os.close(descriptor)
            lock_path.replace(backup)
            print(f"Preserved unreadable lock at {backup}", flush=True)
        run(["install", "--package-lock-only", "--prefer-offline"], timeout=900)
        lock = read_lock(lock_path)
    if not matches_manifest(lock, manifest):
        raise RuntimeError("Resolved lock does not match the exact quality-tool dependency pins.")

    def inspect_cache():
        result = subprocess.run([node, "-e", CACHE_INSPECTION, str(cacache), str(cache)],
                                input=json.dumps(lock), text=True, stdout=subprocess.PIPE,
                                cwd=folder, env=env, check=True, timeout=300)
        return json.loads(result.stdout)

    inspection = inspect_cache()
    missing = inspection["missing"]
    print(f"Cache: {inspection['required']} required archives, {len(missing)} missing; "
          f"{inspection['skipped']} optional packages excluded for "
          f"{inspection['platform']}/{inspection['arch']}.", flush=True)
    for start in range(0, len(missing), 8):
        batch = missing[start:start + 8]
        print(f"Caching archives {start + 1}-{start + len(batch)} of {len(missing)}", flush=True)
        run(["cache", "add", *(entry["url"] for entry in batch), "--prefer-offline"], timeout=900)
    if missing and inspect_cache()["missing"]:
        raise RuntimeError("Some pinned archives are still missing from cache; offline installation was not started.")
    # npm verifies archive integrity during extraction; hasContent above checks presence only.
    run(["ci", "--offline"])
    subprocess.run([node, str(quality.ROOT / "scripts/quality/check_node_security.cjs"), str(folder)],
                   cwd=folder, env=env, check=True, timeout=120)
    print(f"Installed pinned Node tools offline. Resolved lock: {lock_path}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(getattr(error, "returncode", 1))
