"""Candidate Node replacement boundaries, using small synthetic archives only."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

FILE = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security/install-runtime-node.py'
SPEC = importlib.util.spec_from_file_location('node_runtime_installer', FILE)
installer = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(installer)


class NodeRuntimeInstallerTests(unittest.TestCase):
    def fixture(self, root):
        target = root/installer.LEGACY.lstrip('/')
        old = {'bin/node': b'old binary', 'include/node/node.h': b'old API',
               'include/node/node_version.h': b'#define NODE_MAJOR_VERSION 24\n#define NODE_MINOR_VERSION 22\n#define NODE_PATCH_VERSION 2\n',
               'include/node/stale.h': b'old removed header',
               'share/man/man1/node.1': b'old manual', 'LICENSE': b'old legal notice',
               'README.md': b'old readme', 'CHANGELOG.md': b'old changelog'}
        for name, value in old.items():
            path = target/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(value)
            path.chmod(0o755 if name == 'bin/node' else 0o644)
        npm = target/'lib/node_modules/npm/package.json'; npm.parent.mkdir(parents=True); npm.write_bytes(b'preserved npm patch')
        new = {name: b'new '+value for name, value in old.items() if name != 'include/node/stale.h'}
        new['include/node/node_version.h'] = old['include/node/node_version.h'].replace(b'VERSION 2\n', b'VERSION 3\n')
        new['include/node/new.h'] = b'new API'
        archive = root/'node.tar.xz'
        with tarfile.open(archive, 'w:xz') as stream:
            for name, value in dict(new, **{'lib/node_modules/npm/package.json': b'archive npm must be ignored'}).items():
                entry = tarfile.TarInfo(installer.PREFIX+'/'+name); entry.size = len(value)
                entry.mode = 0o755 if name == 'bin/node' else 0o644
                stream.addfile(entry, io.BytesIO(value))
        lock = {'status': 'verified-inputs-runtime-validation-pending', 'legacy_root': installer.LEGACY,
                'archive': {'bytes': archive.stat().st_size, 'sha256': installer.digest(archive)},
                'before': {'node': '24.22.2', 'modules': '137', 'platform': 'linux', 'arch': 'arm64'},
                'after': {'node': '24.22.3', 'modules': '137', 'sqlite': '3.54.1', 'platform': 'linux', 'arch': 'arm64'},
                'baseline_files': {name: installer.file_metadata(target/name) for name in old},
                'baseline_directories': {str(p.relative_to(target)): installer.directory_metadata(p)
                    for p in target.rglob('*') if p.is_dir() and installer.selected_directory(str(p.relative_to(target)))},
                'replacement_files': {name: {'sha256': installer.bytes_digest(value), 'bytes': len(value),
                    'mode': 0o755 if name == 'bin/node' else 0o644} for name, value in new.items()}}
        return target, archive, lock, new

    def invoke(self, root, archive, lock):
        with patch.object(installer, 'TARGET_ROOT', root), patch.object(installer, 'require_candidate'), \
                patch.object(installer, 'runtime_info', side_effect=[lock['before'], lock['after']]):
            installer.install(lock, archive, root/'evidence')

    def test_changed_last_preimage_prevents_every_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); target, archive, lock, _ = self.fixture(root)
            (target/'CHANGELOG.md').write_bytes(b'unexpected')
            with self.assertRaisesRegex(ValueError, 'preimage'):
                self.invoke(root, archive, lock)
            self.assertEqual((target/'bin/node').read_bytes(), b'old binary')
            self.assertFalse((root/'evidence').exists())

    def test_verified_update_preserves_package_trees_and_notices(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); target, archive, lock, new = self.fixture(root)
            self.invoke(root, archive, lock)
            for name, value in new.items(): self.assertEqual((target/name).read_bytes(), value)
            self.assertFalse((target/'include/node/stale.h').exists())
            self.assertEqual((target/'lib/node_modules/npm/package.json').read_bytes(), b'preserved npm patch')
            self.assertEqual((root/'evidence/prior-notices/LICENSE').read_bytes(), b'old legal notice')
            self.assertEqual((target/'bin/node').stat().st_mode & 0o777, 0o755)
            self.assertEqual((target/'include/node/new.h').stat().st_mode & 0o777, 0o644)
            receipt = json.loads((root/'evidence/receipt.json').read_text())
            self.assertEqual(receipt['after']['node'], '24.22.3')
            self.assertEqual(set(receipt['installed']), set(new))

    def test_wrong_old_runtime_version_prevents_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); target, archive, lock, _ = self.fixture(root)
            with patch.object(installer, 'TARGET_ROOT', root), patch.object(installer, 'require_candidate'), \
                    patch.object(installer, 'runtime_info', return_value=dict(lock['before'], node='24.22.1')):
                with self.assertRaisesRegex(ValueError, 'runtime preimage'):
                    installer.install(lock, archive, root/'evidence')
            self.assertEqual((target/'bin/node').read_bytes(), b'old binary')

    def test_archive_path_escape_duplicate_and_selected_link_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); _, _, lock, _ = self.fixture(root)
            for names, kind in [([installer.PREFIX+'/../escape'], tarfile.REGTYPE),
                                ([installer.PREFIX+'/bin/node']*2, tarfile.REGTYPE),
                                ([installer.PREFIX+'/bin/node'], tarfile.SYMTYPE)]:
                archive = root/'bad.tar'
                with tarfile.open(archive, 'w') as stream:
                    for name in names:
                        entry = tarfile.TarInfo(name); entry.type = kind
                        stream.addfile(entry, io.BytesIO())
                lock['archive'] = {'bytes': archive.stat().st_size, 'sha256': installer.digest(archive)}
                with self.subTest(names=names), self.assertRaises(ValueError):
                    installer.archive_inventory(archive, lock)

    def test_extra_header_or_linked_target_blocks_before_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); target, archive, lock, _ = self.fixture(root)
            extra = target/'include/node/unreviewed.h'; extra.write_text('unreviewed')
            with self.assertRaisesRegex(ValueError, 'header inventory'):
                self.invoke(root, archive, lock)
            extra.unlink(); (target/'bin/node').unlink(); (target/'bin/node').symlink_to(root/'outside')
            with self.assertRaisesRegex(ValueError, 'linked'):
                self.invoke(root, archive, lock)
            self.assertFalse((root/'outside').exists())

    def test_pending_lock_and_missing_candidate_flag_are_refused(self):
        with patch.dict(installer.os.environ, {}, clear=True), self.assertRaisesRegex(RuntimeError, 'isolated candidate'):
            installer.require_candidate()
        with self.assertRaisesRegex(ValueError, 'verified'):
            installer.archive_inventory(Path('/absent'), {'status': 'pending'})


if __name__ == '__main__': unittest.main()
