"""Owned-scratch/configuration boundaries; no Docker or VM mutation occurs."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SECURITY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), SECURITY/(name+'.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


controller = load('runtime-image-controller')
committer = load('commit-runtime-image')
scratch_helper = load('runtime-assembly-scratch')
OWNER = 'a'*32
CID = 'b'*64
IMAGE = 'sha256:'+'c'*64
SCRATCH = '/tmp/erp-quality-assembly-'+OWNER
CONFIG = {'User': 'frappe', 'Entrypoint': ['/usr/local/bin/entrypoint.sh'], 'Cmd': ['start.sh'],
          'WorkingDir': '/home/frappe/frappe-bench', 'Env': ['LANG=C.UTF-8'], 'Labels': {'source': 'fixture'},
          'Volumes': {controller.BENCH+'/sites': {}, controller.BENCH+'/logs': {}}}


def candidate():
    return {'Id': CID, 'Image': IMAGE, 'Name': '/erp-quality-assembly-candidate-'+OWNER,
            'Config': copy.deepcopy(CONFIG), 'State': {'Running': False, 'ExitCode': 0},
            'HostConfig': {'NetworkMode': 'none'}, 'Mounts': [
                {'Type': 'bind', 'Source': SCRATCH+'/inputs', 'Destination': '/security-input', 'RW': False},
                {'Type': 'bind', 'Source': SCRATCH+'/sites', 'Destination': controller.BENCH+'/sites', 'RW': True},
                {'Type': 'bind', 'Source': SCRATCH+'/logs', 'Destination': controller.BENCH+'/logs', 'RW': True}]}


class RuntimeImageControllerTests(unittest.TestCase):
    def test_customer_or_writable_input_mount_is_rejected(self):
        for index, key, value in [(0, 'RW', True), (1, 'Source', '/customer/sites')]:
            info = candidate(); info['Mounts'][index][key] = value
            with patch.object(controller, 'command', return_value=json.dumps(info)):
                with self.assertRaisesRegex(ValueError, 'identity or mounts'):
                    controller.inspect_owned(CID, OWNER, IMAGE, SCRATCH, False, {})

    def test_cleanup_rejects_another_containers_ancestor_mount(self):
        replies = [CID, json.dumps([{'Source': '/tmp', 'Type': 'bind'}])]
        with patch.object(controller, 'command', side_effect=replies):
            with self.assertRaisesRegex(ValueError, 'still references'):
                controller.require_detached(SCRATCH, {})

    def test_scratch_path_cannot_escape_owned_prefix(self):
        for token in ['../customer', '', 'a'*31, 'A'*32]:
            with self.assertRaises(ValueError): scratch_helper.scratch_path(token)
        self.assertEqual(str(scratch_helper.scratch_path(OWNER)), SCRATCH)

    def test_failed_evidence_export_stops_and_retains_owned_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); context = root/'context'; context.mkdir()
            output = root/'output'; output.mkdir(); (context/'input').write_text('fixture')
            helper, built = '1'*64, '2'*64
            calls = []
            def command(args, env, data=None):
                calls.append(args)
                if args[3] == 'create': return helper if 'staging' in args[args.index('--name')+1] else built
                if args[3] == 'cp': raise subprocess.CalledProcessError(1, args, 'drive unavailable')
                return ''
            vm_state = {'path': SCRATCH, 'token': OWNER, 'identity': {'device': 1, 'inode': 2, 'uid': 0}}
            receipt = {}
            with patch.object(controller.uuid, 'uuid4', return_value=SimpleNamespace(hex=OWNER)), \
                    patch.object(controller, 'resources', return_value={key: 3*1024**3 for key in ['host','scratch','docker','memory']}), \
                    patch.object(controller, 'vm', return_value=vm_state) as vm, \
                    patch.object(controller, 'command', side_effect=command), \
                    patch.object(controller, 'inspect_owned', return_value={}), \
                    patch.object(controller, 'guarded', side_effect=[None, RuntimeError('assembly failed')]):
                with self.assertRaisesRegex(RuntimeError, 'assembly failed'):
                    controller.assemble(context, output, {'Id': IMAGE, 'Config': CONFIG}, 'fixed-base', 'fixture', {}, receipt)
            self.assertEqual(receipt['retained_for_evidence']['containers'], [helper, built])
            self.assertTrue(receipt['evidence_copy_errors'])
            self.assertEqual([args[3] for args in calls].count('stop'), 2)
            stopped = next(index for index, args in enumerate(calls) if args[3] == 'stop' and args[-1] == built)
            copied = next(index for index, args in enumerate(calls) if args[3] == 'cp')
            self.assertLess(stopped, copied)
            self.assertFalse(any(args[3] == 'rm' for args in calls))
            self.assertEqual([call.args[0]['action'] for call in vm.call_args_list], ['create'])

    def test_commit_sends_exact_base_config_and_checks_the_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            iid = Path(temporary)/'image-id.txt'; committed = 'sha256:'+'d'*64
            def command(*args):
                if args[:2] == ('image', 'inspect'):
                    return json.dumps(CONFIG if args[-1] == committed else {'Id': IMAGE, 'Config': CONFIG})
                if args[0] == 'inspect': return json.dumps(candidate())
                if args[0] == 'context': return json.dumps('unix:///unused-erp-socket')
                if args[0] == 'version': return '1.51'
                raise AssertionError(args)
            response = SimpleNamespace(status=201, read=lambda: json.dumps({'Id': committed}).encode())
            argv = ['commit', '--container', CID, '--owner', OWNER, '--tag', '20261116t010203.000004z', '--iidfile', str(iid)]
            with patch.object(committer, 'command', side_effect=command), patch('sys.argv', argv), \
                    patch.object(committer.http.client.HTTPConnection, 'request') as request, \
                    patch.object(committer.http.client.HTTPConnection, 'getresponse', return_value=response):
                committer.main()
            self.assertEqual(json.loads(request.call_args.kwargs['body']), CONFIG)
            self.assertEqual(iid.read_text().strip(), committed)

    def test_commit_rejects_failed_candidate_before_socket_access(self):
        info = candidate(); info['State']['ExitCode'] = 1
        replies = [json.dumps({'Id': IMAGE, 'Config': CONFIG}), json.dumps(info)]
        argv = ['commit', '--container', CID, '--owner', OWNER, '--tag', '20261116t010203.000004z', '--iidfile', '/unused']
        with patch.object(committer, 'command', side_effect=replies), patch('sys.argv', argv), \
                patch.object(committer.socket, 'socket', side_effect=AssertionError('must not connect')):
            with self.assertRaisesRegex(ValueError, 'successful offline'):
                committer.main()


if __name__ == '__main__': unittest.main()
