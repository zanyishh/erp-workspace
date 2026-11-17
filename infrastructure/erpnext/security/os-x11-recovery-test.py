#!/usr/bin/env python3
"""Saved X11 package checks must reject changed bytes and incomplete phases."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('recovery', HERE/'os-x11-recovery.py')
recovery = importlib.util.module_from_spec(spec); spec.loader.exec_module(recovery)


class CheckpointTests(unittest.TestCase):
    def fixture(self, directory):
        source = {'sources': {}, 'abi_contract_sha256': 'a'*64}
        lock = {'base_image': 'immutable', 'x11': source}
        (directory/'os-artifacts.lock.json').write_text(json.dumps(lock))
        (directory/'receipt.json').write_text(json.dumps({'status': 'failed', 'exit_code': 2,
            'source': source, 'base_image': 'immutable', 'application_mounts': []}))
        (directory/'git-manual-build.log').write_text('/usr/local/bin/python3: No module named asciidoc\n')
        (directory/'dpkg-audit.txt').write_text('')
        scope = {'fixture': {'version': '1', 'architecture': 'arm64'}}
        (directory/'compatibility.json').write_text(json.dumps({'component': 'x11',
            'versions': {'fixture': '1'}, 'libxi_public_exports_resolved': 88}))
        package = directory/'fixture_1_arm64.deb'; package.write_bytes(b'tested package')
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        (directory/'fixture.changes').write_text(f'Checksums-Sha256:\n {digest} {package.stat().st_size} {package.name}\n')
        return lock, scope, package

    def test_saved_package_must_match_packaging_checksum(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve(); lock, scope, package = self.fixture(directory)
            result = recovery.verify_checkpoint(directory, lock, scope, families=())
            self.assertIn(package.name, result['files'])
            package.write_bytes(b'changed package')
            with self.assertRaisesRegex(ValueError, 'packaging checksum'):
                recovery.verify_checkpoint(directory, lock, scope, families=())

    def test_incomplete_abi_or_unrelated_failure_is_rejected(self):
        for changed in ('exports', 'failure', 'cleanup'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve(); lock, scope, _ = self.fixture(directory)
                if changed == 'exports':
                    p = directory/'compatibility.json'; d=json.loads(p.read_text()); d['libxi_public_exports_resolved']=87; p.write_text(json.dumps(d))
                elif changed == 'failure': (directory/'git-manual-build.log').write_text('unrelated failure')
                else:
                    p=directory/'receipt.json'; d=json.loads(p.read_text()); d['cleanup_errors']=['export']; p.write_text(json.dumps(d))
                with self.assertRaises(ValueError): recovery.verify_checkpoint(directory, lock, scope, families=())


if __name__ == '__main__': unittest.main()
