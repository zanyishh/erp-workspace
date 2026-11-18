#!/usr/bin/env python3
"""Build/test the locked lxml wheel in an owned container; never activate services."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import time

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY))
import source_builder_mounts
import lxml_recovery
DOCKER = ['docker', '--context', 'colima-erp']
NAME = 'erp-quality-lxml-security-builder'
MIB = 1024**2
HELPERS = ('build-lxml.sh', 'build-lxml-inside.py', 'lxml-offline-setup.py',
           'lxml-ordinary-compatibility.py', 'lxml-artifacts.lock.json',
           'lxml_recovery.py', 'lxml-recovery.lock.json')


def command(*args):
    return subprocess.check_output(DOCKER+list(args), text=True, stderr=subprocess.STDOUT, timeout=60).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_inputs(directory, lock):
    if any(path.is_symlink() for path in (directory, *directory.parents)):
        raise ValueError('Input directory must not use symbolic links')
    entries = lock['sources']+lock['build_test_wheels']
    for entry in entries:
        if Path(entry['filename']).name != entry['filename']:
            raise ValueError('Unsafe locked artifact name')
        path = directory/entry['filename']
        if path.is_symlink() or not path.is_file() or path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
            raise ValueError('Locked artifact checksum/size differs: '+entry['filename'])
        if entry in lock['sources']:
            with tarfile.open(path) as archive:
                members = archive.getmembers()
                if len(members) > 6000 or sum(m.size for m in members) > 60*MIB:
                    raise ValueError('Source archive exceeds its bounded size')
                for member in members:
                    name = PurePosixPath(member.name)
                    if (name.is_absolute() or '..' in name.parts or not name.parts
                            or name.parts[0] != entry['name']+'-'+entry['version']
                            or not (member.isfile() or member.isdir())):
                        raise ValueError('Unexpected source archive member')
    return entries


def finish_container(container, output, receipt, evidence_copied):
    try:
        if command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            command('stop', '--time', '5', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'stop', 'error': str(error)})
        receipt['container_retained'] = container
        return
    if not evidence_copied:
        try:
            command('cp', container+':/security-output/.', str(output))
        except (OSError, subprocess.SubprocessError) as error:
            receipt.setdefault('cleanup_errors', []).append({'action': 'copy-evidence', 'error': str(error)})
            receipt['container_retained'] = container
            return
    try:
        command('rm', '-f', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'remove-container', 'error': str(error)})
        receipt['container_retained'] = container


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--recover-from', type=Path)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    if not args.execute:
        print('Plan only: hash-check official sources/wheels, create a bounded isolated builder, install compiler packages, disconnect its network, build and run complete upstream tests, retain wheel/receipts/relink files, remove only the owned container. No application service changes.')
        return 0
    if not args.inputs or not args.output: parser.error('--inputs and --output are required')
    source, output = args.inputs.absolute(), args.output.absolute()
    lock = json.loads((DIRECTORY/'lxml-artifacts.lock.json').read_text())
    entries = verify_inputs(source, lock)
    recovery_lock = json.loads((DIRECTORY/'lxml-recovery.lock.json').read_text())
    recovery = (lxml_recovery.verify(args.recover_from.absolute(), recovery_lock,
                digest(DIRECTORY/'lxml-artifacts.lock.json')) if args.recover_from else None)
    if output.exists() or any(path.is_symlink() for path in output.parents):
        raise ValueError('Require a new ordinary output directory')
    if shutil.disk_usage('/private/tmp').free < 700*MIB:
        raise RuntimeError('Need at least700MiB host free before the guarded build')
    if subprocess.run(DOCKER+['container', 'inspect', NAME], capture_output=True).returncode == 0:
        raise RuntimeError('Owned builder name already exists; no container was changed')
    base = json.loads(command('image', 'inspect', '--format', '{{json .}}', lock['base_image']))
    if base['Architecture'] != 'arm64' or base['Os'] != 'linux': raise ValueError('Unexpected base platform')
    if recovery and base['Id'] != recovery_lock['base_id']:
        raise ValueError('Recovery requires the exact original base image identity')
    output.mkdir(parents=True, mode=0o700)
    receipt = {'status': 'running', 'base_image': lock['base_image'], 'base_id': base['Id'],
        'source_lock_sha256': digest(DIRECTORY/'lxml-artifacts.lock.json'), 'sources': lock['sources'],
        'application_mounts': [], 'helpers': {name: digest(DIRECTORY/name) for name in HELPERS},
        'limits': lock['limits']}
    if recovery: receipt['compiled_checkpoint_recovery'] = recovery
    container, disconnected, evidence_copied = None, False, False
    try:
        container = command('create', '--pull=never', '--name', NAME,
            '--label', 'erp.quality.owner=runtime-security-lxml', '--cpus', '1', '--memory', '1024m',
            '--memory-swap', '1024m', '--pids-limit', '256', '--user', '0', '--entrypoint', '/bin/sh',
            *source_builder_mounts.arguments(),
            lock['base_image'], '-c', 'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/build-lxml.sh')
        if not re.fullmatch('[0-9a-f]{64}', container): raise ValueError('Unexpected owned container identity')
        receipt['container_id'] = container
        receipt.update(source_builder_mounts.inspect(command, container))
        shutil.copyfile(Path(source_builder_mounts.__file__), output/'source_builder_mounts.py')
        (output/'resource-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 1400*1024: raise RuntimeError('Need1400MiB VM free for the guarded lxml builder')
        command('exec', container, 'mkdir', '-p', '/security-input')
        for entry in entries: command('cp', str(source/entry['filename']), container+':/security-input/'+entry['filename'])
        for name in HELPERS: command('cp', str(DIRECTORY/name), container+':/security-input/'+name)
        if recovery:
            command('exec', container, 'mkdir', '/security-input/recovery')
            for name in recovery_lock['files']:
                command('cp', str(args.recover_from.absolute()/name), container+':/security-input/recovery/'+name)
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic()+lock['limits']['timeout_seconds']
        while command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            if not disconnected:
                ready = subprocess.run(DOCKER+['exec', container, 'test', '-f', '/security-output/dependencies-ready'], capture_output=True)
                if ready.returncode == 0:
                    command('network', 'disconnect', 'bridge', container)
                    if json.loads(command('inspect', '--format', '{{json .NetworkSettings.Networks}}', container)):
                        raise RuntimeError('Owned builder remains attached to a network')
                    disconnected = True
                    command('exec', container, 'touch', '/security-input/offline-ready')
            try: free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
            except subprocess.CalledProcessError:
                if command('inspect', '--format', '{{.State.Running}}', container) == 'false': break
                raise
            host_free = shutil.disk_usage('/private/tmp').free
            receipt['minimum_vm_free_mib'] = min(receipt.get('minimum_vm_free_mib', float('inf')), free_kib/1024)
            receipt['minimum_host_free_mib'] = min(receipt.get('minimum_host_free_mib', float('inf')), host_free/MIB)
            if free_kib < 400*1024 or host_free < 400*MIB or time.monotonic() > deadline:
                raise RuntimeError('Owned lxml builder reached its disk/time guard')
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container+':/security-output/.', str(output))
        evidence_copied = True
        result = json.loads((output/'receipt.json').read_text()) if (output/'receipt.json').exists() else {}
        if receipt['exit_code'] or not disconnected or result.get('status') != 'passed':
            raise RuntimeError('lxml compile/ordinary checks failed; evidence is retained')
        wheel = output/result['wheel']
        if wheel.parent != output or digest(wheel) != result['wheel_sha256']:
            raise ValueError('Wheel copy differs from the tested artifact')
        receipt.update(status='built-upstream-and-ordinary-tests-passed-not-deployed', wheel_sha256=digest(wheel))
    except BaseException as error:
        receipt.update(status='failed', error=str(error)); raise
    finally:
        if container:
            finish_container(container, output, receipt, evidence_copied)
        (output/'resource-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if receipt.get('cleanup_errors'): raise RuntimeError('Inspect retained cleanup_errors')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
