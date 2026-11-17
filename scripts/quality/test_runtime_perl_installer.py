"""Exercise installer preflight and ownership guards with synthetic files only."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security/install-runtime-perl.py'
SPEC = importlib.util.spec_from_file_location('runtime_perl_installer', PATH)
installer = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(installer)


class PerlInstallerTests(unittest.TestCase):
    def fixture(self, root):
        files = {'usr/share/perl/5.40.1/Archive/Tar.pm': b'fixed module', 'usr/bin/ptar': b'fixed tool'}
        old = {}
        for name in files:
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'original')
            old[name] = installer.digest(b'original')
        lock = root/'lock.json'
        lock.write_text(json.dumps({'archive-tar': {'preimages': old,
            'sources': {'Archive-Tar-3.14.tar.gz': {'sha256': 'a'*64}}}}))
        data = dict(files, **{'manifest.json': json.dumps({'version': '3.14', 'source_sha256': 'a'*64,
            'files': {name: installer.digest(value) for name, value in files.items()}}).encode(),
            'Archive-Tar-META.json': b'{}', 'Archive-Tar-README': b'license fixture'})
        payload = root/'payload.tar.gz'
        with tarfile.open(payload, 'w:gz') as archive:
            for name, value in data.items():
                item = tarfile.TarInfo(name); item.size = len(value)
                archive.addfile(item, io.BytesIO(value))
        return lock, payload, files

    def invoke(self, root, lock, payload):
        with patch.object(installer, 'TARGET_ROOT', root), patch.object(installer, 'LOCK', lock), \
                patch.dict(installer.os.environ, {'ERP_SECURITY_IMAGE_BUILD': '1'}), \
                patch('sys.argv', ['installer', '--payload', str(payload), '--receipt', str(root/'evidence/receipt.json')]), \
                patch.object(installer.subprocess, 'check_output', return_value='3.14'):
            installer.main()

    def test_late_preimage_mismatch_leaves_every_file_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, payload, files = self.fixture(root)
            (root/'usr/bin/ptar').write_bytes(b'unexpected original')
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                self.invoke(root, lock, payload)
            self.assertEqual((root/'usr/share/perl/5.40.1/Archive/Tar.pm').read_bytes(), b'original')
            self.assertEqual((root/'usr/bin/ptar').read_bytes(), b'unexpected original')
            self.assertFalse((root/'evidence/receipt.json').exists())

    def test_verified_payload_replaces_only_declared_files_and_records_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, payload, files = self.fixture(root)
            untouched = root/'usr/bin/perl'; untouched.write_bytes(b'interpreter unchanged')
            self.invoke(root, lock, payload)
            for name, data in files.items(): self.assertEqual((root/name).read_bytes(), data)
            self.assertEqual(untouched.read_bytes(), b'interpreter unchanged')
            receipt = json.loads((root/'evidence/receipt.json').read_text())
            self.assertEqual(receipt['payload_sha256'], installer.digest(payload.read_bytes()))

    def test_environment_guard_prevents_opening_payload(self):
        with patch.dict(installer.os.environ, {}, clear=True), \
                patch('sys.argv', ['installer', '--payload', '/absent', '--receipt', '/absent']), \
                patch.object(installer.tarfile, 'open', side_effect=AssertionError('must not read')):
            with self.assertRaisesRegex(RuntimeError, 'isolated candidate'):
                installer.main()


if __name__ == '__main__':
    unittest.main()
