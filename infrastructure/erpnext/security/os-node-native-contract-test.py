#!/usr/bin/env python3
"""Fail closed when a candidate changes the reviewed native-addon inventory."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('native_contract', Path(__file__).with_name('os-node-native-contract.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class NativeContract(unittest.TestCase):
    def setUp(self):
        self.baseline = {'schema': 1, 'base_image': checker.BASE_IMAGE,
                         'roots': ['/usr', '/opt', '/home'],
                         'files': {'/home/addon.node': {'sha256': 'a' * 64, 'target_imports': [],
                                                      'needed': ['libc.so.6'], 'kind': 'elf64-le'}},
                         'node_needed': ['libc.so.6'], 'foreign_platform_addons': [],
                         'runtime_libraries': {'/usr/lib/libc.so.6': {'sha256': 'c' * 64,
                                                                    'target_imports': []}}}

    def test_identical_inventory_passes_without_source_fix_claim(self):
        result = checker.verify(self.baseline, copy.deepcopy(self.baseline))
        self.assertEqual(result['status'], 'unchanged-native-addon-inventory')
        self.assertFalse(result['bundled_zlib_source_fixed'])

    def test_node_search_path_is_rejected_before_resolving_libraries(self):
        metadata = {'elf_machine': 183, 'needed': [], 'search_paths': ['/custom/lib']}
        with patch.object(checker.os, 'walk', return_value=[]), \
                patch.object(checker.shutil, 'which', return_value='/node'), \
                patch.object(checker, 'inspect_file', return_value=metadata), \
                patch.object(checker.subprocess, 'check_output', return_value=''), \
                patch.dict(checker.os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Node library search paths'):
                checker.capture()

    def test_missing_dynamic_metadata_is_rejected(self):
        # Section metadata only; no executable or malformed input is generated.
        for sections in ([], [(0, 3, 0, 0, 0, 1, 0, 0, 0, 0)]):
            with self.subTest(sections=sections):
                with self.assertRaisesRegex(ValueError, 'dynamic metadata'):
                    checker.require_dynamic_metadata(sections)

    def test_changed_bytes_reopen_review(self):
        candidate = copy.deepcopy(self.baseline)
        candidate['files']['/home/addon.node']['sha256'] = 'b' * 64
        with self.assertRaisesRegex(ValueError, 'changed'):
            checker.verify(self.baseline, candidate)

    def test_added_or_removed_addon_reopens_review(self):
        for operation in ('add', 'remove'):
            with self.subTest(operation=operation):
                candidate = copy.deepcopy(self.baseline)
                if operation == 'add':
                    candidate['files']['/home/new.node'] = copy.deepcopy(candidate['files']['/home/addon.node'])
                else:
                    candidate['files'].clear()
                with self.assertRaisesRegex(ValueError, 'file set'):
                    checker.verify(self.baseline, candidate)

    def test_dependency_change_reopens_review(self):
        candidate = copy.deepcopy(self.baseline)
        candidate['files']['/home/addon.node']['needed'].append('libxml2.so.2')
        with self.assertRaisesRegex(ValueError, 'changed'):
            checker.verify(self.baseline, candidate)

    def test_changed_runtime_library_bytes_reopen_review(self):
        candidate = copy.deepcopy(self.baseline)
        candidate['runtime_libraries']['/usr/lib/libc.so.6']['sha256'] = 'd' * 64
        with self.assertRaisesRegex(ValueError, 'dependency inventory changed'):
            checker.verify(self.baseline, candidate)

    def test_missing_dependency_capture_is_rejected(self):
        del self.baseline['runtime_libraries']
        with self.assertRaisesRegex(ValueError, 'dependency capture'):
            checker.verify(self.baseline, copy.deepcopy(self.baseline))

    def test_affected_import_in_baseline_is_not_accepted(self):
        self.baseline['files']['/home/addon.node']['target_imports'] = ['gzwrite']
        with self.assertRaisesRegex(ValueError, 'target imports'):
            checker.verify(self.baseline, copy.deepcopy(self.baseline))

    def test_wrong_base_or_scan_scope_is_rejected(self):
        for key, value in [('base_image', 'unreviewed'), ('roots', ['/home'])]:
            with self.subTest(key=key):
                candidate = copy.deepcopy(self.baseline)
                candidate[key] = value
                with self.assertRaisesRegex(ValueError, 'scope'):
                    checker.verify(self.baseline, candidate)


if __name__ == '__main__':
    unittest.main()
