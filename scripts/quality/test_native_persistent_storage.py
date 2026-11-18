"""Retained storage boundaries; synthetic temporary directories only, no VM calls."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.quality.test_native_security_deployment import secure

HELPER = secure.ROOT/'infrastructure/erpnext/security/native-storage-vm.py'
spec = importlib.util.spec_from_file_location('native_storage_vm', HELPER)
vm = importlib.util.module_from_spec(spec); spec.loader.exec_module(vm)
TOKEN = 'a'*32
FREE = {key: 2*1024**3 for key in ('persistent', 'docker', 'memory')}


class NativePersistentStorageTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()/'erp-secure-native'
        original_stat, original_read = Path.lstat, Path.read_text
        def root_stat(path):
            result = original_stat(path)
            return SimpleNamespace(**{name: (0 if name == 'st_uid' else getattr(result, name))
                for name in ('st_mode','st_uid','st_nlink','st_size','st_dev','st_ino')})
        def read(path, *args, **kwargs):
            return '' if str(path) == '/proc/self/mountinfo' else original_read(path, *args, **kwargs)
        for context in [patch.object(vm, 'ROOT', self.root), patch.object(vm.os, 'geteuid', return_value=0),
                patch.object(vm, 'storage', return_value=FREE), patch.object(Path, 'lstat', root_stat),
                patch.object(Path, 'read_text', read)]:
            context.__enter__(); self.addCleanup(context.__exit__, None, None, None)

    def test_owned_storage_is_retained_and_verified_without_changing_data(self):
        initial = vm.main({'action': 'create', 'token': TOKEN})
        data = self.root/'db-data'/'synthetic-file'; data.write_text('synthetic retained data')
        second = vm.main({'action': 'create', 'token': TOKEN})
        self.assertEqual(initial['ownership'], second['ownership'])
        self.assertEqual(data.read_text(), 'synthetic retained data')
        with self.assertRaisesRegex(ValueError, 'never deleted'):
            vm.main({'action': 'remove', 'token': TOKEN})
        self.assertTrue(data.exists())

    def test_unowned_existing_directory_is_never_adopted_or_emptied(self):
        self.root.mkdir(mode=0o700); foreign = self.root/'foreign'; foreign.write_text('preserve')
        with self.assertRaises((ValueError, FileNotFoundError)):
            vm.main({'action': 'create', 'token': TOKEN})
        self.assertEqual(foreign.read_text(), 'preserve')
        self.assertFalse((self.root/vm.MARKER).exists())

    def test_wrong_token_symlink_and_changed_directory_are_rejected(self):
        vm.main({'action': 'create', 'token': TOKEN})
        with self.assertRaisesRegex(ValueError, 'unowned or changed'):
            vm.main({'action': 'verify', 'token': 'b'*32})
        original = self.root/'logs'; moved = self.root.parent/'old-logs'; original.rename(moved)
        original.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            vm.main({'action': 'verify', 'token': TOKEN})
        original.unlink(); original.mkdir()
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            vm.main({'action': 'verify', 'token': TOKEN})

    def test_storage_is_not_allocated_when_partition_reserve_is_low(self):
        with patch.object(vm, 'storage', return_value={**FREE, 'persistent': 899*1024**2}):
            with self.assertRaisesRegex(RuntimeError, 'reserve'):
                vm.main({'action': 'create', 'token': TOKEN})
        self.assertFalse(self.root.exists())

    def test_start_and_running_resource_floors_cover_both_partitions_and_host(self):
        with patch.object(secure.shutil, 'disk_usage', return_value=SimpleNamespace(free=2*1024**3)):
            for key, amount in [('persistent', 899), ('docker', 399), ('memory', 1023)]:
                with self.subTest(key=key), patch.object(secure, 'vm_storage', return_value={**FREE, key: amount*1024**2}):
                    with self.assertRaises(RuntimeError): secure.resources({})
        with patch.object(secure, 'vm_storage', return_value=FREE), \
                patch.object(secure.shutil, 'disk_usage', return_value=SimpleNamespace(free=899*1024**2)):
            with self.assertRaises(RuntimeError): secure.resources({})

    def test_saved_ownership_change_is_rejected_before_services(self):
        with patch.object(secure, 'STATE', self.root):
            self.root.mkdir(mode=0o700)
            secure.save('storage.json', {'project': secure.PROJECT, 'path': secure.STORAGE_ROOT,
                'token': TOKEN, 'ownership': {'old': 'identity'}})
            with patch.object(secure, 'vm_storage', return_value={'ownership': {'new': 'identity'}}):
                with self.assertRaisesRegex(RuntimeError, 'replaced'): secure.ensure_storage({})
            self.assertEqual(json.loads((self.root/'storage.json').read_text())['ownership'], {'old': 'identity'})


if __name__ == '__main__': unittest.main()
