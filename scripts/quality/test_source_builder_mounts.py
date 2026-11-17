"""No source builder may inherit persistent image application volumes."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

DIRECTORY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), DIRECTORY/(name+'.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


mounts = load('source_builder_mounts')
lxml = load('build-lxml')


def fixture():
    return {'declared_volumes': {name: {} for name in mounts.DESTINATIONS},
        'host': {'Mounts': [{'Type': 'tmpfs', 'Target': name, 'TmpfsOptions': {'SizeBytes': 1048576, 'Mode': 448}}
                            for name in mounts.DESTINATIONS]},
        'mounts': [{'Type': 'tmpfs', 'Destination': name, 'Source': '', 'RW': True}
                   for name in mounts.DESTINATIONS]}


class SourceBuilderMountTests(unittest.TestCase):
    def test_only_two_exact_small_temporary_mounts_are_accepted(self):
        result = mounts.validate(fixture())
        self.assertEqual(len(result['disposable_tmpfs']), 2)
        self.assertEqual(mounts.arguments().count('--mount'), 2)
        self.assertTrue(all(item['size_bytes'] == 1048576 for item in result['disposable_tmpfs']))

    def test_persistent_foreign_and_unbounded_mounts_are_rejected(self):
        changes = []
        value = fixture(); value['mounts'][0].update(Type='volume', Name='an-unowned-volume'); changes.append(value)
        value = fixture(); value['host']['Mounts'][0]['TmpfsOptions'].pop('SizeBytes'); changes.append(value)
        value = fixture(); value['host']['Mounts'][0]['TmpfsOptions']['Mode'] = 0o777; changes.append(value)
        value = fixture(); value['host']['Binds'] = ['/customer:/home/frappe/frappe-bench/sites']; changes.append(value)
        value = fixture(); value['declared_volumes']['/unexpected'] = {}; changes.append(value)
        value = fixture(); value['mounts'].pop(); changes.append(value)
        for index, value in enumerate(changes):
            with self.subTest(index=index), self.assertRaises(ValueError): mounts.validate(value)

    def test_only_exact_separately_owned_curl_work_bind_is_accepted(self):
        work = '/tmp/erp-quality-curl-'+'a'*32
        value = fixture()
        value['host']['Mounts'].append({'Type': 'bind', 'Source': work, 'Target': '/security-work',
                                       'BindOptions': {'Propagation': 'rprivate'}})
        value['mounts'].append({'Type': 'bind', 'Source': work, 'Destination': '/security-work',
                                'Propagation': 'rprivate', 'RW': True})
        self.assertEqual(len(mounts.validate(value, work)['actual_mounts']), 3)
        with self.assertRaises(ValueError): mounts.validate(value)
        with self.assertRaises(ValueError): mounts.validate(value, '/customer')
        broken = copy.deepcopy(value); broken['mounts'][-1]['Source'] = '/customer'
        with self.assertRaises(ValueError): mounts.validate(broken, work)

    def test_lxml_stops_before_export_and_retains_failed_export(self):
        calls = []; receipt = {}
        def command(*args):
            calls.append(args)
            if args[0] == 'inspect': return 'true'
            if args[0] == 'cp': raise subprocess.CalledProcessError(1, args)
            return ''
        with patch.object(lxml, 'command', side_effect=command):
            lxml.finish_container('owned-id', Path('/unused'), receipt, False)
        self.assertEqual([args[0] for args in calls], ['inspect', 'stop', 'cp'])
        self.assertEqual(receipt['container_retained'], 'owned-id')
        self.assertEqual(receipt['cleanup_errors'][0]['action'], 'copy-evidence')

    def test_lxml_successful_export_removes_only_owned_container_without_volume_delete(self):
        calls = []
        def command(*args):
            calls.append(args); return 'false' if args[0] == 'inspect' else ''
        with patch.object(lxml, 'command', side_effect=command):
            lxml.finish_container('owned-id', Path('/unused'), {}, True)
        self.assertEqual(calls[-1], ('rm', '-f', 'owned-id'))
        self.assertFalse(any(args[0] == 'cp' or '-v' in args for args in calls))


if __name__ == '__main__': unittest.main()
