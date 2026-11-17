#!/usr/bin/env python3
"""Apply checksum-pinned Node replacements only during an isolated image build.

Every existing package and archive is checked before any replacement. Complete
package directories are replaced so removed upstream files cannot remain active.
The caller must rebuild assets and test the resulting image before activation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import tarfile
import tempfile


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def image_path(root: Path, value: str) -> Path:
    path = PurePosixPath(value)
    approved = value.startswith('/home/frappe/frappe-bench/apps/') and '/node_modules/' in value
    approved |= value.startswith('/home/frappe/.nvm/versions/node/') and '/lib/node_modules/npm/node_modules/' in value
    if not path.is_absolute() or '..' in path.parts or not approved:
        raise ValueError(f'Unapproved image package path: {value}')
    result = root / str(path).lstrip('/')
    if result.is_symlink() or not result.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Package path escapes image root: {value}')
    return result


def check_archive(archive: Path, expected_name: str, expected_version: str) -> None:
    with tarfile.open(archive, 'r:gz') as stream:
        total = 0
        for member in stream.getmembers():
            parts = PurePosixPath(member.name).parts
            if not parts or parts[0] != 'package' or '..' in parts or member.name.startswith('/'):
                raise ValueError(f'Unsafe archive path: {member.name}')
            if member.issym():
                link = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), member.linkname))
                if member.linkname.startswith('/') or not (link == 'package' or link.startswith('package/')):
                    raise ValueError(f'Unsafe archive path in symlink: {member.name}')
            elif not (member.isfile() or member.isdir()):
                raise ValueError(f'Unsupported archive entry: {member.name}')
            total += member.size
            if total > 512 * 1024 * 1024:
                raise ValueError('Archive exceeds the package size limit')
        source = stream.extractfile('package/package.json')
        if source is None:
            raise ValueError('Missing archive package contract')
        package = json.load(source)
        if (package.get('name'), package.get('version')) != (expected_name, expected_version):
            raise ValueError(f'Archive package contract mismatch: {expected_name}')


def install(manifest: dict, payload: Path, root: Path, receipt: Path) -> dict:
    root = root.resolve()
    payload = payload.resolve()
    packages = {item['archive']: item for item in manifest['packages']}
    checked_archives = set()
    planned = []
    patches = []
    removals = []
    targets = set()
    for item in manifest['replacements']:
        target = image_path(root, item['target_path'])
        if target in targets:
            raise ValueError(f'Duplicate package target: {target}')
        if any(target.is_relative_to(other) or other.is_relative_to(target) for other in targets):
            raise ValueError(f'Overlapping package targets: {target}')
        targets.add(target)
        metadata = target / 'package.json'
        if not metadata.is_file() or sha256(metadata) != item['installed_package_sha256']:
            raise ValueError(f'Package preimage mismatch: {item["target_path"]}')
        current = json.loads(metadata.read_text())
        if (current.get('name'), current.get('version')) != (item['package'], item['installed_version']):
            raise ValueError(f'Existing package contract mismatch: {item["target_path"]}')
        name = item['archive']
        if Path(name).name != name:
            raise ValueError('Archive must be a payload basename')
        archive = payload / name
        if not archive.is_file() or sha256(archive) != item['tar_sha256']:
            raise ValueError(f'Archive checksum mismatch: {name}')
        contract = packages[name]
        if (contract['name'], contract['version']) != (item['package'], item['replacement_version']):
            raise ValueError(f'Manifest package contract mismatch: {name}')
        if name not in checked_archives:
            check_archive(archive, contract['name'], contract['version'])
            checked_archives.add(name)
        planned.append((item, target, archive, target.stat()))
    for patch in manifest.get('dependency_manifest_patches', []):
        target = image_path(root, patch['target_path'])
        if target.name != 'package.json' or not target.is_file() or sha256(target) != patch['source_sha256']:
            raise ValueError(f'Dependency manifest preimage mismatch: {patch["target_path"]}')
        metadata = json.loads(target.read_text())
        expected = (patch['name'], patch['original_version'], patch['original_dependency'])
        actual = (metadata.get('name'), metadata.get('version'), metadata.get('dependencies', {}).get(patch['dependency']))
        if actual != expected:
            raise ValueError(f'Dependency package contract mismatch: {patch["target_path"]}')
        metadata['version'] = patch['replacement_version']
        metadata['dependencies'][patch['dependency']] = patch['replacement_dependency']
        metadata['erpSecurityPatch'] = {'reason': patch['reason'], 'sourcePackageSha256': patch['source_sha256']}
        patches.append((target, metadata))
    for item in manifest.get('orphan_package_removals', []):
        target = image_path(root, item['target_path'])
        metadata = target / 'package.json'
        if not metadata.is_file() or sha256(metadata) != item['installed_package_sha256']:
            raise ValueError(f'Orphan package preimage mismatch: {item["target_path"]}')
        current = json.loads(metadata.read_text())
        if (current.get('name'), current.get('version')) != (item['package'], item['installed_version']):
            raise ValueError('Orphan package contract mismatch')
        consumer = item['consumer_replacement']
        if not any(p['package'] == consumer['package'] and p['replacement_version'] == consumer['version'] for p, *_ in planned):
            raise ValueError('Orphan removal requires its former consumer replacement')
        if any(target.is_relative_to(other) or other.is_relative_to(target) for other in targets):
            raise ValueError('Orphan removal overlaps a replacement')
        removals.append(target)

    # Docker discards a failed build layer; never invoke this against a live tree.
    for item, target, archive, owner in planned:
        if sha256(archive) != item['tar_sha256']:
            raise ValueError(f'Archive checksum changed after preflight: {archive.name}')
        with tempfile.TemporaryDirectory(prefix='.erp-node-', dir=target.parent) as temporary:
            staging = Path(temporary)
            with tarfile.open(archive, 'r:gz') as stream:
                stream.extractall(staging, filter='data')
            replacement = staging / 'package'
            if (owner.st_uid, owner.st_gid) != (os.getuid(), os.getgid()):
                for entry in [replacement, *replacement.rglob('*')]:
                    os.chown(entry, owner.st_uid, owner.st_gid, follow_symlinks=False)
            shutil.rmtree(target)
            replacement.rename(target)
    for target, metadata in patches:
        target.write_text(json.dumps(metadata, indent=2) + '\n')
    for target in removals:
        shutil.rmtree(target)
    result = {'replaced': len(planned), 'dependency_manifests_updated': len(patches),
              'orphan_packages_removed': len(removals),
              'browser_assets_rebuilt': False,
              'manifest_sha256': hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
              'packages': [{'path': item['target_path'], 'version': item['replacement_version'],
                            'archive_sha256': item['tar_sha256']} for item, *_ in planned]}
    receipt.parent.mkdir(parents=True, exist_ok=True)
    receipt.write_text(json.dumps(result, indent=2) + '\n')
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--payload-dir', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    if os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1' or os.uname().sysname != 'Linux':
        parser.error('This installer is only for an explicitly marked isolated Linux image build')
    print(json.dumps(install(json.loads(args.manifest.read_text()), args.payload_dir, Path('/'), args.receipt)))


if __name__ == '__main__':
    main()
