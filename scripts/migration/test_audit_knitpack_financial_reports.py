"""Synthetic financial report fixtures; no customer services or records."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_financial_reports.py")


class FinancialAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.reports = self.root / "source", self.root / "reports"
        self.source.mkdir()
        self.reports.mkdir()
        self.add(self.source, "companies.json", "masters/masters/listCompany", {"result": [{"id": str(i)} for i in range(1, 5)]})
        self.header = {"id": "999", "invoice_id": "10", "inv_id": "10", "companymas_id": "1", "finyear": "1",
                       "invoice_date": "2026-11-14", "invoice_type": "regular", "cancelled": "0", "party_id": "42",
                       "total_kgs": "0.3", "total_rolls_pcs": "2", "total_value": "10.00", "taxable_value": "10.00",
                       "sgst_value": "0.25", "cgst_value": "0.25", "igst_value": "0", "tcs_value": "0",
                       "invoice_value": "11", "r_invoice_value": "10.5", "party_name": "PRIVATE-PARTY"}

    def add(self, folder, name, route, response, filters=None):
        response["currentUserinfo"] = {"token": "PRIVATE-TOKEN"}
        raw = json.dumps(response).encode()
        (folder / name).write_bytes(raw)
        with (folder / "manifest.jsonl").open("a") as f:
            f.write(json.dumps({"file": name, "path": route, "filters": filters,
                                "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}) + "\n")

    def report(self, name, route, array, rows, company="1", extra=None):
        root = {"company_info": {"id": company}, array: rows, "fdate": "2023-04-01", "tdate": "2027-03-31"}
        root.update(extra or {})
        self.add(self.reports, name, "{URI}/getdata/x/" + route + "/{PASS}", {"root": root},
                 {"companymas_id": company, "acc_type": "sales", "sec_acc": "0", "from_date": "2023-04-01", "to_date": "2027-03-31"})

    def invoices(self, *, missing_value=False, wrong_company=False):
        self.report("header.json", "getInvoiceRegPrint", "invoicereg", [self.header])
        rows = [{**self.header, "id": "777", "kgs": "0.1", "rolls_pcs": "1", "value": "4.00", "cgst": "0.1", "sgst": "0.1", "igst": "0", "item_val": "4.2"},
                {**self.header, "id": "777", "kgs": "0.2", "rolls_pcs": "1", "value": None if missing_value else "6.00", "cgst": "0.15", "sgst": "0.15", "igst": "0", "item_val": "6.3"}]
        if wrong_company:
            rows[0]["companymas_id"] = "2"
        self.report("detail.json", "getInvoiceDetRegPrint", "invoicedetreg", rows,
                    extra={"cgst_value": "0.25000000000000004", "sgst_value": "0.25", "igst_value": "0", "invoice_value": "10.5"})

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "Financial report audit must exist")
        spec = importlib.util.spec_from_file_location("financial_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report = module.audit(self.source, self.reports)
        output = json.dumps(report)
        self.assertNotIn("PRIVATE-TOKEN", output)
        self.assertNotIn("PRIVATE-PARTY", output)
        self.assertFalse(report["import_allowed"])
        self.assertIn("voucher_header_coverage", report)
        return report

    def test_explicit_invoice_parent_ids_link_headers_and_preserve_exact_control_difference(self):
        self.invoices()
        report = self.audit()
        self.assertEqual(report["checks"]["header_fields"], {"passed": 10, "different": 0, "unknown": 0})
        self.assertEqual(report["checks"]["line_quantity_totals"]["passed"], 2)
        self.assertEqual(report["checks"]["detail_report_controls"]["different"], 1)
        finding = next(f for f in report["findings"] if f["check"] == "detail_report_controls")
        self.assertEqual(finding["control_minus_row_sum"], "0.00000000000000004")
        self.assertEqual(report["companies"]["1"]["header_detail_overlap_invoices"], 1)

    def test_missing_line_amount_is_unknown_not_zero(self):
        self.invoices(missing_value=True)
        self.assertEqual(self.audit()["checks"]["line_value_diagnostic"]["unknown"], 1)

    def test_wrong_company_row_excludes_entire_scope_from_total_checks(self):
        self.invoices(wrong_company=True)
        report = self.audit()
        self.assertEqual(report["checks"]["header_fields"]["passed"], 0)
        self.assertEqual(report["identity_issues"][0]["kind"], "row_company_mismatch")

    def test_voucher_ids_are_scoped_by_company_and_type_and_never_inferred_as_invoice_links(self):
        self.invoices()
        row = {"id": "10", "acc_type": "sales", "v_date": "2026-11-14", "amt": "11", "taxable_value": "10", "sgst_amt": "0.25", "cgst_amt": "0.25", "igst_amt": "0", "without_tax_value": "10", "tax_value": "0.5"}
        self.report("v1.json", "getVoucherRegister", "statement", [row])
        self.report("v2.json", "getVoucherRegister", "statement", [{**row, "amt": "11.00000000000000000001"}])
        self.report("v3.json", "getVoucherRegister", "statement", [row], company="2")
        report = self.audit()
        self.assertEqual(report["checks"]["voucher_export_overlap"]["different"], 1)
        self.assertEqual(report["voucher_invoice_linkage"], "unknown_no_explicit_foreign_key")
        self.assertEqual(report["companies"]["2"]["distinct_vouchers"], 1)

    def test_original_date_mismatch_is_kept_and_blocks_header_detail_comparison(self):
        self.report("header.json", "getInvoiceRegPrint", "invoicereg", [self.header])
        self.report("detail.json", "getInvoiceDetRegPrint", "invoicedetreg", [{**self.header, "invoice_date": "2026-11-13"}])
        report = self.audit()
        self.assertEqual(report["checks"]["header_fields"]["passed"], 0)
        self.assertTrue(any(f["kind"] == "invoice_date_or_identity_conflict" for f in report["identity_issues"]))

    def test_hash_mismatch_excludes_committed_file(self):
        self.invoices()
        (self.reports / "detail.json").write_text("{}")
        report = self.audit()
        self.assertEqual(report["checks"]["header_fields"]["passed"], 0)
        self.assertIn("selected_file_hash_or_size_mismatch", report["selected_evidence_integrity"]["issues"])

    def test_native_party_headers_cover_registers_and_match_print_fields_without_exposing_values(self):
        voucher = {"id": "10", "companymas_id": "1", "party_id": "42", "sec_acc": "0", "v_date": "2026-11-14",
                   "cancelled": "0", "updated_time": "2026-11-14 10:00:00", "narration": "PRIVATE-PARTY"}
        self.add(self.reports, "party.json", "x/getPartyLedgerPrint/x", {"root": [
            {"company_info": {"id": "1"}, "party_info": {"id": "42"}, "ledg_list": [voucher]}]}, {"companymas_id": "1"})
        self.add(self.reports, "print.json", "x/getVoucherPrint/x", {"root": {
            "company_info": {"id": "1"}, "voucher": voucher}}, {"id": "10"})
        self.report("register.json", "getVoucherRegister", "statement", [{"id": "10", "acc_type": "sales", "v_date": "2026-11-14"}])
        coverage = self.audit()["voucher_header_coverage"]
        self.assertEqual(coverage["counts"]["all_header_fields_present_and_exact"], 1)
        self.assertEqual(coverage["register_ids_without_party_header"], [])
        self.assertEqual(coverage["register_keys_missing_observed_header_fields"], [])

    def test_missing_party_header_and_changed_original_date_are_not_declared_covered(self):
        voucher = {"id": "10", "companymas_id": "1", "party_id": "42", "sec_acc": "0", "v_date": "2026-11-14"}
        self.add(self.reports, "party.json", "x/getPartyLedgerPrint/x", {"root": [
            {"company_info": {"id": "1"}, "party_info": {"id": "42"}, "ledg_list": [voucher]}]}, {"companymas_id": "1"})
        self.add(self.reports, "print.json", "x/getVoucherPrint/x", {"root": {
            "company_info": {"id": "1"}, "voucher": {**voucher, "v_date": "2026-11-13"}}}, {"id": "10"})
        self.report("register.json", "getVoucherRegister", "statement", [{"id": "11", "acc_type": "sales", "v_date": "2026-11-14"}])
        coverage = self.audit()["voucher_header_coverage"]
        self.assertEqual(coverage["register_ids_without_party_header"], [["1", "11", "0"]])
        self.assertEqual(coverage["mismatched_header_field_counts"]["v_date"], 1)


if __name__ == "__main__":
    unittest.main()
