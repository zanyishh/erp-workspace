#!/usr/bin/env python3
"""Replace the pinned Node runtime inside an isolated candidate, preserving npm."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile

TARGET_ROOT = Path('/')
LEGACY = '/home/frappe/.nvm/versions/node/v24.22.2'
PREFIX = 'node-v24.22.3-linux-arm64'
FIXED_FILES = {'bin/node', 'share/man/man1/node.1', 'LICENSE', 'README.md', 'CHANGELOG.md'}
NOTICES = ('LICENSE', 'README.md', 'CHANGELOG.md')
MIB = 1024**2


def bytes_digest(value):
    return hashlib.sha256(value).hexdigest()


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(MIB), b''): value.update(block)
    return value.hexdigest()


def ordinary(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Refuse linked runtime or evidence paths: '+str(path))
    return path


def directory_metadata(path):
    st = ordinary(path).stat()
    return {'uid': st.st_uid, 'gid': st.st_gid, 'mode': st.st_mode & 0o777}


def file_metadata(path):
    ordinary(path)
    if not path.is_file(): raise ValueError('Require an ordinary runtime file: '+str(path))
    return dict(directory_metadata(path), bytes=path.stat().st_size, sha256=digest(path))


def selected_file(name):
    path = PurePosixPath(name)
    return (not path.is_absolute() and '..' not in path.parts and str(path) == name
            and (name in FIXED_FILES or name.startswith('include/node/')))


def selected_directory(name):
    path = PurePosixPath(name)
    return (not path.is_absolute() and '..' not in path.parts and str(path) == name
            and (name in {'bin', 'include', 'include/node', 'share', 'share/man', 'share/man/man1'}
                 or name.startswith('include/node/')))


def require_candidate():
    if (os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1' or os.geteuid() != 0
            or platform.system() != 'Linux' or platform.machine() != 'aarch64'):
        raise RuntimeError('Install only inside the isolated candidate Linux ARM64 build')


def runtime_info(binary):
    value = subprocess.check_output([str(binary), '-p',
        "JSON.stringify({node:process.versions.node,modules:process.versions.modules,sqlite:process.versions.sqlite,platform:process.platform,arch:process.arch})"],
        text=True, timeout=30)
    return json.loads(value)


def require_info(actual, expected, label):
    if any(actual.get(key) != value for key, value in expected.items()):
        raise ValueError('Node '+label+' differs from the pinned runtime')


def header_version(path, expected):
    text = path.read_text()
    found = []
    for part in ('MAJOR', 'MINOR', 'PATCH'):
        values = re.findall(r'^#\s*define\s+NODE_'+part+r'_VERSION\s+(\d+)\s*$', text, re.M)
        if len(values) != 1: raise ValueError('Ambiguous Node header version')
        found.append(values[0])
    if '.'.join(found) != expected: raise ValueError('Node header version differs from the binary contract')


def archive_inventory(archive_path, lock):
    if lock.get('status') != 'verified-inputs-runtime-validation-pending' or lock.get('legacy_root') != LEGACY:
        raise ValueError('Require verified Node inputs and exact legacy runtime location')
    ordinary(archive_path)
    if (not archive_path.is_file() or archive_path.stat().st_size != lock['archive']['bytes']
            or digest(archive_path) != lock['archive']['sha256']):
        raise ValueError('Official Node archive checksum/size mismatch')
    expected = lock['replacement_files']
    if (not FIXED_FILES | {'include/node/node.h', 'include/node/node_version.h'} <= set(expected)
            or any(not selected_file(name) for name in expected)):
        raise ValueError('Invalid selective Node replacement inventory')
    seen = set(); selected = {}; expanded = 0
    with tarfile.open(archive_path) as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or '..' in name.parts or not name.parts or name.parts[0] != PREFIX
                    or member.name.rstrip('/') != str(name) or str(name) in seen or len(seen) >= 40000):
                raise ValueError('Unexpected or duplicate Node archive path')
            seen.add(str(name))
            expanded += member.size
            if expanded > 600*MIB: raise ValueError('Node archive exceeds its expanded size bound')
            relative = '/'.join(name.parts[1:])
            if member.isdir(): continue
            if selected_file(relative):
                if not member.isfile() or member.size <= 0 or member.mode & 0o7000:
                    raise ValueError('Selected Node archive member must be an ordinary nonempty file')
                if relative not in expected: raise ValueError('Unexpected selected Node archive member')
                info = expected[relative]
                if member.size != info['bytes'] or member.mode & 0o777 != info['mode']:
                    raise ValueError('Node archive member metadata differs')
                selected[relative] = member.name
    if set(selected) != set(expected): raise ValueError('Missing selected Node archive files')
    return selected


def preflight_target(target, lock):
    ordinary(target)
    before = lock['baseline_files']
    if (not FIXED_FILES | {'include/node/node.h', 'include/node/node_version.h'} <= set(before)
            or any(not selected_file(name) for name in before)):
        raise ValueError('Invalid baseline Node inventory')
    headers = target/'include/node'
    actual = set()
    for path in headers.rglob('*'):
        ordinary(path)
        if path.is_file(): actual.add(str(path.relative_to(target)))
        elif not path.is_dir(): raise ValueError('Unexpected special header file')
    if actual != {name for name in before if name.startswith('include/node/')}:
        raise ValueError('Baseline Node header inventory changed')
    for name, expected in before.items():
        if file_metadata(target/name) != expected: raise ValueError('Node file preimage changed: '+name)
    for name, expected in lock['baseline_directories'].items():
        if not selected_directory(name) or directory_metadata(target/name) != expected:
            raise ValueError('Node directory preimage changed: '+name)
    if 'include/node' not in lock['baseline_directories']:
        raise ValueError('Require exact baseline header directory metadata')
    header_version(target/'include/node/node_version.h', lock['before']['node'])
    before_info = runtime_info(target/'bin/node')
    require_info(before_info, lock['before'], 'runtime preimage')
    return before_info


def install(lock, archive_path, output):
    require_candidate()
    selected = archive_inventory(archive_path, lock)
    target = TARGET_ROOT/LEGACY.lstrip('/')
    before_info = preflight_target(target, lock)
    ordinary(output)
    if output.exists(): raise ValueError('Require new Node install evidence directory')
    header_owner = lock['baseline_directories']['include/node']
    # Stage every selected official file and verify all bytes before touching
    # the candidate runtime. Archive npm/yarn/global packages are never read.
    with tempfile.TemporaryDirectory(prefix='.erp-node-', dir=target) as temporary:
        stage = Path(temporary)
        with tarfile.open(archive_path) as archive:
            for name, member_name in selected.items():
                destination = stage/name; destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member_name) as source, destination.open('xb') as sink:
                    shutil.copyfileobj(source, sink, MIB)
                if digest(destination) != lock['replacement_files'][name]['sha256']:
                    raise ValueError('Official Node file checksum mismatch: '+name)
                old = lock['baseline_files'].get(name)
                destination.chmod(old['mode'] if old else lock['replacement_files'][name]['mode'])
                owner = old or header_owner
                os.chown(destination, owner['uid'], owner['gid'])
        for path in sorted((stage/'include/node').rglob('*')) + [stage/'include/node']:
            if path.is_dir():
                name = str(path.relative_to(stage)); old = lock['baseline_directories'].get(name, header_owner)
                path.chmod(old['mode']); os.chown(path, old['uid'], old['gid'])
        header_version(stage/'include/node/node_version.h', lock['after']['node'])
        output.mkdir(parents=True, mode=0o755)
        (output/'prior-notices').mkdir()
        for name in NOTICES: shutil.copy2(target/name, output/'prior-notices'/name)
        # A failed candidate is never committed. Retain only old notices, not
        # old executable code, in the image's permanent evidence directory.
        # Removing this fully verified candidate-only tree avoids renaming a
        # lower-layer directory (which overlayfs can reject with EXDEV). The
        # original tree remains in the immutable baseline image.
        shutil.rmtree(target/'include/node')
        (stage/'include/node').rename(target/'include/node')
        for name in sorted(FIXED_FILES): (stage/name).replace(target/name)
    installed = {}
    for name, expected in lock['replacement_files'].items():
        info = file_metadata(target/name)
        if info['sha256'] != expected['sha256'] or info['bytes'] != expected['bytes']:
            raise ValueError('Installed Node bytes differ from the official archive')
        installed[name] = info
    actual_headers = {str(path.relative_to(target)) for path in (target/'include/node').rglob('*') if path.is_file()}
    if actual_headers != {name for name in installed if name.startswith('include/node/')}:
        raise ValueError('Installed Node header inventory differs')
    after_info = runtime_info(target/'bin/node')
    require_info(after_info, lock['after'], 'updated runtime')
    (output/'receipt.json').write_text(json.dumps({'status': 'installed-ordinary-runtime-tests-pending',
        'legacy_root': LEGACY, 'archive': lock['archive'], 'before': before_info, 'after': after_info,
        'installed': installed, 'prior_notice_hashes': {name: digest(output/'prior-notices'/name) for name in NOTICES},
        'npm_yarn_global_package_trees': 'outside the replacement scope'}, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads(Path(__file__).with_name('node-runtime.lock.json').read_text())
    install(lock, args.archive, args.output)


if __name__ == '__main__': main()
