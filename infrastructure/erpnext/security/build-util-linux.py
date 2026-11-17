#!/usr/bin/env python3
"""Build maintained util-linux in one bounded container without app mounts."""
import argparse
import hashlib
import importlib.util
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
NAME = 'erp-quality-util-linux-builder'


def command(*args):
    return subprocess.run(DOCKER + list(args), capture_output=True, text=True, check=True, timeout=60).stdout.strip()


def verify_archive(path, entry):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Source must be a regular file')
    if path.stat().st_size != entry['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        raise ValueError('Source does not match the reviewed checksum/size')
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        if len(members) > 5000 or sum(m.size for m in members) > 100 * 1024**2:
            raise ValueError('Archive exceeds reviewed extraction budget')
        for member in members:
            relative = PurePosixPath(member.name)
            if (relative.is_absolute() or '..' in relative.parts or not relative.parts
                    or relative.parts[0] != entry['root'] or not (member.isfile() or member.isdir())):
                raise ValueError('Unexpected archive member')


def finish_container(container, output, receipt):
    try:
        if command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            command('stop', '--time', '5', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'stop', 'error': str(error)})
        receipt['container_retained'] = container
        return
    try:
        command('cp', container + ':/security-output/.', str(output))
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'copy-evidence', 'error': str(error)})
        receipt['container_retained'] = container
        return
    try:
        command('rm', '-f', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'remove-container', 'error': str(error)})
        receipt['container_retained'] = container


