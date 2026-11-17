#!/usr/bin/env python3
"""Build the XML backport in a disposable, data-free container.

Input: verified source archives, .dsc, Canonical patch, and published PoC tar.
Output: original Debian-version package plus +erp1, tests and provenance logs.
The original image, every application container and every volume stay intact.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import source_builder_mounts

BASE_IMAGE = 'frappe/erpnext@sha256:32145acc7f699dc598ca141018a95ebf8e56f516d4a0e76beb7287ae68b303b8'
NAME = 'erp-quality-libxml2-security-builder'
LABEL = 'erp.quality.owner=runtime-security-libxml2'
DOCKER = ['docker', '--context', 'colima-erp']
SOURCES = {
    'libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.dsc': '04b1da890535b11e3db231f39114ee09e643badceff79441d749d0ca78efaaa5',
    'libxml2_2.12.7+dfsg+really2.9.14.orig.tar.xz': '4fe913dec8b1ab89d13b489b419a8203176ea39e931eaa0d25b17eafb9c279e9',
    'libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.debian.tar.xz': '3b6d265f482d6a8fbe3c056d2006fb3b563b4a838f7258b388ac5f0b29206921',
    'poc.tar.gz': '2b1c8ff7bcb2e2583d0ee8d5e02dc59521d5788426857796033d18a2fd18c4d2',
    'libxml2-2.9.14-upstream-tests.tar.xz': '60d74a257d1ccec0475e749cba2f21559e48139efba6ff28224357c7c798dfee',
}


def command(*args, **kwargs):
    return subprocess.run(DOCKER + list(args), check=True, text=True, capture_output=True, timeout=60, **kwargs).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.input.resolve()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit('Refusing to overwrite existing build evidence directory')
    for name, expected in SOURCES.items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise SystemExit('Source hash mismatch: ' + name)
    lock = json.loads((Path(__file__).parent / 'runtime-artifacts.lock.json').read_text())
    patch_hash = lock['libxml2']['canonical_patch_sha256']
    if hashlib.sha256((source / 'CVE-2026-6653.patch').read_bytes()).hexdigest() != patch_hash:
        raise SystemExit('Canonical security patch hash mismatch')
    for name, expected in lock['libxml2']['additional_patch_hashes'].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise SystemExit('Additional security patch hash mismatch: ' + name)
    if shutil.disk_usage('/private/tmp').free < 500 * 1024**2:
        raise SystemExit('Need at least 500 MiB host free before isolated build')
    # An existing named builder is never adopted, removed or resumed implicitly.
    exists = subprocess.run(DOCKER + ['container', 'inspect', NAME], capture_output=True)
    if exists.returncode == 0:
        raise SystemExit('Owned builder name already exists; inspect it before retrying')
    command('image', 'inspect', BASE_IMAGE)  # No implicit large image pull.
    output.mkdir(parents=True)
    container_id = None
    receipt = {'base_image': BASE_IMAGE, 'application_mounts': []}
    try:
        container_id = command('create', '--name', NAME, '--label', LABEL, '--cpus', '1', '--memory', '768m',
                '--memory-swap', '768m', '--pids-limit', '256', '--user', '0',
                '--entrypoint', '/bin/sh', *source_builder_mounts.arguments(), BASE_IMAGE, '-c',
                'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/build-libxml2.sh')
        receipt['container_id'] = container_id
        receipt.update(source_builder_mounts.inspect(command, container_id))
        shutil.copyfile(Path(source_builder_mounts.__file__), output/'source_builder_mounts.py')
        (output/'resource-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        command('start', container_id)
        free_kib = int(command('exec', container_id, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 1100 * 1024:
            raise RuntimeError('Need 1100 MiB VM free for bounded compiler/package build')
        command('exec', container_id, 'mkdir', '-p', '/security-input')
        command('cp', str(source) + '/.', container_id + ':/security-input')
        command('cp', str(Path(__file__).with_suffix('.sh')), container_id + ':/security-input/build-libxml2.sh')
        command('cp', str(Path(__file__).with_name('test-libxml2-xinclude.c')), container_id + ':/security-input/test-libxml2-xinclude.c')
        command('exec', container_id, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 1800
        minimum_free = free_kib
        while command('inspect', '--format', '{{.State.Running}}', container_id) == 'true':
            try:
                free_kib = int(command('exec', container_id, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
            except subprocess.CalledProcessError:
                if command('inspect', '--format', '{{.State.Running}}', container_id) == 'false':
                    break
                raise
            minimum_free = min(minimum_free, free_kib)
            if free_kib < 400 * 1024 or shutil.disk_usage('/private/tmp').free < 400 * 1024**2:
                raise RuntimeError('Stopped isolated builder at the 400 MiB storage floor')
            if time.monotonic() > deadline:
                raise RuntimeError('Stopped isolated builder at 30 minute limit')
            time.sleep(3)
        code = int(command('inspect', '--format', '{{.State.ExitCode}}', container_id))
        command('cp', container_id + ':/security-output/.', str(output))
        receipt.update(exit_code=code, minimum_vm_free_mib=minimum_free/1024)
        (output / 'resource-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if code:
            raise RuntimeError('Security build failed; inspect preserved build.log')
    finally:
        if container_id:
            # Only this invocation's newly created container is eligible.
            subprocess.run(DOCKER + ['cp', container_id + ':/security-output/.', str(output)], capture_output=True)
            command('rm', '-f', container_id)


if __name__ == '__main__':
    main()
