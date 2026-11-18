#!/usr/bin/env python3
"""Exclusive, capability-free ordinary Kerberos tests and owned key cleanup."""
import argparse
import ctypes
import errno
import grp
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import re
import signal
import stat
import subprocess
import sys
import time

UID=194812
PROFILE_SHA='2260ea56fb0651494f22338652221f95f888ffc15c9c6b54ecd24c973630d807'
DEFAULT_SHA='536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74'
ENGINE={'version':'29.5.2','commit':'568f755ebeb1ac9c6a8febbda6cd371ea0a9630b','API':'1.54'}
LOCK='tool-os-krb5-test-environment.lock.json'
INPUT=Path('/security-input')
SOURCE=Path('/security-work/krb5-1.22.3')
BUILD=SOURCE/'build'
HOME=Path('/security-work/krb5-test-home')
OUTPUT=Path('/security-output/keyring-tests')
ALLOWS={'names':['add_key','keyctl','request_key'],'action':'SCMP_ACT_ALLOW'}
GET=0;JOIN=1;DESCRIBE=6;CLEAR=7;TIMEOUT=15;INVALIDATE=21
GONE_ERRNOS={126,127,128}  # Linux ENOKEY/EKEYEXPIRED/EKEYREVOKED; host guards use no kernel calls.
TEST_NAMES=['complete-make-check','complete-keyring-collection','complete-keyring-ccache']
ENVIRONMENT_FILES={'tool-os-krb5-seccomp-default.json','tool-os-krb5-seccomp.json',
    'tool-os-krb5-seccomp.LICENSE','tool-os-krb5-seccomp.NOTICE','tool-os-krb5-test-environment.py',
    'tool-os-build-krb5.py','tool-os-build-krb5.sh','tool-os-package-krb5.py',
    'tool-os-krb5-consumers.py','tool-os-krb5-abi-exception.json'}
CONTROL_FILES={'keyring-build-request.json','keyring-start-approval.json','keyring-cleanup-approval.json'}


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_profile(original,profile):
    expected=json.loads(json.dumps(original));expected['syscalls'].append(ALLOWS)
    if (original.get('defaultAction')!='SCMP_ACT_ERRNO' or original.get('defaultErrnoRet')!=1
            or profile!=expected or any(set(ALLOWS['names'])&set(x['names']) for x in original['syscalls'])):
        raise ValueError('Only the exact three keyring syscall allows may change the pinned Docker profile')


def load_environment(directory):
    policy=json.loads((directory/LOCK).read_text())
    if (policy.get('uid')!=UID or policy.get('profile_sha256')!=PROFILE_SHA
            or policy.get('default_sha256')!=DEFAULT_SHA or policy.get('key_ttl_seconds')!=5700
            or policy.get('test_timeout_seconds')!=4800 or set(policy.get('files',{}))!=ENVIRONMENT_FILES
            or policy.get('engine')!=ENGINE or policy.get('kernel_version')!='6.8.0-117-generic'):
        raise ValueError('Unreviewed Kerberos UID, profile or finite key lifetime')
    for name,expected in policy['files'].items():
        path=directory/name
        if (Path(name).name!=name or path.is_symlink() or not path.is_file()
                or path.stat().st_size!=expected['bytes'] or digest(path)!=expected['sha256']):
            raise ValueError('Kerberos test environment input differs: '+name)
    if digest(directory/'tool-os-krb5-seccomp-default.json')!=DEFAULT_SHA or digest(directory/'tool-os-krb5-seccomp.json')!=PROFILE_SHA:
        raise ValueError('Official or narrow profile byte identity changed')
    validate_profile(json.loads((directory/'tool-os-krb5-seccomp-default.json').read_text()),json.loads((directory/'tool-os-krb5-seccomp.json').read_text()))
    return policy


def verify_prerequisite(path,policy):
    if path.is_symlink() or not path.is_file() or path.stat().st_size!=policy['prerequisite']['bytes']:
        raise ValueError('Require the exact regular prerequisite evidence file')
    proof=json.loads(path.read_text())
    if (digest(path)!=policy['prerequisite']['sha256']
            or proof.get('status')!='native-and-exact-narrow-profile-pass-default-EPERM-confirmed'
            or proof.get('uid')!=UID or proof.get('profile_sha256')!=PROFILE_SHA):
        raise ValueError('Actual reviewed Kerberos keyring prerequisite proof differs')
    for case in ['native','default','narrow']:
        result=proof['cases'][case]['result'];after=proof['cases'][case]['after_inventory']
        expected='blocked' if case=='default' else 'passed-benign-keyring-prerequisite'
        if result['status']!=expected or after['uid']!=UID or after['processes'] or after['key_users']:
            raise ValueError('Kerberos prerequisite outcome or owned cleanup did not pass')
        validate_identity(result['identity'],UID,UID,UID,require_seccomp=case!='native')
    return proof


