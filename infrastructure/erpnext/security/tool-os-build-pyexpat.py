#!/usr/bin/env python3
"""Build pinned OS security sources in a bounded, data-free container."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY))
import source_builder_mounts

DOCKER = ['docker', '--context', 'colima-erp']


def staged_sources(sources, repository, quality_home):
    roots = {'repository': repository, 'quality-home': quality_home}
    paths = {}
    for filename, metadata in sources.items():
        base, separator, relative = metadata['staged_path'].partition('/')
        path = Path(relative)
        if (base not in roots or not separator or path.is_absolute()
                or '..' in path.parts or path.name != filename):
            raise ValueError('Invalid staged source path: ' + filename)
        paths[filename] = roots[base] / path
    return paths


def verify_sources(directory, sources):
    for name, entry in sources.items():
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Require a regular source file: ' + name)
        if path.stat().st_size != entry['bytes']:
            raise ValueError('Source size mismatch: ' + name)
        data = path.read_bytes()
        for algorithm in ('sha256', 'sha3_256'):
            if algorithm in entry and hashlib.new(algorithm, data).hexdigest() != entry[algorithm]:
                raise ValueError('Source checksum mismatch: ' + name)


def command(*args):
    return subprocess.run(DOCKER + list(args), capture_output=True, text=True,
                          check=True, timeout=60).stdout.strip()


def finish_container(container, evidence_copied, output, receipt):
    try:
        if command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            command('stop', '--time', '5', container)
    except (OSError, subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors', []).append({'action': 'stop', 'error': str(error)})
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
        receipt['container_retained'] = container


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight', action='store_true', help='Verify inputs only; do not start Docker')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--quality-home', type=Path, help='Quality storage root for staged sources')
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'tool-os-pyexpat.lock.json').read_text())
    entry = lock
    repository = DIRECTORY.parents[2]
    location = repository / '.local/quality/location.json'
    storage = json.loads(location.read_text()) if location.is_file() else {}
    quality_home = (args.quality_home or Path(os.environ.get('ERP_QUALITY_HOME')
                    or storage.get('tool_home') or repository / '.local/quality')).expanduser().resolve()
    source_files = staged_sources(entry['sources'], repository, quality_home)
    output = args.output.resolve()
    if output.exists():
        raise SystemExit('Require a new output directory; existing evidence is never overwritten')
    for filename, metadata in entry['sources'].items():
        verify_sources(source_files[filename].parent, {filename: metadata})
    if args.preflight:
        print(json.dumps({'status': 'verified-inputs-only', 'build_started': False, 'source': entry['local_build']}))
        return
    if shutil.disk_usage('/private/tmp').free < 800 * 1024**2:
        raise SystemExit('Need 800MiB host free before the bounded build')
    name = 'erp-quality-os-' + 'pyexpat' + '-builder'
    if subprocess.run(DOCKER + ['container', 'inspect', name], capture_output=True).returncode == 0:
        raise SystemExit('Builder name exists; no container was changed')
    command('image', 'inspect', lock['base_image'])
    output.mkdir(parents=True)
    shutil.copyfile(DIRECTORY / 'source_builder_mounts.py', output / 'source_builder_mounts.py')
    receipt = {'status': 'running', 'component': 'pyexpat', 'source': entry,
               'source_files': {name: str(path) for name, path in source_files.items()}, 'base_image': lock['base_image'],
               'application_mounts': [], 'network_targets': 'Debian build dependencies only; upstream XML tests use ordinary local fixtures/loopback only'}
    container = None
    evidence_copied = False
    script = 'tool-os-build-pyexpat.sh'
    try:
        container = command('create', '--pull=never', '--name', name, '--label', 'erp.quality.owner=runtime-security-os',
                            '--cpus', '1', '--memory', '640m', '--memory-swap', '640m', '--pids-limit', '256',
                            *source_builder_mounts.arguments(),
                            '--user', '0', '--entrypoint', '/bin/sh', lock['base_image'], '-c',
                            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/' + script)
        receipt['container_id'] = container
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        receipt.update(source_builder_mounts.inspect(command, container))
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 1000 * 1024:
            raise RuntimeError('Need 1000MiB VM free for a bounded source build')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input')
        for archive in entry['sources']:
            command('cp', str(source_files[archive]), container + ':/security-input/' + archive)
        for filename in (script, 'tool-os-pyexpat.py', 'tool-os-build-pyexpat-inside.py', 'tool-os-pyexpat.lock.json'):
            command('cp', str(DIRECTORY / filename), container + ':/security-input/' + filename)
            shutil.copyfile(DIRECTORY / filename, output / filename)
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 5400
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
                raise RuntimeError('Build stopped by the 400MiB disk floor or 90-minute time guard')
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container + ':/security-output/.', str(output))
        evidence_copied = True
        if receipt['exit_code']:
            raise RuntimeError('XML extension build/tests failed; inspect retained build.log')
        identity = json.loads((output / 'build-identity.json').read_text())
        tests = json.loads((output / 'upstream-result.json').read_text())
        if identity.get('status') != 'compiled-and-upstream-tests-passed' or tests.get('status') != 'passed':
            raise RuntimeError('XML extension build or full upstream tests did not pass')
        if identity['source_lock_sha256'] != hashlib.sha256((DIRECTORY / 'tool-os-pyexpat.lock.json').read_bytes()).hexdigest():
            raise RuntimeError('Source lock changed during the build')
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                       source_lock_sha256=identity['source_lock_sha256'], modules=identity['modules'],
                       artifacts={str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in output.rglob('*') if p.is_file() and p.name != 'receipt.json'})
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
