"""Synthetic native tax-child and allocation-evidence checks; no posting."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_voucher_children.py")


class VoucherChildrenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.source = self.header("10", "credit", "100")
        self.target = self.header("11", "debit", "40")
        self.second = self.header("12", "debit", "60")
        self.add("native", "native/headers", {"root": {"ledg_list": [self.source, self.target, self.second]}})

    def header(self, name, entry, amount, **extra):
        return {"id": name, "companymas_id": "1", "sec_acc": "0", "party_id": "8", "entry_type": entry,
                "v_date": "2023-04-10", "finyear": "1", "amt": amount, "adj_val": amount, "pend_amt": "0",
                "taxable_value": "0", "cgst_value": "0", "sgst_value": "0", "igst_value": "0", "cancelled": "0", **extra}

    def add(self, name, route, payload, filters=None):
        raw = json.dumps({**payload, "currentUserinfo": {"token": "PRIVATE-TOKEN"}}).encode()
        (self.folder / (name + ".json")).write_bytes(raw)
        with (self.folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": name + ".json", "path": route, "filters": filters,
                                     "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}) + "\n")

    def full(self, tax_rows):
        self.add("full", "accv2/accounts/getvoucher/10", {"result": {**self.source, "tax_list": tax_rows, "debit_advice_list": [], "removed_tax_list": []}},
                 {"voucher_id": "10", "companymas_id": "1", "sec_acc": "0"})

    def allocation(self, rows, returned_book="0"):
        self.add("allocation", "accv2/accounts/getAdjInfowithTaxType/1/8/credit/0/10", {"result": {"adj_list": rows, "acc_type": returned_book}},
                 {"voucher_id": "10", "companymas_id": "1", "sec_acc": "0"})

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "The native-child evidence auditor must exist")
        spec = importlib.util.spec_from_file_location("voucher_children", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.audit(self.folder)
        self.assertFalse(result["import_allowed"])
        self.assertNotIn("PRIVATE-TOKEN", json.dumps(result))
        self.assertEqual(result["proven_persisted_allocation_edges"], 0)
        return result

    def test_native_tax_ids_and_parent_links_survive_even_when_saved_header_is_zero(self):
        self.full([{"id": "101", "voucher_id": "10", "taxable_value": "100", "cgst_value": "9", "sgst_value": "9", "igst_value": "0",
                    "created_time": "2023-04-10 12:00:00", "updated_time": "2023-04-11 12:00:00"}])
        result = self.audit()
        full = result["full_vouchers"][0]
        self.assertEqual(full["valid_native_tax_children"], 1)
        self.assertEqual(full["tax_controls"]["taxable_value"]["status"], "different")
        self.assertEqual(full["tax_controls"]["taxable_value"]["source_control"], "0")
        self.assertFalse(full["tax_comparisons_are_business_gate_controls"])
        self.assertEqual(full["tax_children"][0]["source_created_time"], "2023-04-10 12:00:00")

    def test_positive_amounts_do_not_turn_unresolved_endpoints_into_persisted_edges(self):
        self.allocation([{"id": "11", "v_date": "2023-04-10", "acc_id": "10", "toaccid": "11", "entry_type": "credit", "toentrytype": "debit", "val": "40"},
                         {"id": "12", "v_date": "2023-04-10", "acc_id": "12", "toaccid": "0", "entry_type": "debit", "toentrytype": "credit", "val": "60"}])
        result = self.audit()
        allocation = result["allocation_responses"][0]
        self.assertEqual(allocation["row_counts"]["positive_explicit_endpoint_candidates"], 1)
        self.assertEqual(allocation["row_counts"]["positive_unresolved_endpoint_rows"], 1)
        self.assertEqual(allocation["diagnostics"]["observed_val_sum_vs_saved_adj_val"]["status"], "passed")
        self.assertEqual(allocation["row_id_semantics"], "target_voucher_candidate_id; native allocation ID unproved")
        self.assertEqual(allocation["allocation_effective_dates"], "not_supplied")

    def test_future_zero_candidates_are_not_historical_allocations(self):
        future = self.header("13", "debit", "10", v_date="2024-01-01")
        self.add("future", "native/future", {"root": {"voucher": future}})
        self.allocation([{"id": "13", "v_date": "2024-01-01", "acc_id": "13", "toaccid": "0", "val": "0"}])
        row = self.audit()["allocation_responses"][0]
        self.assertEqual(row["row_counts"]["zero_value_rows"], 1)
        self.assertEqual(row["row_counts"]["zero_value_future_target_rows"], 1)

    def test_duplicate_or_wrong_parent_tax_ids_withhold_sum_controls(self):
        self.full([{"id": "101", "voucher_id": "11"}, {"id": "101", "voucher_id": "10"}])
        full = self.audit()["full_vouchers"][0]
        self.assertGreater(full["tax_child_identity_issues"], 0)
        self.assertEqual(full["tax_controls"], {})

    def test_cross_company_target_is_not_resolved_by_matching_numeric_id(self):
        self.add("foreign", "native/foreign", {"root": {"voucher": self.header("50", "debit", "100", companymas_id="2")}})
        self.allocation([{"id": "50", "v_date": "2023-04-10", "acc_id": "10", "toaccid": "50", "val": "100"}])
        row = self.audit()["allocation_responses"][0]
        self.assertEqual(row["row_counts"]["target_identity_unresolved_rows"], 1)
        self.assertEqual(row["row_counts"]["positive_explicit_endpoint_candidates"], 0)

    def test_missing_allocation_amount_stays_unknown(self):
        self.allocation([{"id": "11", "v_date": "2023-04-10", "val": None}])
        row = self.audit()["allocation_responses"][0]
        self.assertEqual(row["diagnostics"]["observed_val_sum_vs_saved_adj_val"]["status"], "unknown")

    def test_absent_target_dates_cannot_be_corroborated_by_none_equal_none(self):
        missing = self.header("14", "debit", "100", v_date=None)
        self.add("undated", "native/undated", {"root": {"voucher": missing}})
        self.allocation([{"id": "14", "v_date": None, "acc_id": "10", "toaccid": "14", "entry_type": "credit", "toentrytype": "debit", "val": "100"}])
        row = self.audit()["allocation_responses"][0]
        self.assertEqual(row["row_counts"]["target_identity_unresolved_rows"], 1)
        self.assertEqual(row["row_counts"]["positive_explicit_endpoint_candidates"], 0)

    def test_repeat_full_responses_do_not_inflate_unique_native_copy_coverage(self):
        self.full([])
        self.add("full_again", "accv2/accounts/getvoucher/10", {"result": {**self.source, "tax_list": []}})
        result = self.audit()
        self.assertEqual(result.get("coverage", {}).get("distinct_full_voucher_keys"), 1)
        self.assertEqual(result["coverage"]["native_header_keys_without_full_copy"], 2)

    def test_allocation_scope_indicator_must_match_requested_native_book(self):
        self.allocation([{"id": "11", "v_date": "2023-04-10", "val": "40"}], returned_book="1")
        response = self.audit()["allocation_responses"][0]
        self.assertEqual(response["status"], "current_header_identity_or_response_unresolved")

    def test_missing_allocation_scope_indicator_is_unresolved(self):
        self.allocation([], returned_book=None)
        response = self.audit()["allocation_responses"][0]
        self.assertEqual(response["status"], "current_header_identity_or_response_unresolved")


if __name__ == "__main__":
    unittest.main()
