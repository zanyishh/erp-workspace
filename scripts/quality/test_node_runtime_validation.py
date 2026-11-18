"""Ensure the isolated Node probe and final image gate cannot claim unrun checks."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'
SPEC = importlib.util.spec_from_file_location('node_runtime_validation', HERE/'validate-node-runtime.py')
probe = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(probe)


class ValidationGuards(unittest.TestCase):
    def test_plan_never_starts_or_inspects_a_container(self):
        lock = {'replacement_files': {'bin/node': {'bytes': 10}}}
        with patch.object(probe, 'preflight', return_value=({}, {}, lock)), \
                patch.object(probe, 'command', side_effect=AssertionError('Docker must not run')), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            probe.validate(Path('/unused'), Path('/unused'), execute=False)
        self.assertEqual(json.loads(output.getvalue())['status'], 'inputs-verified-no-container-created')

    def test_image_requires_completed_actual_node_validation(self):
        with patch.object(probe.builder, 'check_node_runtime_inputs'), \
                self.assertRaisesRegex(ValueError, 'must finish first'):
            probe.builder.check_node_runtime_gates({}, {})

    def test_success_word_without_matching_source_and_exit_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'receipt.json'
            path.write_text(json.dumps({'status': 'installed-and-ordinary-tests-passed-candidate-image-validation-pending',
                                        'exit_code': 0, 'base_image': 'unexpected'}))
            with patch.object(probe.builder, 'check_node_runtime_inputs'), \
                    self.assertRaisesRegex(ValueError, 'does not match current'):
                probe.builder.check_node_runtime_gates({}, {'evidence/node-runtime/validation/receipt.json': path})


if __name__ == '__main__': unittest.main()
