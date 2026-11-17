#!/usr/bin/env python3
"""Finish only the exact N7 packages after correcting the GSS OID assertion."""
import argparse
import ast
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import time
import uuid

HERE=Path(__file__).resolve().parent
LOCK='tool-os-krb5-postbuild.lock.json'
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
build=module('original_krb_builder','tool-os-build-krb5.py')
package=module('postbuild_krb_package','tool-os-package-krb5.py')
environment=build.test_environment
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text())

def verify_assertion_only_change(old,new):
    original=ast.parse(old);changed=ast.parse(new)
    helper=[n for n in changed.body if isinstance(n,ast.FunctionDef) and n.name=='require_name_roundtrip']
    if len(helper)!=1:raise ValueError('Require the one reviewed OID-value helper')
    changed.body.remove(helper[0])
    assertion=ast.parse('assert ctypes.string_at(displayed.value, displayed.length) == text and kind.value == user_name.value').body[0]
    call=ast.parse('require_name_roundtrip(text, ctypes.string_at(displayed.value, displayed.length), user_name, kind)').body[0]
    replacements=[]
    class Restore(ast.NodeTransformer):
        def visit_Expr(self,node):
            if ast.dump(node)==ast.dump(call):
                replacements.append(node);return copy.deepcopy(assertion)
            return self.generic_visit(node)
    changed=Restore().visit(changed)
    if len(replacements)!=1 or ast.dump(original)!=ast.dump(changed):
        raise ValueError('Only the postbuild OID assertion may differ; compiled package/build code changed')

def deb_tar(path,prefix):
    raw=path.read_bytes()
    if raw[:8]!=b'!<arch>\n':raise ValueError('Invalid pinned Debian package')
    offset=8
    while offset<len(raw):
        header=raw[offset:offset+60];size=int(header[48:58]);name=header[:16].decode().strip().rstrip('/')
        if header[-2:]!=b'`\n':raise ValueError('Invalid Debian archive member')
        if name.startswith(prefix):return tarfile.open(fileobj=io.BytesIO(raw[offset+60:offset+60+size]))
        offset+=60+size+(size%2)
    raise ValueError('Missing pinned Debian package archive: '+prefix)