def native_inventory():
    processes=[]
    for path in Path('/proc').iterdir():
        if not path.name.isdecimal():continue
        try:
            fields=dict(x.split(':',1) for x in (path/'status').read_text().splitlines() if ':' in x)
            if UID in [int(x) for x in fields['Uid'].split()]:processes.append(int(path.name))
        except (FileNotFoundError,ProcessLookupError):pass
    rows=[x for x in Path('/proc/key-users').read_text().splitlines() if int(x.split(':',1)[0])==UID]
    return {'uid':UID,'account':any(x.pw_uid==UID for x in pwd.getpwall()),
            'group':any(x.gr_gid==UID for x in grp.getgrall()),'processes':sorted(processes),'key_users':rows}


def require_unused(inventory):
    if (inventory.get('uid')!=UID or inventory.get('account') or inventory.get('group')
            or inventory.get('processes') or inventory.get('key_users')):
        raise ValueError('KEYRING SECURITY GUARD: reserved UID194812 is occupied; no other UID may be adopted')


def validate_builder(info,profile):
    host=info['HostConfig'];options=host.get('SecurityOpt') or []
    profiles=[x.removeprefix('seccomp=') for x in options if x.startswith('seccomp=')]
    if (info['Config'].get('User')!='0' or host.get('Privileged') or host.get('CapAdd')
            or host.get('PidMode')!='' or host.get('IpcMode')!='private' or host.get('UsernsMode')!=''
            or host.get('NetworkMode')!='bridge' or host.get('Memory')!=640*1024**2
            or host.get('MemorySwap')!=640*1024**2 or host.get('NanoCpus')!=1000000000
            or host.get('PidsLimit')!=256 or host.get('Init') is not True
            or len(options)!=2 or 'no-new-privileges' not in options or len(profiles)!=1
            or json.loads(profiles[0])!=profile):
        raise ValueError('KEYRING SECURITY GUARD: actual builder profile/privileges/namespaces/resources differ')
    return {'profile_sha256':PROFILE_SHA,'uid':UID,'actual_security_options':options,
            'privileged':False,'extra_capabilities':[],'init_reaps_orphans':True}


def validate_identity(status,uid,euid,gid,require_seccomp,require_bounding=False):
    if (uid!=UID or euid!=UID or gid!=UID or [int(x) for x in status['Uid'].split()]!=[UID]*4
            or [int(x) for x in status['Gid'].split()]!=[UID]*4
            or any(int(status[x],16) for x in ['CapEff','CapPrm','CapAmb'])
            or require_bounding and int(status.get('CapBnd','1'),16)!=0
            or status['NoNewPrivs'].strip()!='1' or require_seccomp and status['Seccomp'].strip()!='2'):
        raise ValueError('KEYRING SECURITY GUARD: require exact nonroot UID/GID, cap0, nnp1 and test seccomp')


def validate_journal(journal,token):
    names={'erp-krb5-tests-'+token,'_pid','_uid.194812','_uid_ses.194812'}
    rings=journal.get('rings',[])
    if (not re.fullmatch('[0-9a-f]{32}',token) or journal.get('token')!=token or journal.get('uid')!=UID
            or journal.get('profile_sha256')!=PROFILE_SHA or not isinstance(journal.get('wrapper_pid'),int)
            or journal['wrapper_pid']<=0 or len(rings)>4 or len({x['id'] for x in rings})!=len(rings)
            or len({x['name'] for x in rings})!=len(rings)
            or any(not isinstance(x['id'],int) or x['id']<=0 or x['name'] not in names for x in rings)):
        raise ValueError('KEYRING SECURITY GUARD: refuse an unreviewed UID/token/profile/key identity')


