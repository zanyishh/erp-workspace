#!/usr/bin/env python3
"""Fail-closed checks for Kerberos source and library contract validation."""
import hashlib
import copy
import ctypes
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

DIRECTORY = Path(__file__).resolve().parent


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, DIRECTORY / file)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


build = module('krb5_build', 'tool-os-build-krb5.py')
package = module('krb5_package', 'tool-os-package-krb5.py')


class Guards(unittest.TestCase):
    def test_gss_name_type_compares_oid_value_not_storage_address(self):
        class OID(ctypes.Structure):
            _fields_ = [('length', ctypes.c_uint32), ('elements', ctypes.c_void_p)]
        a = ctypes.create_string_buffer(b'oid-value')
        b = ctypes.create_string_buffer(b'oid-value')
        left, right = OID(9, ctypes.cast(a, ctypes.c_void_p)), OID(9, ctypes.cast(b, ctypes.c_void_p))
        self.assertNotEqual(ctypes.addressof(left), ctypes.addressof(right))
        package.require_name_roundtrip(b'name', b'name', ctypes.byref(left), ctypes.byref(right))
        for text, returned in ((b'changed', ctypes.byref(right)), (b'name', None)):
            with self.subTest(text=text, returned=returned), self.assertRaises(ValueError):
                package.require_name_roundtrip(b'name', text, ctypes.byref(left), returned)
        right.length = 8
        with self.assertRaises(ValueError):
            package.require_name_roundtrip(b'name', b'name', ctypes.byref(left), ctypes.byref(right))
        right.length = 9
        b.value = b'other-oid'
        with self.assertRaises(ValueError):
            package.require_name_roundtrip(b'name', b'name', ctypes.byref(left), ctypes.byref(right))

    def test_abi_contract_hash_path_and_symlink_are_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = json.loads((DIRECTORY/'tool-os-krb5.lock.json').read_text())
            data = (DIRECTORY/'tool-os-krb5-abi-exception.json').read_bytes()
            (root/'tool-os-krb5.lock.json').write_text(json.dumps(source))
            contract = root/'tool-os-krb5-abi-exception.json'; contract.write_bytes(data)
            package.load_abi_contract(root)
            contract.write_bytes(data+b' ')
            with self.assertRaises(ValueError): package.load_abi_contract(root)
            contract.write_bytes(data)
            source['abi_exception']['file'] = 'different.json'
            (root/'tool-os-krb5.lock.json').write_text(json.dumps(source))
            with self.assertRaises(ValueError): package.load_abi_contract(root)
            source['abi_exception']['file'] = contract.name
            (root/'tool-os-krb5.lock.json').write_text(json.dumps(source))
            contract.rename(root/'target.json'); contract.symlink_to(root/'target.json')
            with self.assertRaises(ValueError): package.load_abi_contract(root)

    def test_only_exact_reviewed_internal_removal_allowed(self):
        contract = json.loads((DIRECTORY/'tool-os-krb5-abi-exception.json').read_text())
        source = json.loads((DIRECTORY/'tool-os-krb5.lock.json').read_text())
        context = {'base_image': source['base_image'], 'baseline_version': contract['baseline_package_version'],
                   'candidate_version': source['package_version'], 'upstream_version': source['upstream_version'],
                   'source_sha256': source['sources'][contract['source_archive']]['sha256'],
                   'provider_path': contract['baseline_provider']['path'],
                   'provider_sha256': contract['baseline_provider']['sha256'], 'soname': contract['soname']}
        missing = {contract['removed_symbol']}
        result = package.reviewed_removal(missing, context, contract)
        self.assertEqual(result['missing_symbols'], sorted(missing))
        self.assertFalse(result['full_export_parity'])
        for key in context:
            changed = dict(context, **{key: 'different'})
            with self.subTest(context=key), self.assertRaises(ValueError):
                package.reviewed_removal(missing, changed, contract)
        for symbols in ({'other@@V1'}, missing | {'other@@V1'}):
            with self.subTest(symbols=symbols), self.assertRaises(ValueError):
                package.reviewed_removal(symbols, context, contract)

    def test_new_runtime_consumers_and_provider_changes_rejected(self):
        contract = json.loads((DIRECTORY/'tool-os-krb5-abi-exception.json').read_text())
        provider = dict(contract['unmodified_bundled_provider'], target_literal=True,
                        elf={'imports': [], 'definitions': [contract['removed_symbol'].split('@')[0]]})
        inventory = {'status': 'completed', 'errors': [], 'matches': [provider],
                     'roots': ['/usr', '/opt', '/home', '/etc'],
                     'target': contract['removed_symbol'].split('@')[0]}
        package.require_consumer_scope(inventory, contract, {})
        documented = dict(provider, path='/usr/share/doc/library/README', elf=None)
        accepted = copy.deepcopy(inventory); accepted['matches'].append(documented)
        package.require_consumer_scope(accepted, contract, {documented['path']: documented['sha256']})
        documented['elf'] = {'imports': [], 'definitions': []}
        with self.assertRaises(ValueError):
            package.require_consumer_scope(accepted, contract, {documented['path']: documented['sha256']})
        for change in ('provider_hash', 'new_import', 'new_literal', 'scan_error'):
            changed = copy.deepcopy(inventory)
            if change == 'provider_hash': changed['matches'][0]['sha256'] = '0'*64
            elif change == 'new_import': changed['matches'].append(dict(provider, path='/usr/lib/new.so',
                elf={'imports':[contract['removed_symbol'].split('@')[0]], 'definitions':[]}))
            elif change == 'new_literal': changed['matches'].append(dict(provider, path='/home/frappe/new.py', elf=None))
            else: changed['errors'] = [{'path': '/usr/lib/unknown.so'}]
            with self.subTest(change=change), self.assertRaises(ValueError):
                package.require_consumer_scope(changed, contract, {})

    def test_capture_preserves_files_and_records_known_slim_image_omissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'output').mkdir()
            library = root / 'library'
            library.write_bytes(b'baseline bytes')
            omitted = '/usr/share/doc/libkrb5support0/changelog.Debian.gz'
            with patch.object(package, 'WORK', root), patch.object(package, 'OUTPUT', root / 'output'), \
                    patch.object(package, 'PACKAGES', {'libkrb5support0': 'libkrb5support.so.0'}), \
                    patch.object(package, 'run', side_effect=[
                        'Version: 1.21.3-5+deb13u1\n', str(library) + '\n' + omitted]):
                package.capture()
            contract = json.loads((root / 'output/original-package-contracts.json').read_text())['libkrb5support0']
            self.assertEqual(contract['paths'], [str(library)])
            self.assertEqual(contract['image_excluded_paths'], [omitted])
            self.assertEqual((root / 'baseline' / library.relative_to('/')).read_bytes(), b'baseline bytes')

    def test_capture_never_omits_a_missing_runtime_file_or_copyright(self):
        for missing in ('/usr/lib/aarch64-linux-gnu/libkrb5support.so.0.1',
                        '/usr/share/doc/libkrb5support0/copyright',
                        '/usr/share/doc/libkrb5support0/unexpected.txt'):
            with self.subTest(path=missing), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'output').mkdir()
                with patch.object(package, 'WORK', root), patch.object(package, 'OUTPUT', root / 'output'), \
                        patch.object(package, 'PACKAGES', {'libkrb5support0': 'libkrb5support.so.0'}), \
                        patch.object(package, 'run', side_effect=['Version: 1.21.3-5+deb13u1\n', missing]), \
                        self.assertRaisesRegex(ValueError, 'Missing baseline package path'):
                    package.capture()

    def test_failed_export_retains_stopped_evidence_container(self):
        receipt = {}
        with patch.object(build, 'command', side_effect=[
            'true', '', subprocess.CalledProcessError(1, ['docker', 'cp'])
        ]) as command:
            build.finish_container('owned-id', False, Path('/output'), receipt)
        self.assertEqual(receipt['container_retained'], 'owned-id')
        self.assertEqual([call.args[0] for call in command.call_args_list], ['inspect', 'stop', 'cp'])

    def test_source_hash_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            file = root / 'source'
            file.write_bytes(b'expected source')
            entry = {'source': {'bytes': file.stat().st_size,
                                'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}}
            build.verify_sources(root, entry)
            file.write_bytes(b'changed! source')
            with self.assertRaises(ValueError):
                build.verify_sources(root, entry)
            file.unlink()
            file.symlink_to('/etc/hosts')
            with self.assertRaises(ValueError):
                build.verify_sources(root, entry)

    def test_abi_preserved(self):
        with patch.object(package, 'run', return_value='(SONAME) [libkrb5.so.3]'), \
             patch.object(package, 'symbols', side_effect=[{'old@@V1'}, {'old@@V1', 'new@@V1'}, {'old@@V1'}, {'old@@V1', 'new@@V1'}]):
            result = package.check_abi(Path('old'), Path('new'), 'libkrb5.so.3')
        self.assertEqual(result['missing_symbols'], [])
        self.assertEqual(result['old_symbols'], 1)

    def test_missing_export_rejected(self):
        with patch.object(package, 'run', return_value='(SONAME) [libkrb5.so.3]'), \
             patch.object(package, 'symbols', side_effect=[{'old@@V1'}, {'new@@V1'}]), \
             self.assertRaisesRegex(ValueError, 'Removed exported symbols'):
            package.check_abi(Path('old'), Path('new'), 'libkrb5.so.3')

    def test_changed_soname_rejected(self):
        with patch.object(package, 'run', return_value='(SONAME) [libkrb5.so.4]'), \
             self.assertRaisesRegex(ValueError, 'Changed SONAME'):
            package.check_abi(Path('old'), Path('new'), 'libkrb5.so.3')


if __name__ == '__main__':
    unittest.main()
