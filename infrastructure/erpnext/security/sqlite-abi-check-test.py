#!/usr/bin/env python3
"""ABI transition guards, without Docker or application data."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('abi', Path(__file__).with_name('sqlite-abi-check.py'))
abi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(abi)


class SQLiteAbiGuards(unittest.TestCase):
    def test_only_reviewed_internal_removal_is_accepted(self):
        result = abi.compare_exports({'sqlite3_open', 'sqlite3Internal'}, {'sqlite3_open'},
                                     {'sqlite3_open'}, {'sqlite3Internal'})
        self.assertEqual(result['public_exports_preserved'], 1)
        self.assertEqual(result['audited_internal_removals'], ['sqlite3Internal'])

    def test_lost_public_api_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Public SQLite'):
            abi.compare_exports({'sqlite3_open', 'sqlite3Internal'}, {'sqlite3Internal'},
                                {'sqlite3_open'}, {'sqlite3Internal'})

    def test_unreviewed_internal_removal_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unreviewed'):
            abi.compare_exports({'sqlite3_open', 'sqlite3OtherInternal'}, {'sqlite3_open'},
                                {'sqlite3_open'}, {'sqlite3Internal'})

    def test_public_symbol_cannot_be_classified_as_internal(self):
        with self.assertRaisesRegex(ValueError, 'classification'):
            abi.compare_exports({'sqlite3_open'}, set(), {'sqlite3_open'}, {'sqlite3_open'})

    def test_changed_audit_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'audit.json'
            path.write_text('{"imports":["unexpected"]}')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                abi.verified_json(path, '0' * 64)


if __name__ == '__main__':
    unittest.main()
