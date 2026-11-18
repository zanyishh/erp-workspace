"""The N7 finish-only path must not adopt a different build or code delta."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).parent
spec=importlib.util.spec_from_file_location('finish',HERE/'tool-os-finish-krb5.py')
finish=importlib.util.module_from_spec(spec);spec.loader.exec_module(finish)

class Guards(unittest.TestCase):
    def test_only_the_gss_assertion_change_is_allowed(self):
        old='def smoke():\n    assert ctypes.string_at(displayed.value, displayed.length) == text and kind.value == user_name.value\n\ndef package():\n    return 1\n'
        new='def require_name_roundtrip(a,b,c,d):\n    pass\n\ndef smoke():\n    require_name_roundtrip(text, ctypes.string_at(displayed.value, displayed.length), user_name, kind)\n\ndef package():\n    return 1\n'
        finish.verify_assertion_only_change(old,new)
        for changed in (new.replace('return 1','return 2'),new+'\ndef extra():\n    pass\n',new.replace('user_name, kind','kind, user_name')):
            with self.subTest(changed=changed),self.assertRaises(ValueError):
                finish.verify_assertion_only_change(old,changed)

    def test_actual_checkpoint_and_changed_file_rejection(self):
        checkpoint=Path('/Volumes/ERPQuality/erp-quality/os-krb5-build-20261116-7')
        finish.verify_checkpoint(checkpoint)
        original=finish.digest
        for name in ['receipt.json','upstream-tests.log','keyring-test-session.json','abi-comparison.json','libgssapi-krb5-2_1.22.3-0+erp1_arm64.deb']:
            def altered(path):return '0'*64 if path.name==name else original(path)
            with self.subTest(file=name),patch.object(finish,'digest',side_effect=altered),self.assertRaises(ValueError):
                finish.verify_checkpoint(checkpoint)

if __name__=='__main__':unittest.main()
