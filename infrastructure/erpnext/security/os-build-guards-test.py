#!/usr/bin/env python3
"""Exercise preflight failures without starting Docker or touching app data."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('os_builder', Path(__file__).with_name('build-os-package.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class SourceGuards(unittest.TestCase):
    def test_unconfirmed_stop_retains_container_without_export_or_removal(self):
        for failure in ('inspect', 'stop'):
            for evidence_copied in (False, True):
                with self.subTest(failure=failure, evidence_copied=evidence_copied):
                    calls = []
                    def command(*args):
                        calls.append(args)
                        if args[0] == failure:
                            raise OSError('Docker stop state unavailable')
                        return 'true' if args[0] == 'inspect' else ''
                    receipt = {}
                    with patch.object(builder, 'command', command):
                        builder.finish_container('new-owned-id', evidence_copied, Path('/evidence'), receipt)
                    self.assertFalse(any(args[0] in ('cp', 'rm') for args in calls))
                    self.assertEqual(receipt['container_retained'], 'new-owned-id')
                    self.assertEqual(receipt['cleanup_errors'][0]['action'], 'stop')

    def test_failed_evidence_export_retains_owned_container(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[0] == 'inspect':
                return 'true'
            if args[0] == 'cp':
                raise OSError('external destination unavailable')
            return ''
        receipt = {}
        with patch.object(builder, 'command', command):
            builder.finish_container('new-owned-id', False, Path('/evidence'), receipt)
        self.assertIn(('stop', '--time', '5', 'new-owned-id'), calls)
        self.assertFalse(any(args[0] == 'rm' for args in calls))
        self.assertEqual(receipt['container_retained'], 'new-owned-id')

    def test_declared_payload_is_hashed_without_debian_version_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'module-payload.tar.gz').write_bytes(b'payload')
            self.assertEqual(builder.collect_artifacts(root, ['module-payload.tar.gz']),
                             {'module-payload.tar.gz': hashlib.sha256(b'payload').hexdigest()})

    def test_missing_declared_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Missing'):
                builder.collect_artifacts(Path(directory), ['missing.tar.gz'])

    def test_source_without_hash_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'source.tar.xz').write_bytes(b'original')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                builder.verify_sources(root, {'source.tar.xz': {'bytes': 8}})

    def test_source_names_cannot_escape_input_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'basename'):
                builder.verify_sources(Path(directory), {'../outside': {'bytes': 0, 'sha256': 'unused'}})

    def test_helper_names_cannot_escape_security_directory(self):
        with self.assertRaisesRegex(ValueError, 'basename'):
            builder.local_helper('../outside.py')

    def test_modified_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'source.tar.xz'
            archive.write_bytes(b'original')
            entry = {'bytes': 8, 'sha256': hashlib.sha256(b'original').hexdigest()}
            builder.verify_sources(root, {'source.tar.xz': entry})
            archive.write_bytes(b'modified')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                builder.verify_sources(root, {'source.tar.xz': entry})

    def test_symlink_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'original').write_bytes(b'original')
            (root / 'source.tar.xz').symlink_to('original')
            with self.assertRaisesRegex(ValueError, 'regular'):
                builder.verify_sources(root, {'source.tar.xz': {'bytes': 8, 'sha256': hashlib.sha256(b'original').hexdigest()}})

    def test_incomplete_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'source.tar.xz').write_bytes(b'partial')
            with self.assertRaisesRegex(ValueError, 'size'):
                builder.verify_sources(root, {'source.tar.xz': {'bytes': 8, 'sha256': '0' * 64}})


if __name__ == '__main__':
    unittest.main()
