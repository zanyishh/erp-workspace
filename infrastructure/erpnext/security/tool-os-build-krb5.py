#!/usr/bin/env python3
"""Build pinned OS security sources in a bounded, data-free container."""
import argparse
import hashlib
import importlib.util
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
spec=importlib.util.spec_from_file_location('krb5_test_environment',DIRECTORY/'tool-os-krb5-test-environment.py')
test_environment=importlib.util.module_from_spec(spec);spec.loader.exec_module(test_environment)

DOCKER = ['docker', '--context', 'colima-erp']


def native_environment(action, journal=None, token=None, evidence=None):
    code=(DIRECTORY/'tool-os-krb5-test-environment.py').read_text()
    args=['colima','ssh','--profile','erp','--','sudo']
    if action=='cleanup-json':
        args+=['setpriv','--reuid',str(test_environment.UID),'--regid',str(test_environment.UID),
               '--clear-groups','--bounding-set=-all','--inh-caps=-all','--ambient-caps=-all','--no-new-privs']
    args+=['python3','-',action]
    if journal is not None:args+=['--journal-json',json.dumps(journal),'--token',token]
    run=subprocess.run(args,input=code,text=True,capture_output=True,timeout=30)
    if evidence is not None:
        evidence.with_suffix('.stdout').write_text(run.stdout);evidence.with_suffix('.stderr').write_text(run.stderr)
    if run.returncode:raise RuntimeError('KEYRING SECURITY GUARD: native '+action+' failed: '+run.stderr[-2000:])
    return json.loads(run.stdout)


def copy_control_json(container,path,receipt):
    if path.name not in test_environment.CONTROL_FILES or path.is_symlink() or not path.is_file():
        raise ValueError('Only the three fixed controller JSON files may be transferred')
    command('cp',str(path),container+':/security-input/'+path.name+'.pending')
    installed=json.loads(command('exec',container,'python3','/security-input/tool-os-krb5-test-environment.py',
                                 'install-control','--name',path.name))
    if (installed['name']!=path.name or installed['after']!={'uid':0,'gid':0,'mode':'0o644','nlink':1}
            or installed['sha256']!=test_environment.digest(path)):
        raise ValueError('Controller file ownership/content normalization failed')
    receipt.setdefault('control_file_transfers',{})[path.name]=installed


def approve_keyring_stage(container, output, request, stage, receipt):
    journal=None
    if stage=='cleanup':
        command('cp',container+':/security-output/keyring-tests/session.json',str(output/'keyring-test-session.json'))
        journal=json.loads((output/'keyring-test-session.json').read_text())
        test_environment.require_completed(journal,request['token'])
        for name,expected in journal['verbose_log_sha256'].items():
            target=output/('keyring-'+name)
            command('cp',container+':/security-output/keyring-tests/'+name,str(target))
            if test_environment.digest(target)!=expected:raise ValueError('Ordinary keyring execution log differs')
        test_environment.verify_keyring_logs((output/'keyring-t_cccol-verbose.log').read_text(),(output/'keyring-t_ccache-verbose.log').read_text())
    deadline=time.monotonic()+10
    while True:
        inventory=native_environment('inventory')
        try:test_environment.require_unused(inventory);break
        except ValueError:
            if stage=='start' or time.monotonic()>deadline:raise
            time.sleep(.5)
    proof=dict(request,stage=stage,UID_processes_absent=True,UID_keys_absent=True,native_inventory=inventory)
    if journal is not None:proof['journal_sha256']=test_environment.digest(output/'keyring-test-session.json')
    path=output/('keyring-'+stage+'-approval.json');path.write_text(json.dumps(proof,indent=2)+'\n');path.chmod(0o644)
    copy_control_json(container,path,receipt)
    receipt['keyring_'+stage+'_approval_sha256']=test_environment.digest(path)


def finish_keyring_environment(container, output, request, receipt):
    # Ask only this journalled test wrapper to stop before the existing owned
    # container/evidence cleanup. The helper handles its own process/key cleanup.
    try:
        code="""import json,os,pathlib,signal
p=pathlib.Path('/security-output/keyring-tests/session.json')
if p.exists():
 j=json.loads(p.read_text());token=TOKEN
 assert j['uid']==194812 and j['token']==token
 pid=j['wrapper_pid'];s=pathlib.Path('/proc')/str(pid)/'status'
 if s.exists():
  d=dict(x.split(':',1) for x in s.read_text().splitlines() if ':' in x)
  assert [int(x) for x in d['Uid'].split()]==[194812]*4
  os.kill(pid,signal.SIGTERM)
""".replace('TOKEN',repr(request['token']))
        if command('inspect','--format','{{.State.Running}}',container)=='true':
            command('exec',container,'python3','-c',code)
            deadline=time.monotonic()+8
            while native_environment('inventory')['processes'] and time.monotonic()<deadline:time.sleep(.5)
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
        receipt.setdefault('cleanup_errors',[]).append({'action':'request-owned-keyring-test-stop','error':str(error)})


