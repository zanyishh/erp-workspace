"""Dependency gates must not pass when custom lock files were not recognized."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('dependency_scan', Path(__file__).with_name('dependency_scan.py'))
SCAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCAN)


class DependencyCoverageTests(unittest.TestCase):
    def test_unrecognized_python_lock_cannot_pass_empty_scan(self):
        with self.assertRaisesRegex(RuntimeError, 'not recognized'):
            SCAN.summarize({'Results': []}, ['locks/checkov/requirements.txt'])

    def test_mapped_locks_must_remain_byte_identical(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            config = source / 'infrastructure/erpnext/quality'
            config.mkdir(parents=True)
            for name in ('core', 'semgrep', 'checkov'):
                (config / f'requirements-{name}.lock.txt').write_text(f'{name}==1.0\n')
            mapping = SCAN.stage_python_locks(source)
            self.assertEqual(len(mapping), 3)
            for row in mapping:
                self.assertEqual((source / row['source']).read_bytes(), (source / row['target']).read_bytes())
            (source / mapping[0]['target']).write_text('changed')
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                SCAN.verify_mapping(source, mapping)

    def test_raw_medium_is_retained_but_only_high_critical_fail_gate(self):
        rows = {'Results': [{'Target': 'locks/checkov/requirements.txt', 'Type': 'pip',
                             'Vulnerabilities': [{'Severity': 'MEDIUM'}, {'Severity': 'HIGH'}]}]}
        result = SCAN.summarize(rows, ['locks/checkov/requirements.txt'])
        self.assertEqual(result['severities'], {'MEDIUM': 1, 'HIGH': 1})
        self.assertEqual(result['high_critical_occurrences'], 1)


if __name__ == '__main__':
    unittest.main()
