"""Security boundaries for the isolated source build; no Docker needed."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import subprocess

SPEC = importlib.util.spec_from_file_location('build_util_linux', Path(__file__).with_name('build-util-linux.py'))
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)
RECOVERY_SPEC = importlib.util.spec_from_file_location('recover_util_linux', Path(__file__).with_name('recover-util-linux.py'))
RECOVERY = importlib.util.module_from_spec(RECOVERY_SPEC)
RECOVERY_SPEC.loader.exec_module(RECOVERY)


class ArchiveBoundaryTests(unittest.TestCase):
    def check_archive(self, name, *, link=None, bad_hash=False):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'source.tar.xz'
            with tarfile.open(path, 'w:xz') as archive:
                member = tarfile.TarInfo(name)
                if link is None:
                    member.size = 4
                    archive.addfile(member, io.BytesIO(b'test'))
                else:
                    member.type = tarfile.SYMTYPE
                    member.linkname = link
                    archive.addfile(member)
            entry = {'bytes': path.stat().st_size,
                     'sha256': '0' * 64 if bad_hash else hashlib.sha256(path.read_bytes()).hexdigest(),
                     'root': 'util-linux-2.41.6'}
            BUILD.verify_archive(path, entry)

    def test_valid_official_shape(self):
        self.check_archive('util-linux-2.41.6/COPYING')

    def test_checksum_mismatch_rejected(self):
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.check_archive('util-linux-2.41.6/COPYING', bad_hash=True)

    def test_parent_traversal_rejected_even_with_matching_digest(self):
        with self.assertRaisesRegex(ValueError, 'member'):
            self.check_archive('util-linux-2.41.6/../../outside')

    def test_link_rejected_even_with_matching_digest(self):
        with self.assertRaisesRegex(ValueError, 'member'):
            self.check_archive('util-linux-2.41.6/source', link='/etc/passwd')


class EvidenceRetentionTests(unittest.TestCase):
    def test_failed_export_retains_stopped_container(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[0] == 'inspect':
                return 'true'
            if args[0] == 'cp':
                raise subprocess.CalledProcessError(1, args)
            return ''
        receipt = {}
        with patch.object(BUILD, 'command', command):
            BUILD.finish_container('owned-id', Path('/unused'), receipt)
        self.assertEqual([call[0] for call in calls], ['inspect', 'stop', 'cp'])
        self.assertEqual(receipt['container_retained'], 'owned-id')

    def test_successful_export_precedes_removal(self):
        with patch.object(BUILD, 'command', side_effect=['false', '', '']) as command:
            BUILD.finish_container('owned-id', Path('/unused'), {})
        self.assertEqual([call.args[0] for call in command.call_args_list], ['inspect', 'cp', 'rm'])

    def test_stop_failure_does_not_remove_or_copy_live_container(self):
        receipt = {}
        with patch.object(BUILD, 'command', side_effect=['true', subprocess.CalledProcessError(1, 'stop')]) as command:
            BUILD.finish_container('owned-id', Path('/unused'), receipt)
        self.assertEqual([call.args[0] for call in command.call_args_list], ['inspect', 'stop'])
        self.assertEqual(receipt['container_retained'], 'owned-id')


class RecoveryBoundaryTests(unittest.TestCase):
    def make_fixture(self, directory, *, member='installed/bin/tool', link=None, phase_source=None):
        source = {'version': 'fixture'}
        with tarfile.open(directory / 'validated-build-inputs.tar.gz', 'w:gz') as archive:
            item = tarfile.TarInfo(member)
            if link is None:
                item.size = 4; archive.addfile(item, io.BytesIO(b'test'))
            else:
                item.type = tarfile.SYMTYPE; item.linkname = link; archive.addfile(item)
        (directory / 'upstream-tests.log').write_text('All 340 tests PASSED\nSKIPPED (fixture)\n')
        (directory / 'source-applicability.json').write_text('{}')
        def entry(name):
            data = (directory / name).read_bytes()
            return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        files = {name: entry(name) for name in ('validated-build-inputs.tar.gz', 'upstream-tests.log', 'source-applicability.json')}
        (directory / 'validated-build-inputs.json').write_text(json.dumps({
            'status': 'tested', 'source_lock': phase_source if phase_source is not None else source, 'files': files}))
        (directory / 'receipt.json').write_text(json.dumps({'status': 'failed', 'exit_code': 1,
            'error': 'package failed', 'application_mounts': [], 'source': source}))
        files.update({name: entry(name) for name in ('validated-build-inputs.json', 'receipt.json')})
        return {'files': files, 'prior_outer_status': 'failed', 'prior_outer_error': 'package failed',
                'retained_phase': 'tested'}, source

    def test_completed_phase_can_recover_without_disguising_old_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); lock, source = self.make_fixture(directory)
            result = RECOVERY.verify(directory, lock, source)
            self.assertFalse(result['recompiled'])
            self.assertTrue(result['upstream_skips_retained'])
            self.assertEqual(json.loads((directory / 'receipt.json').read_text())['status'], 'failed')

    def test_changed_retained_input_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); lock, source = self.make_fixture(directory)
            (directory / 'upstream-tests.log').write_text('edited')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                RECOVERY.verify(directory, lock, source)

    def test_completed_phase_with_different_source_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); lock, source = self.make_fixture(directory, phase_source={'version': 'other'})
            with self.assertRaisesRegex(ValueError, 'identity'):
                RECOVERY.verify(directory, lock, source)

    def test_path_traversal_and_escaping_link_rejected(self):
        for member, link in [('installed/../../outside', None), ('installed/bin/link', '../../../etc/passwd')]:
            with self.subTest(member=member), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); lock, source = self.make_fixture(directory, member=member, link=link)
                with self.assertRaisesRegex(ValueError, 'member|escapes'):
                    RECOVERY.verify(directory, lock, source)


class PreparedPackageBoundaryTests(unittest.TestCase):
    def fixture(self, root, *, altered_phase=False):
        source = {'version': 'fixture'}; recovery = {'archive_sha256': 'f' * 64}
        packages = {}
        for name in 'util-linux mount bsdutils libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2 login'.split():
            filename = name + '.deb'; data = ('synthetic ' + name).encode(); (root / filename).write_bytes(data)
            packages[name] = {'package': filename, 'sha256': hashlib.sha256(data).hexdigest()}
        (root / 'package-receipt.json').write_text(json.dumps({'all_original_elf_replaced': True, 'packages': packages}))
        (root / 'receipt.json').write_text(json.dumps({'source': source, 'status': 'failed', 'exit_code': 100,
            'application_mounts': [], 'packaging_recovery': {'other': True} if altered_phase else recovery}))
        files = {}
        for name in ['package-receipt.json', 'prior-package-install-failed.json', *[x['package'] for x in packages.values()]]:
            path = root / ('receipt.json' if name == 'prior-package-install-failed.json' else name)
            data = path.read_bytes(); files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        return {'files': files, 'expected_failed_exit_code': 100}, source, recovery

    def test_exact_reviewed_package_set_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, source, recovery = self.fixture(root)
            self.assertEqual(len(BUILD.verify_prepared_packages(root, lock, source, recovery)['packages']), 9)

    def test_changed_archive_rejected_before_container(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, source, recovery = self.fixture(root)
            (root / 'util-linux.deb').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                BUILD.verify_prepared_packages(root, lock, source, recovery)

    def test_different_completed_phase_rejected_even_with_matching_file_hashes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, source, recovery = self.fixture(root, altered_phase=True)
            with self.assertRaisesRegex(ValueError, 'different tested tree'):
                BUILD.verify_prepared_packages(root, lock, source, recovery)

    def test_linked_receipt_rejected_even_with_matching_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); lock, source, recovery = self.fixture(root)
            (root / 'receipt.json').rename(root / 'linked.json')
            (root / 'receipt.json').symlink_to(root / 'linked.json')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                BUILD.verify_prepared_packages(root, lock, source, recovery)


if __name__ == '__main__':
    unittest.main()
