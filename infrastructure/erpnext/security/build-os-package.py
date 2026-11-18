#!/usr/bin/env python3
"""Build pinned OS security sources in a bounded, data-free container."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY))
import source_builder_mounts
DOCKER = ['docker', '--context', 'colima-erp']


def require_basename(name):
    if not isinstance(name, str) or Path(name).name != name or name in ('', '.', '..'):
        raise ValueError('Require a basename within the selected directory')


def local_helper(name):
    require_basename(name)
    path = DIRECTORY / name
    if path.is_symlink() or not path.is_file():
        raise ValueError('Require a regular local helper: ' + name)
    return path


def verify_sources(directory, sources):
    for name, entry in sources.items():
        require_basename(name)
        if not re.fullmatch(r'[0-9a-f]{64}', entry.get('sha256', '')):
            raise ValueError('Require a pinned SHA-256 checksum: ' + name)
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Require a regular source file: ' + name)
        if path.stat().st_size != entry['bytes']:
            raise ValueError('Source size mismatch: ' + name)
        data = path.read_bytes()
        for algorithm in ('sha256', 'sha3_256'):
            if algorithm in entry and hashlib.new(algorithm, data).hexdigest() != entry[algorithm]:
                raise ValueError('Source checksum mismatch: ' + name)


def collect_artifacts(output, expected=None):
    names = expected if expected is not None else sorted(p.name for p in output.glob('*.deb'))
    if not isinstance(names, list) or not names:
        raise ValueError('No build artifacts declared or produced')
    artifacts = {}
    for name in names:
        require_basename(name)
        path = output / name
        if path.is_symlink() or not path.is_file() or not path.stat().st_size:
            raise ValueError('Missing regular build artifact: ' + name)
        artifacts[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return artifacts


def command(*args):
    return subprocess.run(DOCKER + list(args), capture_output=True, text=True,
                          check=True, timeout=60).stdout.strip()


def finish_container(container, evidence_copied, output, receipt):
    try:
        if command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            command('stop', '--time', '5', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'stop', 'error': str(error)})
        # Without a confirmed stopped state, an export may be changing while it
        # is copied. Retain the owned builder and all evidence for inspection.
        receipt['container_retained'] = container
        return
    if not evidence_copied:
        try:
            command('cp', container + ':/security-output/.', str(output))
            evidence_copied = True
        except (OSError, subprocess.SubprocessError) as error:
            receipt.setdefault('cleanup_errors', []).append({'action': 'copy-evidence', 'error': str(error)})
    if evidence_copied:
        try:
            command('rm', '-f', container)
        except (OSError, subprocess.SubprocessError) as error:
            receipt.setdefault('cleanup_errors', []).append({'action': 'remove-container', 'error': str(error)})
    else:
        # /security-output is in the container, not an external mounted folder.
        receipt['container_retained'] = container


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('component', help='Component key from the selected source lock')
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--lock-file', type=Path, default=DIRECTORY / 'os-artifacts.lock.json')
    parser.add_argument('--compatibility-script', default='os-runtime-compatibility.py')
    parser.add_argument('--x11-checkpoint', type=Path, help='Finish only the verified manual-Python failure after completed X11 builds')
    args = parser.parse_args()
    lock_path = args.lock_file.resolve()
    lock = json.loads(lock_path.read_text())
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', args.component) or not isinstance(lock.get(args.component), dict):
        raise SystemExit('Require a named component present in the selected source lock')
    entry = lock[args.component]
    script = 'build-os-' + args.component + '.sh'
    recovery = None
    if args.x11_checkpoint:
        if args.component != 'x11' or lock_path != DIRECTORY/'os-artifacts.lock.json':
            raise ValueError('The finish-only checkpoint is restricted to the original X11 source contract')
        spec = importlib.util.spec_from_file_location('x11_recovery', DIRECTORY/'os-x11-recovery.py')
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        scope = json.loads((DIRECTORY/'runtime-os-closure.lock.json').read_text())['components']['x11']['packages']
        recovery = helper.verify_checkpoint(args.x11_checkpoint, lock, scope)
        script = 'build-os-x11-finish.sh'
    helper_names = list(dict.fromkeys([script, args.compatibility_script, *entry.get('helpers', [])]))
    helper_paths = [local_helper(name) for name in helper_names]
    if lock_path.name in helper_names:
        raise SystemExit('The lock filename must not overwrite a build helper')
    source, output = args.input.resolve(), args.output.resolve()
    if output.exists():
        raise SystemExit('Require a new output directory; existing evidence is never overwritten')
    verify_sources(source, entry['sources'])
    if shutil.disk_usage('/private/tmp').free < 800 * 1024**2:
        raise SystemExit('Need 800MiB host free before the bounded build')
    name = 'erp-quality-os-' + args.component + '-builder'
    if subprocess.run(DOCKER + ['container', 'inspect', name], capture_output=True).returncode == 0:
        raise SystemExit('Builder name exists; no container was changed')
    command('image', 'inspect', lock['base_image'])
    output.mkdir(parents=True)
    if recovery:
        checkpoint = output/'prior-build'; checkpoint.mkdir()
        for name, expected in recovery['files'].items():
            original = args.x11_checkpoint/name; target = checkpoint/name
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(original, target)
            if helper.metadata(target) != expected: raise ValueError('Checkpoint changed while freezing: '+name)
        recovery['helpers'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in helper_paths}
        (output/'os-x11-recovery.lock.json').write_text(json.dumps(recovery, indent=2)+'\n')
    receipt = {'status': 'running', 'component': args.component, 'source': entry,
               'source_directory': str(source), 'base_image': lock['base_image'],
               'application_mounts': [], 'network_targets': 'Debian build dependencies; Git official HTTPS compatibility check'}
    if recovery: receipt['finish_only_recovery'] = {'checkpoint_lock_sha256': hashlib.sha256((output/'os-x11-recovery.lock.json').read_bytes()).hexdigest(),
        'prior_failed_receipt_sha256': recovery['prior_failed_receipt_sha256'], 'source_libraries_recompiled': False}
    container = None
    evidence_copied = False
    try:
        container = command('create', '--pull=never', '--name', name, '--label', 'erp.quality.owner=runtime-security-os',
                            '--cpus', '1', '--memory', '640m', '--memory-swap', '640m', '--pids-limit', '256',
                            '--user', '0', '--entrypoint', '/bin/sh', *source_builder_mounts.arguments(), lock['base_image'], '-c',
                            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/' + script)
        receipt['container_id'] = container
        receipt.update(source_builder_mounts.inspect(command, container))
        shutil.copyfile(Path(source_builder_mounts.__file__), output/'source_builder_mounts.py')
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 1000 * 1024:
            raise RuntimeError('Need 1000MiB VM free for a bounded source build')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input')
        if recovery:
            command('exec', container, 'mkdir', '/security-input/checkpoint')
            command('cp', str(output/'prior-build')+'/.', container+':/security-input/checkpoint/')
            command('cp', str(output/'os-x11-recovery.lock.json'), container+':/security-input/os-x11-recovery.lock.json')
        for archive in entry['sources']:
            command('cp', str(source / archive), container + ':/security-input/' + archive)
        for helper in [*helper_paths, lock_path]:
            command('cp', str(helper), container + ':/security-input/' + helper.name)
            shutil.copyfile(helper, output / helper.name)
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
                raise RuntimeError('Build stopped by the 400MiB disk floor or one-hour time guard')
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container + ':/security-output/.', str(output))
        evidence_copied = True
        if receipt['exit_code']:
            raise RuntimeError('OS package build/tests failed; inspect retained build.log')
        artifacts = collect_artifacts(output, entry.get('outputs'))
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                       artifacts=artifacts,
                       packages={name: digest for name, digest in artifacts.items() if name.endswith('.deb')})
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        if container:
            finish_container(container, evidence_copied, output, receipt)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('cleanup_errors'):
        raise RuntimeError('Inspect cleanup_errors before retrying')


if __name__ == '__main__':
    main()