def verify_prepared_packages(folder, package_lock, source_lock, recovery_proof):
    for name, entry in package_lock['files'].items():
        if Path(name).name != name: raise ValueError('Prepared package input must be a basename')
        path = folder / ('receipt.json' if name == 'prior-package-install-failed.json' else name)
        if (path.is_symlink() or not path.is_file() or path.stat().st_size != entry['bytes']
                or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']):
            raise ValueError('Pinned prepared package/provenance mismatch: ' + name)
    prior = json.loads((folder / 'receipt.json').read_text())
    package_receipt = json.loads((folder / 'package-receipt.json').read_text())
    if (prior.get('source') != source_lock or prior.get('status') != 'failed'
            or not package_lock['expected_failed_exit_code'] or prior.get('exit_code') != package_lock['expected_failed_exit_code']
            or prior.get('cleanup_errors') or prior.get('container_retained') or prior.get('application_mounts') != []
            or prior.get('packaging_recovery') != recovery_proof
            or package_receipt.get('all_original_elf_replaced') is not True
            or set(package_receipt.get('packages', {})) != set('util-linux mount bsdutils libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2 login'.split())):
        raise ValueError('Prepared package provenance is incomplete or uses a different tested tree')
    expected_names = {'package-receipt.json', 'prior-package-install-failed.json'}
    for entry in package_receipt['packages'].values():
        name = entry['package']; expected_names.add(name)
        if (Path(name).name != name or not name.endswith('.deb')
                or name not in package_lock['files'] or entry['sha256'] != package_lock['files'][name]['sha256']):
            raise ValueError('Prepared package differs from reviewed output')
    if expected_names != set(package_lock['files']): raise ValueError('Prepared package file set differs')
    return package_receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--debian-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--validated-build', type=Path, help='Pinned completed test/install phase for packaging-only recovery')
    parser.add_argument('--prepared-packages', type=Path, help='Exact built packages awaiting dependency-ordered install validation')
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'util-linux-artifacts.lock.json').read_text())
    sources = {'util-linux-2.41.6.tar.xz': args.source, 'util-linux-debian.tar.xz': args.debian_source}
    for name, source in sources.items():
        verify_archive(source, lock['sources'][name])
    for name, entry in lock['maintenance_patches'].items():
        if Path(name).name != name:
            raise ValueError('Patch must be a basename')
        patch = DIRECTORY / name
        if (patch.is_symlink() or not patch.is_file() or patch.stat().st_size != entry['bytes']
                or hashlib.sha256(patch.read_bytes()).hexdigest() != entry['sha256']):
            raise ValueError('Maintenance patch checksum/size mismatch')
    helpers = ['build-util-linux.sh', 'package-util-linux.py', 'util-linux-artifacts.lock.json', *lock['maintenance_patches']]
    script = 'build-util-linux.sh'
    recovery_proof = None
    if args.validated_build:
        recovery = json.loads((DIRECTORY / 'util-linux-recovery.lock.json').read_text())
        if hashlib.sha256((DIRECTORY / 'util-linux-artifacts.lock.json').read_bytes()).hexdigest() != recovery['source_lock_sha256']:
            raise ValueError('Reviewed source lock changed')
        spec = importlib.util.spec_from_file_location('recover_util_linux', DIRECTORY / 'recover-util-linux.py')
        recover = importlib.util.module_from_spec(spec); spec.loader.exec_module(recover)
        recovery_proof = recover.verify(args.validated_build, recovery, lock)
        sources.update({name: args.validated_build / name for name in recovery['files']})
        script = 'build-util-linux-finish.sh'
        helpers += [script, 'recover-util-linux.py', 'util-linux-recovery.lock.json', 'util-linux-ordinary-compatibility.py']
    package_proof = None
    if args.prepared_packages:
        if not recovery_proof: raise ValueError('Prepared packages require the pinned completed upstream phase')
        folder = args.prepared_packages
        package_lock_path = DIRECTORY / 'util-linux-packages.lock.json'
        package_lock = json.loads(package_lock_path.read_text())
        if hashlib.sha256((DIRECTORY / 'util-linux-artifacts.lock.json').read_bytes()).hexdigest() != package_lock['source_lock_sha256']:
            raise ValueError('Prepared package source lock changed')
        package_receipt = verify_prepared_packages(folder, package_lock, lock, recovery_proof)
        package_proof = {'source_directory': str(folder.resolve()), 'files': {}}
        for entry in package_receipt['packages'].values():
            name = entry['package']; path = folder / name
            if (Path(name).name != name or not name.endswith('.deb') or path.is_symlink() or not path.is_file()
                    or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']):
                raise ValueError('Prepared package checksum/name mismatch')
            sources[name] = path; package_proof['files'][name] = entry['sha256']
        sources['package-receipt.json'] = folder / 'package-receipt.json'
        sources['prior-package-install-failed.json'] = folder / 'receipt.json'
        package_proof['package_receipt_sha256'] = hashlib.sha256(sources['package-receipt.json'].read_bytes()).hexdigest()
        package_proof['prior_failed_receipt_sha256'] = hashlib.sha256((folder / 'receipt.json').read_bytes()).hexdigest()
        script = 'install-tested-util-linux.sh'; helpers += [script, 'util-linux-packages.lock.json']
    output = args.output.resolve()
    if output.exists() or args.output.is_symlink():
        raise SystemExit('Use a new output directory; previous evidence is retained')
    if shutil.disk_usage('/private/tmp').free < 800 * 1024**2:
        raise SystemExit('Need 800MiB host free before this bounded build')
    if subprocess.run(DOCKER + ['container', 'inspect', NAME], capture_output=True).returncode == 0:
        raise SystemExit('Owned builder name already exists; no container changed')
    command('image', 'inspect', lock['base_image'])
    output.mkdir(parents=True)
    receipt = {'status': 'running', 'source': lock, 'output': str(output), 'application_mounts': [],
               'privileged': False, 'test_identity': 'frappe (unprivileged)',
               'network_targets': 'Debian package repositories only'}
    if recovery_proof: receipt['packaging_recovery'] = recovery_proof
    if package_proof:
        receipt['prepared_package_validation'] = package_proof
        receipt['network_targets'] = 'none'
    container = None
    try:
        limits = ['--cpus', '0.25', '--memory', '128m', '--memory-swap', '128m', '--network', 'none'] if package_proof else ['--cpus', '1', '--memory', '640m', '--memory-swap', '640m']
        container = command('create', '--name', NAME, '--label', 'erp.quality.owner=runtime-security-util-linux',
                            *limits, '--pids-limit', '256',
                            '--user', '0', '--entrypoint', '/bin/sh', *source_builder_mounts.arguments(), lock['base_image'], '-c',
                            'mkdir -p /security-input /security-output; while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/' + script)
        receipt['container_id'] = container
        receipt.update(source_builder_mounts.inspect(command, container))
        shutil.copyfile(Path(source_builder_mounts.__file__), output/'source_builder_mounts.py')
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        start_mib = 600 if package_proof else 1000
        if free_kib < start_mib * 1024:
            raise RuntimeError(f'Need {start_mib}MiB VM free before the selected util-linux phase')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input', '/security-output')
        for name, path in sources.items():
            command('cp', str(path.resolve()), container + ':/security-input/' + name)
        for name in helpers:
            command('cp', str(DIRECTORY / name), container + ':/security-input/' + name)
            shutil.copyfile(DIRECTORY / name, output / name)
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 3600
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
                raise RuntimeError('Build stopped by the 400MiB disk floor or one-hour time limit')
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        if receipt['exit_code']:
            raise RuntimeError('util-linux build/tests failed; inspect retained logs')
        receipt['status'] = 'built-upstream-tests-passed-final-runtime-validation-pending'
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        if container:
            finish_container(container, output, receipt)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('cleanup_errors'):
        raise RuntimeError('Inspect cleanup errors before retrying')


if __name__ == '__main__':
    main()
