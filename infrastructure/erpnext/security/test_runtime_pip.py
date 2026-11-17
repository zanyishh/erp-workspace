#!/usr/bin/env python3
"""Reject changed seed sources and unofficial or stale installed pip bytes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('runtime_pip', Path(__file__).with_name('install-runtime-pip.py'))
pip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pip)


class PipContracts(unittest.TestCase):
    def test_seed_patch_requires_exact_preimage_and_one_constant(self):
        source = b'# original notice\n_PIP_VERSION = "26.2.2"\n'
        entry = {'sha256': pip.digest(source), 'old_constant': '_PIP_VERSION = "26.2.2"',
                 'new_constant': '_PIP_VERSION = "26.3"'}
        self.assertEqual(pip.patch_ensurepip(source, entry), b'# original notice\n_PIP_VERSION = "26.3"\n')
        with self.assertRaises(ValueError):
            pip.patch_ensurepip(source + b'# unrelated edit\n', entry)
        duplicate = source + source
        with self.assertRaises(ValueError):
            pip.patch_ensurepip(duplicate, dict(entry, sha256=pip.digest(duplicate)))

    def test_checksum_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'artifact'
            path.write_bytes(b'official')
            self.assertEqual(pip.verify_file(path, pip.digest(b'official'), 8), b'official')
            with self.assertRaises(ValueError):
                pip.verify_file(path, pip.digest(b'changed'))
            link = Path(temporary) / 'link'
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                pip.verify_file(link, pip.digest(b'official'))

    def test_wheel_identity_detects_tamper_stale_files_and_missing_notice(self):
        members = {'pip/__init__.py': b'VERSION="test"\n', 'pip/_vendor/LICENSE': b'original notice\n',
                   'pip-test.dist-info/METADATA': b'Name: pip\n', 'pip-test.dist-info/RECORD': b''}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            wheel = directory / 'official.whl'
            with zipfile.ZipFile(wheel, 'w') as archive:
                for name, data in members.items():
                    archive.writestr(name, data)
                    target = directory / 'site' / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
            site = directory / 'site'
            self.assertEqual(pip.installed_matches_wheel(site, wheel), 3)
            stale = site / 'pip/removed.py'
            stale.write_text('old code')
            with self.assertRaises(ValueError): pip.installed_matches_wheel(site, wheel)
            stale.unlink()
            source = site / 'pip/__init__.py'
            source.write_text('modified code')
            with self.assertRaises(ValueError): pip.installed_matches_wheel(site, wheel)
            source.write_bytes(members['pip/__init__.py'])
            (site / 'pip/_vendor/LICENSE').unlink()
            with self.assertRaises(ValueError): pip.installed_matches_wheel(site, wheel)


if __name__ == '__main__':
    unittest.main()
