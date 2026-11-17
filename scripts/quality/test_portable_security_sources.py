"""Exercise pyexpat's named preflight entry point from a relocated checkout."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SECURITY = Path(__file__).resolve().parents[2] / 'infrastructure/erpnext/security'


class PortableSourceTests(unittest.TestCase):
    def test_moved_checkout_and_external_quality_root_verify_the_same_locked_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = root / 'original checkout'
            recipe = Path('infrastructure/erpnext/security')
            directory = checkout / recipe
            directory.mkdir(parents=True)
            for name in ('tool-os-build-pyexpat.py', 'source_builder_mounts.py'):
                shutil.copyfile(SECURITY / name, directory / name)
            quality = root / 'separate quality storage'
            source_root = checkout / '.local/source'
            source_root.mkdir(parents=True)
            quality.mkdir()
            sources = {}
            for name, file, reference in (
                ('external.tar', quality / 'external.tar', 'quality-home/external.tar'),
                ('local.deb', source_root / 'local.deb', 'repository/.local/source/local.deb'),
            ):
                content = name.encode()
                file.write_bytes(content)
                sources[name] = {'staged_path': reference, 'bytes': len(content),
                                 'sha256': hashlib.sha256(content).hexdigest()}
            (directory / 'tool-os-pyexpat.lock.json').write_text(
                json.dumps({'sources': sources, 'local_build': 'synthetic'}))
            checkout = checkout.rename(root / 'relocated checkout')
            command = [sys.executable, str(checkout / recipe / 'tool-os-build-pyexpat.py'),
                       '--quality-home', str(quality), '--output', str(root / 'output'), '--preflight']
            good = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertFalse(json.loads(good.stdout)['build_started'])
            (quality / 'external.tar').write_bytes(b'external.bad')
            bad = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn('Source checksum mismatch', bad.stderr)
            self.assertFalse((root / 'output').exists())


if __name__ == '__main__':
    unittest.main()
