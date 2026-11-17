#!/usr/bin/env python3
"""Install and smoke-test the exact N10 packages; never rebuild or repeat its suites."""
import argparse
import ast
import copy
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

HERE=Path(__file__).resolve().parent
LOCK='tool-os-curl-postbuild.lock.json'
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
build=module('curl_finish_build','tool-os-build-curl.py')
packages=module('curl_finish_packages','tool-os-curl-install.py')
offline=module('curl_finish_offline','install-runtime-debs.py')
digest=packages.digest
def read(path):return json.loads(path.read_text())

def require_cleanup(receipt):
    if any(receipt.get(k) for k in ['cleanup_errors','container_retained','evidence_copy_errors','scratch_retained']):
        receipt['status']='cleanup-failed'
        raise RuntimeError('Finish-only owned cleanup or evidence export failed')

def suite_counts(text):
    return [tuple(map(int,item)) for item in re.findall(r'^TESTDONE: (\d+) tests out of (\d+) reported OK: 100%$',text,re.M)]

def require_original_cleanup(proof, original, receipt_sha):
    if (proof.get('status')!='independently-clean-no-owned-native-jobs' or proof.get('container_inspect_exit')!=1
            or proof.get('scratch_absence_exit')!=0 or proof.get('container_id')!=original['container_id']
            or proof.get('scratch')!=original['scratch']['path'] or proof.get('receipt_sha256')!=receipt_sha):
        raise ValueError('Original independent N10 owned cleanup proof differs')

def verify_reviewed_smoke_changes(old, new):
    original=ast.parse(old);changed=ast.parse(new)
    helpers=[node for node in changed.body if isinstance(node,ast.FunctionDef) and node.name=='native_request_diagnostic']
    if len(helpers)!=1:raise ValueError('Require only the reviewed native failure diagnostic helper')
    changed.body.remove(helpers[0])
    handlers=[node for node in ast.walk(changed) if isinstance(node,ast.ClassDef) and node.name=='Handler']
    if len(handlers)!=1:raise ValueError('Require the original one local HTTPS fixture')
    methods=[node for node in handlers[0].body if isinstance(node,ast.FunctionDef) and node.name=='do_GET']
    if len(methods)!=1:raise ValueError('Require the original one fixture GET method')
    header=ast.parse("self.send_header('Content-Length', str(len(b'ERP curl compatibility\\n')))").body[0]
    ending=ast.parse('self.end_headers()').body[0]
    indexes=[i for i,node in enumerate(methods[0].body) if ast.dump(node)==ast.dump(ending)]
    if len(indexes)!=1 or indexes[0]<1 or ast.dump(methods[0].body[indexes[0]-1])!=ast.dump(header):
        raise ValueError('Require the one exact body-length header immediately before end_headers')
    methods[0].body.pop(indexes[0]-1)
    additions=[ast.parse(code).body[0] for code in [
        'error_buffer = ctypes.create_string_buffer(256)',
        'assert library.curl_easy_setopt(handle, 10010, error_buffer) == 0',
        'code = library.curl_easy_perform(handle)']]
    observed=[0,0,0,0]
    assertion=ast.parse('assert code == 0, native_request_diagnostic(name, code, error_buffer, library)').body[0]
    old_assertion=ast.parse('assert library.curl_easy_perform(handle) == 0').body[0]
    class Restore(ast.NodeTransformer):
        def visit(self,node):
            for index,addition in enumerate(additions):
                if ast.dump(node)==ast.dump(addition):observed[index]+=1;return None
            if ast.dump(node)==ast.dump(assertion):observed[3]+=1;return copy.deepcopy(old_assertion)
            return super().visit(node)
    changed=Restore().visit(changed)
    if observed!=[1,1,1,1] or ast.dump(original)!=ast.dump(changed):
        raise ValueError('Only failure diagnostics and the exact body-length header may change; TLS/URL/proxy/body/zero assertions must remain')

