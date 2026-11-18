"""Deployment boundary checks: synthetic fixtures only; never start a real service."""
import importlib.machinery
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'erp-native-secure.command'
loader = importlib.machinery.SourceFileLoader('native_secure', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
secure = importlib.util.module_from_spec(spec)
loader.exec_module(secure)
IMAGES = dict(zip(secure.IMAGES, ['sha256:' + digit * 64 for digit in '123']))


def model():
    result = {'name': secure.PROJECT, 'services': {},
              'volumes': {name: {'name': secure.PROJECT+'-'+name, 'driver_opts': secure.volume_options(name)} for name in secure.VOLUMES},
              'networks': {'native': {'internal': True, 'name': secure.PROJECT}},
              'secrets': {name: {'file': str(secure.STATE/'secrets'/file)}
                          for name, file in [('db_root', 'db-root'), ('site_admin', 'site-admin')]}}
    for name in ['asset-seed', 'initializer', 'db', 'redis-cache', 'redis-queue',
                 'native-test-backend', 'native-test-frontend', 'websocket', 'worker']:
        service = {'image': IMAGES['ERP_SECURE_DB_IMAGE' if name == 'db' else 'ERP_SECURE_REDIS_IMAGE' if name.startswith('redis-') else 'ERP_SECURE_IMAGE'], 'pull_policy': 'never'}
        if name == 'asset-seed':
            service['network_mode'] = 'none'
            service['volumes'] = [{'type': 'volume', 'source': name, 'target': '/home/frappe/frappe-bench/'+name,
                                   'volume': {'nocopy': True}} for name in ('sites', 'logs')]
        else:
            service['networks'] = {'native': None}
        if name not in {'asset-seed', 'db', 'redis-cache', 'redis-queue'}:
            service.update(user='frappe', cap_drop=['ALL'], security_opt=['no-new-privileges:true'])
        if name == 'native-test-frontend':
            service.update(ports=[{'host_ip': '127.0.0.1', 'published': '8081', 'target': 8080}],
                           environment={'FRAPPE_SITE_NAME_HEADER': secure.SITE})
        result['services'][name] = service
    return result


def original(running=True):
    return {'id': 'a'*64, 'image': 'sha256:'+'4'*64, 'running': running,
            'labels': {'com.docker.compose.project': 'erp-baseline',
                       'com.docker.compose.service': 'native-test-frontend',
                       'com.docker.compose.project.config_files': str(secure.ROOT/'infrastructure/erpnext/compose.yaml')},
            'ports': {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '8081'}]}}