class Keys:
    def __init__(self):
        if sys.platform!='linux' or platform.machine()!='aarch64':raise ValueError('Linux ARM64 only')
        self.libc=ctypes.CDLL(None,use_errno=True);self.libc.syscall.restype=ctypes.c_long
    def ctl(self,command,a=0,b=0,c=0,d=0):
        values=[ctypes.c_long(x) if isinstance(x,int) else x for x in [command,a,b,c,d]]
        ctypes.set_errno(0);result=self.libc.syscall(ctypes.c_long(219),*values)
        if result<0:raise OSError(ctypes.get_errno(),os.strerror(ctypes.get_errno()))
        return result
    def describe(self,key):
        buffer=ctypes.create_string_buffer(512);size=self.ctl(DESCRIBE,key,buffer,len(buffer))
        if size>len(buffer):raise ValueError('Unexpected owned key description size')
        return buffer.value.decode().split(';',4)


def cleanup_rings(keys,journal,token):
    validate_journal(journal,token);result=[]
    for ring in reversed(journal['rings']):
        item=dict(ring)
        try:
            description=keys.describe(ring['id'])
            if len(description)!=5 or description[0]!='keyring' or int(description[1])!=UID or description[4]!=ring['name']:
                raise ValueError('KEYRING SECURITY GUARD: recorded ring owner/name changed; never modify it')
            keys.ctl(CLEAR,ring['id']);keys.ctl(INVALIDATE,ring['id']);item['cleared_and_invalidated']=True
        except OSError as error:
            if error.errno in GONE_ERRNOS:item['already_gone']=True
            else:item['error']=str(error)
        except Exception as error:item['error']=str(error)
        result.append(item)
    return result


def require_completed(journal,token):
    validate_journal(journal,token)
    cleanup=journal.get('ring_cleanup',[])
    if (journal.get('status')!='upstream-tests-passed-owned-rings-cleaned' or journal.get('tests_passed') is not True
            or journal.get('descendants_after_cleanup')!=[] or len(journal['rings'])!=4
            or journal.get('keyring_paths_executed') is not True
            or set(journal.get('verbose_log_sha256',{}))!={'t_cccol-verbose.log','t_ccache-verbose.log'}
            or [x.get('name') for x in journal.get('commands',[])]!=TEST_NAMES
            or any(x.get('exit_code')!=0 for x in journal['commands']) or len(cleanup)!=4
            or {x['id'] for x in cleanup}!={x['id'] for x in journal['rings']}
            or any('error' in x or not (x.get('cleared_and_invalidated') or x.get('already_gone')) for x in cleanup)):
        raise ValueError('No packaging before all unchanged ordinary checks and complete owned cleanup')


def verify_keyring_logs(collection,ccache):
    if (any(marker not in collection for marker in ['KEYRING:user:','KEYRING:thread:abcd'])
            or any(marker not in ccache for marker in ['KEYRING:session:','KEYRING:legacy:'])):
        raise ValueError('Original ordinary keyring branches were not executed; no skipped-branch success claim')


def status():return {k:v.strip() for k,v in (x.split(':',1) for x in Path('/proc/self/status').read_text().splitlines() if ':' in x)}


def protected_json(path):
    value=path.lstat()
    if path.is_symlink() or not stat.S_ISREG(value.st_mode) or value.st_uid!=0 or value.st_nlink!=1 or value.st_mode&0o022:
        raise ValueError('KEYRING SECURITY GUARD: controller authorization must be a private root-owned regular file')
    return json.loads(path.read_text())


def install_control(name):
    if name not in CONTROL_FILES or os.geteuid()!=0:
        raise ValueError('Normalize only the three fixed controller JSON paths as builder root')
    pending=INPUT/(name+'.pending');value=pending.lstat()
    if pending.is_symlink() or not stat.S_ISREG(value.st_mode) or value.st_nlink!=1:
        raise ValueError('Controller transfer must be a regular single-link file')
    def metadata(path):
        info=path.lstat();return {'uid':info.st_uid,'gid':info.st_gid,'mode':oct(stat.S_IMODE(info.st_mode)),'nlink':info.st_nlink}
    before=metadata(pending)
    os.chown(pending,0,0,follow_symlinks=False);os.chmod(pending,0o644,follow_symlinks=False)
    protected_json(pending)
    target=INPUT/name;pending.replace(target)
    protected_json(target)
    return {'name':name,'before':before,'after':metadata(target),'sha256':digest(target)}


