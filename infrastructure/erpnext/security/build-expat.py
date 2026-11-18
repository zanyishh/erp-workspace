#!/usr/bin/env python3
"""Build a verified Expat release in an owned container without app mounts."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import time

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY))
import source_builder_mounts
DOCKER = ['docker', '--context', 'colima-erp']
NAME = 'erp-quality-expat-security-builder'


def command(*args):
    return subprocess.run(DOCKER + list(args), capture_output=True, text=True, check=True, timeout=60).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'expat-artifacts.lock.json').read_text())
    archive, output = args.source.resolve(), args.output.resolve()
    if args.source.is_symlink() or not archive.is_file() or output.exists():
        raise SystemExit('Require a real source archive and a new output directory')
    if archive.stat().st_size != lock['source_bytes'] or hashlib.sha256(archive.read_bytes()).hexdigest() != lock['source_sha256']:
        raise SystemExit('Official source size/checksum does not match')
    with tarfile.open(archive) as source:
        members = source.getmembers()
        if len(members) > 1000 or sum(m.size for m in members) > 15 * 1024**2:
            raise SystemExit('Source archive exceeds the reviewed size budget')
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'expat-2.10.0' or not (member.isfile() or member.isdir()):
                raise SystemExit('Unexpected source archive entry')
    if shutil.disk_usage('/private/tmp').free < 700 * 1024**2:
        raise SystemExit('Need 700MiB host free before the bounded build')
    if subprocess.run(DOCKER + ['container', 'inspect', NAME], capture_output=True).returncode == 0:
        raise SystemExit('Builder name already exists; no container was changed')
    command('image', 'inspect', lock['base_image'])
    output.mkdir(parents=True)
    receipt = {'status': 'running', 'source': lock, 'output': str(output), 'application_mounts': [], 'network_targets': 'Debian compiler package repositories only'}
    container = None
    try:
        container = command('create', '--name', NAME, '--label', 'erp.quality.owner=runtime-security-expat',
                            '--cpus', '1', '--memory', '512m', '--memory-swap', '512m', '--pids-limit', '256',
                            '--user', '0', '--entrypoint', '/bin/sh', *source_builder_mounts.arguments(), lock['base_image'], '-c',
                            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/build-expat.sh')
        receipt['container_id'] = container
        receipt.update(source_builder_mounts.inspect(command, container))
        shutil.copyfile(Path(source_builder_mounts.__file__), output/'source_builder_mounts.py')
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 900 * 1024:
            raise RuntimeError('Need 900MiB VM free for the isolated build')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input')
        command('cp', str(archive), container + ':/security-input/expat-2.10.0.tar.xz')
        command('cp', str(DIRECTORY / 'build-expat.sh'), container + ':/security-input/build-expat.sh')
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 1200
        while command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            try:
                free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
            except subprocess.CalledProcessError:
                if command('inspect', '--format', '{{.State.Running}}', container) == 'false':
                    break
                raise
            host_free = shutil.disk_usage('/private/tmp').free
            receipt['minimum_vm_free_mib'] = min(receipt['minimum_vm_free_mib'], free_kib / 1024)
            receipt['minimum_host_free_mib'] = min(receipt.get('minimum_host_free_mib', float('inf')), host_free / 1024**2)
            if free_kib < 400 * 1024 or host_free < 400 * 1024**2 or time.monotonic() > deadline:
                raise RuntimeError('Build stopped by the disk/time guard')
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container + ':/security-output/.', str(output))
        if receipt['exit_code']:
            raise RuntimeError('Expat build/tests failed; inspect retained build.log')
        package = output / 'libexpat1_2.10.0-0+erp1_arm64.deb'
        receipt.update(status='built-upstream-tests-passed-runtime-validation-pending',
                       package_sha256=hashlib.sha256(package.read_bytes()).hexdigest())
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        if container:
            for action in (['cp', container + ':/security-output/.', str(output)], ['rm', '-f', container]):
                try:
                    command(*action)
                except (OSError, subprocess.SubprocessError) as error:
                    receipt.setdefault('cleanup_errors', []).append({'action': action[0], 'error': str(error)})
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('cleanup_errors'):
        raise RuntimeError('Build evidence retained; inspect cleanup_errors before retrying')


if __name__ == '__main__':
    main()
