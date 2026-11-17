#!/usr/bin/env python3
"""Rebuild candidate-image assets and write an auditable, image-internal receipt."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

BENCH = Path('/home/frappe/frappe-bench')
SECURITY = Path('/opt/erp-security')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def preserve_asset_snapshot(source):
    """Keep committed asset metadata outside the base image's sites volume."""
    snapshot = SECURITY / 'fresh-sites-assets'
    if snapshot.is_symlink(): raise ValueError('Unexpected linked asset snapshot')
    if snapshot.exists(): shutil.rmtree(snapshot)
    snapshot.mkdir()
    inventory = {}
    for path in sorted(source.rglob('*')):
        relative = path.relative_to(source)
        destination = snapshot / relative
        if path.is_symlink():
            resolved = path.resolve(strict=True)
            if not resolved.is_relative_to(BENCH / 'apps'):
                raise ValueError('Asset link escapes the candidate application sources')
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.symlink_to(str(resolved))
            inventory[str(relative)] = 'link:' + str(resolved)
        elif path.is_dir(): destination.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            if digest(path) != digest(destination): raise ValueError('Asset snapshot copy differs')
            inventory[str(relative)] = digest(destination)
        else: raise ValueError('Unexpected asset metadata file type')
    return inventory


def main():
    lock = json.loads((SECURITY / 'runtime-artifacts.lock.json').read_text())
    inputs = {'runtime-artifacts.lock.json': digest(SECURITY / 'runtime-artifacts.lock.json')}
    apps = (BENCH / 'sites/apps.txt').read_text().splitlines()
    if set(apps) != {'frappe', 'erpnext'}:
        raise ValueError('Only the pinned image applications may enter this asset build')
    for app in apps:
        if not app or '/' in app or app in ('.', '..'):
            raise ValueError('Unexpected app in candidate image')
        for name in ('package.json', 'yarn.lock', 'pyproject.toml'):
            path = BENCH / 'apps' / app / name
            if path.exists():
                inputs[str(path.relative_to(BENCH))] = digest(path)
    for name in ('runtime-image-inputs.json', 'node-remediation-receipt.json'):
        path = SECURITY / name
        if path.exists():
            inputs[name] = digest(path)
    for name in ('package.json', 'yarn.lock'):
        path = BENCH / 'apps/erpnext/banking' / name
        if path.exists():
            inputs[str(path.relative_to(BENCH))] = digest(path)
    command = ['bench', 'build', '--production']
    # Remove generated output in this derived image so success cannot reuse
    # old bundles. Application sources and original legal notices are retained.
    assets = BENCH / 'sites/assets'
    generated = [BENCH / 'apps' / app / app / 'public/dist' for app in apps]
    banking = BENCH / 'apps/erpnext/erpnext/public/banking'
    if (BENCH / 'apps/erpnext/banking/package.json').exists():
        generated.append(banking)
    notices = SECURITY / 'prior-generated-asset-notices'
    for folder in generated:
        if folder.is_symlink() or not folder.resolve().is_relative_to(BENCH / 'apps'):
            raise ValueError('Generated asset directory escapes candidate applications')
        if folder.exists():
            for path in folder.rglob('*'):
                if path.is_file() and any(word in path.name.lower() for word in ('license', 'notice', 'copyright', 'copying')):
                    destination = notices / path.relative_to(BENCH)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, destination)
            shutil.rmtree(folder)
    for name in ('assets.json', 'assets-rtl.json'):
        (assets / name).unlink(missing_ok=True)
    (SECURITY / 'asset-build.json').unlink(missing_ok=True)
    env = dict(os.environ, NODE_OPTIONS='--max-old-space-size=512', GOMAXPROCS='1')
    subprocess.run(['runuser', '-u', 'frappe', '--', *command], cwd=BENCH, env=env, check=True)
    manifests = {}
    outputs = {}
    for name in ('assets.json', 'assets-rtl.json'):
        path = assets / name
        if not path.is_file():
            raise ValueError('Asset build did not create ' + name)
        manifests[name] = digest(path)
        data = json.loads(path.read_text())
        if not data:
            raise ValueError('Empty asset manifest: ' + name)
        for url in data.values():
            if not isinstance(url, str) or not url.startswith('/assets/'):
                raise ValueError('Unexpected asset output URL')
            target = assets / url.removeprefix('/assets/')
            resolved = target.resolve(strict=True)
            if not resolved.is_file() or not any(resolved.is_relative_to(folder) for folder in generated):
                raise ValueError('Asset output is not part of the fresh candidate build')
            outputs[url] = digest(resolved)
    if (BENCH / 'apps/erpnext/banking/package.json').exists():
        if not (banking / 'index.html').is_file():
            raise ValueError('ERPNext custom banking asset build is missing')
    # Include shared chunks, maps and generated resources that main manifests
    # do not list directly, so the seed receipt covers the complete new output.
    for folder in generated:
        app = folder.relative_to(BENCH / 'apps').parts[0]
        for path in sorted(folder.rglob('*')):
            if path.is_file():
                if not path.resolve(strict=True).is_relative_to(folder):
                    raise ValueError('Generated output links outside its fresh directory')
                outputs['/assets/' + app + '/' + str(path.relative_to(folder.parent))] = digest(path)
    snapshot = preserve_asset_snapshot(assets)
    receipt = {'status': 'passed', 'base_image': lock['base_images']['erpnext'],
               'command': command, 'exit_code': 0,
               'source_manifest_sha256': hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest(),
               'inputs': inputs, 'asset_manifests': manifests, 'asset_files': outputs,
               'asset_snapshot_path': '/opt/erp-security/fresh-sites-assets',
               'asset_snapshot': snapshot,
               'prior_generated_outputs_removed': True,
               'ordinary_build_completed': True,
               'scope': 'candidate image only; no existing sites/assets volume mounted'}
    (SECURITY / 'asset-build.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
