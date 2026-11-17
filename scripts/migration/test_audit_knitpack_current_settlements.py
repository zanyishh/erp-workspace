"""Synthetic final-state reference conservation; no source calls or postings."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_current_settlements.py")


class CurrentSettlementTests(unittest.TestCase):
    def setUp(self):
        self.headers = {("1", "10", "0"): self.header("10", "credit"),
                        ("1", "11", "0"): self.header("11", "debit")}
        self.views = [{"source_key": ["1", "10", "0"], "rows": [self.row("11", "11", "0")]},
                      {"source_key": ["1", "11", "0"], "rows": [self.row("11", "10", "11")]}]

    def header(self, name, entry):
        return {"id": name, "companymas_id": "1", "sec_acc": "0", "party_id": "8", "entry_type": entry,
                "v_date": "2023-04-10", "v_no": "V" + name, "amt": "100", "adj_val": "100", "pend_amt": "0", "cancelled": "0"}

    def row(self, target, left, right):
        return {"id": target, "v_date": "2023-04-10", "v_no": "V" + target, "val": "100", "acc_id": left, "toaccid": right}

    def audit(self, verified=True):
        self.assertTrue(SCRIPT.exists(), "The current-state auditor must exist")
        spec = importlib.util.spec_from_file_location("current_settlements", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.analyse(self.headers, self.views, ui_contract_verified=verified)
        self.assertFalse(result["import_allowed"])
        return result

    def test_conserved_ui_edge_does_not_require_source_allocation_child_id_or_event_date(self):
        result = self.audit()
        self.assertEqual(result["counts"]["conserved_current_state_edges"], 1)
        self.assertEqual(result["counts"]["positive_self_summary_rows"], 1)
        self.assertEqual(result["edges"][0]["endpoint_evidence"], "same_amount_endpoint_witness_in_another_view")
        self.assertIsNone(result["edges"][0]["source_allocation_effective_date"])

    def test_self_summary_is_not_a_self_allocation(self):
        self.views = [{"source_key": ["1", "10", "0"], "rows": [self.row("10", "10", "0")]}, self.views[1]]
        result = self.audit()
        self.assertEqual(result["edges"], [])
        self.assertEqual(result["counts"].get("conserved_current_state_edges", 0), 0)

    def test_pending_header_difference_is_separate_from_conserved_current_state(self):
        self.headers[("1", "11", "0")]["pend_amt"] = "9"
        result = self.audit()
        self.assertEqual(result["counts"]["conserved_current_state_edges"], 1)
        self.assertEqual(result["counts"]["native_amount_adjusted_pending_different"], 1)

    def test_cross_party_target_and_same_entry_type_cannot_be_accepted(self):
        self.headers[("1", "11", "0")]["party_id"] = "9"
        self.assertEqual(self.audit()["edges"], [])
        self.headers[("1", "11", "0")]["party_id"] = "8"
        self.headers[("1", "11", "0")]["entry_type"] = "credit"
        self.assertEqual(self.audit()["edges"], [])

    def test_explicit_adjustment_row_scope_must_match_its_native_target(self):
        for field, value in (("companymas_id", "2"), ("sec_acc", "1"), ("party_id", "9")):
            with self.subTest(field=field):
                self.setUp()
                self.views[0]["rows"][0][field] = value
                self.assertEqual(self.audit()["edges"], [])

    def test_one_node_shortfall_blocks_its_entire_connected_component(self):
        self.headers[("1", "11", "0")]["adj_val"] = "90"
        result = self.audit()
        self.assertEqual(result["counts"].get("conserved_current_state_edges", 0), 0)
        self.assertEqual(result["components"][0]["status"], "unresolved")

    def test_reciprocal_views_are_one_current_pair_not_two_events(self):
        self.views[1]["rows"] = [self.row("10", "10", "11")]
        self.assertEqual(len(self.audit()["edges"]), 1)
        self.views[1]["rows"][0]["val"] = "90"
        self.assertEqual(self.audit()["counts"].get("conserved_current_state_edges", 0), 0)

    def test_duplicate_target_within_one_view_is_unresolved_even_when_values_equal(self):
        self.views[0]["rows"].append(copy.deepcopy(self.views[0]["rows"][0]))
        result = self.audit()
        self.assertEqual(result["counts"].get("conserved_current_state_edges", 0), 0)

    def test_missing_native_target_or_missing_date_is_not_a_zero_balance(self):
        self.views[0]["rows"][0]["id"] = "99"
        self.assertEqual(self.audit()["edges"], [])
        self.views[0]["rows"][0]["id"] = "11"
        self.views[0]["rows"][0]["v_date"] = None
        self.assertEqual(self.audit()["edges"], [])

    def test_overallocation_and_unreviewed_ui_contract_cannot_certify_state(self):
        self.assertEqual(self.audit(False)["counts"].get("conserved_current_state_edges", 0), 0)
        self.headers[("1", "11", "0")]["amt"] = "90"
        self.assertEqual(self.audit()["counts"].get("conserved_current_state_edges", 0), 0)

    def test_native_opening_identity_can_conserve_current_state_without_fabricated_date(self):
        opening = self.headers[("1", "11", "0")]
        opening.update(acc_type="opening-balance", v_date="0000-00-00")
        self.views = [self.views[0]]
        self.views[0]["rows"][0]["v_date"] = "0000-00-00"
        result = self.audit()
        self.assertEqual(result["counts"]["conserved_current_state_edges"], 1)
        node = next(row for row in result["node_controls"] if row["source_key"][1] == "11")
        self.assertEqual(node["original_date"], "0000-00-00")
        self.assertEqual(node["original_date_status"], "invalid_or_missing")

    def test_identical_recapture_is_evidence_not_a_second_reference_but_changes_stay_unresolved(self):
        self.views.append(copy.deepcopy(self.views[0]))
        result = self.audit()
        self.assertEqual(result["counts"]["conserved_current_state_edges"], 1)
        self.assertEqual(result["counts"]["identical_view_recaptures"], 1)
        self.views[-1]["rows"][0]["val"] = "90"
        self.assertEqual(self.audit()["counts"].get("conserved_current_state_edges", 0), 0)

    def test_false_opening_response_with_different_context_does_not_prove_requested_book_absence(self):
        spec = importlib.util.spec_from_file_location("current_settlements_scope", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            raw = json.dumps({"result": {"acc_type": "2", "d": False}}).encode()
            (folder / "opening.json").write_bytes(raw)
            (folder / "ui.js").write_text("unreviewed synthetic UI")
            manifest = json.dumps({"file": "opening.json", "path": "accv2/accounts/getopbal/1/8/0",
                "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}).encode()
            result = module.audit(folder, manifest, folder / "ui.js")
            self.assertEqual(result["native_opening_evidence"].get("explicit_no_record", 0), 0)
            self.assertEqual(result["native_opening_evidence"]["false_with_different_or_missing_context"], 1)
            self.assertEqual(result["native_header_keys"], 0)


if __name__ == "__main__":
    unittest.main()
