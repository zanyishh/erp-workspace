#!/usr/bin/env python3
"""Plan or explicitly grow only the ERP data disk from 8 to 12 GiB. GPL-3.0."""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / 'infrastructure/erpnext/compose.yaml'
COLIMA = Path.home() / '.colima'
ENDPOINT = 'unix://' + str(COLIMA / 'erp/docker.sock')
DISK = COLIMA / '_lima/_disks/colima-erp/datadisk'
DOCKER = ['docker', '--context', 'colima-erp']
GIB = 2**30
MIN_FREE = math.ceil(2.4 * GIB)
LAUNCHERS = ['erpnext.command', 'setup-native-test.command', 'setup-customer-workspace.command']
SERVICES = {'erp-baseline': set('backend configurator create-site db frontend native-test-backend native-test-frontend customer-frontend queue-long queue-short redis-queue redis-cache scheduler websocket'.split()),
            'erp-secure-native': set('asset-seed initializer db redis-cache redis-queue native-test-backend websocket worker native-test-frontend'.split())}
CONTAINER_FORMAT = '''{"id":{{json .Id}},"name":{{json .Name}},"image":{{json .Image}},"project":{{json (index .Config.Labels "com.docker.compose.project")}},"service":{{json (index .Config.Labels "com.docker.compose.service")}},"config_files":{{json (index .Config.Labels "com.docker.compose.project.config_files")}},"running":{{json .State.Running}},"paused":{{json .State.Paused}},"restarting":{{json .State.Restarting}},"dead":{{json .State.Dead}},"health":{{with index .State "Health"}}{{json .Status}}{{else}}null{{end}},"restart_policy":{{json .HostConfig.RestartPolicy}},"mounts":{{json .Mounts}}}'''
VOLUME_FORMAT = '''{"Name":{{json .Name}},"Driver":{{json .Driver}},"Scope":{{json .Scope}},"Mountpoint":{{json .Mountpoint}},"CreatedAt":{{json .CreatedAt}},"Labels":{{json .Labels}}}'''
GUEST_PROBE = """import json,os,pathlib
d=os.statvfs('/var/lib/docker');r=os.statvfs('/')
print(json.dumps({'device_bytes':int(pathlib.Path('/sys/class/block/vdb/size').read_text())*512,
'partition_bytes':int(pathlib.Path('/sys/class/block/vdb1/size').read_text())*512,
'docker_total':d.f_blocks*d.f_frsize,'docker_free':d.f_bavail*d.f_frsize,'root_total':r.f_blocks*r.f_frsize}))
"""


def guard(state, free, activities, launchers_ready):
    expected = {'profile': 'erp', 'context': 'colima-erp', 'endpoint': ENDPOINT, 'cpu': 2,
        'memory': 3*GIB, 'root_disk': 4*GIB, 'disk': 8*GIB, 'vm_type': 'vz',
        'runtime': 'docker', 'disk_format': 'raw', 'disk_instance': 'colima-erp', 'configured_disk': 8,
        'driver': 'macOS Virtualization.Framework'}
    if any(state.get(key) != value for key, value in expected.items()):
        raise RuntimeError('Only the existing erp/colima-erp, CPU2/RAM3/root4/VZ, raw8GiB data disk is supported')
    for item in state['containers']:
        config = {'erp-baseline': str(COMPOSE), 'erp-secure-native': str(ROOT / 'infrastructure/erpnext/compose.security-native.yaml')}
        if (item['project'] not in config or item['config_files'] != config[item['project']]
                or item['service'] not in SERVICES[item['project']] or item['paused'] or item['restarting'] or item['dead']):
            raise RuntimeError('Unknown container/project or unstable container state; no service may be interrupted')
    if free < MIN_FREE:
        raise RuntimeError('Host free space must be at least 2.4 GiB before maintenance')
    if activities:
        raise RuntimeError('Tests/builds are active; finish them before maintenance: ' + ', '.join(activities))
    if not launchers_ready:
        raise RuntimeError('Update all three existing launchers together to --disk 12 on the approved path first')


