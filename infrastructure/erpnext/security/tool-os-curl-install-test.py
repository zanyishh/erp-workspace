#!/usr/bin/env python3
"""Host guards for exact Curl package recovery and its offline transition."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE/file)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
install = load('curl_install', 'tool-os-curl-install.py')
build = load('curl_build_install_test', 'tool-os-build-curl.py')

class Guards(unittest.TestCase):
    def test_exact_manifest_identity_and_inventory(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            packages = {}
            for name, version in install.EXPECTED.items():
                relative = ('dependencies/' if name.startswith('libng') else '')+f'{name}_{version}_arm64.deb'
                path = directory/relative; path.parent.mkdir(exist_ok=True); path.write_bytes(name.encode())
                packages[relative] = {'Package': name, 'Version': version, 'Architecture': 'arm64'}
            def control(path, prefix):
                return packages[str(path.relative_to(directory))]
            with patch.object(install, 'control', side_effect=control):
                manifest = install.manifest(directory)
                self.assertEqual(len(manifest['debian_packages']), 8)
                for field, value in [('Version','unexpected'),('Architecture','amd64'),('Package','other')]:
                    name = next(iter(packages)); original = packages[name][field]; packages[name][field] = value
                    with self.subTest(field=field), self.assertRaises(ValueError): install.manifest(directory)
                    packages[name][field] = original
                extra = directory/'unexpected.deb'; extra.write_bytes(b'x')
                with self.assertRaises(ValueError): install.manifest(directory)
                extra.unlink()
                name = next(iter(packages)); target=directory/name; target.unlink(); target.symlink_to(directory/'absent')
                with self.assertRaises(ValueError): install.manifest(directory)

    def test_installed_bytes_and_symlink_changes_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); path=root/'usr/bin/curl'; path.parent.mkdir(parents=True); path.write_bytes(b'ELF bytes')
            expected={'usr/bin/curl':install.digest(path)}
            self.assertEqual(install.verify_installed(expected, root), expected)
            path.write_bytes(b'changed')
            with self.assertRaises(ValueError): install.verify_installed(expected, root)
            path.unlink(); path.symlink_to('other')
            with self.assertRaises(ValueError): install.verify_installed(expected, root)

    def test_network_transition_requires_same_exact_owned_ready_builder(self):
        info={'Id':'a'*64,'Created':'created','Name':'/owned','Config':{'Image':'pinned', 'Labels':{'erp.quality.owner':'runtime-security-os'}},
              'State':{'Running':True},'HostConfig':{'NetworkMode':'bridge'},
              'NetworkSettings':{'Networks':{'bridge':{'NetworkID':'b'*64,'EndpointID':'c'*64}}}}
        expected={'Id':info['Id'],'Created':'created','Name':'/owned','Image':'pinned','NetworkID':'b'*64,'HostConfig':copy.deepcopy(info['HostConfig'])}
        self.assertTrue(build.require_install_builder(info, expected, True))
        for field in ['Id','Created','Name']:
            bad=copy.deepcopy(info);bad[field]='wrong'
            with self.subTest(field=field),self.assertRaises(ValueError):build.require_install_builder(bad,expected,True)
        for mode in ['host','none','custom','default']:
            bad=copy.deepcopy(info);bad['HostConfig']['NetworkMode']=mode
            with self.subTest(mode=mode),self.assertRaises(ValueError):build.require_install_builder(bad,expected,True)
        for field in ['Image','Labels']:
            bad=copy.deepcopy(info);bad['Config'][field]='wrong'
            with self.subTest(field=field),self.assertRaises(ValueError):build.require_install_builder(bad,expected,True)
        for networks in [{},{'other':{}},{'bridge':{'NetworkID':'wrong','EndpointID':'c'*64}}, {'bridge':{},'other':{}}]:
            bad=copy.deepcopy(info);bad['NetworkSettings']['Networks']=networks
            with self.assertRaises(ValueError):build.require_install_builder(bad,expected,True)
        with self.assertRaises(ValueError):build.require_install_builder(info,expected,False)
        bad=copy.deepcopy(info);bad['NetworkSettings']['Networks']={}
        self.assertTrue(build.require_install_builder(bad,expected,True,detached=True))

    def test_original_bounded_gate_never_installs_before_network_approval(self):
        script=(HERE/'tool-os-build-curl.sh').read_text()
        self.assertIn('remaining=180',script)
        self.assertIn('test "$remaining" -gt 0',script)
        self.assertLess(script.index('test "$remaining" -gt 0'),script.index('ERP_SECURITY_IMAGE_BUILD=1'))
        self.assertNotIn('--force',script)
        self.assertNotIn('--no-download',script)

    def test_wrong_checkpoint_hash_missing_and_unexpected_files_fail_first(self):
        finish=load('curl_finish_inventory_guard','tool-os-finish-curl.py')
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary).resolve();checkpoint=root/'checkpoint';checkpoint.mkdir();source=root/'source';source.mkdir()
            item=checkpoint/'receipt.json';item.write_text('{}')
            lock={'checkpoint_files':{'receipt.json':{'bytes':2,'sha256':install.digest(item)}},'finish_sources':{}}
            (source/finish.LOCK).write_text(json.dumps(lock))
            with patch.object(finish,'HERE',source):
                item.write_text('[]')
                with self.assertRaisesRegex(ValueError,'bytes changed'):finish.verify_checkpoint(checkpoint)
                item.unlink()
                with self.assertRaisesRegex(ValueError,'inventory differs'):finish.verify_checkpoint(checkpoint)
                item.write_text('{}');(checkpoint/'extra').write_text('x')
                with self.assertRaisesRegex(ValueError,'inventory differs'):finish.verify_checkpoint(checkpoint)

    def test_only_expected_default_bridge_is_disconnected_before_marker(self):
        info={'Id':'a'*64,'Created':'created','Name':'/owned','Config':{'Image':'pinned','Labels':{'erp.quality.owner':'runtime-security-os'}},
              'State':{'Running':True},'HostConfig':{'NetworkMode':'bridge'},
              'NetworkSettings':{'Networks':{'bridge':{'NetworkID':'b'*64,'EndpointID':'c'*64}}}}
        expected={'Id':info['Id'],'Created':'created','Name':'/owned','Image':'pinned','NetworkID':'b'*64,'HostConfig':copy.deepcopy(info['HostConfig'])}
        detached=copy.deepcopy(info);detached['NetworkSettings']['Networks']={}
        for interfaces in [['lo'],['lo','eth0']]:
            calls=[];inspections=iter([info,detached])
            def command(*args):
                calls.append(args)
                if args[0]=='inspect':return json.dumps(next(inspections))
                if args[:2]==('exec',info['Id']) and 'python3' in args:return json.dumps(interfaces)
                return 'ready'
            with tempfile.TemporaryDirectory() as temporary,patch.object(build,'command',side_effect=command):
                if interfaces==['lo']:build.offline_install(info['Id'],expected,Path(temporary),{})
                else:
                    with self.assertRaises(ValueError):build.offline_install(info['Id'],expected,Path(temporary),{})
            self.assertEqual([c for c in calls if c[0]=='network'],[('network','disconnect','b'*64,'a'*64)])
            released=any('touch' in c for c in calls)
            self.assertEqual(released,interfaces==['lo'])

    def test_cleanup_failure_cannot_be_accepted(self):
        finish=load('curl_finish_guard','tool-os-finish-curl.py')
        for key in ['cleanup_errors','container_retained','evidence_copy_errors','scratch_retained']:
            receipt={'status':'built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',key:['retained']}
            with self.subTest(key=key),self.assertRaises(RuntimeError):finish.require_cleanup(receipt)
            self.assertEqual(receipt['status'],'cleanup-failed')

    def test_finisher_cannot_gain_network_privilege_or_resources(self):
        finish=load('curl_finish_control_guard','tool-os-finish-curl.py')
        info={'Name':'/owned','Config':{'Image':'pinned','User':'0','Labels':{'erp.quality.owner':'runtime-security-curl-finish'}},
              'HostConfig':{'NetworkMode':'none','Privileged':False,'CapAdd':None,'Memory':640*1024**2,
                            'MemorySwap':640*1024**2,'NanoCpus':10**9,'PidsLimit':256,'SecurityOpt':['no-new-privileges'],'Init':True}}
        finish.require_controls(info,'owned','pinned')
        for key,value in [('NetworkMode','bridge'),('Privileged',True),('CapAdd',['SYS_ADMIN']),('Memory',1024**3),
                          ('MemorySwap',1024**3),('NanoCpus',2*10**9),('PidsLimit',512),('SecurityOpt',[]),('Init',False)]:
            bad=copy.deepcopy(info);bad['HostConfig'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):finish.require_controls(bad,'owned','pinned')

    def test_original_cleanup_requires_exact_container_scratch_and_receipt(self):
        finish=load('curl_finish_original_cleanup_guard','tool-os-finish-curl.py')
        original={'container_id':'a'*64,'scratch':{'path':'/tmp/own'}}
        proof={'status':'independently-clean-no-owned-native-jobs','container_inspect_exit':1,'scratch_absence_exit':0,
               'container_id':original['container_id'],'scratch':'/tmp/own','receipt_sha256':'b'*64}
        finish.require_original_cleanup(proof,original,'b'*64)
        for key in proof:
            bad=copy.deepcopy(proof);bad[key]='wrong'
            with self.subTest(key=key),self.assertRaises(ValueError):finish.require_original_cleanup(bad,original,'b'*64)

    def test_reviewed_smoke_delta_cannot_change_tls_body_or_zero_assertions(self):
        finish=load('curl_finish_diagnostic_delta_guard','tool-os-finish-curl.py')
        old='''class Handler:
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ERP curl compatibility\\n')
def lib_request(name, url, certificate):
    assert library.curl_easy_setopt(handle, 10065, certificate) == 0
    assert library.curl_easy_perform(handle) == 0
    assert body == b'expected body'
'''
        header="        self.send_header('Content-Length', str(len(b'ERP curl compatibility\\n')))\n"
        new="def native_request_diagnostic(name, code, error_buffer, library):\n    return str(code)\n"+old.replace(
            '    assert library.curl_easy_perform(handle) == 0',
            '    error_buffer = ctypes.create_string_buffer(256)\n    assert library.curl_easy_setopt(handle, 10010, error_buffer) == 0\n    code = library.curl_easy_perform(handle)\n    assert code == 0, native_request_diagnostic(name, code, error_buffer, library)').replace('        self.end_headers()\n',header+'        self.end_headers()\n')
        finish.verify_reviewed_smoke_changes(old,new)
        for bad in [new.replace('10065','10066'),new.replace("self.send_response(200)","self.send_response(201)"),
                    new.replace("assert body == b'expected body'",'assert True'),new.replace('assert code == 0,','assert code in (0,60),'),
                    new.replace('create_string_buffer(256)','create_string_buffer(4096)'),new.replace(header,''),
                    new.replace(header,header+header),new.replace("len(b'ERP curl compatibility\\n')",'22'),
                    new.replace(header+'        self.end_headers()\n','        self.end_headers()\n'+header)]:
            with self.assertRaises(ValueError):finish.verify_reviewed_smoke_changes(old,bad)

if __name__ == '__main__': unittest.main()
