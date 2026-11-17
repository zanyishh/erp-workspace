#!/usr/bin/env python3
"""Prepare or explicitly operate the isolated synthetic security deployment. GPL-3.0."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'infrastructure/erpnext/compose.security-native.yaml'
STATE = ROOT / '.local/quality/secure-native'
STORAGE_HELPER = ROOT / 'infrastructure/erpnext/security/native-storage-vm.py'
STORAGE_ROOT = '/var/lib/erp-secure-native'
PROJECT = 'erp-secure-native'
SITE = 'native-test.localhost'
IMAGES = ('ERP_SECURE_IMAGE', 'ERP_SECURE_DB_IMAGE', 'ERP_SECURE_REDIS_IMAGE')
SERVICES = {'asset-seed', 'initializer', 'db', 'redis-cache', 'redis-queue',
            'native-test-backend', 'native-test-frontend', 'websocket', 'worker'}
VOLUMES = {'sites', 'logs', 'db-data', 'redis-cache-data', 'redis-queue-data'}
DOCKER = ['docker', '--context', 'colima-erp']
COMPOSE = DOCKER + ['compose', '--env-file', '/dev/null', '-p', PROJECT, '-f', str(CONFIG)]
INSPECT = '{"id":{{json .Id}},"image":{{json .Image}},"labels":{{json .Config.Labels}},"running":{{json .State.Running}},"ports":{{json .HostConfig.PortBindings}}}'

# Committed asset metadata is outside the image's declared sites volume, so
# automatic volume initialization can never restore old manifests into this seed.
ASSET_SEED = r'''
import hashlib,json,os,pathlib,pwd,shutil,tempfile
source=pathlib.Path('/opt/erp-security/fresh-sites-assets')
target=pathlib.Path('/home/frappe/frappe-bench/sites')
marker=target/'.erp-secure-native.json'
def inventory(folder,verify_links=False):
 result={}
 for p in sorted(folder.rglob('*')):
  name=str(p.relative_to(folder))
  if p.is_symlink():
   if verify_links and not p.resolve(strict=True).is_relative_to('/home/frappe/frappe-bench/apps'):
    raise RuntimeError('Public asset symlink leaves the image application directory')
   result[name]='link:'+os.readlink(p)
  elif p.is_file(): result[name]=hashlib.sha256(p.read_bytes()).hexdigest()
 return result
if not source.is_dir() or not (source/'assets.json').is_file():
 raise RuntimeError('Candidate image lacks its production asset build')
assets=inventory(source,verify_links=True)
receipt_path=pathlib.Path('/opt/erp-security/asset-build.json')
receipt=json.loads(receipt_path.read_text())
if receipt['status']!='passed' or receipt['exit_code']!=0 or receipt['command']!=['bench','build','--production']:
 raise RuntimeError('Candidate image does not have a successful production asset build receipt')
if receipt.get('asset_snapshot_path')!=str(source) or receipt.get('asset_snapshot')!=assets:
 raise RuntimeError('Committed asset snapshot differs from the production build receipt')
for name in ('assets.json','assets-rtl.json'):
 if hashlib.sha256((source/name).read_bytes()).hexdigest()!=receipt['asset_manifests'][name]:
  raise RuntimeError('Candidate asset manifest differs from its build receipt')
manifest=json.loads((source/'assets.json').read_text())
if not manifest: raise RuntimeError('Candidate asset manifest is empty')
for value in manifest.values():
 if not isinstance(value,str) or not value.startswith('/assets/'):
  raise RuntimeError('Unexpected asset manifest entry')
 path=(source/value.removeprefix('/assets/')).resolve(strict=True)
 if not path.is_file() or not path.is_relative_to('/home/frappe/frappe-bench/apps'):
  raise RuntimeError('Asset manifest does not resolve to image-built public bytes')
def check_public_bytes(folder):
 for url,digest in receipt['asset_files'].items():
  if not url.startswith('/assets/'): raise RuntimeError('Unexpected public asset receipt path')
  path=(folder/url.removeprefix('/assets/')).resolve(strict=True)
  if not path.is_relative_to('/home/frappe/frappe-bench/apps') or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
   raise RuntimeError('Public asset bytes differ from their production build receipt')
check_public_bytes(source)
expected={'project':'erp-secure-native','site':'native-test.localhost','assets':assets,
 'asset_receipt_sha256':hashlib.sha256(receipt_path.read_bytes()).hexdigest()}
foreign=[p for p in target.glob('*/site_config.json') if p.parent.name!='native-test.localhost']
if foreign or ((target/'native-test.localhost').exists() and not marker.exists()):
 raise RuntimeError('Refusing foreign or unmarked application data')
if marker.exists() and json.loads(marker.read_text())!=expected:
 raise RuntimeError('Retained assets differ; review a deliberate isolated-volume upgrade')
if (target/'assets').exists():
 if inventory(target/'assets')!=assets: raise RuntimeError('Retained public assets differ from the candidate image')
else:
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.assets-staging-',dir=target))
 try:
  shutil.copytree(source,stage/'assets',symlinks=True)
  (stage/'assets').rename(target/'assets')
 finally: shutil.rmtree(stage)
if inventory(target/'assets',verify_links=True)!=assets:
 raise RuntimeError('Seeded asset snapshot differs after copying')
check_public_bytes(target/'assets')
marker.write_text(json.dumps(expected,sort_keys=True)+'\n')
owner=pwd.getpwnam('frappe')
logs=pathlib.Path('/home/frappe/frappe-bench/logs')
if not logs.is_dir() or logs.is_symlink(): raise RuntimeError('Dedicated log volume is not an ordinary directory')
os.chown(logs,owner.pw_uid,owner.pw_gid)
os.chown(target,owner.pw_uid,owner.pw_gid)
for p in [marker,target/'assets',*(target/'assets').rglob('*')]: os.chown(p,owner.pw_uid,owner.pw_gid,follow_symlinks=False)
print('Verified candidate assets in the dedicated retained synthetic volume.')
'''

INITIALIZE = r'''
import json,os,pathlib,subprocess
os.chdir('/home/frappe/frappe-bench')
sites=pathlib.Path('sites'); site='native-test.localhost'
marker=json.loads((sites/'.erp-secure-native.json').read_text())
if marker['project']!='erp-secure-native' or marker['site']!=site:
 raise RuntimeError('The synthetic volume ownership marker is invalid')
if any(p.parent.name!=site for p in sites.glob('*/site_config.json')):
 raise RuntimeError('Refusing any non-synthetic site')
common={'db_host':'db','db_port':3306,'redis_cache':'redis://redis-cache:6379',
 'redis_queue':'redis://redis-queue:6379','redis_socketio':'redis://redis-queue:6379',
 'socketio_port':9000,'default_site':site,'serve_default_site':True}
(sites/'common_site_config.json').write_text(json.dumps(common)+'\n')
(sites/'apps.txt').write_text('frappe\nerpnext\nerp_extensions\n')
def bench(label,*args):
 result=subprocess.run(['bench',*args],check=False)
 if result.returncode: raise RuntimeError('Synthetic setup step failed: '+label)
if not (sites/site/'site_config.json').exists():
 db=pathlib.Path('/run/secrets/db_root').read_text().strip()
 admin=pathlib.Path('/run/secrets/site_admin').read_text().strip()
 bench('create new synthetic site','new-site',site,'--db-root-username=root',
  '--db-root-password='+db,'--admin-password='+admin,
  '--mariadb-user-host-login-scope=%','--install-app','erpnext')
result=subprocess.run(['bench','--site',site,'list-apps'],text=True,stdout=subprocess.PIPE,check=False)
if result.returncode: raise RuntimeError('Could not inspect installed synthetic applications')
if not any(line.split() and line.split()[0]=='erp_extensions' for line in result.stdout.splitlines()):
 bench('install synthetic extension','--site',site,'install-app','erp_extensions')
bench('migrate retained synthetic site','--site',site,'migrate')
for method in ['erp_extensions.setup.configure_test_site','erp_extensions.knitting.install.install','erp_extensions.knitting.demo.seed']:
 bench(method,'--site',site,'execute',method)
bench('disable scheduler','--site',site,'disable-scheduler')
print('Fresh or retained synthetic site is ready; no customer data was imported.')
'''


def run(args, env=None, data=None, capture=True, timeout=120, guard_resources=False):
    if guard_resources:
        # File-backed output avoids pipe backpressure; failures retain private logs.
        with tempfile.TemporaryFile(mode='w+') as source:
            source.write(data or ''); source.seek(0)
            descriptor, name = tempfile.mkstemp(prefix='activation-', suffix='.log', dir=STATE)
            process = None
            try:
                with os.fdopen(descriptor, 'w') as output:
                    process = subprocess.Popen(args, cwd=ROOT, env=env, stdin=source,
                        stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                    deadline = time.monotonic()+timeout
                    while process.poll() is None:
                        resources(env, starting=False)
                        if time.monotonic() > deadline: raise RuntimeError('Synthetic activation timed out')
                        time.sleep(3)
                if process.returncode: raise RuntimeError('Synthetic activation failed; private log: '+name)
                resources(env, starting=False)
                return ''
            finally:
                if process and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL); process.wait()
    result = subprocess.run(args, cwd=ROOT, env=env, input=data, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Command failed: ' + ' '.join(args[:8]))
    return result.stdout or ''


def image_id(value):
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', value or ''):
        raise RuntimeError('Supply immutable local sha256 image IDs for all three secure images')
    return value


def environment(images):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('COMPOSE_', 'ERP_', 'FRAPPE_', 'DOCKER_'))}
    env.update({k: image_id(images[k]) for k in IMAGES})
    env['ERP_SECURE_STATE'] = str(STATE)
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:' + env.get('PATH', '')
    return env


def safe_state():
    for path in [STATE, *STATE.parents]:
        if path.is_symlink():
            raise RuntimeError('Refusing a symlink in deployment state')


def save(name, value):
    safe_state()
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    STATE.chmod(0o700)
    destination = STATE / name
    if destination.is_symlink():
        raise RuntimeError('Refusing linked deployment metadata')
    temporary = STATE / (name + '.new')
    with temporary.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
    temporary.chmod(0o600)
    temporary.replace(destination)


def validate_model(model, images):
    if model.get('name') != PROJECT or set(model['services']) != SERVICES:
        raise RuntimeError('Unexpected project or service scope')
    if set(model['volumes']) != VOLUMES:
        raise RuntimeError('Unexpected retained volume scope')
    for name, value in model['volumes'].items():
        if (value.get('external') or value.get('driver_opts') != volume_options(name)
                or value.get('driver', 'local') != 'local' or value['name'] != PROJECT + '-' + name):
            raise RuntimeError('Existing/shared volumes are forbidden')
    network = model['networks'].get('native', {})
    if (set(model['networks']) != {'native'} or not network.get('internal')
            or network.get('name') != PROJECT or network.get('external')):
        raise RuntimeError('The native network must be private and internal')
    if set(model.get('secrets', {})) != {'db_root', 'site_admin'}:
        raise RuntimeError('Unexpected secret scope')
    for name, file in [('db_root', 'db-root'), ('site_admin', 'site-admin')]:
        if model['secrets'][name].get('file') != str(STATE/'secrets'/file) or model['secrets'][name].get('external'):
            raise RuntimeError('Only newly generated synthetic secrets may be mounted')
    allowed_binds = {str(ROOT/'apps/erp_extensions'), str(STATE/'native-api-methods.conf'), str(STATE/'security_headers.conf')}
    for name, service in model['services'].items():
        if any(service.get(key) for key in ('privileged', 'devices', 'pid', 'ipc', 'volumes_from')):
            raise RuntimeError('Host privileges and namespaces are forbidden')
        if name == 'asset-seed':
            if service.get('network_mode') != 'none' or service.get('networks'):
                raise RuntimeError('Public asset seeding must have no network')
            mounts = service.get('volumes', [])
            expected = {'sites': '/home/frappe/frappe-bench/sites', 'logs': '/home/frappe/frappe-bench/logs'}
            if (len(mounts) != 2 or {m.get('source'): m.get('target') for m in mounts} != expected
                    or any(m.get('type') != 'volume' or m.get('read_only')
                           or m.get('volume', {}).get('nocopy') is not True for m in mounts)):
                raise RuntimeError('Seeding must override both declared image volumes without copying old image data')
        elif service.get('network_mode') or set(service.get('networks', {})) != {'native'}:
            raise RuntimeError('Services must use only the isolated native network')
        expected = images['ERP_SECURE_DB_IMAGE' if name == 'db' else 'ERP_SECURE_REDIS_IMAGE' if name.startswith('redis-') else 'ERP_SECURE_IMAGE']
        if service['image'] != expected or service.get('pull_policy') != 'never':
            raise RuntimeError('Only the prepared local images may run')
        for mount in service.get('volumes', []):
            if mount['type'] == 'bind':
                if mount['source'] not in allowed_binds or not mount.get('read_only'):
                    raise RuntimeError('Unreviewed or writable host bind')
            elif mount['type'] != 'volume' or mount['source'] not in VOLUMES:
                raise RuntimeError('Unreviewed data mount')
        ports = service.get('ports', [])
        if name == 'native-test-frontend':
            if len(ports) != 1 or (ports[0].get('host_ip'), str(ports[0].get('published')), ports[0].get('target')) != ('127.0.0.1', '8081', 8080):
                raise RuntimeError('Only localhost8081 may be published')
            if service['environment'].get('FRAPPE_SITE_NAME_HEADER') != SITE:
                raise RuntimeError('The proxy site must be fixed to the synthetic site')
        elif ports:
            raise RuntimeError('Internal services cannot publish ports')
        if name not in {'db', 'redis-cache', 'redis-queue', 'asset-seed'}:
            if service.get('user') != 'frappe' or service.get('cap_add') or 'ALL' not in service.get('cap_drop', []) or 'no-new-privileges:true' not in service.get('security_opt', []):
                raise RuntimeError('Application services must run without privilege escalation')


def preflight():
    # Preparation itself writes less than64KiB; activation also needs room for a fresh DB.
    if shutil.disk_usage(ROOT).free < 256 * 1024**2:
        raise RuntimeError('Preparation requires 256 MiB of internal disk headroom')


def volume_options(name):
    if name not in VOLUMES: raise RuntimeError('Unknown retained synthetic volume')
    return {'type': 'none', 'o': 'bind', 'device': STORAGE_ROOT+'/'+name}


def vm_storage(request, env):
    code = STORAGE_HELPER.read_text()+'\nprint(json.dumps(main('+repr(request)+')))\n'
    return json.loads(run(['colima', 'ssh', '--profile', 'erp', '--', 'sudo', 'python3', '-'], env, data=code))


def ensure_storage(env):
    path = STATE/'storage.json'
    if path.is_symlink(): raise RuntimeError('Refusing linked storage state')
    if path.exists():
        state = json.loads(path.read_text())
        if state.get('project') != PROJECT or state.get('path') != STORAGE_ROOT:
            raise RuntimeError('Unexpected retained storage scope')
    else:
        state = {'project': PROJECT, 'path': STORAGE_ROOT, 'token': secrets.token_hex(16)}
        # Save intent before creating directories, so interrupted creation cannot be adopted with a new token.
        save('storage.json', state)
    verified = vm_storage({'action': 'create', 'token': state['token']}, env)
    if 'ownership' in state and state['ownership'] != verified['ownership']:
        raise RuntimeError('Persistent synthetic storage was replaced')
    state['ownership'] = verified['ownership']; save('storage.json', state)


def resources(env, starting=True):
    available = vm_storage({'action': 'storage'}, env)
    available['host'] = shutil.disk_usage(ROOT).free
    reserve = (900 if starting else 400)*1024**2
    if min(available['host'], available['persistent']) < reserve or available['docker'] < 400*1024**2:
        raise RuntimeError('Synthetic activation storage reserve is insufficient; retained data is preserved')
    if available['memory'] < (1024 if starting else 128)*1024**2:
        raise RuntimeError('Synthetic activation has insufficient available VM memory')
    if not starting:
        state = json.loads((STATE/'storage.json').read_text())
        verified = vm_storage({'action': 'verify', 'token': state['token']}, env)
        if state['ownership'] != verified['ownership']:
            raise RuntimeError('Persistent synthetic storage identity changed')


def inspect_images(images, env):
    for value in set(images.values()):
        info = json.loads(run(DOCKER + ['image', 'inspect', '--format', '{"id":{{json .Id}},"os":{{json .Os}},"arch":{{json .Architecture}}}', value], env))
        if info != {'id': value, 'os': 'linux', 'arch': 'arm64'}:
            raise RuntimeError('Candidate image identity/platform does not match the prepared input')


def prepare(images):
    safe_state()
    preflight()
    if (STATE/'activation.json').exists():
        raise RuntimeError('Rollback the active deployment before preparing another image set')
    env = environment(images)
    inspect_images(images, env)
    model = json.loads(run(COMPOSE + ['--profile', 'bootstrap', 'config', '--format', 'json'], env))
    validate_model(model, images)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    STATE.chmod(0o700)
    secret_dir = STATE/'secrets'
    if secret_dir.is_symlink(): raise RuntimeError('Refusing linked secrets')
    secret_dir.mkdir(mode=0o700, exist_ok=True)
    secret_dir.chmod(0o700)
    for name in ('db-root', 'site-admin'):
        path = secret_dir/name
        if path.is_symlink(): raise RuntimeError('Refusing linked secrets')
        if not path.exists():
            with path.open('x') as stream: stream.write(secrets.token_urlsafe(32)+'\n')
        # The enclosing host directory is private; assigned nonroot containers must read the mounted file.
        path.chmod(0o444)
    files = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [CONFIG, STORAGE_HELPER]}
    for source, destination in [('native-api-methods.conf', 'native-api-methods.conf'), ('native-security-headers.conf', 'security_headers.conf')]:
        path = ROOT/'infrastructure/erpnext'/source
        content = path.read_text()
        if destination == 'security_headers.conf':
            content += '\n# Fixed synthetic Host allowlist.\nif ($host !~* "^(localhost|127\\.0\\.0\\.1|native-test\\.localhost)$") { return 421; }\n'
        output = STATE/destination
        if output.is_symlink(): raise RuntimeError('Refusing linked proxy configuration')
        output.write_text(content)
        output.chmod(0o644)
        files[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        files[str(output)] = hashlib.sha256(output.read_bytes()).hexdigest()
    save('prepared.json', {'project': PROJECT, 'site': SITE, 'images': images, 'files': files,
                          'prepared_at': datetime.now(timezone.utc).isoformat()})
    print('Prepared isolated synthetic deployment. No containers or existing services were changed.')


def prepared(verify=True):
    safe_state()
    data = json.loads((STATE/'prepared.json').read_text())
    if data['project'] != PROJECT or data['site'] != SITE:
        raise RuntimeError('Unexpected preparation scope')
    env = environment(data['images'])
    if verify:
        if any(hashlib.sha256(Path(path).read_bytes()).hexdigest() != value for path, value in data['files'].items()):
            raise RuntimeError('Deployment inputs changed; prepare again before activation')
        inspect_images(data['images'], env)
        validate_model(json.loads(run(COMPOSE + ['--profile', 'bootstrap', 'config', '--format', 'json'], env)), data['images'])
    return data, env


def container(identifier, env):
    if not re.fullmatch(r'[0-9a-f]{64}', identifier): raise RuntimeError('Invalid saved container identity')
    return json.loads(run(DOCKER + ['container', 'inspect', '--format', INSPECT, identifier], env))


def baseline(env):
    ids = run(DOCKER + ['ps', '-aq', '--no-trunc', '--filter', 'label=com.docker.compose.project=erp-baseline'], env).split()
    return sorted([container(identifier, env) for identifier in ids], key=lambda item: item['id'])


def original_frontend(snapshot):
    matches = [item for item in snapshot if item['labels'].get('com.docker.compose.service') == 'native-test-frontend']
    if len(matches) > 1: raise RuntimeError('More than one original native frontend exists')
    if not matches: return None
    item = matches[0]
    if (item['labels'].get('com.docker.compose.project') != 'erp-baseline'
            or item['labels'].get('com.docker.compose.project.config_files') != str(ROOT/'infrastructure/erpnext/compose.yaml')
            or item['ports'] != {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '8081'}]}):
        raise RuntimeError('Original native frontend does not have the exact approved identity/port')
    return item


def check_volumes(env):
    names = set(run(DOCKER + ['volume', 'ls', '--format', '{{.Name}}'], env).splitlines())
    for short in VOLUMES:
        name = PROJECT+'-'+short
        if name in names:
            info = json.loads(run(DOCKER + ['volume', 'inspect', '--format', '{"labels":{{json .Labels}},"driver":{{json .Driver}},"options":{{json .Options}}}', name], env))
            if (info.get('labels', {}).get('com.docker.compose.project') != PROJECT
                    or info.get('labels', {}).get('erp.scope') != 'synthetic-native-only'
                    or info.get('driver') != 'local' or info.get('options') != volume_options(short)):
                raise RuntimeError('Refusing an unowned existing volume: '+name)
    networks = run(DOCKER + ['network', 'ls', '--format', '{{.Name}}'], env).splitlines()
    if PROJECT in networks:
        info = json.loads(run(DOCKER + ['network', 'inspect', '--format', '{{json .}}', PROJECT], env))
        if not info.get('Internal') or info.get('Labels', {}).get('com.docker.compose.project') != PROJECT:
            raise RuntimeError('Refusing an existing unowned/private-network collision')
        for identifier in info.get('Containers', {}):
            if container(identifier, env)['labels'].get('com.docker.compose.project') != PROJECT:
                raise RuntimeError('A foreign container is attached to the isolated network')


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def healthcheck():
    opener = build_opener(ProxyHandler({}), NoRedirect())
    with opener.open('http://127.0.0.1:8081/api/method/ping', timeout=4) as response:
        if (response.geturl() != 'http://127.0.0.1:8081/api/method/ping'
                or json.load(response).get('message') != 'pong'
                or response.headers.get('X-Content-Type-Options') != 'nosniff'):
            raise RuntimeError('Synthetic endpoint did not return the expected health response')
    try:
        opener.open(Request('http://127.0.0.1:8081/api/method/ping', headers={'Host': 'wrong-site.example.invalid'}), timeout=4)
    except HTTPError as error:
        if error.code == 421: return
        raise
    raise RuntimeError('Synthetic proxy accepted an unapproved Host header')


def stop(env):
    ids = run(DOCKER + ['ps', '-q', '--no-trunc', '--filter', 'label=com.docker.compose.project='+PROJECT], env).split()
    for identifier in ids:
        item = container(identifier, env)
        if (item['labels'].get('com.docker.compose.project') != PROJECT
                or item['labels'].get('com.docker.compose.service') not in SERVICES
                or item['labels'].get('com.docker.compose.project.config_files') != str(CONFIG)):
            raise RuntimeError('Refusing to stop a container outside the exact secure deployment')
    # Include a still-running one-off initializer if its CLI was interrupted.
    if ids: run(DOCKER + ['stop', '--time', '30', *ids], env, timeout=180)
    print('Stopped only the isolated security deployment; all application volumes were retained.')


def rollback(env):
    state = json.loads((STATE/'activation.json').read_text())
    if state['project'] != PROJECT or state['site'] != SITE:
        raise RuntimeError('Unexpected rollback scope')
    stop(env)
    original = state['original']
    if original:
        current = container(original['id'], env)
        original_frontend([current])
        if current['image'] != original['image']:
            raise RuntimeError('Original frontend image changed; automatic restore refused')
        if original['running'] and not current['running']:
            run(DOCKER + ['start', original['id']], env)
    state['status'] = 'rolled-back'
    save('last-rollback.json', state)
    (STATE/'activation.json').unlink()
    print('Restored the original native8081 frontend state; baseline/customer services were not restarted.')


def start(env):
    if (STATE/'activation.json').exists():
        raise RuntimeError('An activation record already exists; use stop/rollback before a new activation')
    resources(env)
    check_volumes(env)
    ensure_storage(env)
    before = baseline(env)
    original = original_frontend(before)
    save('activation.json', {'project': PROJECT, 'site': SITE, 'original': original, 'baseline_before': before, 'status': 'preparing'})
    try:
        run(COMPOSE + ['run', '--rm', '--no-deps', '-T', 'asset-seed'], env, data=ASSET_SEED, timeout=180, guard_resources=True)
        run(COMPOSE + ['up', '-d', '--wait', '--wait-timeout', '150', 'db', 'redis-cache', 'redis-queue'], env, timeout=180, guard_resources=True)
        run(COMPOSE + ['run', '--rm', '--no-deps', '-T', 'initializer'], env, data=INITIALIZE, timeout=900, guard_resources=True)
        run(COMPOSE + ['up', '-d', '--wait', '--wait-timeout', '150', 'native-test-backend', 'websocket', 'worker'], env, timeout=180, guard_resources=True)
        # The existing native frontend stays up until the new backend is healthy.
        if baseline(env) != before: raise RuntimeError('Original service state changed during preparation')
        if original and original['running']: run(DOCKER + ['stop', '--time', '30', original['id']], env)
        run(COMPOSE + ['up', '-d', '--no-deps', 'native-test-frontend'], env, timeout=120, guard_resources=True)
        for attempt in range(30):
            try:
                healthcheck()
                break
            except Exception:
                if attempt == 29: raise
                time.sleep(2)
        run(COMPOSE + ['exec', '-T', 'native-test-frontend', 'nginx', '-t'], env)
        after = baseline(env)
        preserved = lambda entries: [entry for entry in entries if not original or entry['id'] != original['id']]
        if preserved(after) != preserved(before):
            raise RuntimeError('A baseline/customer service changed during activation')
        state = json.loads((STATE/'activation.json').read_text()); state['status'] = 'active'; save('activation.json', state)
        print('Isolated synthetic candidate is active at http://127.0.0.1:8081.')
    except BaseException:
        rollback(env)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'prepare', 'start', 'stop', 'rollback'], nargs='?', default='plan')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    if args.action == 'plan' or not args.execute:
        print('Plan: immutable ERP/DB/Redis image IDs; fresh synthetic-only volumes; candidate-image assets; localhost8081 only. prepare writes local configuration, start creates the isolated site and switches only the verified native frontend, stop retains all data, rollback restores its previous state. Explicit --execute is required for changes.')
        return 0
    if args.action == 'prepare':
        prepare({name: image_id(os.environ.get(name)) for name in IMAGES})
    else:
        _, env = prepared(verify=args.action == 'start')
        {'start': start, 'stop': stop, 'rollback': rollback}[args.action](env)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('Secure native launcher: '+str(error), file=sys.stderr)
        sys.exit(1)
