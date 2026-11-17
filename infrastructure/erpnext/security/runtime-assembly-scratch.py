#!/usr/bin/env python3
"""Manage only identity-checked, disposable image-build scratch in the ERP VM."""
import json
import os
from pathlib import Path
import re
import shutil
import stat


def scratch_path(token):
    if not isinstance(token, str) or not re.fullmatch('[0-9a-f]{32}', token):
        raise ValueError('Require an exclusive scratch identifier')
    return Path('/tmp/erp-quality-assembly-'+token)


def storage():
    paths = {'scratch': Path('/tmp'), 'docker': Path('/var/lib/docker')}
    if paths['scratch'].stat().st_dev == paths['docker'].stat().st_dev:
        raise RuntimeError('Build inputs must use a filesystem separate from Docker')
    result = {name: os.statvfs(path).f_bavail*os.statvfs(path).f_frsize for name, path in paths.items()}
    result['memory'] = int(re.search(r'^MemAvailable:\s+(\d+) kB$', Path('/proc/meminfo').read_text(), re.M)[1])*1024
    return result


def identity(path):
    value = path.lstat()
    if not stat.S_ISDIR(value.st_mode) or value.st_uid != 0 or stat.S_IMODE(value.st_mode) != 0o700:
        raise ValueError('Scratch must be an exclusive root-owned directory')
    return {'device': value.st_dev, 'inode': value.st_ino, 'uid': value.st_uid}


def validate(path, token, expected):
    if path != scratch_path(token) or path.resolve() != path or identity(path) != expected:
        raise ValueError('Scratch directory identity changed')
    marker = path/'.erp-quality-owner'; value = marker.lstat()
    if (not stat.S_ISREG(value.st_mode) or value.st_uid != 0 or value.st_nlink != 1
            or marker.read_text() != token+'\n'):
        raise ValueError('Scratch marker ownership changed')


def main(request):
    if os.geteuid() != 0 or Path('/tmp').resolve() != Path('/tmp'):
        raise RuntimeError('Require root inside the ERP VM and an ordinary /tmp')
    if request['action'] == 'storage': return storage()
    token = request['token']; path = scratch_path(token)
    if request['action'] == 'create':
        available = storage()
        if available['scratch'] < 800*1024**2 or available['docker'] < 1400*1024**2 or available['memory'] < 1200*1024**2:
            raise RuntimeError('Require800MiB root disk,1400MiB Docker disk and1200MiB available RAM')
        path.mkdir(mode=0o700)
        marker = path/'.erp-quality-owner'
        with marker.open('x') as stream: stream.write(token+'\n')
        marker.chmod(0o600)
        for name in ('inputs', 'sites', 'logs'): (path/name).mkdir(mode=0o755)
        return {'path': str(path), 'token': token, 'identity': identity(path), 'free_bytes': available}
    validate(path, token, request['identity'])
    if request['action'] == 'verify': return {'verified': str(path), 'free_bytes': storage()}
    if request['action'] != 'remove': raise ValueError('Unexpected scratch action')
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        target = line.split()[4]
        if target == str(path) or target.startswith(str(path)+'/'):
            raise ValueError('Scratch still contains a mounted filesystem')
    if request.get('containers_detached') is not True or not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError('Require detached containers and symlink-safe cleanup')
    shutil.rmtree(path)
    return {'removed': str(path)}
