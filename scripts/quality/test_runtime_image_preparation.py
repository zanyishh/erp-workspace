"""Offline boundary tests for image preparation; no containers or dependencies run."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SECURITY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), SECURITY/(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load('build-runtime-image')
assets = load('build-assets')
lxml_builder = load('build-lxml')
assembler = load('assemble-runtime')
os_checks = load('check-runtime-os')


class RuntimeImagePreparationTests(unittest.TestCase):
    def test_x11_contract_is_hash_bound_and_copied_to_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); context = root/'context'; security = root/'security'
            prepared = builder.prepare_context({'artifacts': {}, 'debian_packages': [], 'python_packages': []}, {}, context)
            name = 'os-x11-abi-contract.json'
            self.assertEqual(prepared['files'][name], builder.metadata(SECURITY/name))
            python = root/'python'; python.touch()
            with patch.object(assembler, 'INPUT', context), patch.object(assembler, 'SECURITY', security), \
                    patch.object(assembler, 'PYTHON', python), patch.object(assembler.sys, 'platform', 'linux'), \
                    patch.object(assembler, 'run', side_effect=RuntimeError('stop after contract staging')):
                with self.assertRaisesRegex(RuntimeError, 'stop after contract staging'): assembler.main()
            self.assertEqual(builder.metadata(security/name), prepared['files'][name])

    def test_x11_candidate_check_requires_staged_abi_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); inputs = root/'inputs'; inputs.mkdir(); security = root/'security'; security.mkdir()
            closure = {'components': {name: {'status': 'verified-build-handoff', 'required_baselines': []}
                                      for name in os_checks.COMPONENTS}}
            (inputs/'runtime-os-closure.lock.json').write_text(json.dumps(closure))
            def run(command, **kwargs):
                if command[2:3] == ['x11']:
                    self.assertEqual(command[3:], ['--x11-abi-contract', str(security/'os-x11-abi-contract.json')])
                return SimpleNamespace(returncode=0)
            def sndfile_smoke():
                (security/'os-checks/libsndfile/candidate-codecs.json').write_text('{}')
            module = SimpleNamespace(smoke=sndfile_smoke)
            loader = SimpleNamespace(exec_module=lambda value: None)
            with patch.object(os_checks, 'INPUT', inputs), patch.object(os_checks, 'SECURITY', security), \
                    patch.object(os_checks.subprocess, 'run', side_effect=run), \
                    patch.object(os_checks.importlib.util, 'spec_from_file_location', return_value=SimpleNamespace(loader=loader)), \
                    patch.object(os_checks.importlib.util, 'module_from_spec', return_value=module), \
                    contextlib.redirect_stdout(io.StringIO()):
                os_checks.main()

    def test_default_plan_never_invokes_docker(self):
        with patch.object(builder.subprocess, 'Popen', side_effect=AssertionError('no build')), \
                patch.object(builder, 'command', side_effect=AssertionError('no inspect')), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(builder.main([]), 0)

    def test_mutable_base_and_context_traversal_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'immutable ERP base'):
            builder.check_manifest({'base_image': 'frappe/erpnext:latest'}, Path('/unused'))
        with self.assertRaisesRegex(ValueError, 'artifact name'):
            builder.check_manifest({'base_image': builder.BASE, 'artifacts': {'../private': {}}}, Path('/unused'))

    def test_offline_apt_probe_failure_retention_or_changed_installer_cannot_open_build_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            receipt = Path(temporary)/'receipt.json'
            original = {'status': 'passed-offline-local-apt-and-ordinary-util-tests', 'exit_code': 0,
                'base_image': builder.BASE, 'network': 'none', 'application_mounts': [],
                'sources': {'install-runtime-debs.py': builder.digest(builder.SCRIPTS['install-runtime-debs.py'])}}
            for changed in [{'status': 'failed'}, {'container_retained': 'owned-id'},
                            {'cleanup_errors': ['export failed']},
                            {'sources': {'install-runtime-debs.py': '0'*64}}]:
                receipt.write_text(json.dumps(dict(original, **changed)))
                with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, 'match the current installer'):
                    builder.check_local_apt_gates({}, {'evidence/offline-apt/receipt.json': receipt})

    def test_lxml_plan_does_not_inspect_or_start_containers(self):
        with patch.object(lxml_builder, 'command', side_effect=AssertionError('no Docker')), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(lxml_builder.main([]), 0)

    def test_lxml_refuses_changed_official_archive_before_docker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'lxml-6.1.3.tar.gz'
            archive.write_bytes(b'original')
            entry = {'filename': archive.name, 'bytes': 8, 'sha256': lxml_builder.digest(archive)}
            archive.write_bytes(b'modified')
            with self.assertRaisesRegex(ValueError, 'checksum/size'):
                lxml_builder.verify_inputs(root, {'sources': [entry], 'build_test_wheels': []})

    def test_lxml_refuses_source_archive_path_traversal(self):
        import tarfile
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'lxml-6.1.3.tar.gz'
            with tarfile.open(archive, 'w:gz') as package:
                member = tarfile.TarInfo('../outside.txt'); member.size = 7
                package.addfile(member, io.BytesIO(b'fixture'))
            entry = {'filename': archive.name, 'bytes': archive.stat().st_size,
                     'sha256': lxml_builder.digest(archive), 'name': 'lxml', 'version': '6.1.3'}
            with self.assertRaisesRegex(ValueError, 'archive member'):
                lxml_builder.verify_inputs(root, {'sources': [entry], 'build_test_wheels': []})

    def test_artifact_source_outside_security_staging_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); source = root/'private.txt'; source.write_text('not build input')
            manifest = {'base_image': builder.BASE, 'artifacts': {'evidence/private.txt': {'source': str(source), **builder.metadata(source)}}}
            with self.assertRaisesRegex(ValueError, 'owned security staging'):
                builder.check_manifest(manifest, root/'tools')

    def test_checksum_change_after_validation_prevents_context_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); source = root/'wheel.whl'; source.write_bytes(b'original')
            manifest = {'artifacts': {'wheels/wheel.whl': builder.metadata(source)}}
            source.write_bytes(b'changed')
            with patch.object(builder, 'CONTRACTS', {}), patch.object(builder, 'SCRIPTS', {}):
                with self.assertRaisesRegex(ValueError, 'changed after verification'):
                    builder.prepare_context(manifest, {'wheels/wheel.whl': source}, root/'context')

    def fixture(self, root):
        bench = root/'bench'; security = root/'security'; security.mkdir()
        (security/'runtime-artifacts.lock.json').write_text(json.dumps({'base_images': {'erpnext': builder.BASE}}))
        (bench/'sites/assets').mkdir(parents=True)
        (bench/'sites/apps.txt').write_text('frappe\nerpnext\n')
        for app in ('frappe', 'erpnext'):
            public = bench/'apps'/app/app/'public'; (public/'dist').mkdir(parents=True)
            (public/'dist/stale.js').write_text('old bundle')
            (public/'dist/LICENSE.txt').write_text('preserved legal notice')
            (bench/'sites/assets'/app).symlink_to(public)
        for name in ('assets.json', 'assets-rtl.json'):
            (bench/'sites/assets'/name).write_text('{"old":"/assets/frappe/dist/stale.js"}')
        return bench, security

    def test_successful_build_cannot_reuse_stale_assets_or_old_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            bench, security = self.fixture(Path(temporary).resolve())
            (security/'asset-build.json').write_text('{"status":"passed"}')
            with patch.object(assets, 'BENCH', bench), patch.object(assets, 'SECURITY', security), \
                    patch.object(assets.subprocess, 'run'):
                with self.assertRaisesRegex(ValueError, 'did not create'): assets.main()
            self.assertFalse((bench/'apps/frappe/frappe/public/dist/stale.js').exists())
            self.assertFalse((security/'asset-build.json').exists())
            self.assertEqual((security/'prior-generated-asset-notices/apps/frappe/frappe/public/dist/LICENSE.txt').read_text(), 'preserved legal notice')

    def test_fresh_output_receipt_hashes_actual_bundles(self):
        with tempfile.TemporaryDirectory() as temporary:
            bench, security = self.fixture(Path(temporary).resolve())
            def build(*args, **kwargs):
                self.assertFalse((bench/'apps/frappe/frappe/public/dist').exists())
                target = bench/'apps/frappe/frappe/public/dist/new.js'; target.parent.mkdir(); target.write_text('new bundle')
                for name in ('assets.json', 'assets-rtl.json'):
                    (bench/'sites/assets'/name).write_text('{"new":"/assets/frappe/dist/new.js"}')
            with patch.object(assets, 'BENCH', bench), patch.object(assets, 'SECURITY', security), \
                    patch.object(assets.subprocess, 'run', side_effect=build): assets.main()
            receipt = json.loads((security/'asset-build.json').read_text())
            self.assertEqual(receipt['status'], 'passed')
            self.assertEqual(receipt['asset_files']['/assets/frappe/dist/new.js'], assets.digest(bench/'apps/frappe/frappe/public/dist/new.js'))
            self.assertTrue(receipt['prior_generated_outputs_removed'])

    def test_receipt_rejects_unrebuilt_source_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            bench, security = self.fixture(Path(temporary).resolve())
            target = bench/'apps/frappe/frappe/public/source.js'; target.write_text('not a bundle')
            def build(*args, **kwargs):
                for name in ('assets.json', 'assets-rtl.json'):
                    (bench/'sites/assets'/name).write_text('{"new":"/assets/frappe/source.js"}')
            with patch.object(assets, 'BENCH', bench), patch.object(assets, 'SECURITY', security), \
                    patch.object(assets.subprocess, 'run', side_effect=build):
                with self.assertRaisesRegex(ValueError, 'fresh candidate build'): assets.main()
            self.assertFalse((security/'asset-build.json').exists())

    def test_committed_snapshot_seeds_exact_bytes_and_rejects_retained_corruption(self):
        import importlib.machinery
        launcher = SECURITY.parents[2]/'scripts/erp-native-secure.command'
        loader = importlib.machinery.SourceFileLoader('secure_seed_fixture', str(launcher))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        secure = importlib.util.module_from_spec(spec); loader.exec_module(secure)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); bench, security = self.fixture(root)
            target = root/'dedicated-sites'; target.mkdir()
            def build(*args, **kwargs):
                bundle = bench/'apps/frappe/frappe/public/dist/new.js'
                bundle.parent.mkdir(); bundle.write_text('new bundle')
                (bundle.parent/'shared-chunk.js').write_text('new shared chunk')
                for name in ('assets.json', 'assets-rtl.json'):
                    (bench/'sites/assets'/name).write_text('{"new":"/assets/frappe/dist/new.js"}')
            with patch.object(assets, 'BENCH', bench), patch.object(assets, 'SECURITY', security), \
                    patch.object(assets.subprocess, 'run', side_effect=build): assets.main()
            receipt = json.loads((security/'asset-build.json').read_text())
            self.assertIn('/assets/frappe/dist/shared-chunk.js', receipt['asset_files'])
            script = secure.ASSET_SEED.replace('/opt/erp-security', str(security)) \
                .replace('/home/frappe/frappe-bench/apps', str(bench/'apps')) \
                .replace('/home/frappe/frappe-bench/sites', str(target))
            logs = root/'logs'; logs.mkdir()
            script = script.replace('/home/frappe/frappe-bench/logs', str(logs))
            # The test remaps filesystem roots; the seed algorithm is unchanged.
            receipt['asset_snapshot_path'] = str(security/'fresh-sites-assets')
            (security/'asset-build.json').write_text(json.dumps(receipt))
            with patch('pwd.getpwnam', return_value=SimpleNamespace(pw_uid=0, pw_gid=0)), \
                    patch('os.chown'), contextlib.redirect_stdout(io.StringIO()):
                exec(compile(script, '<asset-seed-fixture>', 'exec'), {})
                self.assertEqual((target/'assets/frappe/dist/new.js').read_text(), 'new bundle')
                (target/'assets/assets.json').write_text('{"stale":true}')
                with self.assertRaisesRegex(RuntimeError, 'Retained public assets differ'):
                    exec(compile(script, '<asset-seed-fixture>', 'exec'), {})


if __name__ == '__main__':
    unittest.main()
