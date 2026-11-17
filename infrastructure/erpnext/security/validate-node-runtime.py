#!/usr/bin/env python3
"""Install and ordinarily test the pinned Node update in a disposable offline image."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import source_builder_mounts


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


installer = load('install-runtime-node')
builder = load('build-runtime-image')
cleanup = load('build-os-package')
DOCKER = ['docker', '--context', 'colima-erp']
MIB = 1024**2
NAME = 'erp-quality-node-runtime-validation'
RUN = '''#!/bin/sh
set -eu
umask 022
ulimit -c 0
export ERP_SECURITY_IMAGE_BUILD=1 PYTHONDONTWRITEBYTECODE=1 NODE_OPTIONS=--max-old-space-size=128
exec > /security-output/validation.log 2>&1
python3 -B /security-input/install-runtime-node.py --archive /security-input/node-v24.22.3-linux-arm64.tar.xz --output /security-output/install
runuser -u frappe -- node /security-input/node-runtime-ordinary.cjs > /security-output/ordinary.json
'''


def command(*args):
    return subprocess.check_output(DOCKER+list(args), text=True, stderr=subprocess.STDOUT, timeout=60).strip()


def free_vm(container):
    return int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))*1024


def preflight(manifest_path):
    manifest = json.loads(builder.ordinary(manifest_path).read_text())
    names = ('artifacts/node-v24.22.3-linux-arm64.tar.xz',
             'evidence/node-runtime/staging-receipt.json', 'evidence/node-runtime/preimage.json')
    files = {name: builder.ordinary(manifest['artifacts'][name]['source']) for name in names}
    for name, path in files.items():
        if not any(path.is_relative_to(parent) for parent in
                   (ROOT/'.local/quality/security-remediation', Path('/Volumes/ERPQuality/erp-quality/security-remediation'))):
            raise ValueError('Node validation reads only owned security staging')
        if builder.metadata(path) != {key: manifest['artifacts'][name][key] for key in ('bytes', 'sha256')}:
            raise ValueError('Node validation input changed: '+name)
    builder.check_node_runtime_inputs(manifest, files)
    lock = json.loads((HERE/'node-runtime.lock.json').read_text())
    installer.archive_inventory(files[names[0]], lock)
    return manifest, files, lock


def validate(manifest_path, output, execute=False):
    manifest, files, lock = preflight(manifest_path)
    if not execute:
        print(json.dumps({'status': 'inputs-verified-no-container-created', 'network': 'none',
                          'selected_bytes': sum(value['bytes'] for value in lock['replacement_files'].values())}))
        return
    output = builder.ordinary(output).resolve()
    if not output.is_relative_to(ROOT/'.local/quality/security-remediation') or output.exists():
        raise ValueError('Require a new owned local security evidence directory')
    if shutil.disk_usage(ROOT).free < 800*MIB: raise RuntimeError('Need800MiB host free before Node validation')
    if subprocess.run(DOCKER+['container', 'inspect', NAME], capture_output=True).returncode == 0:
        raise RuntimeError('The validation container name exists; nothing was changed')
    base = json.loads(command('image', 'inspect', '--format', '{{json .}}', builder.BASE))
    if base['Os'] != 'linux' or base['Architecture'] != 'arm64': raise ValueError('Require pinned Linux ARM64 base')
    output.mkdir(mode=0o700)
    sources = {name: HERE/name for name in ('install-runtime-node.py', 'node-runtime.lock.json',
               'node-runtime-ordinary.cjs', 'source_builder_mounts.py', 'validate-node-runtime.py', 'build-os-package.py')}
    for name, path in sources.items(): shutil.copy2(path, output/name)
    (output/'run.sh').write_text(RUN)
    receipt = {'status': 'running', 'base_image': builder.BASE, 'base_id': base['Id'],
               'network': 'none', 'application_mounts': [], 'source_lock_sha256': builder.digest(HERE/'node-runtime.lock.json'),
               'sources': {name: builder.digest(path) for name, path in sources.items()},
               'inputs': {name: manifest['artifacts'][name] for name in files}}
    container = None; copied = False
    try:
        container = command('create', '--pull=never', '--name', NAME, '--network', 'none',
            '--cpus', '1', '--memory', '384m', '--memory-swap', '384m', '--pids-limit', '128',
            '--security-opt', 'no-new-privileges:true', *source_builder_mounts.arguments(),
            '--user', '0', '--entrypoint', '/bin/sh', builder.BASE, '-c',
            'mkdir -p /security-input /security-output; while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/run.sh')
        receipt['container_id'] = container
        (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        receipt.update(source_builder_mounts.inspect(command, container))
        actual = json.loads(command('inspect', '--format', '{{json .}}', container))
        if actual['Image'] != base['Id'] or actual['HostConfig']['NetworkMode'] != 'none':
            raise ValueError('Validation container identity/network differs')
        command('start', container)
        if free_vm(container) < 1000*MIB: raise RuntimeError('Need1000MiB VM free before Node validation')
        command('exec', container, 'mkdir', '-p', '/security-input', '/security-output')
        for name, source in sources.items(): command('cp', str(source), container+':/security-input/'+name)
        command('cp', str(output/'run.sh'), container+':/security-input/run.sh')
        command('cp', str(files['artifacts/node-v24.22.3-linux-arm64.tar.xz']),
                container+':/security-input/node-v24.22.3-linux-arm64.tar.xz')
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic()+1200
        while command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            try: vm_free = free_vm(container)
            except subprocess.CalledProcessError:
                if command('inspect', '--format', '{{.State.Running}}', container) == 'false': break
                raise
            host_free = shutil.disk_usage(ROOT).free
            for key, value in [('minimum_vm_free_mib', vm_free/MIB), ('minimum_host_free_mib', host_free/MIB)]:
                receipt[key] = min(value, receipt.get(key, float('inf')))
            if min(vm_free, host_free) < 400*MIB or time.monotonic() > deadline:
                raise RuntimeError('Node validation reached its400MiB disk floor or20minute deadline')
            time.sleep(2)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container+':/security-output/.', str(output)); copied = True
        if receipt['exit_code'] != 0: raise RuntimeError('Node install/ordinary checks failed; retained validation.log')
        installed = json.loads((output/'install/receipt.json').read_text())
        ordinary = json.loads((output/'ordinary.json').read_text())
        if (installed['status'] != 'installed-ordinary-runtime-tests-pending'
                or installed['after'] != lock['after'] or ordinary.get('status') != 'passed'
                or ordinary.get('uid') == 0 or ordinary.get('executable') != installer.LEGACY+'/bin/node'
                or ordinary.get('versions', {}).get('node') != '24.22.3'):
            raise ValueError('Actual Node validation evidence differs from the locked contract')
        for name, path in sources.items():
            if builder.digest(path) != receipt['sources'][name]: raise ValueError('Validation source changed during execution')
        receipt.update(status='installed-and-ordinary-tests-passed-candidate-image-validation-pending',
                       installed_receipt_sha256=builder.digest(output/'install/receipt.json'),
                       ordinary_receipt_sha256=builder.digest(output/'ordinary.json'),
                       validation_log_sha256=builder.digest(output/'validation.log'))
    except BaseException as error:
        receipt.update(status='failed', error=str(error)); raise
    finally:
        if container: cleanup.finish_container(container, copied, output, receipt)
        (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if receipt.get('cleanup_errors') or receipt.get('container_retained'):
        raise RuntimeError('Validation evidence/container cleanup needs review')
    print(json.dumps(receipt, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    validate(args.inputs, args.output, args.execute)


if __name__ == '__main__': main()
