"""Synthetic candidate-basis diagnostics; arithmetic is never a causal finding."""
import unittest
from pathlib import Path
import subprocess
import sys
import tempfile

from trace_knitpack_physical_movements import candidate, movement_candidates


class MovementTraceTests(unittest.TestCase):
    def test_cli_cannot_overwrite_input_trace(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            trace = folder / "trace.json"
            trace.write_text("original")
            response = subprocess.run([sys.executable, str(Path(__file__).with_name("trace_knitpack_physical_movements.py")),
                str(folder / "reports"), str(trace), "--report", str(trace)], capture_output=True, text=True)
            self.assertEqual(response.returncode, 2)
            self.assertIn("outside", response.stderr)
            self.assertEqual(trace.read_text(), "original")

    def test_exact_matching_delta_does_not_prove_semantics(self):
        value = candidate(["0.1", "0.2"], "0.3", "0.7", "1.0")
        self.assertEqual(value["delta_equals_sum"]["status"], "passed")
        self.assertFalse(value["explanation_proved"])

    def test_missing_amount_is_unknown_not_zero(self):
        self.assertEqual(candidate([None], "0", "0", "0")["delta_equals_sum"]["status"], "unknown")

    def test_explicit_cancellation_groups_remain_raw_named_observations(self):
        rows = [{"net_kgs": "1", "cancelled": "0", "yarn_dc_id": "7"},
                {"net_kgs": "2", "cancelled": "1", "yarn_dc_id": "8"}]
        values = movement_candidates(rows, "yarnreturns", "kgs", "2", "3", "5")
        match = next(v for v in values if v.get("group") == {"cancelled": "1"})
        self.assertEqual(match["delta_equals_sum"]["status"], "passed")
        self.assertFalse(match["explanation_proved"])

    def test_missing_dataset_is_not_reported_as_empty(self):
        self.assertEqual(movement_candidates(None, "yarnreturns", "kgs", "1", "1", "2"), [])


if __name__ == "__main__":
    unittest.main()
