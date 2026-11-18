"""OS artifact provenance and omission gates; synthetic fixtures, no Docker."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SECURITY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'
spec = importlib.util.spec_from_file_location('os_closure', SECURITY/'check-runtime-os-closure.py')
gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
BASE = 'fixed-immutable-base'


class RuntimeOsClosureTests(unittest.TestCase):
    def test_script_set_cannot_succeed_with_omitted_or_changed_test(self):
        scripts = {'one': 'a'*64, 'two': 'b'*64}
        good = {name: {'status': 'passed', 'exit_code': 0, 'stderr_bytes': 0,
                      'script_sha256': sha, 'stdout_sha256': 'c'*64} for name, sha in scripts.items()}
        records = lambda values: [dict(result, name=name) for name, result in values.items()]
        gate.verify_script_results({'tests': records(good)}, scripts)
        for changed in ('omitted', 'source', 'failure', 'stderr', 'duplicate'):
            tests = json.loads(json.dumps(good))
            if changed == 'omitted': tests.pop('two')
            elif changed == 'source': tests['two']['script_sha256'] = 'd'*64
            elif changed == 'failure': tests['two']['exit_code'] = 1
            elif changed == 'stderr': tests['two']['stderr_bytes'] = 1
            result = records(tests)
            if changed == 'duplicate': result.append(result[0])
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, 'Ordinary script'):
                gate.verify_script_results({'tests': result}, scripts)

    def fixture(self, root):
        config, output = root/'config', root/'build'; config.mkdir(); output.mkdir()
        source = {'base_image': BASE, 'git': {'package_version': '1:2.50.2-0+erp1', 'sources': {'archive': 'fixed'}}}
        (config/'source.json').write_text(json.dumps(source))
        files, artifacts = {}, {}
        def put(name, basename, content):
            path = output/basename; path.write_bytes(content)
            sha = hashlib.sha256(content).hexdigest(); files[name] = path
            artifacts[name] = {'sha256': sha, 'bytes': len(content), 'source': str(path)}
            return {'artifact': name, 'sha256': sha}
        snapshot = put('evidence/git/source.json', 'source.json', json.dumps(source).encode())
        package = put('debs/git.deb', 'git.deb', b'normal synthetic package fixture')
        receipt = {'status': 'passed-normal-tests', 'exit_code': 0, 'source': source['git'],
                   'base_image': BASE, 'application_mounts': [], 'packages': {'git.deb': package['sha256']}}
        proof = put('evidence/git/receipt.json', 'receipt.json', json.dumps(receipt).encode())
        compatibility = put('evidence/git/compatibility.json', 'compatibility.json', b'{"ordinary":true}')
        entry = {'status': 'verified-build-handoff', 'source_lock': 'source.json', 'source_key': 'git',
            'expected_build_status': 'passed-normal-tests',
            'packages': {'git': {'version': '1:2.50.2-0+erp1', 'architecture': 'arm64'}},
            'build_receipts': [{**proof, 'source_snapshot': snapshot['artifact'], 'source_snapshot_sha256': snapshot['sha256']}],
            'evidence_files': {'compatibility.json': compatibility}, 'required_baselines': [],
            'required_json_evidence': {'compatibility.json': {'ordinary': True}},
            'package_artifacts': {'git': {**package, 'proof_artifact': proof['artifact'], 'proof_path': ['packages','git.deb']}}}
        closure = {'base_image': BASE, 'components': {'git': entry}}
        manifest = {'base_image': BASE, 'artifacts': artifacts,
                    'debian_packages': [{'name': 'git', 'version': '1:2.50.2-0+erp1', 'architecture': 'arm64', 'artifact': package['artifact']}]}
        return config, closure, entry, manifest, files

    def verify(self, config, closure, manifest, files):
        (config/'runtime-os-closure.lock.json').write_text(json.dumps(closure))
        with patch.object(gate, 'COMPONENTS', {'git'}): return gate.verify(manifest, files, config)

    def test_pending_component_blocks_before_any_artifact_use(self):
        with tempfile.TemporaryDirectory() as temp:
            config, closure, entry, manifest, files = self.fixture(Path(temp))
            entry['status'] = 'pending-validated-artifacts'
            with patch.object(gate, 'digest') as artifact_read:
                with self.assertRaisesRegex(ValueError, 'handoffs remain pending'):
                    self.verify(config, closure, manifest, files)
                artifact_read.assert_not_called()

    def test_complete_synthetic_handoff_validates(self):
        with tempfile.TemporaryDirectory() as temp:
            config, closure, entry, manifest, files = self.fixture(Path(temp))
            self.assertEqual(self.verify(config, closure, manifest, files), closure)

    def test_omitted_package_and_missing_ordinary_evidence_are_rejected(self):
        for changed in ('package', 'baseline', 'compatibility'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temp:
                config, closure, entry, manifest, files = self.fixture(Path(temp))
                if changed == 'package': entry['package_artifacts'].clear()
                if changed == 'baseline': entry['required_baselines'] = ['missing.json']
                if changed == 'compatibility': entry['required_json_evidence']['compatibility.json']['ordinary'] = False
                with self.assertRaises(ValueError): self.verify(config, closure, manifest, files)

    def test_tampered_package_and_wrong_proof_are_rejected(self):
        for changed in ('bytes', 'proof', 'origin'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temp:
                config, closure, entry, manifest, files = self.fixture(Path(temp))
                if changed == 'bytes': files['debs/git.deb'].write_bytes(b'changed')
                if changed == 'proof': entry['package_artifacts']['git']['proof_path'] = ['status']
                if changed == 'origin':
                    foreign = Path(temp)/'foreign.deb'; foreign.write_bytes(files['debs/git.deb'].read_bytes()); files['debs/git.deb'] = foreign
                with self.assertRaises(ValueError): self.verify(config, closure, manifest, files)

    def test_failed_receipt_still_fails_when_its_hash_is_recorded(self):
        with tempfile.TemporaryDirectory() as temp:
            config, closure, entry, manifest, files = self.fixture(Path(temp))
            path = files['evidence/git/receipt.json']; receipt = json.loads(path.read_text()); receipt['exit_code'] = 1
            path.write_text(json.dumps(receipt)); sha = hashlib.sha256(path.read_bytes()).hexdigest()
            entry['build_receipts'][0]['sha256'] = sha; manifest['artifacts']['evidence/git/receipt.json']['sha256'] = sha
            with self.assertRaisesRegex(ValueError, 'receipt/source validation failed'):
                self.verify(config, closure, manifest, files)


if __name__ == '__main__': unittest.main()
