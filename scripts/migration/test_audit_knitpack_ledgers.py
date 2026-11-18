"""Synthetic ledger controls only; no customer files or network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_ledgers.py")


class LedgerAuditTests(unittest.TestCase):
    def test_third_book_annual_controls_and_carry_forward_are_included_once(self):
        from audit_knitpack_ledgers import audit
        self.ledger(filename="c1-general-ledgers-book2-fy2023.json", book="2")
        self.ledger(filename="c1-general-ledgers-book2-fy2024.json", book="2",
                    start="2024-04-01", end="2025-03-31", opening="14", closing="16")
        report = audit(self.source, self.reports, annual_only=True)
        self.assertEqual(len(report["partitions"]), 2)
        self.assertTrue(all(p["requested_book"] == "2" and p["balance_equation"]["status"] == "passed" for p in report["partitions"]))
        self.assertEqual(len(report["carry_forward"]), 1)
        self.assertEqual(report["carry_forward"][0]["comparison"]["status"], "passed")

    def test_designated_final_file_retains_annual_scope_without_renaming_original_bytes(self):
        from audit_knitpack_ledgers import audit
        self.ledger(filename="final-control-ledger.json")
        entry = json.loads((self.reports / "manifest.jsonl").read_text())
        entry["audit_original_file"] = "c1-general-ledgers-book0-fy2023.json"
        captured = (json.dumps(entry) + "\n").encode()
        report = audit(self.source, self.reports, annual_only=True, report_manifest=captured)
        self.assertEqual(len(report["partitions"]), 1)
        self.assertTrue(report["partitions"][0]["path"].endswith("final-control-ledger.json"))

    def test_whole_unit_projection_keeps_row_rounding_distinct_from_total_rounding(self):
        from audit_knitpack_ledgers import general_projection_diagnostic
        root = {"ledger_info": {"entry_type": "debit"}, "ledg_list": [
            {"total": "0.5", "debit": "0", "credit": "0"}, {"total": "0.5", "debit": "0", "credit": "0"}],
            "opbal": {"debit": "0", "credit": "0"}, "clbal": {"debit": "0", "credit": "0"},
            "cdtotal": {"dtotal": "1", "ctotal": "0"}}
        value = general_projection_diagnostic(root)
        self.assertEqual(value["row_projection_checks"]["passed"], 4)
        self.assertEqual(value["control_comparisons"]["debit"]["cdtotal_vs_exact_amount_sum"]["status"], "passed")
        self.assertEqual(value["control_comparisons"]["debit"]["cdtotal_vs_sum_of_rounded_rows"]["status"], "different")
        self.assertFalse(value["posting_rule_proved"])
        root["opbal"]["debit"] = "1"
        self.assertEqual(general_projection_diagnostic(root)["control_comparisons"]["credit"]["cdtotal_vs_net_opening_plus_exact_sum"]["status"], "passed")

    def test_missing_native_total_does_not_become_zero_in_projection(self):
        from audit_knitpack_ledgers import general_projection_diagnostic
        value = general_projection_diagnostic({"ledger_info": {"entry_type": "debit"}, "ledg_list": [{"debit": "0", "credit": "0"}]})
        self.assertEqual(value["row_projection_checks"]["unknown"], 2)
        self.assertEqual(value["control_comparisons"]["debit"]["cdtotal_vs_exact_amount_sum"]["status"], "unknown")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.reports = self.root / "source", self.root / "reports"
        self.source.mkdir()
        self.reports.mkdir()
        self.add(self.source, "companies.json", "masters/masters/listCompany", {"result": [{"id": "1"}, {"id": "2"}]})

    def add(self, folder, name, route, payload, filters=None):
        payload["currentUserinfo"] = {"token": "PRIVATE-TOKEN"}
        data = json.dumps(payload).encode()
        (folder / name).write_bytes(data)
        with (folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": name, "path": route, "filters": filters,
                                    "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}) + "\n")

    def ledger(self, filename="ledger.json", *, book="0", start="2023-04-01", end="2024-03-31", opening="10", closing="12", debit="5", credit="1", bad_company=False, bad_period=False, control_debit=""):
        root = {"ledger_info": {"id": "1", "ledger_name": "PRIVATE-LEDGER"}, "company_info": {"id": "1"},
                "fdate": "2020-01-01" if bad_period else start, "tdate": end,
                "opbal": {"ledger_id": "1", "debit": opening, "credit": "2"},
                "clbal": {"ledger_id": "1", "debit": closing, "credit": "0"},
                "cdtotal": {"ledger_id": "1", "dtotal": debit if control_debit == "" else control_debit, "ctotal": credit},
                "closing_amount": closing, "closing_type": "Debit", "ledg_list": [
                    {"ledger_id": "1", "companymas_id": "2" if bad_company else "1", "v_id": "9", "v_date": start,
                     "debit": debit, "credit": credit, "auto_narration": "PRIVATE-PARTY"}]}
        self.add(self.reports, filename, "{URI}/getdata/x/accountLedgerPrint/{PASS}", {"root": [root]},
                 {"companymas_id": "1", "ledger_id": "", "sec_acc": book, "from_date": start, "to_date": end})

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "Ledger audit must exist")
        spec = importlib.util.spec_from_file_location("ledger_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report = module.audit(self.source, self.reports)
        self.assertFalse(report["import_allowed"])
        for secret in ("PRIVATE-TOKEN", "PRIVATE-LEDGER", "PRIVATE-PARTY"):
            self.assertNotIn(secret, json.dumps(report))
        return report

    def test_opening_plus_signed_movements_matches_closing_exactly(self):
        self.ledger()
        report = self.audit()
        self.assertEqual(len(report["partitions"]), 1)
        partition = report["partitions"][0]
        self.assertEqual(partition["balance_equation"]["status"], "passed")
        self.assertEqual(partition["opening_net"], "8")
        self.assertEqual(partition["movement_net"], "4")
        self.assertEqual(partition["closing_net"], "12")
        self.assertEqual(partition["returned_book_identity"], "unknown")

    def test_missing_opening_is_unknown_never_zero(self):
        self.ledger(opening=None)
        self.assertEqual(self.audit()["partitions"][0]["balance_equation"]["status"], "unknown")

    def test_exact_small_delta_is_not_rounded_away(self):
        self.ledger(closing="12.00000000000000000001")
        comparison = self.audit()["partitions"][0]["balance_equation"]
        self.assertEqual(comparison["status"], "different")
        self.assertEqual(comparison["control_minus_row_sum"], "0.00000000000000000001")

    def test_adjacent_period_carry_forward_uses_original_controls(self):
        self.ledger()
        self.ledger("next.json", start="2024-04-01", end="2025-03-31", opening="14", closing="16")
        continuity = self.audit()["carry_forward"]
        self.assertEqual(len(continuity), 1)
        self.assertEqual(continuity[0]["comparison"]["status"], "passed")

    def test_identical_book_responses_are_flagged_without_combining_entries(self):
        self.ledger()
        self.ledger("book1.json", book="1")
        report = self.audit()
        self.assertEqual(len(report["partitions"]), 2)
        self.assertEqual(len(report["book_ambiguities"]), 1)
        self.assertTrue(report["book_ambiguities"][0]["returned_ledger_objects_identical"])
        self.assertTrue(all(p["returned_book_identity"] == "unknown" for p in report["partitions"]))

    def test_wrong_company_or_period_blocks_arithmetic(self):
        self.ledger(bad_company=True)
        self.ledger("bad-period.json", bad_period=True)
        report = self.audit()
        self.assertTrue(all(p["balance_equation"]["status"] == "unknown" for p in report["partitions"]))
        self.assertEqual(len(report["identity_issues"]), 2)

    def test_hash_mismatch_is_excluded(self):
        self.ledger()
        (self.reports / "ledger.json").write_text("{}")
        report = self.audit()
        self.assertEqual(report["partitions"], [])
        self.assertIn("selected_file_hash_or_size_mismatch", report["selected_evidence_integrity"]["issues"])

    def test_party_native_identity_book_and_query_coverage(self):
        root = {"party_info": {"id": "1"}, "party_id": "1", "company_info": {"id": "1"},
                "fdate": "2023-04-01", "tdate": "2024-03-31", "sec_accF": "1",
                "opbal": {"party_id": "1", "debit": "10", "credit": "2"},
                "clbal": {"party_id": "1", "debit": "12", "credit": "0"},
                "cdtotal": {"party_id": "1", "dtotal": "0", "ctotal": "0"},
                "ledg_list": [{"id": "9", "party_id": "1", "companymas_id": "1", "sec_acc": "1",
                               "v_date": "2023-04-01", "debit": "5", "credit": "1"}]}
        self.add(self.reports, "party.json", "{URI}/getdata/x/getPartyLedgerPrint/{PASS}", {"root": [root]},
                 {"companymas_id": "1", "party_id": "1,2", "sec_acc": "1", "from_date": "2023-04-01", "to_date": "2024-03-31"})
        report = self.audit()
        self.assertEqual(len(report["partitions"]), 1)
        partition = report["partitions"][0]
        self.assertEqual(partition["kind"], "party")
        self.assertEqual(partition["balance_equation"]["status"], "passed")
        self.assertEqual(partition["returned_book_identity"], "passed")
        self.assertEqual(partition["balance_control_book_identity"], "unknown")
        self.assertEqual(report["scope_coverage"][0]["requested_ids_without_returned_partition"], ["2"])

    def test_voucher_native_book_is_corroborated_without_reassigning_balance_controls(self):
        self.ledger()
        self.add(self.reports, "voucher.json", "{URI}/getdata/x/getVoucherPrint/{PASS}", {"root": {
            "voucher": {"id": "9", "companymas_id": "1", "sec_acc": "1", "v_date": "2023-04-01"},
            "company_info": {"id": "1"}}}, {"id": "9"})
        partition = self.audit()["partitions"][0]
        self.assertEqual(partition["balance_equation"]["status"], "passed")
        self.assertEqual(partition["returned_book_identity"], "different")
        self.assertEqual(partition["balance_control_book_identity"], "unknown")
        self.assertEqual(partition["movements_by_proven_actual_book"]["1"]["rows"], 1)
        self.assertEqual(partition["movements_by_proven_actual_book"]["1"]["net"], "4")

    def test_null_cdtotal_does_not_pass_as_zero(self):
        self.ledger(debit=None)
        partition = self.audit()["partitions"][0]
        self.assertEqual(partition["cdtotal_vs_movements_diagnostic"]["dtotal"]["status"], "unknown")

    def test_control_net_opening_pattern_is_diagnostic_and_keeps_original_delta(self):
        self.ledger(control_debit="13")
        control = self.audit()["partitions"][0]["cdtotal_vs_movements_diagnostic"]["dtotal"]
        self.assertEqual(control["status"], "different")
        self.assertEqual(control["control_minus_row_sum"], "8")
        self.assertEqual(control["pattern"].get("control_equals_net_opening_column_plus_movements"), "passed")

    def test_cash_numeric_id_collision_does_not_establish_native_voucher_namespace(self):
        self.ledger()
        root = json.loads((self.reports / "ledger.json").read_text())["root"][0]
        row = root["ledg_list"][0]
        row["voucher_id"] = row.pop("v_id")
        row["cash_ledger_id"] = row.pop("ledger_id")
        row["date"] = row.pop("v_date")
        self.add(self.reports, "cash.json", "x/getCashLedgerPrint/x", {"root": [root]},
                 {"companymas_id": "1", "ledger_id": "1", "sec_acc": "0", "from_date": "2023-04-01", "to_date": "2024-03-31"})
        self.add(self.reports, "voucher.json", "x/getVoucherPrint/x", {"root": {
            "voucher": {"id": "9", "companymas_id": "1", "sec_acc": "1", "v_date": "2023-04-01"},
            "company_info": {"id": "1"}}}, {"id": "9"})
        cash = next(p for p in self.audit()["partitions"] if p["kind"] == "cash")
        self.assertEqual(cash["returned_book_identity"], "unknown")
        self.assertEqual(cash["movements_by_proven_actual_book"], {})

    def test_identical_cash_company_responses_remain_unassigned_even_with_header_candidate(self):
        self.ledger()
        root = json.loads((self.reports / "ledger.json").read_text())["root"][0]
        row = root["ledg_list"][0]
        row["voucher_id"] = row.pop("v_id")
        row["cash_ledger_id"] = row.pop("ledger_id")
        row["date"] = row.pop("v_date")
        row.pop("companymas_id")
        row["v_no"] = "7"
        for company in ("1", "2"):
            root["company_info"]["id"] = company
            self.add(self.reports, f"cash-{company}.json", "x/getCashLedgerPrint/x", {"root": [root]},
                     {"companymas_id": company, "ledger_id": "1", "sec_acc": "0", "from_date": "2023-04-01", "to_date": "2024-03-31"})
        self.add(self.reports, "voucher.json", "x/getVoucherPrint/x", {"root": {
            "voucher": {"id": "9", "companymas_id": "1", "sec_acc": "1", "v_date": "2023-04-01", "v_no": "7", "cash_ledger": "1", "amt": "4"},
            "company_info": {"id": "1"}}}, {"id": "9"})
        report = self.audit()
        self.assertEqual(len(report.get("cash_cross_company_ambiguities", [])), 1)
        self.assertTrue(report["cash_cross_company_ambiguities"][0]["returned_accounting_data_identical"])
        self.assertEqual(report["cash_header_correspondence"]["candidate_company_differs_from_requested"], 1)
        for partition in report["partitions"]:
            if partition["kind"] == "cash":
                self.assertEqual(partition["company_attribution"], "unknown_cash_report_scope")
                self.assertFalse(partition["source_identity_and_period_valid"])
                self.assertEqual(partition["balance_equation"]["status"], "passed")


if __name__ == "__main__":
    unittest.main()
