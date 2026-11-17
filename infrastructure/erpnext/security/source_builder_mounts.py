"""Bound unused image sites/logs to disposable tmpfs in source builders only."""
import hashlib
import json
from pathlib import Path
import re

DESTINATIONS = ('/home/frappe/frappe-bench/sites', '/home/frappe/frappe-bench/logs')
SIZE = 1024**2


def arguments():
    return [item for destination in DESTINATIONS for item in
        ('--mount', f'type=tmpfs,dst={destination},tmpfs-size={SIZE},tmpfs-mode=0700')]


def validate(info, owned_work=None):
    """Permit only the two tmpfs mounts and curl's separately verified work bind."""
    if owned_work is not None and not re.fullmatch('/tmp/erp-quality-curl-[0-9a-f]{32}', owned_work):
        raise ValueError('Only the verified curl scratch prefix may be bound')
    if set(info.get('declared_volumes') or {}) != set(DESTINATIONS):
        raise ValueError('Unexpected base-image declared volumes')
    host = info['host']
    if host.get('Binds') or host.get('VolumesFrom') or host.get('Tmpfs'):
        raise ValueError('Unreviewed source-builder mount mechanism')
    configured = host.get('Mounts') or []
    expected_count = 2 + (owned_work is not None)
    if len(configured) != expected_count or len(info['mounts']) != expected_count:
        raise ValueError('Unexpected source-builder mount count')
    seen = set()
    for mount in configured:
        target = mount['Target']
        if target in seen: raise ValueError('Duplicate source-builder mount target')
        seen.add(target)
        if target in DESTINATIONS:
            if mount != {'Type': 'tmpfs', 'Target': target, 'TmpfsOptions': {'SizeBytes': SIZE, 'Mode': 0o700}}:
                raise ValueError('Source-builder tmpfs is not exactly bounded/private')
        elif (target != '/security-work' or owned_work is None or mount.get('Type') != 'bind'
                or mount.get('Source') != owned_work or mount.get('ReadOnly', False)
                or mount.get('BindOptions') != {'Propagation': 'rprivate'}
                or set(mount) - {'Type', 'Target', 'Source', 'ReadOnly', 'BindOptions'}):
            raise ValueError('Unexpected source-builder bind')
    actual_targets = set()
    for mount in info['mounts']:
        target = mount['Destination']; actual_targets.add(target)
        if mount.get('Name') or mount.get('RW') is not True:
            raise ValueError('Persistent or read-only source-builder mount is unexpected')
        if target in DESTINATIONS:
            if mount['Type'] != 'tmpfs' or mount.get('Source'):
                raise ValueError('Declared application paths must use disposable tmpfs')
        elif (target != '/security-work' or owned_work is None or mount['Type'] != 'bind'
                or mount.get('Source') != owned_work or mount.get('Propagation') != 'rprivate'):
            raise ValueError('Unexpected source-builder actual mount')
    if actual_targets != seen: raise ValueError('Configured and actual source-builder mounts differ')
    return {'disposable_tmpfs': [{'destination': path, 'size_bytes': SIZE, 'mode': '0700'} for path in DESTINATIONS],
            'actual_mounts': info['mounts'], 'configured_mounts': configured,
            'mount_guard_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


def inspect(command, container, owned_work=None):
    template = '{"mounts":{{json .Mounts}},"declared_volumes":{{json .Config.Volumes}},"host":{"Mounts":{{json (index .HostConfig "Mounts")}},"Binds":{{json (index .HostConfig "Binds")}},"VolumesFrom":{{json (index .HostConfig "VolumesFrom")}},"Tmpfs":{{json (index .HostConfig "Tmpfs")}}}}'
    return validate(json.loads(command('inspect', '--format', template, container)), owned_work)