def ordered_groups(containers, *, starting=False):
    groups = [[], [], []]
    for item in containers:
        if item['running']:
            role = 2 if item['service'] == 'db' else 1 if item['service'].startswith('redis-') else 0
            groups[role].append(item['id'])
    return [group for group in (reversed(groups) if starting else groups) if group]


def same_identities(before, after):
    def immutable(state):
        return {'daemon_id': state['daemon_id'], 'data_disk_identity': state['data_disk_identity'],
            'volumes': sorted(state['volumes'], key=lambda x: x['Name']),
            'containers': {item['id']: {k: v for k, v in item.items() if k not in {'running', 'health', 'paused', 'restarting', 'dead'}}
                           for item in state['containers']}}
    if immutable(before) != immutable(after):
        raise RuntimeError('Container/image/restart-policy/mount or volume identity changed; refusing to adopt replacements')


def restore(before, now, action):
    same_identities(before, now)
    wanted = {item['id'] for item in before['containers'] if item['running']}
    active = {item['id'] for item in now['containers'] if item['running']}
    extras = [item for item in now['containers'] if item['id'] in active - wanted]
    for group in ordered_groups(extras): action('stop', group)
    missing = [item for item in before['containers'] if item['id'] in wanted - active]
    for group in ordered_groups(missing, starting=True): action('start', group)


def busy_command(command):
    return bool(re.search(r'\b(?:pytest|unittest|run-tests|make|gmake|ninja)\b|\bflutter\s+(?:test|build)\b|\bcmake\b.*--build|\bdocker\b.*\bexec\b|(?:run-android-apk|run-mobsf-apk|runtime-image-controller|native_target|test_[A-Za-z0-9_]+)\.py\b', command))