def verify_final_uid_cleanup(output, request, receipt):
    inventory=native_environment('inventory')
    if inventory['account'] or inventory['group']:
        raise RuntimeError('KEYRING SECURITY GUARD: reserved native UID/GID identity changed; do not adopt or clean it')
    if inventory['processes']:
        raise RuntimeError('KEYRING SECURITY GUARD: reserved UID processes remain after owned container stop')
    if inventory['key_users']:
        journal_path=output/'keyring-tests/session.json'
        if not journal_path.is_file():raise RuntimeError('KEYRING SECURITY GUARD: UID keys remain without an owned journal; do not adopt them')
        journal=json.loads(journal_path.read_text());test_environment.validate_journal(journal,request['token'])
        receipt['native_owned_key_cleanup']=native_environment('cleanup-json',journal,request['token'],output/'native-owned-key-cleanup')
    deadline=time.monotonic()+10
    while True:
        inventory=native_environment('inventory')
        try:test_environment.require_unused(inventory);break
        except ValueError:
            if time.monotonic()>deadline:raise
            time.sleep(.5)
    receipt['reserved_uid_after_cleanup']=inventory


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
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'tool-os-krb5.lock.json').read_text())
    entry = lock
    source, output = args.input.resolve(), args.output.resolve()
    if output.exists():
        raise SystemExit('Require a new output directory; existing evidence is never overwritten')
    verify_sources(source, entry['sources'])
    verify_sources(DIRECTORY, {p['file']: p for p in lock['patches']})
    environment_path=DIRECTORY/test_environment.LOCK
    if test_environment.digest(environment_path)!=lock['test_environment']['sha256']:
        raise ValueError('Kerberos ordinary test policy differs from its source lock')
    environment=test_environment.load_environment(DIRECTORY)
    prerequisite=DIRECTORY.parents[2]/environment['prerequisite']['source']
    test_environment.verify_prerequisite(prerequisite,environment)
    abi_path = DIRECTORY/lock['abi_exception']['file']
    if test_environment.digest(abi_path) != lock['abi_exception']['sha256']:
        raise ValueError('Reviewed image-specific ABI contract changed')
    abi = json.loads(abi_path.read_text())
    reviewed = {}
    for basename, item in abi['review_evidence'].items():
        path = DIRECTORY.parents[2]/item['source']
        if Path(basename).name != basename or not path.resolve().is_relative_to(DIRECTORY.parents[2]):
            raise ValueError('ABI review evidence must be an exact local task artifact')
        verify_sources(path.parent, {path.name: item})
        reviewed[basename] = path
    if args.preflight:
        print(json.dumps({'status': 'verified-inputs-only', 'build_started': False, 'source': entry['upstream_version']}))
        return
    if shutil.disk_usage('/private/tmp').free < 800 * 1024**2:
        raise SystemExit('Need 800MiB host free before the bounded build')
    name = 'erp-quality-os-' + 'krb5' + '-builder'
    if subprocess.run(DOCKER + ['container', 'inspect', name], capture_output=True).returncode == 0:
        raise SystemExit('Builder name exists; no container was changed')
    version=json.loads(command('version','--format','{{json .Server}}'))
    if (version['Version']!=environment['engine']['version']
            or not environment['engine']['commit'].startswith(version['GitCommit'])
            or version['KernelVersion']!=environment['kernel_version']):
        raise ValueError('Kerberos prerequisite daemon/kernel revision changed')
    inventory=native_environment('inventory');test_environment.require_unused(inventory)
    base=json.loads(command('image','inspect','--format','{{json .}}',lock['base_image']))
    if base['Architecture']!='arm64' or base['Os']!='linux':raise ValueError('Require pinned Linux ARM64 base')
    output.mkdir(parents=True)
    (output/'abi-review').mkdir()
    for basename, path in reviewed.items():
        shutil.copyfile(path, output/'abi-review'/basename)
    shutil.copyfile(DIRECTORY / 'source_builder_mounts.py', output / 'source_builder_mounts.py')
    receipt = {'status': 'running', 'component': 'krb5', 'source': entry,
               'source_directory': str(source), 'base_image': lock['base_image'],
               'application_mounts': [], 'network_targets': 'Debian build dependencies only; upstream tests use disposable local test realms'}
    receipt['abi_exception'] = {'contract_sha256': test_environment.digest(abi_path),
        'review_evidence_sha256': {name: test_environment.digest(path) for name, path in reviewed.items()},
        'scope': abi['scope'], 'bundled_psycopg2_kerberos_source_fixed': False}
    request={'uid':test_environment.UID,'token':uuid.uuid4().hex,'profile_sha256':test_environment.PROFILE_SHA,
             'environment_sha256':test_environment.digest(environment_path)}
    receipt.update(test_environment={'policy':environment,'sha256':request['environment_sha256'],
                                    'request':request,'initial_reserved_uid':inventory,'daemon':version})
    request_path=output/'keyring-build-request.json';request_path.write_text(json.dumps(request,indent=2)+'\n');request_path.chmod(0o644)
    container = None
    evidence_copied = False
    script = 'tool-os-build-krb5.sh'
    try:
        container = command('create', '--pull=never', '--name', name, '--label', 'erp.quality.owner=runtime-security-os',
                            '--network','bridge',
                            '--cpus', '1', '--memory', '640m', '--memory-swap', '640m', '--pids-limit', '256',
                            '--init','--security-opt','no-new-privileges','--security-opt','seccomp='+str(DIRECTORY/'tool-os-krb5-seccomp.json'),
                            *source_builder_mounts.arguments(),
                            '--user', '0', '--entrypoint', '/bin/sh', lock['base_image'], '-c',
                            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/' + script)
        receipt['container_id'] = container
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        receipt.update(source_builder_mounts.inspect(command, container))
        info=json.loads(command('inspect','--format','{{json .}}',container))
        if info['Image']!=base['Id'] or info['Name']!='/'+name:raise ValueError('Owned Kerberos builder identity differs')
        receipt['test_environment']['actual_builder']=test_environment.validate_builder(info,json.loads((DIRECTORY/'tool-os-krb5-seccomp.json').read_text()))
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        command('start', container)
        free_kib = int(command('exec', container, 'sh', '-c', "df -Pk / | awk 'NR==2 {print $4}'"))
        if free_kib < 1000 * 1024:
            raise RuntimeError('Need 1000MiB VM free for a bounded source build')
        receipt['minimum_vm_free_mib'] = free_kib / 1024
        command('exec', container, 'mkdir', '-p', '/security-input')
        for archive in entry['sources']:
            command('cp', str(source / archive), container + ':/security-input/' + archive)
        for filename in dict.fromkeys((script, 'tool-os-package-krb5.py', 'tool-os-krb5.lock.json',test_environment.LOCK,
                         *environment['files'],*[p['file'] for p in lock['patches']])):
            command('cp', str(DIRECTORY / filename), container + ':/security-input/' + filename)
            shutil.copyfile(DIRECTORY / filename, output / filename)
        copy_control_json(container,request_path,receipt)
        command('cp',str(prerequisite),container+':/security-input/keyring-prerequisite.json')
        shutil.copyfile(prerequisite,output/'keyring-prerequisite.json')
        command('exec', container, 'touch', '/security-input/ready')
        deadline = time.monotonic() + 5400
        approved=set()
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
            try:
                stage=command('exec',container,'python3','-c',"from pathlib import Path;print('cleanup' if Path('/security-output/keyring-tests-finished').exists() else 'start' if Path('/security-output/keyring-test-ready').exists() else 'building')")
            except subprocess.CalledProcessError:
                if command('inspect','--format','{{.State.Running}}',container)=='false':break
                raise
            if stage in {'start','cleanup'} and stage not in approved:
                approve_keyring_stage(container,output,request,stage,receipt);approved.add(stage)
            time.sleep(3)
        receipt['exit_code'] = int(command('inspect', '--format', '{{.State.ExitCode}}', container))
        command('cp', container + ':/security-output/.', str(output))
        evidence_copied = True
        if receipt['exit_code']:
            raise RuntimeError('OS package build/tests failed; inspect retained build.log')
        if approved!={'start','cleanup'}:raise ValueError('No packaging acceptance without both reserved-UID controller proofs')
        test_environment.require_completed(json.loads((output/'keyring-tests/session.json').read_text()),request['token'])
        packages = sorted(output.glob('*.deb'))
        if not packages:
            raise RuntimeError('No packages produced')
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                       packages={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in packages})
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        if container:
            finish_keyring_environment(container,output,request,receipt)
            finish_container(container, evidence_copied, output, receipt)
            try:verify_final_uid_cleanup(output,request,receipt)
            except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
                receipt.setdefault('cleanup_errors',[]).append({'action':'reserved-UID-keyring-security-guard','error':str(error)})
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if receipt.get('cleanup_errors'):
        raise RuntimeError('Inspect cleanup_errors before retrying')


if __name__ == '__main__':
    main()
