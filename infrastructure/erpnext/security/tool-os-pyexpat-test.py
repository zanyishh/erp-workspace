#!/usr/bin/env python3
"""Guard regressions for the exact, coupled CPython XML extension rebuild."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import subprocess
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('xml_rebuild', HERE / 'tool-os-pyexpat.py')
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
spec = importlib.util.spec_from_file_location('xml_controller', HERE / 'tool-os-build-pyexpat.py')
controller = importlib.util.module_from_spec(spec); spec.loader.exec_module(controller)
LOCK = json.loads((HERE / 'tool-os-pyexpat.lock.json').read_text())


class Guards(unittest.TestCase):
    def test_stop_failure_retains_container_without_export_or_removal(self):
        receipt = {}
        with patch.object(controller, 'command', side_effect=[
            'true', subprocess.CalledProcessError(1, ['docker', 'stop'])
        ]) as command:
            controller.finish_container('owned-id', False, Path('/output'), receipt)
        self.assertEqual(receipt['container_retained'], 'owned-id')
        self.assertEqual([call.args[0] for call in command.call_args_list], ['inspect', 'stop'])

    def test_requested_modules_must_all_finish_successfully(self):
        names = LOCK['upstream_tests']
        log = '\n'.join(names) + '\nAll 8 tests OK.\nTotal test files: run=8/8\n'
        helper.validate_upstream_log(log, names)
        for changed in (log.replace('All 8 tests OK.', '7 tests OK.'),
                        log.replace('run=8/8', 'run=8/8 skipped=1'),
                        log.replace('run=8/8', 'run=7/8'),
                        log.replace(names[0], '')):
            with self.subTest(log=changed), self.assertRaisesRegex(ValueError, 'Incomplete'):
                helper.validate_upstream_log(changed, names)

    def test_changed_abi_configuration_is_rejected(self):
        with patch.object(helper.platform, 'system', return_value='Linux'), \
             patch.object(helper.platform, 'machine', return_value='aarch64'), \
             patch.object(helper.platform, 'python_version', return_value=LOCK['python_version']), \
             patch.object(helper.sysconfig, 'get_config_var', return_value='unexpected'), \
             self.assertRaisesRegex(ValueError, 'configuration changed'):
            helper.require_runtime(LOCK)

    def test_upstream_failure_cannot_activate_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'upstream-result.json').write_text(json.dumps({'status':'failed','suites':LOCK['upstream_tests']}))
            with patch.object(helper, 'prepare_pair') as prepare, self.assertRaisesRegex(ValueError, 'successful complete'):
                helper.install(LOCK, root, root / 'output')
            prepare.assert_not_called()

    def test_missing_notice_blocks_before_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'modules').mkdir(); (root / 'notices').mkdir()
            names = {n+LOCK['baseline']['variables']['EXT_SUFFIX'] for n in helper.MODULES}
            for name in names: (root / 'modules' / name).write_bytes(b'fixture')
            identity = {'source_lock_sha256':helper.digest(HERE/'tool-os-pyexpat.lock.json'),
                        'system_expat':{'version':'expat_2.10.0'},
                        'modules':{n:helper.digest(root/'modules'/n) for n in names},'notices':{}}
            (root/'build-identity.json').write_text(json.dumps(identity))
            with patch.dict(helper.os.environ, ERP_SECURITY_IMAGE_BUILD='1'), \
                 patch.object(helper.os,'geteuid',return_value=0), \
                 patch.object(helper,'verify_baseline'), \
                 patch.object(helper,'require_expat',return_value=identity['system_expat']), \
                 self.assertRaisesRegex(ValueError,'license notices'):
                helper.prepare_pair(LOCK,root,root/'output')
            self.assertFalse((root/'output').exists())

    def test_source_escape_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name,kind in [('source/../escape',tarfile.REGTYPE),('source/link',tarfile.SYMTYPE)]:
                archive=root/'source.tar'; entry=tarfile.TarInfo(name); entry.type=kind
                with tarfile.open(archive,'w') as output: output.addfile(entry,io.BytesIO())
                with self.subTest(name=name),self.assertRaisesRegex(ValueError,'Unexpected source archive'):
                    helper.extract_source(archive,root/'target','source')
            self.assertFalse((root/'target').exists())


if __name__=='__main__': unittest.main()