def request():
    value=protected_json(INPUT/'keyring-build-request.json')
    if (value.get('uid')!=UID or value.get('profile_sha256')!=PROFILE_SHA
            or value.get('environment_sha256')!=digest(INPUT/LOCK)
            or not re.fullmatch('[0-9a-f]{32}',value.get('token',''))):
        raise ValueError('KEYRING SECURITY GUARD: controller request identity differs')
    return value


def root_gate(kind):
    if os.geteuid()!=0:raise ValueError('Controller gates run only as builder root')
    value=request();path=INPUT/('keyring-'+kind+'-approval.json');deadline=time.monotonic()+60
    while not path.exists():
        if time.monotonic()>deadline:raise RuntimeError('Controller did not approve keyring '+kind+' within60seconds')
        time.sleep(.5)
    approved=protected_json(path)
    if (approved.get('uid')!=UID or approved.get('token')!=value['token']
            or approved.get('environment_sha256')!=value['environment_sha256']
            or approved.get('profile_sha256')!=PROFILE_SHA or approved.get('UID_processes_absent') is not True
            or approved.get('UID_keys_absent') is not True):
        raise ValueError('KEYRING SECURITY GUARD: independent reserved-UID proof differs')
    if kind=='cleanup':
        journal=json.loads((OUTPUT/'session.json').read_text());validate_journal(journal,value['token'])
        require_completed(journal,value['token'])
        if approved.get('journal_sha256')!=digest(OUTPUT/'session.json'):
            raise ValueError('No packaging before full ordinary tests and independent key cleanup')


def prepare_paths():
    if os.geteuid()!=0:raise ValueError('Prepare only in the disposable root builder')
    request()
    for path in [SOURCE,HOME,OUTPUT]:
        if path.is_symlink() or path.resolve()!=path:raise ValueError('Linked test path')
        if path!=SOURCE:path.mkdir(mode=0o700,exist_ok=False)
        if not path.is_dir():raise ValueError('Missing disposable test source directory')
        for parent,dirs,files in os.walk(path,followlinks=False):
            for item in [Path(parent),*(Path(parent)/x for x in dirs+files)]:os.chown(item,UID,UID,follow_symlinks=False)


def own_children():
    result=[]
    for path in Path('/proc').iterdir():
        if not path.name.isdecimal() or int(path.name)==os.getpid():continue
        try:fields=dict(x.split(':',1) for x in (path/'status').read_text().splitlines() if ':' in x)
        except (FileNotFoundError,ProcessLookupError):continue
        ids=[int(x) for x in fields['Uid'].split()]
        if UID in ids:
            if ids!=[UID]*4:raise ValueError('KEYRING SECURITY GUARD: unexpected mixed-UID child')
            result.append(int(path.name))
    return result


def stop_children():
    def reap():
        while True:
            try:
                if os.waitpid(-1,os.WNOHANG)[0]==0:break
            except ChildProcessError:break
    for sig,seconds in [(signal.SIGTERM,3),(signal.SIGKILL,2)]:
        for pid in own_children():
            try:
                fields=dict(x.split(':',1) for x in Path(f'/proc/{pid}/status').read_text().splitlines() if ':' in x)
                if [int(x) for x in fields['Uid'].split()]==[UID]*4:os.kill(pid,sig)
            except (FileNotFoundError,ProcessLookupError):pass
        deadline=time.monotonic()+seconds
        while own_children() and time.monotonic()<deadline:reap();time.sleep(.1)
        reap()
    if own_children():raise RuntimeError('KEYRING SECURITY GUARD: test descendants remain')