def verify_checkpoint(checkpoint):
    lock=read(HERE/LOCK)
    if any(p.is_symlink() for p in [checkpoint,*checkpoint.parents]):raise ValueError('Checkpoint symlink')
    if any(p.is_symlink() for p in checkpoint.rglob('*')):raise ValueError('Checkpoint contains a symlink')
    actual={str(p.relative_to(checkpoint)) for p in checkpoint.rglob('*') if p.is_file()}
    if actual!=set(lock['checkpoint_files']):raise ValueError('Exact N7 file inventory differs')
    for name,expected in lock['checkpoint_files'].items():
        path=checkpoint/name
        if path.is_symlink() or path.stat().st_size!=expected['bytes'] or digest(path)!=expected['sha256']:
            raise ValueError('N7 evidence or package bytes changed: '+name)
    original=read(checkpoint/'receipt.json')
    if (digest(checkpoint/'receipt.json')!=lock['checkpoint_receipt_sha256']
            or original['status']!='failed' or original['exit_code']!=1
            or any(original.get(k) for k in ['cleanup_errors','container_retained','evidence_copy_errors'])
            or (checkpoint/'dpkg-audit.txt').read_bytes()):raise ValueError('N7 did not reach the exact clean postbuild failure')
    environment.require_unused(original['reserved_uid_after_cleanup'])
    current=read(HERE/'tool-os-krb5.lock.json');old_source=read(checkpoint/'tool-os-krb5.lock.json')
    if original['source']!=old_source or digest(HERE/'tool-os-krb5.lock.json')!=lock['postbuild_source_lock_sha256']:
        raise ValueError('N7 source receipt or postbuild source binding changed')
    old_comparable=copy.deepcopy(old_source);new_comparable=copy.deepcopy(current)
    old_comparable['test_environment'].pop('sha256');new_comparable['test_environment'].pop('sha256')
    if old_comparable!=new_comparable:raise ValueError('Compiled sources, patches or production contract changed')
    old_policy=environment.load_environment(checkpoint);new_policy=environment.load_environment(HERE)
    if environment.digest(checkpoint/environment.LOCK)!=old_source['test_environment']['sha256']:
        raise ValueError('N7 ordinary test environment is not source-bound')
    before=copy.deepcopy(old_policy);after=copy.deepcopy(new_policy)
    before['files'].pop('tool-os-package-krb5.py');after['files'].pop('tool-os-package-krb5.py')
    if before!=after:raise ValueError('Ordinary test environment changed beyond postbuild assertion checker')
    if (digest(checkpoint/'tool-os-package-krb5.py')!=lock['original_checker_sha256']
            or digest(HERE/'tool-os-package-krb5.py')!=lock['postbuild_checker_sha256']):
        raise ValueError('Reviewed old/new postbuild checker bytes changed')
    verify_assertion_only_change((checkpoint/'tool-os-package-krb5.py').read_text(),(HERE/'tool-os-package-krb5.py').read_text())
    token=original['test_environment']['request']['token'];journal=read(checkpoint/'keyring-test-session.json')
    environment.require_completed(journal,token)
    if original['test_environment']['policy']!=old_policy:raise ValueError('Actual N7 test policy differs')
    for stage in ['start','cleanup']:
        path=checkpoint/('keyring-'+stage+'-approval.json');approval=read(path)
        if (digest(path)!=original['keyring_'+stage+'_approval_sha256'] or approval['token']!=token
                or approval['environment_sha256']!=old_source['test_environment']['sha256']
                or not approval['UID_processes_absent'] or not approval['UID_keys_absent']):
            raise ValueError('N7 independent test/cleanup approval differs')
        environment.require_unused(approval['native_inventory'])
    if approval['journal_sha256']!=digest(checkpoint/'keyring-test-session.json'):raise ValueError('N7 completion journal differs')
    environment.verify_keyring_logs((checkpoint/'keyring-t_cccol-verbose.log').read_text(),(checkpoint/'keyring-t_ccache-verbose.log').read_text())
    abi=read(checkpoint/'abi-comparison.json');contract,_=package.load_abi_contract(HERE)
    reviewed=read(checkpoint/'abi-exception-evidence.json')
    expected=package.reviewed_removal(set(reviewed['missing_symbols']),reviewed['reviewed_context'],contract)
    if any(reviewed.get(k)!=v for k,v in expected.items()):raise ValueError('Reviewed N7 ABI difference changed')
    if set(lock['packages'])!={p.name for p in checkpoint.glob('*.deb')}:raise ValueError('Require exact four N7 packages')
    seen={}
    for name,sha in lock['packages'].items():
        path=checkpoint/name
        if digest(path)!=sha:raise ValueError('N7 package changed')
        with deb_tar(path,'control.tar') as archive:
            control=archive.extractfile(next(x for x in archive if x.name.lstrip('./')=='control')).read().decode()
            fields=dict(re.findall(r'^(Package|Version|Architecture): (.+)$',control,re.M))
            if fields['Package'] not in package.PACKAGES or fields['Version']!=package.VERSION or fields['Architecture']!='arm64':
                raise ValueError('N7 Debian package identity changed')
        with deb_tar(path,'data.tar') as archive:
            for item in archive:
                if not item.isfile():continue
                data=archive.extractfile(item).read()
                if data[:4]==b'\x7fELF':
                    relative=item.name.removeprefix('./');sha=hashlib.sha256(data).hexdigest()
                    if relative not in abi or abi[relative]['candidate_sha256']!=sha:raise ValueError('Packaged ELF differs from N7 ABI receipt')
                    seen[relative]=sha
    if set(seen)!=set(abi) or len(lock['packages'])!=4:raise ValueError('Incomplete N7 installed ELF/package inventory')
    return {'lock':lock,'original':original,'source':current,'installed_ELF_sha256':seen}

