#!/usr/bin/env python3
"""Manage retained synthetic-only storage inside the ERP VM; never remove data."""
import json
import os
from pathlib import Path
import re
import stat

ROOT = Path('/var/lib/erp-secure-native')
VOLUMES = {'sites', 'logs', 'db-data', 'redis-cache-data', 'redis-queue-data'}
MARKER = '.erp-secure-native-owner.json'


def ordinary(path):
    for value in [path, *path.parents]:
        if value.is_symlink(): raise ValueError('Linked persistent storage paths are forbidden')


def identity(path, private=False):
    ordinary(path)
    value = path.lstat()
    if not stat.S_ISDIR(value.st_mode): raise ValueError('Persistent storage must be a directory')
    if private and (value.st_uid != 0 or stat.S_IMODE(value.st_mode) != 0o700):
        raise ValueError('Persistent storage root must remain private and root-owned')
    return {'device': value.st_dev, 'inode': value.st_ino}


def storage():
    ordinary(ROOT.parent)
    root_device = ROOT.parent.stat().st_dev
    if root_device == Path('/var/lib/docker').stat().st_dev:
        raise ValueError('Synthetic data must use the partition separate from Docker')
    result = {}
    for name, path in [('persistent', ROOT.parent), ('docker', Path('/var/lib/docker'))]:
        value = os.statvfs(path); result[name] = value.f_bavail*value.f_frsize
    result['memory'] = int(re.search(r'^MemAvailable:\s+(\d+) kB$', Path('/proc/meminfo').read_text(), re.M)[1])*1024
    return result


def verify(token):
    root = identity(ROOT, private=True)
    marker = ROOT/MARKER; ordinary(marker); value = marker.lstat()
    if (not stat.S_ISREG(value.st_mode) or value.st_uid != 0 or value.st_nlink != 1
            or stat.S_IMODE(value.st_mode) != 0o600 or value.st_size > 8192):
        raise ValueError('Persistent storage ownership marker is invalid')
    receipt = json.loads(marker.read_text())
    if (receipt.get('project') != 'erp-secure-native' or receipt.get('site') != 'native-test.localhost'
            or receipt.get('token') != token or receipt.get('root') != root
            or set(receipt.get('volumes', {})) != VOLUMES
            or {path.name for path in ROOT.iterdir()} != VOLUMES | {MARKER}):
        raise ValueError('Refusing unowned or changed persistent synthetic storage')
    for name in VOLUMES:
        current = identity(ROOT/name)
        if current != receipt['volumes'][name] or current['device'] != root['device']:
            raise ValueError('Persistent volume directory identity changed')
    # The named volumes bind these paths elsewhere, never mount over these paths.
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        target = line.split()[4]
        if target == str(ROOT) or target.startswith(str(ROOT)+'/'):
            raise ValueError('Unexpected mounted filesystem inside persistent storage')
    return receipt


def main(request):
    if os.geteuid() != 0: raise ValueError('Require root inside the dedicated ERP VM')
    action = request['action']
    if action == 'storage': return storage()
    token = request.get('token', '')
    if not re.fullmatch('[0-9a-f]{32}', token): raise ValueError('Require the saved exclusive storage token')
    ordinary(ROOT)
    if action == 'create':
        available = storage()
        if available['persistent'] < 900*1024**2 or available['docker'] < 400*1024**2:
            raise RuntimeError('Require500MiB synthetic data reserve plus400MiB free-space floor')
        # Existing directories are verified, never adopted, emptied or replaced.
        if not ROOT.exists():
            ROOT.mkdir(mode=0o700)
            receipt = {'project': 'erp-secure-native', 'site': 'native-test.localhost',
                       'token': token, 'root': identity(ROOT, private=True), 'volumes': {}}
            for name in sorted(VOLUMES):
                (ROOT/name).mkdir(mode=0o755)
                receipt['volumes'][name] = identity(ROOT/name)
            descriptor = os.open(ROOT/MARKER, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'w') as stream:
                json.dump(receipt, stream, sort_keys=True); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
    elif action != 'verify':
        raise ValueError('Only create, verify and storage are supported; retained data is never deleted')
    return {'path': str(ROOT), 'ownership': verify(token), 'free_bytes': storage()}