def verify_prior_finish(lock, diagnostic=False):
    number='2' if diagnostic else '1'
    evidence='diagnostic_finish_evidence' if diagnostic else 'prior_finish_evidence'
    cleanup_sha='diagnostic_finish_cleanup_sha256' if diagnostic else 'prior_finish_cleanup_sha256'
    prior=Path('/Volumes/ERPQuality/erp-quality/os-curl-finish-20261116-'+number)
    for name,entry in lock[evidence].items():
        path=prior/name
        if path.is_symlink() or path.stat().st_size!=entry['bytes'] or digest(path)!=entry['sha256']:
            raise ValueError('Original failed finish'+number+' evidence changed: '+name)
    receipt=read(prior/'receipt.json');require_cleanup(receipt)
    cleanup=HERE.parents[2]/('.local/quality/security-remediation/curl-native-smoke-diagnostic/finish2-cleanup.json' if diagnostic
                             else '.local/quality/security-remediation/curl-offline-finish-preparation/finish1-cleanup.json')
    proof=read(cleanup)
    if (digest(cleanup)!=lock[cleanup_sha] or receipt['status']!='failed' or receipt['exit_code']!=1
            or proof['receipt_sha256']!=digest(prior/'receipt.json') or proof['container_id']!=receipt['container_id']
            or proof['container_inspect_exit']!=1 or proof['scratch']!='none-created'
            or proof['status']!='independently-clean-no-owned-native-jobs'
            or read(prior/'offline-install/receipt.json')['status']!='passed'
            or read(prior/'installed-ELF.json')!={'status':'passed','installed_ELF_sha256':lock['installed_ELF_sha256']}):
        raise ValueError('Require original exact finish installation success/smoke failure/owned cleanup')
    if diagnostic:
        native=json.loads(next(line.removeprefix('AssertionError: ') for line in (prior/'finish.log').read_text().splitlines()
                               if line.startswith('AssertionError: {')))
        if native['library']!='libcurl.so.4' or native['curlcode']!=56 or 'unexpected eof while reading' not in native['error_buffer']:
            raise ValueError('Require the actual exact OpenSSL unexpected EOF evidence')
    return prior,cleanup

