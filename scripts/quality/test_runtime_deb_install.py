"""Reject unintended local package transactions before any installation."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security/install-runtime-debs.py'
spec = importlib.util.spec_from_file_location('runtime_debs', path)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class OfflineDebianInstallTests(unittest.TestCase):
    expected = {'bsdutils': {'version': '1:2.41.6-0+erp1', 'architecture': 'arm64'}}

    def test_epoch_local_upgrade_and_configure(self):
        plan = 'Inst bsdutils [1:2.41.5] (1:2.41.6-0+erp1 local-deb [arm64])\nConf bsdutils (1:2.41.6-0+erp1 local-deb [arm64])\n'
        self.assertEqual(module.transaction(plan, self.expected), {'bsdutils': '1:2.41.6-0+erp1'})

    def test_unlisted_version_removal_architecture_and_malformed_actions_fail(self):
        for text in ['Remv bsdutils [1:2.41.5]', 'Inst other (1:2.41.6-0+erp1 local-deb [arm64])',
                     'Inst bsdutils (old local-deb [arm64])',
                     'Inst bsdutils (1:2.41.6-0+erp1 local-deb [amd64])',
                     'Inst bsdutils:amd64 (1:2.41.6-0+erp1 local-deb [amd64])', 'Inst bsdutils malformed']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                module.transaction(text, self.expected)

    def test_actual_apt_interim_dependency_diagnostics_are_not_package_actions(self):
        expected = {'liblastlog2-2': {'version': '2.41.6-0+erp1', 'architecture': 'arm64'}}
        line = 'Inst liblastlog2-2 [2.41.5-0+deb13u1] (2.41.6-0+erp1 local-deb [arm64]) [util-linux:arm64 on liblastlog2-2:arm64] [util-linux:arm64 ]'
        self.assertEqual(module.transaction(line, expected), {'liblastlog2-2': '2.41.6-0+erp1'})
        with self.assertRaises(ValueError): module.transaction(line+' Inst other (1 local-deb [arm64])', expected)

    def test_global_inventory_and_configured_state_must_match(self):
        before = {'bsdutils:arm64': {'version': 'old', 'status': 'ii '},
                  'unchanged:arm64': {'version': '1', 'status': 'ii '}}
        after = dict(before, **{'bsdutils:arm64': {'version': '1:2.41.6-0+erp1', 'status': 'ii '}})
        module.verify_state(before, after, self.expected)
        for changed in [dict(after, **{'unchanged:arm64': {'version': '2', 'status': 'ii '}}),
                        {'bsdutils:arm64': after['bsdutils:arm64']},
                        dict(after, **{'bsdutils:arm64': {'version': '1:2.41.6-0+erp1', 'status': 'iU '}})]:
            with self.assertRaises(ValueError): module.verify_state(before, changed, self.expected)


if __name__ == '__main__': unittest.main()
