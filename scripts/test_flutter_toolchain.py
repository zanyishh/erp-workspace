"""Project Flutter selection must never fall back to an older global SDK."""
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import flutter_toolchain


class FlutterToolchainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'external/tools'
        self.sdk = self.home / 'sdk/flutter'
        (self.sdk / 'bin/cache').mkdir(parents=True)
        for name in ('bin/flutter', 'bin/dart', 'bin/cache/dart-sdk/bin/dart',
                     'bin/cache/dart-sdk/bin/dartvm', 'bin/cache/dart-sdk/bin/dartaotruntime'):
            executable = self.sdk / name
            executable.parent.mkdir(parents=True, exist_ok=True)
            executable.write_text('#!/bin/sh\nexit 0\n')
            executable.chmod(0o755)
        self.versions = {
            'frameworkVersion': '3.47.9', 'frameworkRevision': 'pinned-framework',
            'engineRevision': 'pinned-engine', 'dartSdkVersion': '3.13.7', 'channel': 'stable',
        }
        self.write('infrastructure/erpnext/quality/flutter-toolchain.json', {'version': self.versions})
        self.write('.local/quality/location.json', {'tool_home': str(self.home),
            'mountpoint': str(self.root / 'external'), 'volume_uuid': 'selected-volume'})
        self.write('.local/quality/flutter-sdk.json', {'sdk': str(self.sdk)})
        (self.sdk / 'bin/cache/flutter.version.json').write_text(json.dumps(self.versions))
        self.mount = patch.object(flutter_toolchain.os.path, 'ismount', return_value=True)
        self.mount.start()
        self.addCleanup(self.mount.stop)
        self.identity = patch.object(flutter_toolchain.subprocess, 'check_output',
                                     return_value=plistlib.dumps({'VolumeUUID': 'selected-volume'}))
        self.identity.start()
        self.addCleanup(self.identity.stop)

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def test_selected_command_and_mutable_caches_use_external_sdk(self):
        inherited = {'PATH': '/old/flutter/bin:/usr/bin', 'FLUTTER_ROOT': '/old/flutter',
                     'PUB_HOSTED_URL': 'https://untrusted.invalid', 'GRADLE_USER_HOME': '/host/cache'}
        with patch.dict(os.environ, inherited), patch.object(flutter_toolchain.os, 'execvpe') as execute:
            flutter_toolchain.main(['analyze', '--no-pub'], root=self.root)
        executable, command, env = execute.call_args.args
        self.assertEqual(Path(executable), self.sdk / 'bin/flutter')
        self.assertEqual(command[-2:], ['analyze', '--no-pub'])
        self.assertEqual(env['PATH'].split(os.pathsep)[0], str(self.sdk / 'bin'))
        self.assertEqual(env['FLUTTER_ROOT'], str(self.sdk))
        self.assertEqual(env['PUB_HOSTED_URL'], 'https://pub.dev')
        self.assertEqual(env['FLUTTER_STORAGE_BASE_URL'], 'https://storage.googleapis.com')
        for name in ('PUB_CACHE', 'TMPDIR', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME',
                     'XDG_DATA_HOME', 'GRADLE_USER_HOME', 'ANDROID_USER_HOME'):
            self.assertTrue(Path(env[name]).is_relative_to(self.home), name)
            self.assertTrue(Path(env[name]).is_dir(), name)

    def test_missing_selection_never_executes_path_fallback(self):
        (self.root / '.local/quality/flutter-sdk.json').unlink()
        with patch.object(flutter_toolchain.os, 'execvpe') as execute:
            with self.assertRaisesRegex(RuntimeError, 'selection'):
                flutter_toolchain.main(['--version'], root=self.root)
        execute.assert_not_called()

    def test_older_or_different_engine_metadata_is_rejected(self):
        for key, bad in [('frameworkVersion', '3.38.7'), ('dartSdkVersion', '3.10.7'),
                         ('engineRevision', 'different')]:
            with self.subTest(key=key):
                (self.sdk / 'bin/cache/flutter.version.json').write_text(json.dumps({**self.versions, key: bad}))
                with self.assertRaisesRegex(RuntimeError, 'pinned'):
                    flutter_toolchain.selected_sdk(self.root)

    def test_sdk_outside_external_home_is_rejected(self):
        self.write('.local/quality/flutter-sdk.json', {'sdk': '/opt/homebrew/share/flutter'})
        with self.assertRaisesRegex(RuntimeError, 'external'):
            flutter_toolchain.selected_sdk(self.root)

    def test_missing_mount_cannot_create_a_host_cache(self):
        with patch.object(flutter_toolchain.os.path, 'ismount', return_value=False):
            with self.assertRaisesRegex(RuntimeError, 'mounted'):
                flutter_toolchain.main(['--version'], root=self.root)
        self.assertFalse((self.home / 'flutter-project').exists())

    def test_dart_uses_the_same_selected_sdk(self):
        with patch.object(flutter_toolchain.os, 'execvpe') as execute:
            flutter_toolchain.main(['--dart', '--version'], root=self.root)
        self.assertEqual(Path(execute.call_args.args[0]), self.sdk / 'bin/dart')

    def test_cache_symlink_cannot_write_to_the_host(self):
        elsewhere = self.root / 'host-cache'
        elsewhere.mkdir()
        (self.home / 'pub-cache').symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'outside'):
            flutter_toolchain.main(['--version'], root=self.root)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_another_volume_at_the_same_mount_is_rejected(self):
        with patch.object(flutter_toolchain.subprocess, 'check_output',
                          return_value=plistlib.dumps({'VolumeUUID': 'another-volume'})):
            with self.assertRaisesRegex(RuntimeError, 'identity'):
                flutter_toolchain.main(['--version'], root=self.root)
        self.assertFalse((self.home / 'flutter-project').exists())

    def test_bundled_dart_cannot_resolve_to_another_sdk(self):
        external = self.root / 'old-dart'
        external.write_text('#!/bin/sh\nexit 0\n')
        external.chmod(0o755)
        executable = self.sdk / 'bin/cache/dart-sdk/bin/dart'
        executable.unlink()
        executable.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError, 'pinned'):
            flutter_toolchain.selected_sdk(self.root)


if __name__ == '__main__':
    unittest.main()
