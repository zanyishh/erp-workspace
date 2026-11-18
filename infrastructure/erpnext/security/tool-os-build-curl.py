#!/usr/bin/env python3
"""Build pinned OS security sources in a bounded, data-free container."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY))
import source_builder_mounts

DOCKER = ['docker', '--context', 'colima-erp']
VM = ['colima', 'ssh', '--profile', 'erp', '--', 'sudo', 'python3', '-']
MIB = 1024**2


def vm_request(request):
    script = (DIRECTORY / 'tool-os-curl-scratch.py').read_text()
    result = subprocess.run(VM, input=script + '\nmain(' + repr(request) + ')\n',
                            capture_output=True, text=True, check=True, timeout=60)
    return json.loads(result.stdout)


def reject_shared_scratch(path):
    identifiers = command('ps', '-aq', '--no-trunc').split()
    if len(identifiers) > 64:
        raise RuntimeError('Too many containers for the bounded scratch ownership check')
    if identifiers:
        rows = command('inspect', '--format', '{{json .Mounts}}', *identifiers)
        for row in rows.splitlines():
            for mount in json.loads(row):
                source = mount.get('Source', '').rstrip('/') or '/'
                if (source == path or source.startswith(path + '/')
                        or path.startswith(source.rstrip('/') + '/')):
                    raise RuntimeError('Another container references the scratch path: ' + source)


def check_space(free, host_free, initial=False):
    floors = {'docker': 1000, 'scratch': 1400} if initial else {'docker': 400, 'scratch': 400}
    if any(free[name] < limit * MIB for name, limit in floors.items()):
        raise RuntimeError('VM filesystem storage guard failed: ' + json.dumps(floors))
    if host_free < (1200 if initial else 400) * MIB:
        raise RuntimeError('Host storage guard failed')


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
        return False
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
    return evidence_copied


def require_install_builder(info, expected, ready, detached=False):
    config=info.get('Config',{}); labels=config.get('Labels',{})
    networks=info.get('NetworkSettings',{}).get('Networks',{})
    if (not ready or any(info.get(k)!=expected[k] for k in ['Id','Created','Name'])
            or config.get('Image')!=expected['Image'] or not isinstance(labels,dict)
            or labels.get('erp.quality.owner')!='runtime-security-os'
            or info.get('State',{}).get('Running') is not True
            or info.get('HostConfig')!=expected['HostConfig'] or expected['HostConfig'].get('NetworkMode')!='bridge'):
        raise ValueError('Only the same ready owned default-bridge Curl builder may become offline')
    if detached:
        if networks: raise ValueError('Curl installer still has a network attachment')
    elif (set(networks)!={'bridge'} or networks['bridge'].get('NetworkID')!=expected['NetworkID']
            or not networks['bridge'].get('EndpointID')):
        raise ValueError('Require the sole original Docker default-bridge attachment')
    return True


def offline_install(container, expected, output, receipt):
    ready=command('exec',container,'sh','-c','test -f /security-output/offline-install-ready && test ! -L /security-output/offline-install-ready && echo ready')=='ready'
    before=json.loads(command('inspect','--format','{{json .}}',container))
    require_install_builder(before,expected,ready)
    command('network','disconnect',expected['NetworkID'],container)
    after=json.loads(command('inspect','--format','{{json .}}',container))
    require_install_builder(after,expected,ready,detached=True)
    interfaces=command('exec',container,'python3','-c',"import json,pathlib;print(json.dumps(sorted(p.name for p in pathlib.Path('/sys/class/net').iterdir())))")
    if json.loads(interfaces)!=['lo']: raise ValueError('Offline Curl installer requires only lo')
    proof={'status':'owned-default-bridge-detached-before-local-install','before':before,'after':after,
           'interfaces':['lo'],'installer_sha256':hashlib.sha256((DIRECTORY/'install-runtime-debs.py').read_bytes()).hexdigest()}
    (output/'offline-install-network.json').write_text(json.dumps(proof,indent=2)+'\n')
    receipt['offline_install_network_sha256']=hashlib.sha256((output/'offline-install-network.json').read_bytes()).hexdigest()
    command('exec',container,'touch','/security-input/offline-install-approved')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight', action='store_true', help='Verify inputs only; do not start Docker')
    parser.add_argument('--vm-scratch', action='store_true',
                        help='Use a fresh owned VM /tmp folder for compiler output; no application mounts')
    parser.add_argument('--compiler-probe', action='store_true',
                        help='Measure one exact test object and wait for its hash-bound review before the full build')
    parser.add_argument('--mtls-diagnose', action='store_true',
                        help='Before unchanged OpenSSL ordinary suites, run original2095 and original2088/2089/2095 selections')
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'tool-os-curl.lock.json').read_text())
    entry = lock
    source, output = args.input.resolve(), args.output.resolve()
    if output.exists():
        raise SystemExit('Require a new output directory; existing evidence is never overwritten')
    verify_sources(source, entry['sources'])
    verify_sources(DIRECTORY, {p['file']: p for p in lock['patches']})
    review_entry=lock['protocol_contract']['rtmp_removal_review']
    review=DIRECTORY.parents[2]/review_entry['source']
    if not review.resolve().is_relative_to(DIRECTORY.parents[2]):
        raise ValueError('Require the exact local ERP protocol review')
    verify_sources(review.parent,{review.name:review_entry})
    if args.preflight:
        print(json.dumps({'status': 'verified-inputs-only', 'build_started': False,
                          'source': entry['upstream_version'], 'vm_scratch': args.vm_scratch,
                          'compiler_probe': args.compiler_probe, 'mtls_diagnose': args.mtls_diagnose}))
        return
    if shutil.disk_usage('/private/tmp').free < 1200 * 1024**2:
        raise SystemExit('Need 1200MiB host free before the bounded build')
    name = 'erp-quality-os-' + 'curl' + '-builder'
    if subprocess.run(DOCKER + ['container', 'inspect', name], capture_output=True).returncode == 0:
        raise SystemExit('Builder name exists; no container was changed')
    command('image', 'inspect', lock['base_image'])
    output.mkdir(parents=True)
    shutil.copyfile(review,output/'rtmp-removal-review.json')
    shutil.copyfile(DIRECTORY / 'source_builder_mounts.py', output / 'source_builder_mounts.py')
    receipt = {'status': 'running', 'component': 'curl', 'source': entry,
               'source_directory': str(source), 'base_image': lock['base_image'],
               'application_mounts': [], 'network_targets': 'Debian build dependencies only; upstream tests use disposable local protocol servers'}
    receipt['protocol_removal_review_sha256']=hashlib.sha256(review.read_bytes()).hexdigest()
    receipt['mtls_diagnose_requested']=args.mtls_diagnose
    container = None
    scratch = None
    evidence_copied = False
    script = 'tool-os-build-curl.sh'
    try:
        mounts = []
        if args.vm_scratch:
            free = vm_request({'action': 'storage'})
            check_space(free, shutil.disk_usage('/private/tmp').free, initial=True)
            token = uuid.uuid4().hex
            path = '/tmp/erp-quality-curl-' + token
            reject_shared_scratch(path)
            receipt['scratch_request'] = {'path': path, 'token': token}
            (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            scratch = vm_request({'action': 'create', 'token': token})
            receipt['scratch'] = scratch
            mounts = ['--mount', 'type=bind,src=' + scratch['path'] + ',dst=/security-work,bind-propagation=rprivate']
            shutil.copyfile(DIRECTORY / 'tool-os-curl-scratch.py', output / 'tool-os-curl-scratch.py')
        container = command('create', '--pull=never', '--name', name, '--label', 'erp.quality.owner=runtime-security-os',
                            '--network','bridge','--cpus', '1', '--memory', '640m', '--memory-swap', '640m', '--pids-limit', '256',
                            *(['--env','ERP_CURL_COMPILER_PROBE=1'] if args.compiler_probe else []),
                            *(['--env','ERP_CURL_MTLS_DIAGNOSE=1'] if args.mtls_diagnose else []),
                            *source_builder_mounts.arguments(),
                            *mounts, '--user', '0', '--entrypoint', '/bin/sh', lock['base_image'], '-c',
                            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/' + script)
        receipt['container_id'] = container
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        receipt.update(source_builder_mounts.inspect(command, container, scratch['path'] if scratch else None))
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        actual=json.loads(command('inspect','--format','{{json .}}',container))
        install_identity={k:actual[k] for k in ['Id','Created','Name']}
        install_identity.update(Image=lock['base_image'],HostConfig=actual['HostConfig'],NetworkID=command('network','inspect','--format','{{.Id}}','bridge'))
        require_install_builder(actual,install_identity,True)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if scratch:
            check_space(vm_request({'action': 'storage'}), shutil.disk_usage('/private/tmp').free, initial=True)
        elif free_kib < 1600 * 1024:
            raise RuntimeError('Need 1600MiB VM free for a bounded source build')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input')
        for archive in entry['sources']:
            command('cp', str(source / archive), container + ':/security-input/' + archive)
        for filename in (script, Path(__file__).name, 'tool-os-check-curl.py', 'tool-os-curl.lock.json',
                         'tool-os-curl-install.py','install-runtime-debs.py', *[p['file'] for p in lock['patches']]):
            command('cp', str(DIRECTORY / filename), container + ':/security-input/' + filename)
            shutil.copyfile(DIRECTORY / filename, output / filename)
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 7200
        probe_exported = probe_approved = install_approved = False
        while command('inspect', '--format', '{{.State.Running}}', container) == 'true':
            try:
                free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
            except subprocess.CalledProcessError:
                if command('inspect', '--format', '{{.State.Running}}', container) == 'false':
                    break
                raise
            host_free = shutil.disk_usage('/private/tmp').free
            if scratch:
                free = vm_request({'action': 'storage'})
                for partition, available in free.items():
                    key = 'minimum_' + partition + '_free_mib'
                    receipt[key] = min(receipt.get(key, float('inf')), available / MIB)
                check_space(free, host_free)
            receipt['minimum_vm_free_mib'] = min(receipt['minimum_vm_free_mib'], free_kib / 1024)
            receipt['minimum_host_free_mib'] = min(receipt.get('minimum_host_free_mib', float('inf')), host_free / 1024**2)
            if free_kib < 400 * 1024 or host_free < 400 * 1024**2 or time.monotonic() > deadline:
                raise RuntimeError('Build stopped by the 400MiB disk floor or two-hour time guard')
            if args.compiler_probe and not probe_exported:
                ready=command('exec',container,'sh','-c','if [ -f /security-output/compiler-probe-finished ]; then echo ready; fi')
                if ready=='ready':
                    for filename in ['compiler-probe.json','compiler-probe-build.log','test-compiler-flags-openssl.json','test-compiler-flags-gnutls.json']:
                        command('cp',container+':/security-output/'+filename,str(output/filename))
                    receipt['compiler_probe']=json.loads((output/'compiler-probe.json').read_text())
                    receipt['compiler_probe_sha256']=hashlib.sha256((output/'compiler-probe.json').read_bytes()).hexdigest()
                    receipt['status']='compiler-probe-ready-awaiting-review';probe_exported=True
                    (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
                    print(json.dumps({'status':receipt['status'],'result':receipt['compiler_probe'],
                                      'probe_sha256':receipt['compiler_probe_sha256']}),flush=True)
            if probe_exported and not probe_approved and (output/'compiler-probe-continue.json').exists():
                decision=output/'compiler-probe-continue.json'
                expected={'probe_sha256':receipt['compiler_probe_sha256'],'continue':True}
                if (decision.is_symlink() or json.loads(decision.read_text())!=expected
                        or receipt['compiler_probe']['status']!='compiler-object-fits'):
                    raise ValueError('Only an exact reviewed successful compiler probe may start the full build')
                command('cp',str(decision),container+':/security-input/compiler-probe-continue.json')
                probe_approved=True;receipt['compiler_probe_reviewed']=expected
                receipt['status']='running-full-build-after-reviewed-compiler-fit'
                (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
            if not install_approved:
                ready=command('exec',container,'sh','-c','if [ -f /security-output/offline-install-ready ]; then echo ready; fi')
                if ready=='ready':
                    offline_install(container,install_identity,output,receipt);install_approved=True
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container + ':/security-output/.', str(output))
        evidence_copied = True
        if receipt['exit_code']:
            raise RuntimeError('OS package build/tests failed; inspect retained build.log')
        packages = sorted(output.glob('*.deb'))
        if not packages:
            raise RuntimeError('No packages produced')
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                       packages={str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest() for p in output.rglob('*.deb')})
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        if container:
            evidence_copied = finish_container(container, evidence_copied, output, receipt)
        if scratch:
            if evidence_copied and not receipt.get('cleanup_errors'):
                try:
                    reject_shared_scratch(scratch['path'])
                    receipt['scratch_cleanup'] = vm_request(dict(scratch, action='remove', containers_detached=True))
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                    receipt.setdefault('cleanup_errors', []).append({'action': 'remove-scratch', 'error': str(error)})
            else:
                receipt['scratch_retained'] = 'Evidence export or container cleanup was incomplete; inspect the exact recorded path'
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('cleanup_errors'):
        raise RuntimeError('Inspect cleanup_errors before retrying')


if __name__ == '__main__':
    main()