def verify_checkpoint(checkpoint):
    lock=read(HERE/LOCK)
    if any(p.is_symlink() for p in [checkpoint,*checkpoint.parents,*checkpoint.rglob('*')]):
        raise ValueError('N10 checkpoint must not contain symlinks')
    actual={str(p.relative_to(checkpoint)) for p in checkpoint.rglob('*') if p.is_file()}
    if actual!=set(lock['checkpoint_files']):raise ValueError('Exact N10 evidence inventory differs')
    for name,entry in lock['checkpoint_files'].items():
        path=checkpoint/name
        if path.stat().st_size!=entry['bytes'] or digest(path)!=entry['sha256']:
            raise ValueError('N10 evidence/package bytes changed: '+name)
    for name,entry in lock['finish_sources'].items():
        path=HERE/name
        if path.is_symlink() or path.stat().st_size!=entry['bytes'] or digest(path)!=entry['sha256']:
            raise ValueError('Reviewed finish-only source changed: '+name)
    original=read(checkpoint/'receipt.json')
    require_cleanup(original)
    cleanup=HERE.parents[2]/'.local/quality/security-remediation/curl2095-replay/N10-cleanup.json'
    if digest(cleanup)!=lock['original_owned_cleanup_sha256']:raise ValueError('Original cleanup evidence changed')
    require_original_cleanup(read(cleanup),original,digest(checkpoint/'receipt.json'))
    source=read(HERE/'tool-os-curl.lock.json')
    if (original['status']!='failed' or original['exit_code']!=1 or original['source']!=source
            or original['source']!=read(checkpoint/'tool-os-curl.lock.json')
            or original['base_image']!=source['base_image'] or original['application_mounts']!=[]):
        raise ValueError('Require the exact clean N10 install-only failure')
    verify_reviewed_smoke_changes((checkpoint/'tool-os-check-curl.py').read_text(),(HERE/'tool-os-check-curl.py').read_text())
    prior_finish,prior_cleanup=verify_prior_finish(lock)
    diagnostic_finish,diagnostic_cleanup=verify_prior_finish(lock,diagnostic=True)
    causal=HERE.parents[2]/'.local/quality/security-remediation/curl-native-smoke-diagnostic/finish2-actual-native-evidence.json'
    if digest(causal)!=lock['native_EOF_causal_packet_sha256']:raise ValueError('Actual EOF causal packet changed')
    expected=[(1886,1886),(1881,1881)]
    if (suite_counts((checkpoint/'build.log').read_text())!=expected
            or suite_counts((checkpoint/'upstream-openssl-tests.log').read_text())!=expected[:1]
            or suite_counts((checkpoint/'upstream-gnutls-tests.log').read_text())!=expected[1:]):
        raise ValueError('All four actual original suites must have completed successfully')
    abi=read(checkpoint/'abi-comparison.json')
    if {k:{x:v[x] for x in ['old_exports','new_exports','missing_exports']} for k,v in abi.items()}!={
            'libcurl.so.4':{'old_exports':97,'new_exports':101,'missing_exports':[]},
            'libcurl-gnutls.so.4':{'old_exports':97,'new_exports':202,'missing_exports':[]}}:
        raise ValueError('N10 SONAME/export proof differs')
    fixture=source['patches'][0]
    if read(checkpoint/'test-fixture-patch.json')['contract']!=fixture:
        raise ValueError('Actual local test-fixture patch is not source bound')
    for backend in ['openssl','gnutls']:
        flags=read(checkpoint/('test-compiler-flags-'+backend+'.json'))
        if flags['test_fixture_sha256']!=fixture['patched_sha256']:
            raise ValueError('Actual backend fixture differs')
    frozen=packages.manifest(checkpoint)
    if frozen!=lock['runtime_inputs']:raise ValueError('Exact eight N10 packages differ')
    runtime=read(checkpoint/'runtime-packages.json')
    for item in runtime.values():
        if frozen['files'][item['filename']]['sha256']!=item['sha256']:
            raise ValueError('Built runtime packages differ from original package receipt')
    elf=packages.elf_inventory(checkpoint,frozen)
    if elf!=lock['installed_ELF_sha256']:raise ValueError('Packaged ELF inventory differs')
    return {'lock':lock,'original':original,'source':source,'runtime_inputs':frozen,'installed_ELF_sha256':elf,
            'original_cleanup':cleanup,'prior_finish':prior_finish,'prior_finish_cleanup':prior_cleanup,
            'diagnostic_finish':diagnostic_finish,'diagnostic_cleanup':diagnostic_cleanup,'native_EOF_causal_packet':causal}

SCRIPT='''set -eu
umask 022
ulimit -c 0
mkdir -p /security-output
exec > /security-output/finish.log 2>&1
ERP_SECURITY_IMAGE_BUILD=1 python3 /security-input/install-runtime-debs.py --inputs /security-input/packages --output /security-output/offline-install
python3 /security-input/tool-os-curl-install.py verify --inputs /security-input/packages --output /security-output/installed-ELF.json
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/tool-os-check-curl.py smoke --baseline-dir /security-input/baseline > /security-output/compatibility.json
'''

def require_controls(info, name, image):
    host=info['HostConfig']
    if (info['Config']['Image']!=image or host['NetworkMode']!='none' or host['Privileged']
            or info['Config']['User']!='0' or info['Name']!='/'+name
            or info['Config']['Labels'].get('erp.quality.owner')!='runtime-security-curl-finish'
            or host.get('CapAdd') or host['Memory']!=640*1024**2 or host['MemorySwap']!=640*1024**2
            or host['NanoCpus']!=10**9 or host['PidsLimit']!=256 or host['SecurityOpt']!=['no-new-privileges']
            or not host['Init']):
        raise ValueError('Finish-only isolation/resource controls changed')

