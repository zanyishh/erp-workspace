#!/usr/bin/env python3
"""The package upgrade must not silently drop an existing codec."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('sndfile_check', Path(__file__).with_name('tool-os-check-libsndfile.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class Codecs(unittest.TestCase):
    def test_changed_source_harness_is_rejected(self):
        for files in ({}, {name: b'changed' for name in check.SERIAL_HARNESS_HASHES}):
            with self.subTest(files=list(files)), self.assertRaises(ValueError):
                check.serial_harness_labels(files)

    def test_complete_original_serial_output_is_required(self):
        labels = ['passed section %d.' % index for index in range(30)]
        lines = ['Running unit tests from src/ directory of source code tree.',
                 'Running end-to-end tests from tests/ directory.']
        lines += ['  libsndfile-1.2.2 ' + label for label in labels]
        lines += ['PASS: tests/pedantic-header-test.sh', '1 test passed',
                  'DEBIAN_BUILD_AND_ORDINARY_MAKE_CHECK_EXIT=0']
        self.assertEqual(check.serial_suite_report('\n'.join(lines), labels)['completed_wrapper_sections'], 30)
        for index in (0, 1, 2, 17, 31, 32, 33, 34):
            with self.subTest(missing_line=index), self.assertRaises(ValueError):
                check.serial_suite_report('\n'.join(lines[:index] + lines[index+1:]), labels)
        for failure in ('FAIL: tests/pedantic-header-test.sh', 'ERROR: test driver',
                        'DEBIAN_BUILD_AND_ORDINARY_MAKE_CHECK_EXIT=1'):
            with self.subTest(failure=failure), self.assertRaises(ValueError):
                check.serial_suite_report('\n'.join(lines + [failure]), labels)
        with self.assertRaises(ValueError):
            check.serial_suite_report('\n'.join(lines), labels[:-1])

    def test_codec_removal_rejected(self):
        old = {'major': [{'id': 0x010000}, {'id': 0x020000}],
               'subtype': [{'id': 2}, {'id': 0x60}],
               'valid_stereo_48khz_formats': [0x010002, 0x020002, 0x200060]}
        check.require_features(old, copy.deepcopy(old))
        for key in old:
            new = copy.deepcopy(old)
            new[key].pop()
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.require_features(old, new)


if __name__ == '__main__':
    unittest.main()
