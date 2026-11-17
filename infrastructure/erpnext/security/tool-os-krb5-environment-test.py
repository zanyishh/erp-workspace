#!/usr/bin/env python3
"""No kernel calls: exact test policy and exclusive-owned cleanup boundaries."""
import copy
import errno
import importlib.util
import json
from pathlib import Path
import shutil
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('environment',HERE/'tool-os-krb5-test-environment.py')
environment=importlib.util.module_from_spec(spec);spec.loader.exec_module(environment)
TOKEN='f0a0f6ec6229472e86284c9dad65735d'


class FakeKeys:
    def __init__(self,foreign=False,missing=False):self.foreign=foreign;self.missing=missing;self.changed=[]
    def describe(self,key):
        if self.missing:raise OSError(126,'already gone')
        names={101:'erp-krb5-tests-'+TOKEN,102:'_pid',103:'_uid.194812',104:'_uid_ses.194812'}
        return ['keyring','0' if self.foreign else '194812','194812','perm',names[key]]
    def ctl(self,command,key,*args):self.changed.append((command,key));return 0


class Guards(unittest.TestCase):
    def journal(self):
        return {'uid':194812,'token':TOKEN,'wrapper_pid':123,
                'profile_sha256':environment.PROFILE_SHA,
                'rings':[{'id':101,'name':'erp-krb5-tests-'+TOKEN},{'id':102,'name':'_pid'},
                         {'id':103,'name':'_uid.194812'},{'id':104,'name':'_uid_ses.194812'}]}

    def test_uid_reuse_or_any_other_uid_is_rejected(self):
        good={'uid':194812,'account':False,'group':False,'processes':[],'key_users':[]}
        environment.require_unused(good)
        for key,value in [('uid',0),('uid',194813),('account',True),('group',True),('processes',['42']),('key_users',['194812: key'])]:
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):environment.require_unused(dict(good,**{key:value}))

    def test_extra_permission_or_changed_original_profile_is_rejected(self):
        base=json.loads((HERE/'tool-os-krb5-seccomp-default.json').read_text());profile=json.loads((HERE/'tool-os-krb5-seccomp.json').read_text())
        environment.validate_profile(base,profile)
        for kind in ['syscall','rule','default']:
            changed=copy.deepcopy(profile)
            if kind=='syscall':changed['syscalls'][-1]['names'].append('bpf')
            elif kind=='rule':changed['syscalls'].pop(0)
            else:changed['defaultAction']='SCMP_ACT_ALLOW'
            with self.subTest(kind=kind),self.assertRaises(ValueError):environment.validate_profile(base,changed)

    def test_other_uid_token_profile_name_or_ring_id_is_never_adopted(self):
        for kind in ['uid','token','profile','name','id','duplicate']:
            j=self.journal()
            if kind=='uid':j['uid']=0
            elif kind=='token':j['token']='b'*32
            elif kind=='profile':j['profile_sha256']='0'*64
            elif kind=='name':j['rings'][0]['name']='outside-keyring'
            elif kind=='id':j['rings'][0]['id']=-4
            else:j['rings'].append(j['rings'][0])
            with self.subTest(kind=kind),self.assertRaises(ValueError):environment.validate_journal(j,TOKEN)

    def test_cleanup_changes_only_four_exact_owned_keyrings(self):
        keys=FakeKeys();result=environment.cleanup_rings(keys,self.journal(),TOKEN)
        self.assertFalse(any('error' in x for x in result))
        self.assertEqual({key for _,key in keys.changed},{101,102,103,104})

    def test_foreign_owner_is_never_modified(self):
        keys=FakeKeys(foreign=True);result=environment.cleanup_rings(keys,self.journal(),TOKEN)
        self.assertTrue(all('error' in x for x in result));self.assertEqual(keys.changed,[])

    def test_already_garbage_collected_keys_are_not_recreated(self):
        keys=FakeKeys(missing=True);result=environment.cleanup_rings(keys,self.journal(),TOKEN)
        self.assertTrue(all(x.get('already_gone') for x in result));self.assertEqual(keys.changed,[])

    def test_root_capabilities_and_missing_seccomp_are_rejected(self):
        good={'Uid':'194812 194812 194812 194812','Gid':'194812 194812 194812 194812',
              'CapEff':'0000000000000000','CapPrm':'0000000000000000','CapAmb':'0000000000000000','CapBnd':'0000000000000000','NoNewPrivs':'1','Seccomp':'2'}
        environment.validate_identity(good,194812,194812,194812,require_seccomp=True,require_bounding=True)
        for key,value in [('Uid','0 0 0 0'),('CapEff','0000000000000001'),('CapBnd','0000000000000001'),('NoNewPrivs','0'),('Seccomp','0')]:
            with self.subTest(key=key),self.assertRaises(ValueError):environment.validate_identity(dict(good,**{key:value}),194812,194812,194812,require_seccomp=True,require_bounding=True)

    def test_actual_builder_inspection_rejects_extra_privilege_or_other_profile(self):
        profile=json.loads((HERE/'tool-os-krb5-seccomp.json').read_text())
        info={'Config':{'User':'0'},'HostConfig':{'SecurityOpt':['no-new-privileges','seccomp='+json.dumps(profile)],
            'Privileged':False,'CapAdd':None,'PidMode':'','IpcMode':'private','UsernsMode':'','NetworkMode':'bridge',
            'Memory':640*1024**2,'MemorySwap':640*1024**2,'NanoCpus':1000000000,'PidsLimit':256,'Init':True}}
        environment.validate_builder(info,profile)
        for key,value in [('Privileged',True),('CapAdd',['SYS_ADMIN']),('PidMode','host'),('Init',False),
                          ('NetworkMode','default'),('NetworkMode','host'),('NetworkMode','none'),('NetworkMode','unreviewed'),
                          ('SecurityOpt',['no-new-privileges','seccomp=unconfined'])]:
            changed=copy.deepcopy(info);changed['HostConfig'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):environment.validate_builder(changed,profile)

    def test_packaging_requires_every_original_test_and_complete_cleanup(self):
        journal=self.journal();journal.update(status='upstream-tests-passed-owned-rings-cleaned',tests_passed=True,
            descendants_after_cleanup=[],commands=[{'name':n,'exit_code':0} for n in environment.TEST_NAMES],
            ring_cleanup=[{'id':r['id'],'cleared_and_invalidated':True} for r in journal['rings']],
            keyring_paths_executed=True,verbose_log_sha256={'t_cccol-verbose.log':'a'*64,'t_ccache-verbose.log':'b'*64})
        environment.require_completed(journal,TOKEN)
        for kind in ['omitted','failure','child','cleanup']:
            changed=copy.deepcopy(journal)
            if kind=='omitted':changed['commands'].pop()
            elif kind=='failure':changed['commands'][0]['exit_code']=1
            elif kind=='child':changed['descendants_after_cleanup']=[1234]
            else:changed['ring_cleanup'][0]={'id':101,'error':'denied'}
            with self.subTest(kind=kind),self.assertRaises(ValueError):environment.require_completed(changed,TOKEN)

    def test_preparation_cannot_chown_baseline_files_through_source_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary).resolve();source=root/'source';source.mkdir();baseline=root/'baseline';baseline.mkdir()
            original=baseline/'copyright';original.write_text('preserved notice');before=original.stat()
            (source/'linked-baseline').symlink_to(baseline,target_is_directory=True)
            with patch.object(environment,'SOURCE',source),patch.object(environment,'HOME',root/'home'), \
                    patch.object(environment,'OUTPUT',root/'output'),patch.object(environment,'request'), \
                    patch.object(environment.os,'geteuid',return_value=0),patch.object(environment.os,'chown') as chown:
                environment.prepare_paths()
            self.assertEqual(original.stat(),before)
            self.assertTrue(all(call.kwargs=={'follow_symlinks':False} for call in chown.call_args_list))
            self.assertFalse(any(Path(call.args[0]).is_relative_to(baseline) for call in chown.call_args_list))

    def test_changed_source_bytes_missing_helper_or_other_engine_fail_closed(self):
        environment.load_environment(HERE)
        for kind in ['uid','engine','helper','bytes','extra']:
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary)
                for name in [environment.LOCK,*environment.ENVIRONMENT_FILES]:shutil.copy2(HERE/name,root/name)
                if kind in ['uid','engine','extra']:
                    p=root/environment.LOCK;policy=json.loads(p.read_text())
                    if kind=='uid':policy['uid']=0
                    elif kind=='engine':policy['engine']['version']='unreviewed'
                    else:policy['files']['unreviewed.py']={'bytes':0,'sha256':'0'*64}
                    p.write_text(json.dumps(policy))
                elif kind=='helper':(root/'tool-os-krb5-test-environment.py').unlink()
                else:
                    with (root/'tool-os-krb5-seccomp-default.json').open('a') as stream:stream.write(' ')
                with self.assertRaises(ValueError):environment.load_environment(root)

    def test_skipped_keyring_branch_cannot_masquerade_as_executed(self):
        environment.verify_keyring_logs('KEYRING:user:fixture KEYRING:thread:abcd',
            'KEYRING:session:fixture KEYRING:legacy:fixture')
        with self.assertRaises(ValueError):environment.verify_keyring_logs('KEYRING:process:abcd; keyrings skipped',
            'KEYRING:process:abcd; keyrings skipped')

    def test_protected_controller_json_rejects_wrong_owner_mode_and_hardlinks(self):
        good={'st_mode':stat.S_IFREG|0o644,'st_uid':0,'st_nlink':1}
        with patch.object(Path,'is_symlink',return_value=False),patch.object(Path,'read_text',return_value='{}'):
            with patch.object(Path,'lstat',return_value=SimpleNamespace(**good)):
                self.assertEqual(environment.protected_json(Path('/synthetic')), {})
            for key,value in [('st_uid',501),('st_mode',stat.S_IFREG|0o664),('st_nlink',2)]:
                with self.subTest(key=key),patch.object(Path,'lstat',return_value=SimpleNamespace(**dict(good,**{key:value}))),self.assertRaises(ValueError):
                    environment.protected_json(Path('/synthetic'))

    def test_normalization_can_target_only_three_fixed_controller_files(self):
        for name in ['other.json','../keyring-build-request.json','tool-os-krb5.lock.json']:
            with self.subTest(name=name),patch.object(environment.os,'geteuid',return_value=0),patch.object(environment.os,'chown') as chown,self.assertRaises(ValueError):
                environment.install_control(name)
            chown.assert_not_called()


if __name__=='__main__':unittest.main()