def verify_results(output, verified):
    if (output/'dpkg-audit.txt').read_bytes():raise ValueError('Package audit is not empty')
    install=read(output/'offline-install/receipt.json');frozen=verified['runtime_inputs']
    if (install['status']!='passed' or install['packages']!={x['name']:x for x in frozen['debian_packages']}
            or install['repositories']!=[] or install['network']!='loopback-only' or install['unlisted_package_changes']!=[]):
        raise ValueError('Exact offline installation proof is incomplete')
    for name,sha in install['evidence'].items():
        if Path(name).name!=name or digest(output/'offline-install'/name)!=sha:raise ValueError('Offline install evidence changed')
    before=read(output/'offline-install/packages-before.json');after=read(output/'offline-install/packages-after.json')
    expected=install['packages'];offline.verify_state(before,after,expected)
    needed={name:item['version'] for name,item in expected.items()
            if before.get(name+':'+item['architecture'])!={'version':item['version'],'status':'ii '}}
    if (offline.transaction((output/'offline-install/transaction-plan.log').read_text(),expected)!=needed
            or install['selected']!=needed or (output/'offline-install/dpkg-audit.txt').read_bytes()):
        raise ValueError('Exact offline transaction/state proof differs')
    installed=read(output/'installed-ELF.json')
    if installed!={'status':'passed','installed_ELF_sha256':verified['installed_ELF_sha256']}:
        raise ValueError('Actual installed ELF bytes differ from exact N10 packages')
    smoke=read(output/'compatibility.json')
    if smoke!={'cli_verified_https':True,'openssl_verified_https':True,'gnutls_verified_https':True,
               'gnutls3_symbol_alias':True,'upstream_removed_protocols':['rtmp','smb','smbs'],'upstream_removed_features':['TLS-SRP']}:
        raise ValueError('All unchanged actual HTTPS/alias smoke checks must pass')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--preflight',action='store_true');args=parser.parse_args()
    verified=verify_checkpoint(args.checkpoint);output=args.output.resolve()
    if output.exists():raise ValueError('Require fresh finish-only output; never rewrite N10 failure')
    if args.preflight:
        print(json.dumps({'status':'exact-N10-eight-packages-four-suites-ABI-verified-no-container','ELFs':verified['installed_ELF_sha256']}));return
    if shutil.disk_usage('/private/tmp').free<1200*1024**2:raise RuntimeError('Need original 1200MiB host start floor')
    output.mkdir(parents=True);shutil.copytree(args.checkpoint,output/'prior-build')
    shutil.copy2(verified['original_cleanup'],output/'original-owned-cleanup.json')
    for name in verified['lock']['prior_finish_evidence']:
        target=output/'prior-finish'/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(verified['prior_finish']/name,target)
    shutil.copy2(verified['prior_finish_cleanup'],output/'prior-finish/owned-cleanup.json')
    for name in verified['lock']['diagnostic_finish_evidence']:
        target=output/'prior-diagnostic-finish'/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(verified['diagnostic_finish']/name,target)
    shutil.copy2(verified['diagnostic_cleanup'],output/'prior-diagnostic-finish/owned-cleanup.json')
    shutil.copy2(verified['native_EOF_causal_packet'],output/'prior-diagnostic-finish/actual-native-evidence.json')
    for path in args.checkpoint.iterdir():
        if path.is_dir():shutil.copytree(path,output/path.name)
        elif path.name!='receipt.json':shutil.copy2(path,output/path.name)
    tools=output/'postbuild-tools';tools.mkdir()
    for filename in [*verified['lock']['finish_sources'],LOCK,Path(__file__).name]:
        shutil.copy2(HERE/filename,tools/filename)
        shutil.copy2(HERE/filename,output/filename)
    original=verified['original'];receipt=copy.deepcopy(original)
    receipt.update(status='running',exit_code=None,network_targets='loopback-only; local package installation and synthetic HTTPS',
        postbuild_recovery={'original_failed_receipt_sha256':digest(args.checkpoint/'receipt.json'),
        'finish_controller_sha256':digest(Path(__file__)),'checkpoint_contract_sha256':digest(HERE/LOCK),
        'original_owned_cleanup_sha256':verified['lock']['original_owned_cleanup_sha256'],
        'finish_sources':verified['lock']['finish_sources'],'only_installation_harness_and_reviewed_smoke_changes':True,
        'compiled_bytes_changed':False,'upstream_tests_repeated':False,'smoke_code_changed':True,
        'smoke_changes':['failure-only diagnostics','exact Content-Length for unchanged23byte body'],
        'production_TLS_policy_changed':False,
        'compiled_checker_sha256':digest(args.checkpoint/'tool-os-check-curl.py'),
        'current_checker_sha256':digest(HERE/'tool-os-check-curl.py'),
        'prior_failed_finish_receipt_sha256':verified['lock']['prior_finish_evidence']['receipt.json']['sha256'],
        'prior_finish_cleanup_sha256':verified['lock']['prior_finish_cleanup_sha256'],
        'diagnostic_failed_finish_receipt_sha256':verified['lock']['diagnostic_finish_evidence']['receipt.json']['sha256'],
        'diagnostic_finish_cleanup_sha256':verified['lock']['diagnostic_finish_cleanup_sha256'],
        'native_EOF_causal_packet_sha256':verified['lock']['native_EOF_causal_packet_sha256'],
        'installed_ELF_sha256':verified['installed_ELF_sha256'],
        'compiled_build_source_directory':'prior-build',
        'current_build_pipeline_executed':False})
    for key in ['error','container_id','scratch','scratch_request','scratch_cleanup',
                *[key for key in receipt if key.startswith('minimum_')]]:
        receipt.pop(key,None)
    container=None;copied=False
    try:
        name='erp-quality-curl-N10-finish-'+uuid.uuid4().hex
        container=build.command('create','--pull=never','--name',name,'--label','erp.quality.owner=runtime-security-curl-finish',
            '--network','none','--cpus','1','--memory','640m','--memory-swap','640m','--pids-limit','256',
            '--init','--security-opt','no-new-privileges',*build.source_builder_mounts.arguments(),
            '--user','0','--entrypoint','/bin/sh',verified['source']['base_image'],'-c',
            'while [ ! -f /security-input/ready ]; do sleep 1; done; exec sh /security-input/finish.sh')
        receipt['container_id']=container;receipt.update(build.source_builder_mounts.inspect(build.command,container))
        info=json.loads(build.command('inspect','--format','{{json .}}',container));require_controls(info,name,verified['source']['base_image'])
        receipt['postbuild_recovery']['actual_builder']=info
        build.command('start',container)
        free=int(build.command('exec',container,'sh','-c',"df -Pk / | awk 'NR==2 {print $4}'"))/1024
        if free<1000:raise RuntimeError('Need original 1000MiB VM start floor')
        receipt['minimum_vm_free_mib']=free
        build.command('exec',container,'mkdir','-p','/security-input/packages/dependencies','/security-input/baseline','/security-output')
        for relative in verified['runtime_inputs']['files']:
            build.command('cp',str(args.checkpoint/relative),container+':/security-input/packages/'+relative)
        (output/'runtime-image-inputs.json').write_text(json.dumps(verified['runtime_inputs'],indent=2)+'\n')
        build.command('cp',str(output/'runtime-image-inputs.json'),container+':/security-input/packages/runtime-image-inputs.json')
        for filename in ['install-runtime-debs.py','tool-os-curl-install.py','tool-os-check-curl.py','tool-os-curl.lock.json']:
            build.command('cp',str(HERE/filename),container+':/security-input/'+filename)
        build.command('cp',str(args.checkpoint/'original-curl-version.txt'),container+':/security-input/baseline/original-curl-version.txt')
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
        if receipt['exit_code']:raise RuntimeError('Exact N10 offline install/smoke failed; retain raw evidence')
        verify_results(output,verified)
        receipt.update(status='built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                       packages={k:v['sha256'] for k,v in verified['runtime_inputs']['files'].items()})
        receipt['postbuild_recovery']['new_result_sha256']={name:digest(output/name) for name in
            ['compatibility.json','installed-ELF.json','offline-install/receipt.json']}
        (output/'postbuild-verification.json').write_text(json.dumps({'status':'exact-N10-packages-offline-install-and-framed-smoke-passed',
            'all_four_original_suites_passed':True,'both_original_ABI_checks_passed':True,
            **receipt['postbuild_recovery']},indent=2)+'\n')
    except BaseException as error:receipt.update(status='failed',error=str(error));raise
    finally:
        if container:build.finish_container(container,copied,output,receipt)
        try:require_cleanup(receipt)
        finally:(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')

if __name__=='__main__':main()
