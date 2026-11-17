"""Recovery must reject changed provenance, escaping archives and binary drift."""
import importlib.util
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

DIRECTORY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'
sys.path.insert(0, str(DIRECTORY))
spec = importlib.util.spec_from_file_location('lxml_recovery', DIRECTORY/'lxml_recovery.py')
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class LxmlRecoveryTests(unittest.TestCase):
    def test_changed_checkpoint_is_rejected_before_archive_is_opened(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root/'compiled-source.tar.gz').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'checksum/size'):
                recovery.verify(root, {'source_lock_sha256': 'trusted', 'files': {
                    'compiled-source.tar.gz': {'bytes': 8, 'sha256': '0'*64}}}, 'trusted')

    def test_archive_link_cannot_escape_compiled_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'checkpoint.tar.gz'
            with tarfile.open(path, 'w:gz') as archive:
                member = tarfile.TarInfo('lxml-6.1.3/escape')
                member.type = tarfile.SYMTYPE; member.linkname = '../../outside'
                archive.addfile(member)
            with self.assertRaisesRegex(ValueError, 'link escapes'):
                recovery.validate_archive(path, {'archive_root': 'lxml-6.1.3', 'archive_entries_limit': 10,
                                'archive_expanded_bytes_limit': 100})

    def test_changed_production_binary_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root/'etree.so').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Production binary changed'):
                recovery.verify_binaries(root, {'etree.so': '0'*64})


if __name__ == '__main__': unittest.main()