SCRIPT='''set -eu
umask 022
mkdir -p /security-output
exec > /security-output/build.log 2>&1
dpkg -i /security-input/packages/libkrb5support0_*.deb /security-input/packages/libk5crypto3_*.deb /security-input/packages/libkrb5-3_*.deb /security-input/packages/libgssapi-krb5-2_*.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/tool-os-package-krb5.py smoke > /security-output/compatibility.json
'''

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--checkpoint',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--preflight',action='store_true');args=parser.parse_args()
    verified=verify_checkpoint(args.checkpoint);output=args.output.resolve()
    if output.exists():raise ValueError('Require fresh finish-only output; never rewrite N7 failure')
    if args.preflight:print(json.dumps({'status':'exact-N7-packages-and-original-tests-verified-no-container','ELFs':verified['installed_ELF_sha256']}));return
    if shutil.disk_usage('/private/tmp').free<800*1024**2:raise RuntimeError('Need original 800MiB host start floor')
    initial=build.native_environment('inventory');environment.require_unused(initial)
    output.mkdir(parents=True);shutil.copytree(args.checkpoint,output/'prior-build')
    for path in args.checkpoint.iterdir():
        if path.is_file() and path.name!='receipt.json':shutil.copy2(path,output/path.name)
    source=verified['source'];policy=environment.load_environment(HERE)
    for name in ['tool-os-krb5.lock.json',environment.LOCK,*policy['files'],LOCK,Path(__file__).name]:
        shutil.copy2(HERE/name,output/name)
    original=verified['original'];receipt=copy.deepcopy(original)
    receipt.update(status='running',exit_code=None,source=source,postbuild_recovery={
        'original_failed_receipt_sha256':verified['lock']['checkpoint_receipt_sha256'],
        'postbuild_checker_sha256':verified['lock']['postbuild_checker_sha256'],
        'finish_controller_sha256':digest(Path(__file__)),'checkpoint_contract_sha256':digest(HERE/LOCK),
        'only_postbuild_assertion_changed':True,'compiled_bytes_changed':False,'upstream_tests_repeated':False,
        'installed_ELF_sha256':verified['installed_ELF_sha256'],'initial_reserved_uid':initial})
    for key in ['error','minimum_vm_free_mib','minimum_host_free_mib','container_id']:receipt.pop(key,None)
    container=None;copied=False
    try:
        name='erp-quality-krb5-N7-finish-'+uuid.uuid4().hex
        container=build.command('create','--pull=never','--name',name,'--label','erp.quality.owner=runtime-security-krb5-finish',
            '--network','none','--cpus','1','--memory','640m','--memory-swap','640m','--pids-limit','256',
            '--init','--security-opt','no-new-privileges',*build.source_builder_mounts.arguments(),
            '--user','0','--entrypoint','/bin/sh',source['base_image'],'-c',
            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/finish.sh')
        receipt['container_id']=container;receipt.update(build.source_builder_mounts.inspect(build.command,container))
        info=json.loads(build.command('inspect','--format','{{json .}}',container));host=info['HostConfig']
        if (info['Config']['Image']!=source['base_image'] or host['NetworkMode']!='none' or host['Privileged']
                or info['Config']['User']!='0' or info['Name']!='/'+name
                or info['Config']['Labels'].get('erp.quality.owner')!='runtime-security-krb5-finish'
                or host.get('CapAdd') or host['Memory']!=640*1024**2 or host['MemorySwap']!=640*1024**2
                or host['NanoCpus']!=10**9 or host['PidsLimit']!=256 or host['SecurityOpt']!=['no-new-privileges']):
            raise ValueError('Finish-only builder isolation/resource controls changed')
        receipt['postbuild_recovery']['actual_controls']={k:host[k] for k in ['NetworkMode','Memory','MemorySwap','NanoCpus','PidsLimit','Privileged','CapAdd','SecurityOpt']}
        build.command('start',container)
        free=int(build.command('exec',container,'sh','-c',"df -Pk / | awk 'NR==2 {print $4}'"))/1024
        if free<1000:raise RuntimeError('Need original 1000MiB VM start floor')
        receipt['minimum_vm_free_mib']=free
        build.command('exec',container,'mkdir','-p','/security-input/packages','/security-output')
        for filename in verified['lock']['packages']:build.command('cp',str(args.checkpoint/filename),container+':/security-input/packages/'+filename)
        for filename in ['tool-os-package-krb5.py','tool-os-krb5-consumers.py','tool-os-krb5-abi-exception.json','tool-os-krb5.lock.json']:
            build.command('cp',str(HERE/filename),container+':/security-input/'+filename)
        build.command('cp',str(args.checkpoint/'abi-exception-evidence.json'),container+':/security-output/abi-exception-evidence.json')
        (output/'finish.sh').write_text(SCRIPT);build.command('cp',str(output/'finish.sh'),container+':/security-input/finish.sh')
        build.command('exec',container,'touch','/security-input/ready');deadline=time.monotonic()+600
        while build.command('inspect','--format','{{.State.Running}}',container)=='true':
            try:free=int(build.command('exec',container,'sh','-c',"df -Pk / | awk 'NR==2 {print $4}'"))/1024
            except subprocess.CalledProcessError:
                if build.command('inspect','--format','{{.State.Running}}',container)=='false':break
                raise
            host_free=shutil.disk_usage('/private/tmp').free/1024**2
            receipt['minimum_vm_free_mib']=min(receipt['minimum_vm_free_mib'],free)
            receipt['minimum_host_free_mib']=min(receipt.get('minimum_host_free_mib',float('inf')),host_free)
            if min(free,host_free)<400 or time.monotonic()>deadline:raise RuntimeError('Original 400MiB floor or bounded 10-minute finish guard')
            time.sleep(3)
        receipt['exit_code']=int(build.command('inspect','--format','{{.State.ExitCode}}',container))
        build.command('cp',container+':/security-output/.',str(output));copied=True
        if receipt['exit_code'] or (output/'dpkg-audit.txt').read_bytes():raise RuntimeError('Exact N7 install/smoke failed; retain raw logs')
        result=read(output/'compatibility.json')
        if not all(result.get(k) for k in ['gss_name_roundtrip','canonical_native_libraries_loaded','installed_consumer_recheck']):raise ValueError('Incomplete final GSS checks')
        if result.get('loaded_library_sha256')!={'/'+k:v for k,v in verified['installed_ELF_sha256'].items()}:
            raise ValueError('Actual installed libraries/plugin differ from all five N7 packaged ELF hashes')
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',packages=verified['lock']['packages'])
        receipt['postbuild_recovery']['new_smoke_result_sha256']=digest(output/'compatibility.json')
        (output/'postbuild-verification.json').write_text(json.dumps({
            'status':'verified-exact-N7-compiled-bytes-and-final-smoke',
            'compiled_bytes_changed':False,'upstream_tests_repeated':False,
            'all_five_installed_ELF_hashes_match':True,'complete_final_GSS_and_consumer_checks':True,
            **receipt['postbuild_recovery']},indent=2)+'\n')
    except BaseException as error:receipt.update(status='failed',error=str(error));raise
    finally:
        if container:build.finish_container(container,copied,output,receipt)
        try:
            receipt['reserved_uid_after_cleanup']=build.native_environment('inventory');environment.require_unused(receipt['reserved_uid_after_cleanup'])
        except BaseException as error:receipt.setdefault('cleanup_errors',[]).append({'action':'read-only-reserved-UID-postcheck','error':str(error)})
        (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    if receipt.get('cleanup_errors'):raise RuntimeError('Finish-only cleanup did not pass')

if __name__=='__main__':main()
