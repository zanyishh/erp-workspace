import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('runtime_pins', Path(__file__).with_name('runtime-python-pins.py'))
runtime_pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime_pins)


class RuntimeDependencyContractTests(unittest.TestCase):
    def test_pinned_source_changes_only_reviewed_dependencies_and_is_idempotent(self):
        root = Path(__file__).resolve().parents[3]
        original = (root / 'upstream/frappe/pyproject.toml').read_text()
        patched = runtime_pins.patched_manifest(original)
        self.assertEqual(patched.count('"GitPython==3.2.1"'), 1)
        self.assertEqual(patched.count('"pypdf==6.21.4"'), 1)
        restored = patched
        for old, new in runtime_pins.REPLACEMENTS.items():
            restored = restored.replace(new, old)
        self.assertEqual(restored, original)
        self.assertEqual(runtime_pins.patched_manifest(patched), patched)

    def test_changed_or_duplicated_upstream_contract_fails_closed(self):
        for source in ['"GitPython~=3.2.0"\n"pypdf==6.19.0"',
                       '"GitPython~=3.1.45"\n"GitPython~=3.1.45"\n"pypdf==6.19.0"']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                runtime_pins.patched_manifest(source)


if __name__ == '__main__':
    unittest.main()
