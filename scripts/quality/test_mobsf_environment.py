"""MobSF tool selection stays inside the known read-only Android SDK."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import install_mobsf


class MobSFEnvironmentTests(unittest.TestCase):
    def test_fixed_aapt_paths_replace_caller_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            sdk = Path(temporary).resolve() / 'sdk'
            tools = sdk / 'build-tools/36.0.0'; tools.mkdir(parents=True)
            for name in ['aapt', 'aapt2']:
                path = tools / name; path.write_text('public tool fixture'); path.chmod(0o700)
            with patch.object(install_mobsf, 'ANDROID_SDK', sdk), \
                    patch.dict(os.environ, {'MOBSF_AAPT2_BINARY': '/untrusted/tool'}):
                env = install_mobsf.environment(Path(temporary) / 'home')
            self.assertEqual(env['MOBSF_AAPT2_BINARY'], str(tools / 'aapt2'))
            self.assertEqual(env['MOBSF_AAPT_BINARY'], str(tools / 'aapt'))

    def test_missing_pair_is_not_misreported_and_symlink_escape_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); sdk = root / 'sdk'
            tools = sdk / 'build-tools/36.0.0'; tools.mkdir(parents=True)
            with patch.object(install_mobsf, 'ANDROID_SDK', sdk):
                self.assertEqual(install_mobsf.android_aapt_paths(), {})
                other = root / 'foreign'; other.write_text('foreign'); other.chmod(0o700)
                (tools / 'aapt2').symlink_to(other)
                with self.assertRaises(RuntimeError): install_mobsf.android_aapt_paths()


if __name__ == '__main__': unittest.main()
