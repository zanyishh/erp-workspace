#!/usr/bin/env python3
"""Manage only one identity-checked curl build folder in the ERP VM's /tmp."""
import json
import os
from pathlib import Path
import re
import shutil
import stat


def scratch_path(token):
    if not isinstance(token, str) or not re.fullmatch(r'[0-9a-f]{32}', token):
        raise ValueError('Require a fresh 32-character scratch identifier')
    return Path('/tmp/erp-quality-curl-' + token)


def storage():
    paths = {'scratch': Path('/tmp'), 'docker': Path('/var/lib/docker')}
    if paths['scratch'].stat().st_dev == paths['docker'].stat().st_dev:
        raise RuntimeError('Scratch must use a different filesystem from Docker')
    return {name: os.statvfs(path).f_bavail * os.statvfs(path).f_frsize
            for name, path in paths.items()}


def identity(path):
    value = path.lstat()
    if not stat.S_ISDIR(value.st_mode) or value.st_uid != 0:
        raise ValueError('Scratch must be a root-owned directory, never a symlink')
    if stat.S_IMODE(value.st_mode) != 0o700:
        raise ValueError('Scratch directory permissions changed')
    return {'device': value.st_dev, 'inode': value.st_ino, 'uid': value.st_uid}


def validate(path, token, expected):
    if path != scratch_path(token) or path.resolve() != path:
        raise ValueError('Scratch path changed')
    if identity(path) != expected:
        raise ValueError('Scratch directory identity changed')
    marker = path / '.erp-quality-owner'
    value = marker.lstat()
    if not stat.S_ISREG(value.st_mode) or value.st_uid != 0 or value.st_nlink != 1:
        raise ValueError('Scratch ownership marker is not an exclusive regular file')
    if marker.read_text() != token + '\n':
        raise ValueError('Scratch ownership marker changed')


def reject_nested_mounts(path, mountinfo):
    # Our generated path contains no mountinfo escape characters.
    for line in mountinfo.splitlines():
        target = line.split()[4]
        if target == str(path) or target.startswith(str(path) + '/'):
            raise ValueError('Scratch contains a mount; manual inspection required')


def main(request):
    if os.geteuid() != 0 or Path('/tmp').resolve() != Path('/tmp'):
        raise RuntimeError('Require root in the ERP VM and a real /tmp directory')
    action = request['action']
    if action == 'storage':
        result = storage()
    else:
        token = request['token']
        path = scratch_path(token)
        if action == 'create':
            available = storage()
            if available['scratch'] < 1400 * 1024**2 or available['docker'] < 1000 * 1024**2:
                raise RuntimeError('Need 1400MiB scratch and 1000MiB Docker free before creation')
            path.mkdir(mode=0o700)
            marker = path / '.erp-quality-owner'
            with marker.open('x') as stream:
                stream.write(token + '\n')
            marker.chmod(0o600)
            result = {'path': str(path), 'token': token, 'identity': identity(path), 'free_bytes': available}
        elif action == 'remove':
            validate(path, token, request['identity'])
            reject_nested_mounts(path, Path('/proc/self/mountinfo').read_text())
            if request.get('containers_detached') is not True or not shutil.rmtree.avoids_symlink_attacks:
                raise RuntimeError('Require detached containers and symlink-safe deletion')
            shutil.rmtree(path)
            result = {'removed': str(path)}
        else:
            raise ValueError('Unknown scratch action')
    print(json.dumps(result))