def run_tests():
    policy=load_environment(INPUT);value=request();identity=status()
    validate_identity(identity,os.getuid(),os.geteuid(),os.getgid(),True,True)
    if pwd.getpwuid(UID).pw_name!='erp-krb5-tests':raise ValueError('Unexpected container-only test account')
    keys=Keys();token=value['token'];journal={'status':'starting','uid':UID,'token':token,'profile_sha256':PROFILE_SHA,
        'wrapper_pid':os.getpid(),'identity':identity,'rings':[],'commands':[],'descendants_after_cleanup':None}
    def save():
        path=OUTPUT/'session.json';temporary=OUTPUT/'session.pending';temporary.write_text(json.dumps(journal,indent=2)+'\n');temporary.replace(path)
    save()
    def interrupted(signum,frame):raise InterruptedError('Controller requested test shutdown: '+str(signum))
    signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
    try:
        for special,name in [(None,'erp-krb5-tests-'+token),(-2,'_pid'),(-4,'_uid.194812'),(-5,'_uid_ses.194812')]:
            key=keys.ctl(JOIN,ctypes.c_char_p(name.encode())) if special is None else keys.ctl(GET,special,1)
            if key<=0 or key in {x['id'] for x in journal['rings']}:raise ValueError('Invalid or duplicate owned keyring ID')
            journal['rings'].append({'id':key,'name':name});validate_journal(journal,token);save()
            description=keys.describe(key)
            if description[0]!='keyring' or int(description[1])!=UID or description[4]!=name:raise ValueError('KEYRING SECURITY GUARD: new ring ownership differs')
            keys.ctl(TIMEOUT,key,policy['key_ttl_seconds'])
        journal['status']='running-original-upstream-checks';save();deadline=time.monotonic()+policy['test_timeout_seconds']
        commands=[('complete-make-check',['make','-j1','check'],BUILD,None),
            ('complete-keyring-collection',[sys.executable,str(SOURCE/'src/lib/krb5/ccache/t_cccol.py'),'-v'],BUILD/'lib/krb5/ccache',OUTPUT/'t_cccol-verbose.log'),
            ('complete-keyring-ccache',[sys.executable,str(SOURCE/'src/tests/t_ccache.py'),'-v'],BUILD/'tests',OUTPUT/'t_ccache-verbose.log')]
        env=dict(os.environ,PYTHONPATH=str(SOURCE/'src/util'))
        for name,args,cwd,log in commands:
            stream=log.open('w') if log else None
            try:
                process=subprocess.Popen(args,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
                result=process.wait(timeout=max(1,deadline-time.monotonic()))
                journal['commands'].append({'name':name,'exit_code':result,'log':str(log) if log else '/security-output/upstream-tests.log'});save()
                if result:raise RuntimeError('Original ordinary test failed: '+name)
            finally:
                if stream:stream.close()
        verify_keyring_logs((OUTPUT/'t_cccol-verbose.log').read_text(),(OUTPUT/'t_ccache-verbose.log').read_text())
        journal['keyring_paths_executed']=True
        journal['verbose_log_sha256']={name:digest(OUTPUT/name) for name in ['t_cccol-verbose.log','t_ccache-verbose.log']}
        journal['tests_passed']=True
    except BaseException as error:journal.update(status='failed-test-or-cleanup',error=str(error))
    finally:
        signal.signal(signal.SIGTERM,signal.SIG_IGN);signal.signal(signal.SIGINT,signal.SIG_IGN)
        try:stop_children();journal['descendants_after_cleanup']=[]
        except BaseException as error:journal['descendant_cleanup_error']=str(error)
        journal['ring_cleanup']=cleanup_rings(keys,journal,token)
        if (journal.get('tests_passed') and journal['descendants_after_cleanup']==[]
                and not any('error' in x for x in journal['ring_cleanup'])):journal['status']='upstream-tests-passed-owned-rings-cleaned'
        else:journal['status']='failed-test-or-cleanup'
        save()
    print(json.dumps({'keyring_test_status':journal['status'],'uid':UID,'commands':journal['commands']}),flush=True)
    if journal['status']!='upstream-tests-passed-owned-rings-cleaned':raise RuntimeError('Original tests or reserved-UID cleanup failed; packaging is blocked')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['inventory','prepare','wait-start','wait-cleanup','run-tests','cleanup-json','install-control']);parser.add_argument('--journal-json');parser.add_argument('--token');parser.add_argument('--name');args=parser.parse_args()
    if args.action=='inventory':print(json.dumps(native_inventory()));return
    if args.action=='cleanup-json':
        validate_identity(status(),os.getuid(),os.geteuid(),os.getgid(),False,True)
        journal=json.loads(args.journal_json);result=cleanup_rings(Keys(),journal,args.token)
        print(json.dumps({'uid':UID,'token':args.token,'cleanup':result}));
        if any('error' in x for x in result):raise RuntimeError('KEYRING SECURITY GUARD: native owned-ring cleanup failed')
    elif args.action=='install-control':print(json.dumps(install_control(args.name)))
    elif args.action=='prepare':prepare_paths()
    elif args.action=='wait-start':root_gate('start')
    elif args.action=='wait-cleanup':root_gate('cleanup')
    else:run_tests()


if __name__=='__main__':main()