class NativeSecurityDeploymentTests(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def test_plan_and_missing_execute_never_touch_docker_or_files(self):
        with patch.object(secure, 'run', side_effect=AssertionError('must not execute')), \
                patch.object(secure, 'save', side_effect=AssertionError('must not write')):
            self.assertEqual(secure.main(['plan']), 0)
            self.assertEqual(secure.main(['start']), 0)

    def test_mutable_or_missing_images_are_rejected(self):
        for value in [None, '', 'frappe/erpnext:latest', 'mariadb:11.8', 'sha256:short']:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                secure.image_id(value)

    def test_inherited_project_and_target_cannot_redirect_the_launcher(self):
        inherited = {'COMPOSE_PROJECT_NAME': 'customer', 'COMPOSE_FILE': '/tmp/customer.yaml',
                     'DOCKER_HOST': 'tcp://remote:2375', 'FRAPPE_SITE': 'customer', 'ERP_URL': 'https://customer.invalid'}
        with patch.dict(secure.os.environ, inherited):
            env = secure.environment(IMAGES)
        self.assertFalse(set(inherited) & set(env))
        self.assertEqual({key: env[key] for key in IMAGES}, IMAGES)
        self.assertEqual(secure.COMPOSE[:3], ['docker', '--context', 'colima-erp'])
        self.assertEqual(secure.COMPOSE[secure.COMPOSE.index('-p')+1], 'erp-secure-native')

    def test_configuration_rejects_shared_data_writable_binds_and_public_ports(self):
        cases = []
        value = model(); value['volumes']['sites']['name'] = 'erp-baseline_sites'; cases.append(value)
        value = model(); value['volumes']['sites']['driver_opts']['device'] = '/var/lib/docker/volumes/erp-baseline_sites/_data'; cases.append(value)
        value = model(); value['volumes']['sites']['driver_opts']['o'] = 'bind,shared'; cases.append(value)
        value = model(); value['volumes']['sites'].pop('driver_opts'); cases.append(value)
        value = model(); value['services']['asset-seed']['volumes'][0]['volume']['nocopy'] = False; cases.append(value)
        value = model(); value['services']['asset-seed']['volumes'].pop(); cases.append(value)
        value = model(); value['services']['native-test-frontend']['ports'][0]['host_ip'] = '0.0.0.0'; cases.append(value)
        value = model(); value['services']['native-test-frontend']['ports'][0]['published'] = '8082'; cases.append(value)
        value = model(); value['services']['db']['ports'] = [{'published': '3306'}]; cases.append(value)
        value = model(); value['services']['native-test-backend']['volumes'] = [{'type': 'bind', 'source': str(secure.ROOT/'apps/erp_extensions'), 'read_only': False}]; cases.append(value)
        value = model(); value['services']['native-test-backend']['volumes'] = [{'type': 'bind', 'source': '/var/run/docker.sock', 'read_only': True}]; cases.append(value)
        for number, value in enumerate(cases):
            with self.subTest(number=number), self.assertRaises(RuntimeError):
                secure.validate_model(value, IMAGES)

    def test_configuration_rejects_host_network_and_privileged_app(self):
        for change in [{'network_mode': 'host'}, {'privileged': True}, {'cap_add': ['SYS_ADMIN']}, {'user': 'root'}]:
            value = model(); value['services']['native-test-backend'].update(change)
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                secure.validate_model(value, IMAGES)

    def test_prepare_only_inspects_images_and_renders_configuration(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(secure, 'STATE', Path(directory).resolve()), patch.object(secure, 'preflight'):
            calls = []
            def inspect_only(args, *unused, **kwargs):
                calls.append(args)
                if args[3:5] == ['image', 'inspect']:
                    return json.dumps({'id': args[-1], 'os': 'linux', 'arch': 'arm64'})
                if 'config' in args: return json.dumps(model())
                raise AssertionError('Preparation tried to operate containers: '+repr(args))
            with patch.object(secure, 'run', side_effect=inspect_only): secure.prepare(IMAGES)
            self.assertEqual(len(calls), 4)
            self.assertFalse((secure.STATE/'activation.json').exists())
            self.assertIn('native-test\\.localhost', (secure.STATE/'security_headers.conf').read_text())
            self.assertEqual((secure.STATE/'secrets').stat().st_mode & 0o777, 0o700)

    def test_original_frontend_requires_exact_site_port_and_configuration(self):
        for change in [('ports', {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '8082'}]}),
                       ('labels', {**original()['labels'], 'com.docker.compose.project': 'other'})]:
            value = original(); value[change[0]] = change[1]
            with self.subTest(change=change), self.assertRaises(RuntimeError): secure.original_frontend([value])

    def test_start_waits_for_candidate_backend_before_stopping_only_native_frontend(self):
        before = [original()]; after = [original(False)]
        with tempfile.TemporaryDirectory() as directory, patch.object(secure, 'STATE', Path(directory).resolve()), \
                patch.object(secure, 'resources'), patch.object(secure, 'check_volumes'), \
                patch.object(secure, 'ensure_storage'), \
                patch.object(secure, 'baseline', side_effect=[before, before, after]), \
                patch.object(secure, 'healthcheck'), patch.object(secure, 'run', return_value='') as execute:
            secure.start({})
        commands = [call.args[0] for call in execute.call_args_list]
        ready = next(i for i, cmd in enumerate(commands) if '--wait' in cmd and 'native-test-backend' in cmd)
        switch = next(i for i, cmd in enumerate(commands) if cmd[3] == 'stop')
        self.assertLess(ready, switch)
        self.assertEqual(commands[switch], secure.DOCKER+['stop', '--time', '30', 'a'*64])
        self.assertFalse(any('down' in cmd or 'rm' in cmd or 'volume' in cmd for cmd in commands))

    def test_failed_backend_readiness_leaves_original_frontend_running(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(secure, 'STATE', Path(directory).resolve()), \
                patch.object(secure, 'resources'), patch.object(secure, 'check_volumes'), \
                patch.object(secure, 'ensure_storage'), \
                patch.object(secure, 'baseline', return_value=[original()]), \
                patch.object(secure, 'stop') as isolated_stop, patch.object(secure, 'container', return_value=original()):
            def fail_backend(args, *unused, **kwargs):
                if '--wait' in args and 'native-test-backend' in args: raise RuntimeError('candidate not ready')
                if args[3] in ('start', 'stop'): raise AssertionError('Original frontend must stay running')
                return ''
            with patch.object(secure, 'run', side_effect=fail_backend), self.assertRaisesRegex(RuntimeError, 'candidate not ready'):
                secure.start({})
            isolated_stop.assert_called_once()
            self.assertFalse((secure.STATE/'activation.json').exists())

    def test_rollback_does_not_start_an_originally_stopped_frontend(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(secure, 'STATE', Path(directory).resolve()), \
                patch.object(secure, 'stop'), patch.object(secure, 'container', return_value=original(False)), \
                patch.object(secure, 'run', side_effect=AssertionError('must not start baseline')):
            secure.save('activation.json', {'project': secure.PROJECT, 'site': secure.SITE, 'original': original(False)})
            secure.rollback({})
            self.assertTrue((secure.STATE/'last-rollback.json').exists())

    def test_foreign_volume_collision_is_rejected_before_activation(self):
        with patch.object(secure, 'run', side_effect=['erp-secure-native-sites\n', json.dumps({'labels': {'com.docker.compose.project': 'erp-baseline'}, 'driver': 'local', 'options': {}})]):
            with self.assertRaisesRegex(RuntimeError, 'unowned existing volume'): secure.check_volumes({})

    def test_low_disk_blocks_preparation_and_embedded_initializers_compile(self):
        with patch.object(secure.shutil, 'disk_usage', return_value=SimpleNamespace(free=100)):
            with self.assertRaisesRegex(RuntimeError, 'disk headroom'): secure.preflight()
        compile(secure.ASSET_SEED, 'asset-seed', 'exec')
        compile(secure.INITIALIZE, 'initializer', 'exec')


if __name__ == '__main__':
    unittest.main()
