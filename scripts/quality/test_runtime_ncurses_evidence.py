"""Candidate ABI proof uses exact tested bytes without adding runtime binutils."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security/ncurses-compatibility.py'
spec = importlib.util.spec_from_file_location('ncurses_runtime', SOURCE)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class NcursesRuntimeEvidenceTests(unittest.TestCase):
    def check(self, corrupt=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lib = root/'lib'; lib.mkdir(); output = root/'output'; output.mkdir()
            inventory = {}
            for name in module.LIBRARY_NAMES:
                path = lib/name; path.write_bytes(('synthetic tested library '+name).encode())
                inventory[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                   'soname': name, 'symbols': ['normal_public_symbol']}
            ordinary = {'synthetic terminal fixture': 256}
            baseline = root/'baseline.json'; baseline.write_text(json.dumps({'libraries': inventory, 'normal_checks': ordinary}))
            tested = root/'tested.json'; tested.write_text(json.dumps({'status': 'normal-checks-passed', 'libraries': inventory}))
            if corrupt: (lib/module.LIBRARY_NAMES[-1]).write_bytes(b'untested bytes')
            with patch.object(module, 'LIBRARY_DIR', lib), patch.object(module, 'normal_checks', return_value=ordinary), \
                    patch.object(module, 'run', return_value='6.5+20250216-2+erp1'), \
                    patch.object(module.ctypes, 'CDLL') as loaded, \
                    patch.object(module, 'libraries', side_effect=AssertionError('no runtime nm/readelf')), \
                    patch('sys.argv', ['helper', 'runtime', str(baseline), str(tested), str(output)]):
                module.main()
            self.assertEqual(loaded.call_count, 10)
            loaded.assert_any_call(str(lib/'libtic.so.6'))
            receipt = json.loads((output/'ncurses-runtime-compatibility.json').read_text())
            self.assertEqual(receipt['abi_validation'], 'byte-identical to ABI-tested build; all libraries loaded')

    def test_all_tested_library_bytes_are_loaded_without_runtime_binutils(self):
        self.check()

    def test_changed_library_fails_before_claiming_runtime_compatibility(self):
        with self.assertRaisesRegex(ValueError, 'bytes differ'):
            self.check(corrupt=True)


if __name__ == '__main__': unittest.main()
