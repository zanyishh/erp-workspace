"""Prevent connected fixtures and backend tests from crossing deployments."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('native_target', Path(__file__).with_name('native_target.py'))
target = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(target)


class NativeTargetTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name)
        self.addCleanup(patch.stopall)
        patch.object(target, 'STATE', self.state).start()

    def activate(self, status='active', site='native-test.localhost'):
        (self.state/'activation.json').write_text(json.dumps({'project':'erp-secure-native', 'site':site, 'status':status}))
        (self.state/'prepared.json').write_text(json.dumps({'project':'erp-secure-native', 'site':site, 'images':{'ERP_SECURE_IMAGE':'sha256:'+'a'*64}}))

    def container(self, project, service):
        return {'id':'b'*64, 'image':'sha256:'+'a'*64, 'running':True,
                'labels':{'com.docker.compose.project':project, 'com.docker.compose.service':service,
                          'com.docker.compose.project.config_files':str(target.ROOT/'infrastructure/erpnext'/('compose.security-native.yaml' if project=='erp-secure-native' else 'compose.yaml'))},
                'ports':{'8080/tcp':[{'HostIp':'127.0.0.1','HostPort':'8081'}]} if service=='native-test-frontend' else {}}

    def test_active_candidate_selects_only_its_backend(self):
        self.activate()
        with patch.object(target, '_inspect_service', side_effect=self.container):
            command=target.python_command('-')
        self.assertEqual(command[:5], ['docker','--context','colima-erp','exec','-i'])
        self.assertIn('b'*64, command)
        self.assertIn('NATIVE_TEST_SITE=native-test.localhost', command)

    def test_incomplete_activation_never_falls_back_to_original(self):
        self.activate(status='preparing')
        with patch.object(target, '_inspect_service') as inspect:
            with self.assertRaisesRegex(RuntimeError, 'active'):
                target.selected_backend()
        inspect.assert_not_called()

    def test_customer_site_marker_is_rejected(self):
        self.activate(site='customer.localhost')
        with self.assertRaisesRegex(RuntimeError, 'scope'):
            target.selected_backend()

    def test_broken_activation_link_does_not_fall_back(self):
        (self.state/'activation.json').symlink_to(self.state/'missing-state.json')
        with patch.object(target, '_inspect_service', side_effect=self.container):
            with self.assertRaisesRegex(RuntimeError, 'linked'):
                target.selected_backend()

    def test_changed_candidate_image_is_rejected(self):
        self.activate()
        def changed(project,service):
            value=self.container(project,service);value['image']='sha256:'+'c'*64;return value
        with patch.object(target, '_inspect_service', side_effect=changed):
            with self.assertRaisesRegex(RuntimeError, 'image'):
                target.selected_backend()

    def test_other_port_is_rejected(self):
        self.activate()
        def changed(project,service):
            value=self.container(project,service)
            if service=='native-test-frontend':value['ports']['8080/tcp'][0]['HostPort']='8082'
            return value
        with patch.object(target, '_inspect_service', side_effect=changed):
            with self.assertRaisesRegex(RuntimeError, '8081'):
                target.selected_backend()

    def test_without_activation_only_named_original_native_scope_is_allowed(self):
        with patch.object(target, '_inspect_service', side_effect=self.container) as inspect:
            value=target.selected_backend()
        self.assertEqual(value['project'],'erp-baseline')
        self.assertEqual({c.args[0] for c in inspect.call_args_list},{'erp-baseline'})

    def test_secure_password_uses_only_private_synthetic_secret(self):
        self.activate()
        (self.state/'secrets').mkdir()
        (self.state/'secrets/site-admin').write_text('synthetic-secret\n')
        with patch.object(target, '_inspect_service', side_effect=self.container), \
             patch.dict(target.os.environ, {'ERP_LOCAL_PILOT_PASSWORD':'wrong-old-site-secret'}):
            self.assertEqual(target.admin_password(),'synthetic-secret')


if __name__ == '__main__':
    unittest.main()