def run(args, *, data=None, timeout=90):
    env = {k: v for k, v in os.environ.items() if k not in {'DOCKER_HOST', 'DOCKER_CONTEXT', 'COLIMA_PROFILE'}}
    env.update(COLIMA_HOME=str(COLIMA), LIMA_HOME=str(COLIMA / '_lima'))
    result = subprocess.run(args, input=data, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, cwd=ROOT, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Maintenance command failed: ' + ' '.join(args[:4]))
    return result.stdout.strip()


def inventory():
    status = json.loads(run(['colima', 'status', '--profile', 'erp', '--json']))
    disk = json.loads(run(['limactl', 'disk', 'list', '--json', 'colima-erp']))
    endpoint = json.loads(run(DOCKER + ['context', 'inspect', 'colima-erp', '--format', '{{json .Endpoints.docker.Host}}']))
    ids = run(DOCKER + ['ps', '-aq', '--no-trunc']).split()
    containers = [json.loads(line) for line in run(DOCKER + ['inspect', '--format', CONTAINER_FORMAT, *ids]).splitlines()] if ids else []
    volumes = run(DOCKER + ['volume', 'ls', '-q']).split()
    volumes = [json.loads(line) for line in run(DOCKER + ['volume', 'inspect', '--format', VOLUME_FORMAT, *volumes]).splitlines()] if volumes else []
    config = (COLIMA / 'erp/colima.yaml').read_text()
    vm_type = re.search(r'^vmType:\s*(\S+)', config, re.M).group(1)
    return {'profile': 'erp', 'context': 'colima-erp', 'endpoint': endpoint,
        'cpu': status['cpu'], 'memory': status['memory'], 'disk': disk['size'],
        'root_disk': (COLIMA / '_lima/colima-erp/disk').stat().st_size,
        'vm_type': vm_type, 'driver': status['driver'], 'configured_disk': int(re.search(r'^disk:\s*(\d+)', config, re.M).group(1)),
        'data_disk_identity': [DISK.stat().st_dev, DISK.stat().st_ino],
        'runtime': status['runtime'], 'disk_format': disk['format'],
        'disk_instance': disk['instance'], 'daemon_id': run(DOCKER + ['info', '--format', '{{.ID}}']),
        'containers': containers, 'volumes': volumes,
        'db_volume_names': sorted({m['Name'] for c in containers for m in c['mounts']
                if m['Type'] == 'volume' and m['Destination'] in {'/var/lib/mysql', '/var/lib/postgresql/data'}}),
        'guest': json.loads(run(['colima', 'ssh', '--profile', 'erp', '--', 'sudo', 'python3', '-'], data=GUEST_PROBE))}


def activities(state):
    found = []
    # Process arguments stay in memory; reports contain only process IDs/container IDs.
    for line in run(['/bin/ps', '-axo', 'pid=,command=']).splitlines():
        pid, _, command = line.strip().partition(' ')
        if pid != str(os.getpid()) and busy_command(command): found.append('host-process-' + pid)
    for item in state['containers']:
        if item['running']:
            commands = run(DOCKER + ['top', item['id'], '-eo', 'pid,args'])
            if any(busy_command(line) for line in commands.splitlines()[1:]): found.append('container-' + item['id'][:12])
    return found


def launchers_ready():
    for name in LAUNCHERS:
        path = ROOT / 'scripts' / name
        if path.is_symlink() or re.findall(r'--disk\s+(\d+)', path.read_text()) != ['12']:
            return False
    return True


def start_vm(size):
    if size not in {8, 12}: raise RuntimeError('Recovery encountered an unexpected disk size')
    run(['colima', 'start', '--profile', 'erp', '--cpu', '2', '--memory', '3', '--disk', str(size),
         '--root-disk', '4', '--vm-type', 'vz', '--activate=false', '--ssh-config=false'], timeout=240)


def container_action(verb, ids):
    # Bound the client wait without scheduling SIGKILL against retained databases.
    run(DOCKER + ([verb, '--time', '-1', *ids] if verb == 'stop' else [verb, *ids]), timeout=180)
    if verb == 'start':
        deadline = time.monotonic() + 120
        while True:
            status = [json.loads(line) for line in run(DOCKER + ['inspect', '--format', CONTAINER_FORMAT, *ids]).splitlines()]
            if all(c['running'] and c['health'] in {None, 'healthy'} for c in status): return
            if time.monotonic() >= deadline: raise RuntimeError('Restored containers did not become ready')
            time.sleep(2)


def validate_after(before, after):
    same_identities(before, after)
    for key in ['profile', 'context', 'endpoint', 'cpu', 'memory', 'root_disk', 'vm_type', 'driver', 'runtime', 'disk_format', 'disk_instance']:
        if before[key] != after[key]: raise RuntimeError('VM setting changed unexpectedly: ' + key)
    if (after['disk'] != 12*GIB or after['configured_disk'] != 12 or after['guest']['device_bytes'] != 12*GIB
            or after['guest']['partition_bytes'] < 11*GIB or after['guest']['docker_total'] < 11*GIB):
        raise RuntimeError('Data disk, partition or filesystem did not grow to the expected capacity')
    if {c['id']: c['running'] for c in before['containers']} != {c['id']: c['running'] for c in after['containers']}:
        raise RuntimeError('Original container running/stopped states were not restored')
    if any(c['paused'] or c['restarting'] or c['dead'] for c in after['containers']):
        raise RuntimeError('Restored containers have an unstable or paused state')


def maintain(before, report, save):
    report.update(status='stopping', before=before); save(report)
    try:
        for group in ordered_groups(before['containers']): container_action('stop', group)
        stopped = inventory(); same_identities(before, stopped)
        if any(c['running'] for c in stopped['containers']): raise RuntimeError('A container remained running; VM preserved')
        run(['colima', 'stop', '--profile', 'erp'], timeout=180)
        report['status'] = 'starting-with-12GiB'; save(report)
        start_vm(12)
        current = inventory()
        restore(before, current, container_action)
        report['after'] = inventory()
        validate_after(before, report['after'])
        report['status'] = 'completed-12GiB-data-retained'
    except BaseException as error:
        report.update(status='failed', reason=str(error))
        try:
            try:
                current = inventory()
            except Exception:
                # The actual image size decides recovery; never request a shrink.
                actual_size = DISK.stat().st_size
                if actual_size not in {8*GIB, 12*GIB}: raise RuntimeError('Unexpected actual disk size; manual recovery required')
                start_vm(actual_size // GIB)
                current = inventory()
            restore(before, current, container_action)
            report['recovered'] = inventory()
            same_identities(before, report['recovered'])
            report['original_running_states_restored'] = ({c['id']: c['running'] for c in before['containers']} ==
                {c['id']: c['running'] for c in report['recovered']['containers']})
        except BaseException as recovery_error:
            report['recovery_error'] = str(recovery_error)
        raise
    finally:
        report['finished_at'] = datetime.now(timezone.utc).isoformat(); save(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='Permanently grow8->12GiB and briefly stop/restore local ERP services')
    parser.add_argument('--snapshot', type=Path, help='Save selected metadata only inside this workspace .local directory')
    args = parser.parse_args()
    before = inventory()
    free = shutil.disk_usage(DISK).free
    jobs = activities(before)
    blockers = []
    try: guard(before, free, jobs, launchers_ready())
    except RuntimeError as error: blockers.append(str(error))
    report = {'status': 'read-only-plan', 'recorded_at': datetime.now(timezone.utc).isoformat(),
        'before': before, 'host_free_bytes': free, 'minimum_host_free_bytes': MIN_FREE,
        'activities': jobs, 'launchers_ready_for_12GiB': launchers_ready(), 'blockers': blockers,
        'stop_groups': ordered_groups(before['containers']),
        'restore_groups': ordered_groups(before['containers'], starting=True),
        'operation': 'Permanent raw8->12GiB ERP data-disk growth; CPU2/RAM3/root4/VZ unchanged. No shrink, deletion or data migration. Brief interruption includes currently running localhost services.',
        'execute_command': 'scripts/erp-vm-storage.command --execute'}
    target = args.snapshot
    if args.execute:
        if blockers: raise RuntimeError(blockers[0])
        # Repeat the live inventory/activity gate immediately before any mutation.
        fresh = inventory(); guard(fresh, shutil.disk_usage(DISK).free, activities(fresh), launchers_ready())
        same_identities(before, fresh)
        if {c['id']: c['running'] for c in before['containers']} != {c['id']: c['running'] for c in fresh['containers']}:
            raise RuntimeError('Service state changed during preflight; retry only after other work is finished')
        target = target or ROOT / '.local/quality/vm-storage' / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    if target:
        target = target.absolute()
        if not target.resolve().is_relative_to(ROOT / '.local') or any(p.is_symlink() for p in [target, *target.parents]):
            raise RuntimeError('Receipt path must be an ordinary path inside this workspace .local directory')
        if target.exists(): raise RuntimeError('Receipt already exists; preserve previous evidence')
        target.parent.mkdir(parents=True, exist_ok=True)
    def save(value):
        if target:
            with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600), 'w') as output:
                json.dump(value, output, indent=2); output.write('\n')
    if args.execute: maintain(before, report, save)
    else: save(report)
    print(json.dumps({k: report[k] for k in ['status', 'host_free_bytes', 'minimum_host_free_bytes', 'activities', 'launchers_ready_for_12GiB', 'blockers', 'operation', 'execute_command']} |
        {'containers': len(before['containers']), 'running': sum(c['running'] for c in before['containers']),
         'volumes': len(before['volumes']), 'db_volume_names': before['db_volume_names'], 'snapshot': str(target) if target else None}, indent=2))


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print('ERP storage maintenance refused/failed: ' + str(error), file=sys.stderr); raise SystemExit(1)
