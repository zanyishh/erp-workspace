#!/usr/bin/env python3
"""Guard regressions: never remove an unowned path or exhaust either VM disk."""
import importlib.util
import json
from pathlib import Path
import stat
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runner = load('curl_runner', 'tool-os-build-curl.py')
helper = load('curl_scratch', 'tool-os-curl-scratch.py')
TOKEN = '0123456789abcdef' * 2
PATH = str(helper.scratch_path(TOKEN))
IDENTITY = {'device': 1, 'inode': 2, 'uid': 0}


class ScratchGuards(unittest.TestCase):
    def test_path_is_generated_and_never_user_selected(self):
        self.assertEqual(PATH, '/tmp/erp-quality-curl-' + TOKEN)
        for token in ('', '../application-data', 'g' * 32, '0' * 31, None):
            with self.subTest(token=token), self.assertRaises(ValueError):
                helper.scratch_path(token)

    def test_each_partition_and_host_have_independent_floors(self):
        for initial, docker, scratch, host in ((True, 1000, 1400, 1200), (False, 400, 400, 400)):
            good = {'docker': docker * runner.MIB, 'scratch': scratch * runner.MIB}
            runner.check_space(good, host * runner.MIB, initial)
            for partition in good:
                with self.subTest(initial=initial, partition=partition), self.assertRaises(RuntimeError):
                    runner.check_space(dict(good, **{partition: good[partition] - 1}), host * runner.MIB, initial)
            with self.assertRaises(RuntimeError):
                runner.check_space(good, host * runner.MIB - 1, initial)

    def test_container_mount_overlap_in_both_directions_blocks_cleanup(self):
        for source in (PATH, PATH + '/child', '/tmp', '/'):
            with self.subTest(source=source), patch.object(runner, 'command', side_effect=[
                'container-id', json.dumps([{'Source': source}])
            ]), self.assertRaises(RuntimeError):
                runner.reject_shared_scratch(PATH)
        with patch.object(runner, 'command', side_effect=[
            'container-id', json.dumps([{'Source': PATH + '-different'}, {'Source': '/app-data'}])
        ]):
            runner.reject_shared_scratch(PATH)

    def test_same_or_nested_mount_blocks_recursive_deletion(self):
        for mount in (PATH, PATH + '/nested'):
            with self.subTest(mount=mount), self.assertRaises(ValueError):
                helper.reject_nested_mounts(Path(PATH), '1 2 3:4 / ' + mount + ' rw - ext4 /dev/root rw')
        helper.reject_nested_mounts(Path(PATH), '1 2 3:4 / /tmp/other rw - ext4 /dev/root rw')

    def test_symlink_wrong_owner_or_permissions_are_rejected(self):
        for mode, uid in ((stat.S_IFLNK | 0o700, 0), (stat.S_IFDIR | 0o700, 502), (stat.S_IFDIR | 0o777, 0)):
            path = MagicMock(spec=Path)
            path.lstat.return_value = SimpleNamespace(st_mode=mode, st_uid=uid, st_dev=1, st_ino=2)
            with self.subTest(mode=mode, uid=uid), self.assertRaises(ValueError):
                helper.identity(path)

    def test_identity_and_marker_changes_fail_closed(self):
        path = MagicMock(spec=Path)
        path.resolve.return_value = path
        path.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFDIR | 0o700, st_uid=0, st_dev=1, st_ino=2)
        marker = path.__truediv__.return_value
        marker.lstat.return_value = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=0, st_nlink=1)
        marker.read_text.return_value = TOKEN + '\n'
        with patch.object(helper, 'scratch_path', return_value=path):
            helper.validate(path, TOKEN, IDENTITY)
            with self.assertRaises(ValueError):
                helper.validate(path, TOKEN, dict(IDENTITY, inode=3))
            marker.read_text.return_value = 'another-owner\n'
            with self.assertRaises(ValueError):
                helper.validate(path, TOKEN, IDENTITY)
            marker.read_text.return_value = TOKEN + '\n'
            for mode, links in ((stat.S_IFLNK | 0o777, 1), (stat.S_IFREG | 0o600, 2)):
                marker.lstat.return_value = SimpleNamespace(st_mode=mode, st_uid=0, st_nlink=links)
                with self.assertRaises(ValueError):
                    helper.validate(path, TOKEN, IDENTITY)

    def test_existing_uuid_folder_is_never_reused(self):
        with patch.object(helper.os, 'geteuid', return_value=0), \
                patch.object(helper, 'storage', return_value={'scratch': 1500 * runner.MIB, 'docker': 1100 * runner.MIB}), \
                patch.object(Path, 'resolve', lambda path: path), \
                patch.object(Path, 'mkdir', side_effect=FileExistsError('exists')), \
                patch.object(Path, 'open') as opened:
            with self.assertRaises(FileExistsError):
                helper.main({'action': 'create', 'token': TOKEN})
            opened.assert_not_called()

    def test_failed_evidence_export_retains_stopped_container(self):
        receipt = {}
        with patch.object(runner, 'command', side_effect=[
            'true', '', subprocess.CalledProcessError(1, ['docker', 'cp'])
        ]) as command:
            self.assertFalse(runner.finish_container('owned-id', False, Path('/output'), receipt))
        self.assertEqual(receipt['container_retained'], 'owned-id')
        self.assertEqual([call.args[0] for call in command.call_args_list], ['inspect', 'stop', 'cp'])


if __name__ == '__main__':
    unittest.main()
