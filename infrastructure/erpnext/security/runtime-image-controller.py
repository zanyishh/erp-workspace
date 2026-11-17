#!/usr/bin/env python3
"""Build one offline candidate using owned VM-root scratch, then commit it."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

DIRECTORY = Path(__file__).resolve().parent
DOCKER = ['docker', '--context', 'colima-erp']
BENCH = '/home/frappe/frappe-bench'
MIB = 1024**2


def command(args, env, data=None):
    return subprocess.check_output(args, input=data, text=True, env=env,
                                   stderr=subprocess.STDOUT, timeout=60).strip()


def vm(request, env):
    code = (DIRECTORY/'runtime-assembly-scratch.py').read_text()
    code += '\nprint(json.dumps(main('+repr(request)+')))\n'
    return json.loads(command(['colima', 'ssh', '--profile', 'erp', '--', 'sudo', 'python3', '-'], env, code))


def resources(env):
    result = vm({'action': 'storage'}, env)
    result['host'] = shutil.disk_usage('/private/tmp').free
    return result


def inspect_owned(container, owner, image, scratch, writable_input, env):
    result = json.loads(command(DOCKER+['inspect', '--format', '{{json .}}', container], env))
    expected = {'/security-input': (scratch+'/inputs', writable_input),
                BENCH+'/sites': (scratch+'/sites', True), BENCH+'/logs': (scratch+'/logs', True)}
    actual = {item['Destination']: (item['Source'], item['RW']) for item in result['Mounts']}
    if (result['Id'] != container or result['Image'] != image
            or result['Name'] not in {'/erp-quality-assembly-staging-'+owner, '/erp-quality-assembly-candidate-'+owner}
            or result['HostConfig']['NetworkMode'] != 'none'
            or any(item['Type'] != 'bind' for item in result['Mounts']) or actual != expected):
        raise ValueError('Owned assembly container identity or mounts differ')
    return result


def require_detached(scratch, env):
    identifiers = command(DOCKER+['ps', '-aq'], env).split()
    if not identifiers: return
    rows = command(DOCKER+['inspect', '--format', '{{json .Mounts}}', *identifiers], env).splitlines()
    for row in rows:
        for mount in json.loads(row):
            source = Path(mount.get('Source', '/unrelated'))
            if source == Path(scratch) or source.is_relative_to(scratch) or Path(scratch).is_relative_to(source):
                raise ValueError('Another container still references the owned scratch tree')


def guarded(args, logfile, env, receipt, seconds=1800):
    process = None
    try:
        with logfile.open('w') as log:
            process = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic()+seconds
            while process.poll() is None:
                free = resources(env)
                minimum = receipt.setdefault('minimum_free_bytes', {})
                for name, value in free.items(): minimum[name] = min(minimum.get(name, value), value)
                if (any(free[name] < 400*MIB for name in ('host', 'scratch', 'docker'))
                        or free['memory'] < 128*MIB or time.monotonic() > deadline):
                    raise RuntimeError('Owned image step reached a disk/memory/time guard')
                time.sleep(3)
        if process.returncode: raise RuntimeError('Owned image step failed: '+logfile.name)
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait()


def assemble(context, output, base, base_ref, tag, env, receipt):
    total = sum(path.stat().st_size for path in context.rglob('*') if path.is_file())
    if total > 320*MIB: raise ValueError('Curated assembly inputs exceed320MiB')
    free = resources(env)
    if free['host'] < 1600*MIB: raise RuntimeError('Need1600MiB host headroom for owned image assembly')
    if set(base['Config'].get('Volumes') or {}) != {BENCH+'/sites', BENCH+'/logs'}:
        raise ValueError('Unexpected declared base-image volumes')
    owner = uuid.uuid4().hex
    receipt['scratch_request'] = {'path': '/tmp/erp-quality-assembly-'+owner, 'token': owner}
    scratch = vm({'action': 'create', 'token': owner}, env)
    containers = []
    candidate = None
    evidence_exported = False
    receipt.update(strategy='owned-vm-root-scratch-container-commit', scratch=scratch,
                   curated_input_bytes=total, application_mounts=[], network='none',
                   host_controller_hashes={name: hashlib.sha256((DIRECTORY/name).read_bytes()).hexdigest()
                    for name in ('runtime-image-controller.py', 'runtime-assembly-scratch.py', 'commit-runtime-image.py')})
    try:
        def create(role, memory, writable_input, executable):
            args = DOCKER+['create', '--pull=never', '--name', 'erp-quality-assembly-'+role+'-'+owner,
                '--network', 'none', '--cpus', '1',
                '--memory', memory, '--memory-swap', memory, '--pids-limit', '256',
                '--user', '0', '--entrypoint', '/bin/sh',
                '--mount', 'type=bind,src='+scratch['path']+'/inputs,dst=/security-input'+('' if writable_input else ',readonly'),
                '--mount', 'type=bind,src='+scratch['path']+'/sites,dst='+BENCH+'/sites',
                '--mount', 'type=bind,src='+scratch['path']+'/logs,dst='+BENCH+'/logs']
            if role == 'staging': args.append('--read-only')
            container = command(args+[base_ref, '-c', executable], env)
            if not re.fullmatch('[0-9a-f]{64}', container): raise ValueError('Invalid owned container ID')
            containers.append((container, writable_input))
            inspect_owned(container, owner, base['Id'], scratch['path'], writable_input, env)
            return container
        helper = create('staging', '64m', True, 'sleep 3600')
        command(DOCKER+['start', helper], env)
        guarded(DOCKER+['cp', str(context)+'/.', helper+':/security-input/'], output/'input-copy.log', env, receipt)
        initialize = '''import os,pathlib,pwd
p=pathlib.Path('/home/frappe/frappe-bench/sites')
assert not list(p.iterdir())
(p/'apps.txt').write_text('frappe\\nerpnext\\n')
(p/'common_site_config.json').write_text('{}\\n')
user=pwd.getpwnam('frappe')
for path in [p,*p.iterdir(),pathlib.Path('/home/frappe/frappe-bench/logs')]:os.chown(path,user.pw_uid,user.pw_gid)
'''
        command(DOCKER+['exec', helper, 'python3', '-c', initialize], env)
        candidate = create('candidate', '1024m', False,
            'exec /home/frappe/frappe-bench/env/bin/python /security-input/scripts/assemble-runtime.py')
        receipt['candidate_container_id'] = candidate
        guarded(DOCKER+['start', '--attach', candidate], output/'assembly.log', env, receipt)
        state = inspect_owned(candidate, owner, base['Id'], scratch['path'], False, env)['State']
        if state['Running'] or state['ExitCode'] != 0 or state.get('OOMKilled'):
            raise ValueError('Candidate assembly did not finish normally')
        evidence = output/'image-evidence'; evidence.mkdir()
        guarded(DOCKER+['cp', candidate+':/opt/erp-security/.', str(evidence)], output/'evidence-copy.log', env, receipt)
        evidence_exported = True
        result = json.loads((evidence/'assembly-receipt.json').read_text())
        if (result.get('status') != 'passed' or result.get('base_image') != base_ref
                or result.get('inputs_sha256') != hashlib.sha256((context/'runtime-image-inputs.json').read_bytes()).hexdigest()
                or result.get('asset_receipt_sha256') != hashlib.sha256((evidence/'asset-build.json').read_bytes()).hexdigest()):
            raise ValueError('Completed assembly receipt does not match the frozen inputs/assets')
        iid = output/'image-id.txt'
        guarded([sys.executable, str(DIRECTORY/'commit-runtime-image.py'), '--container', candidate,
            '--owner', owner, '--tag', tag, '--iidfile', str(iid)], output/'commit.log', env, receipt, seconds=900)
        image = iid.read_text().strip()
        if not re.fullmatch('sha256:[0-9a-f]{64}', image): raise ValueError('Missing committed image identity')
        receipt.update(status='built-ordinary-checks-and-fresh-assets-passed-not-deployed', image_id=image,
            base_config_sha256=hashlib.sha256(json.dumps(base['Config'], sort_keys=True).encode()).hexdigest(),
            asset_receipt_sha256=hashlib.sha256((evidence/'asset-build.json').read_bytes()).hexdigest())
        return image
    finally:
        stopped = set()
        if candidate and not evidence_exported:
            try:
                inspect_owned(candidate, owner, base['Id'], scratch['path'], False, env)
                command(DOCKER+['stop', '-t', '10', candidate], env)
                stopped.add(candidate)
                destination = output/'image-evidence'; destination.mkdir(exist_ok=True)
                command(DOCKER+['cp', candidate+':/opt/erp-security/.', str(destination)], env)
                evidence_exported = True
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                receipt.setdefault('evidence_copy_errors', []).append(str(error))
        retain = candidate is not None and not evidence_exported
        if retain:
            receipt['retained_for_evidence'] = {'containers': [value[0] for value in containers], 'scratch': scratch}
        for container, writable in reversed(containers):
            try:
                inspect_owned(container, owner, base['Id'], scratch['path'], writable, env)
                if not retain or container not in stopped:
                    command(DOCKER+(['stop', '-t', '10', container] if retain else ['rm', '-f', container]), env)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                receipt.setdefault('cleanup_errors', []).append(str(error))
        if not retain and not receipt.get('cleanup_errors'):
            try:
                require_detached(scratch['path'], env)
                receipt['scratch_cleanup'] = vm(dict(scratch, action='remove', containers_detached=True), env)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                receipt.setdefault('cleanup_errors', []).append(str(error))
