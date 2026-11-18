"""Reject package ownership changes that could grant unintended privileges."""
import importlib.util
from pathlib import Path
import unittest
import tempfile

SPEC = importlib.util.spec_from_file_location('package_util_linux', Path(__file__).with_name('package-util-linux.py'))
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class PayloadMetadataTests(unittest.TestCase):
    def setUp(self):
        self.original = {'usr/bin/wall': {
            'uid': 0, 'gid': 5, 'mode': 0o2755, 'directory': False, 'symlink': None,
        }}

    def test_original_setgid_tty_preserved(self):
        PACKAGE.verify_payload_metadata(self.original, self.original.copy())

    def test_setgid_root_rejected(self):
        changed = {'usr/bin/wall': {**self.original['usr/bin/wall'], 'gid': 0}}
        with self.assertRaisesRegex(RuntimeError, 'ownership'):
            PACKAGE.verify_payload_metadata(self.original, changed)

    def test_permission_change_rejected(self):
        changed = {'usr/bin/wall': {**self.original['usr/bin/wall'], 'mode': 0o4755}}
        with self.assertRaisesRegex(RuntimeError, 'ownership'):
            PACKAGE.verify_payload_metadata(self.original, changed)

    def test_missing_original_path_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'ownership'):
            PACKAGE.verify_payload_metadata(self.original, {})


class RebuiltPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def add_elf(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'\x7fELFsynthetic-path-fixture')
        return path

    def test_legacy_usrmerge_path(self):
        expected = self.add_elf('bin/dmesg')
        self.assertEqual(PACKAGE.rebuilt_elf(self.root, Path('usr/bin/dmesg')), expected)

    def test_explicit_debian_renames(self):
        for destination, source in [('usr/bin/rename.ul', 'usr/bin/rename'),
                                    ('usr/bin/partx', 'usr/sbin/partx'),
                                    ('usr/sbin/chmem', 'usr/bin/chmem'),
                                    ('usr/sbin/isosize', 'usr/bin/isosize')]:
            with self.subTest(destination=destination):
                expected = self.add_elf(source)
                self.assertEqual(PACKAGE.rebuilt_elf(self.root, Path(destination)), expected)

    def test_ambiguous_merged_and_legacy_files_rejected(self):
        self.add_elf('bin/dmesg'); self.add_elf('usr/bin/dmesg')
        with self.assertRaisesRegex(RuntimeError, 'found 2'):
            PACKAGE.rebuilt_elf(self.root, Path('usr/bin/dmesg'))

    def test_unreviewed_category_change_rejected(self):
        self.add_elf('usr/sbin/dmesg')
        with self.assertRaisesRegex(RuntimeError, 'found 0'):
            PACKAGE.rebuilt_elf(self.root, Path('usr/bin/dmesg'))

    def test_symlink_or_non_elf_input_rejected(self):
        target = self.add_elf('bin/dmesg')
        (self.root / 'bin/other').symlink_to(target)
        for name in ('other', 'text'):
            if name == 'text': (self.root / 'bin/text').write_text('text')
            with self.assertRaisesRegex(RuntimeError, 'found 0'):
                PACKAGE.rebuilt_elf(self.root, Path('usr/bin') / name)


class DependencySubstitutionTests(unittest.TestCase):
    def test_exact_same_source_libraries_and_external_minimum_preserved(self):
        self.assertEqual(PACKAGE.resolve_elf_dependencies('libblkid1 (= ${binary:Version}), libc6 (>= 2.38)'),
                         'libblkid1 (= 2.41.6-0+erp1), libc6 (>= 2.38)')

    def test_library_not_rebuilt_here_cannot_use_local_version(self):
        with self.assertRaisesRegex(RuntimeError, 'Unreviewed'):
            PACKAGE.resolve_elf_dependencies('libfdisk1 (= ${binary:Version})')

    def test_unknown_variable_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Unresolved'):
            PACKAGE.resolve_elf_dependencies('libc6 (>= ${other:Version})')


if __name__ == '__main__':
    unittest.main()
