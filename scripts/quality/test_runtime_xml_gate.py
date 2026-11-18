"""Test that candidate assembly cannot accept an incomplete tested XML pair."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SECURITY = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'
SPEC = importlib.util.spec_from_file_location('runtime_image_xml_gate', SECURITY/'build-runtime-image.py')
builder = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(builder)


class XmlPairGateTests(unittest.TestCase):
    def fixture(self, root):
        source = json.loads((SECURITY/'tool-os-pyexpat.lock.json').read_text())
        files = {}; manifest = {'artifacts': {}}; hashes = {}
        def write(name, value):
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value if isinstance(value, str) else json.dumps(value))
            key = 'artifacts/pyexpat/'+name
            files[key] = path; manifest['artifacts'][key] = builder.metadata(path); hashes[name] = builder.digest(path)
        modules = {name+source['baseline']['variables']['EXT_SUFFIX']: name
                   for name in ('pyexpat', '_elementtree')}
        for name, value in modules.items(): write('modules/'+name, value)
        for name in ('CPython-LICENSE', 'Expat-COPYING'): write('notices/'+name, 'preserved notice')
        module_hashes = {name: hashes['modules/'+name] for name in modules}
        identity = {'status': 'compiled-and-upstream-tests-passed',
                    'source_lock_sha256': builder.digest(SECURITY/'tool-os-pyexpat.lock.json'),
                    'modules': module_hashes,
                    'notices': {name: hashes['notices/'+name] for name in ('CPython-LICENSE', 'Expat-COPYING')}}
        tested = {'status': 'passed', 'exit_code': 0, 'suites': source['upstream_tests'],
                  'module_hashes_before': module_hashes, 'module_hashes_after': module_hashes,
                  'junit': {'tests': 100, 'errors': 0, 'failures': 0}}
        write('build-identity.json', identity); write('upstream-result.json', tested)
        write('upstream-tests.log', '\n'.join(source['upstream_tests'])+'\nAll 8 tests OK.\nTotal test files: run=8/8\n')
        write('upstream-tests.xml', '<testsuites/>')
        receipt = {'status': 'built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending',
                   'exit_code': 0, 'base_image': builder.BASE, 'source': source,
                   'source_lock_sha256': identity['source_lock_sha256'], 'application_mounts': [],
                   'modules': module_hashes, 'artifacts': dict(hashes)}
        write('receipt.json', receipt)
        return manifest, files, write, receipt, tested

    def test_exact_pair_and_successful_complete_evidence_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest, files, *_ = self.fixture(Path(temporary))
            builder.check_pyexpat_gates(manifest, files)

    def test_changed_post_test_binary_or_failed_case_cannot_pass(self):
        for failure in ('hash', 'test'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                manifest, files, write, receipt, tested = self.fixture(Path(temporary))
                if failure == 'hash': tested['module_hashes_after'] = {'unexpected': '0'*64}
                else: tested['junit']['failures'] = 1
                write('upstream-result.json', tested)
                receipt['artifacts']['upstream-result.json'] = builder.digest(files['artifacts/pyexpat/upstream-result.json'])
                write('receipt.json', receipt)
                with self.assertRaisesRegex(ValueError, 'exact paired'): builder.check_pyexpat_gates(manifest, files)

    def test_successful_exit_with_skipped_whole_module_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest, files, write, receipt, _ = self.fixture(Path(temporary))
            log = files['artifacts/pyexpat/upstream-tests.log'].read_text().replace('run=8/8', 'run=8/8 skipped=1')
            write('upstream-tests.log', log)
            receipt['artifacts']['upstream-tests.log'] = builder.digest(files['artifacts/pyexpat/upstream-tests.log'])
            write('receipt.json', receipt)
            with self.assertRaisesRegex(ValueError, 'Incomplete'): builder.check_pyexpat_gates(manifest, files)


if __name__ == '__main__': unittest.main()
