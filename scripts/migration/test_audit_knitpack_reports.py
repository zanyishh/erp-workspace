"""Synthetic fixtures for report controls, source coverage, and original dates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_reports.py")


class ReportAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.reports = self.root / "source", self.root / "reports"
        self.source.mkdir()
        self.reports.mkdir()
        self.add(self.source, "companies.json", "masters/masters/listCompany", {"result": [{"id": "1"}, {"id": "2"}]})
        self.add(self.source, "years.json", "knitpack/masters/getFinYearSB", {"result": [{"value": "1", "name": "26-27"}]})
        self.add(self.source, "index.json", "knitpack/inward/getInwardListForProgChart", {"result": {"items": [{"id": "10"}, {"id": "11"}]}},
                 {"limit_from": 0, "limit_to": 100, "searchKeyword": "", "getParams": {
                     "companymas_id": "1", "type": "all", "partymas_id": "null"}})
        self.add(self.source, "full.json", "knitpack/inward/getInward/10", {"result": {
            "id": "10", "companymas_id": "1", "finyear": "1", "jobdate": "2026-11-14",
            "job_fabrics": [{"id": "20", "jobmas_id": "10", "dias": [
                {"id": "30", "jobfabric_id": "20", "programqty": "0.1", "prod_qty": "0.1", "dlvry_kgs": "0", "stock_kgs": "0.1"},
                {"id": "31", "jobfabric_id": "20", "programqty": "0.2", "prod_qty": "0.2", "dlvry_kgs": "0", "stock_kgs": "0.2"}]}]}})

    def add(self, folder, filename, route, response, filters=None):
        response["currentUserinfo"] = {"token": "PRIVATE-TOKEN"}
        raw = json.dumps(response).encode()
        (folder / filename).write_bytes(raw)
        with (folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": filename, "path": route, "filters": filters,
                                     "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}) + "\n")

    def programme(self, *, company="1", quantity="0.2", control="0.30000000000000004"):
        rows = [{"job_id": "10", "fabric_id": "20", "diaorsize": str(i), "order_qty": amount,
                 "prod_qty": amount, "dlvry_kgs": "0", "stock_kgs": amount, "blns_qty": "0",
                 "party_name": "PRIVATE-PARTY"} for i, amount in enumerate(("0.1", quantity), 1)]
        self.add(self.reports, "programme.json", "{URI}knitpack/getprint/getdata/knit_job_mas/programChart/{PASS}",
                 {"root": {"prgm_chart": rows, "from_date": "2026-04-01", "to_date": "2027-03-31",
                           "order_qty": control, "prod_qty": "0.3", "dlvry_kgs": "0", "stock_kgs": "0.3", "blns_qty": "0"}},
                 {"companymas_id": company, "from_date": "2026-04-01", "to_date": "2027-03-31", "type": "all", "stock_type": "all"})

    def audit(self, history_job=None):
        self.assertTrue(SCRIPT.exists(), "The selected-report audit must exist")
        spec = importlib.util.spec_from_file_location("report_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.audit(self.source, self.reports, history_job)
        text = json.dumps(result)
        self.assertNotIn("PRIVATE-TOKEN", text)
        self.assertNotIn("PRIVATE-PARTY", text)
        self.assertFalse(result["import_allowed"])
        self.assertEqual(result["report_archive_completeness"], "unknown")
        return result

    def test_decimal_control_difference_is_preserved_and_only_inferred_as_float_tail(self):
        self.programme()
        result = self.audit()
        company = result["programme_reports"][0]
        control = company["controls"]["order_qty"]
        self.assertEqual(control["status"], "different")
        self.assertEqual(control["row_sum"], "0.3")
        self.assertEqual(control["control_minus_row_sum"], "0.00000000000000004")
        self.assertEqual(control["control_decimal_scale"], 17)
        self.assertEqual(control["row_decimal_scale_max"], 1)
        self.assertEqual(control["interpretation"], "possible_floating_point_tail_inference_only")
        self.assertEqual(company["historical_index_without_programme_ids"], ["11"])
        self.assertEqual(company["archived_job_comparisons"], {"matched_jobs": 1, "passed": 4, "different": 0, "unknown": 0})

    def test_missing_quantity_never_turns_into_zero(self):
        self.programme(quantity=None)
        result = self.audit()
        company = result["programme_reports"][0]
        self.assertEqual(company["controls"]["order_qty"]["status"], "unknown")
        self.assertNotIn("row_sum", company["controls"]["order_qty"])
        self.assertEqual(company["archived_job_comparisons"]["unknown"], 3)

    def test_source_company_mapping_prevents_same_job_id_from_cross_company_match(self):
        self.programme(company="2")
        result = self.audit()
        company = result["programme_reports"][0]
        self.assertEqual(company["archived_job_comparisons"]["matched_jobs"], 0)
        self.assertEqual(company["programme_without_historical_index_ids"], ["10"])

    def test_original_dates_are_retained_and_compared_without_rendered_date_guessing(self):
        self.add(self.reports, "history.json", "{URI}knitpack/getprint/getdata/knit_job_mas/JobTransHistory/{PASS}", {"root": {
            "order_inward": [{"id": "10", "jobdate": "2026-11-14"}],
            "yarninward": [{"jobmas_id": "10", "grndate": "2026-11-14", "partydcdate": "2026-11-14"}],
            "fabricdc": [{"jobmas_id": "10", "dc_date": "2026-11-14"}],
            "production": [{"jobmas_id": "10", "date": "2026-11-13"}]}}, {"jobmas_id": "10"})
        result = self.audit("10")
        history = result["history_reports"][0]
        self.assertEqual(history["archived_job_date_agreement"], "passed")
        self.assertEqual(history["original_dates"]["order_inward.jobdate"], ["2026-11-14"])
        self.assertEqual(history["original_dates"]["production.date"], ["2026-11-13"])

    def test_changed_selected_file_is_excluded_and_unrelated_moving_files_are_not_trusted(self):
        self.programme()
        (self.reports / "programme.json").write_text("{}")
        (self.reports / "download-in-progress.json").write_text("{")
        result = self.audit()
        self.assertEqual(result["programme_reports"], [])
        self.assertEqual(result["selected_evidence_integrity"]["issues"], ["selected_file_hash_or_size_mismatch"])

    def test_fixed_manifest_capture_ignores_later_committed_files(self):
        self.programme()
        captured = (self.reports / "manifest.jsonl").read_bytes()
        self.add(self.reports, "later.json", "later/route", {"root": {}})
        spec = importlib.util.spec_from_file_location("report_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        issues = []
        digest, rows = module.selected_records(self.reports.resolve(), lambda e: True, issues, captured)
        self.assertEqual(digest, hashlib.sha256(captured).hexdigest())
        self.assertEqual([r[0]["file"] for r in rows], ["programme.json"])
        self.assertEqual(issues, [])

    def test_mislinked_archived_size_rows_cannot_prove_job_totals(self):
        self.programme()
        path = self.source / "full.json"
        document = json.loads(path.read_text())
        document["result"]["job_fabrics"][0]["dias"][0]["jobfabric_id"] = "999"
        raw = json.dumps(document).encode()
        path.write_bytes(raw)
        entries = [json.loads(line) for line in (self.source / "manifest.jsonl").read_text().splitlines()]
        for entry in entries:
            if entry["file"] == "full.json":
                entry.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        (self.source / "manifest.jsonl").write_text("\n".join(json.dumps(e) for e in entries) + "\n")
        programme = self.audit()["programme_reports"][0]
        self.assertEqual(programme["archived_job_comparisons"]["passed"], 0)
        self.assertEqual(programme["archived_job_comparisons"]["unknown"], 4)

    def test_sum_preserves_decimal_places_beyond_default_decimal_context(self):
        self.programme(quantity="0.00000000000000000000000000002", control="0.10000000000000000000000000002")
        control = self.audit()["programme_reports"][0]["controls"]["order_qty"]
        self.assertEqual(control["status"], "passed")
        self.assertEqual(control["row_sum"], "0.10000000000000000000000000002")

    def test_history_transaction_in_another_company_cannot_pass_identity(self):
        self.add(self.reports, "history.json", "{URI}knitpack/getprint/getdata/knit_job_mas/JobTransHistory/{PASS}", {"root": {
            "order_inward": [{"id": "10", "jobdate": "2026-11-14"}],
            "yarninward": [{"companymas_id": "2", "jobmas_id": "10", "grndate": "2026-11-14", "partydcdate": "2026-11-14"}]}}, {"jobmas_id": "10"})
        history = self.audit("10")["history_reports"][0]
        self.assertEqual(history["archived_job_date_agreement"], "unknown")
        self.assertGreater(history["identity_issues"], 0)


if __name__ == "__main__":
    unittest.main()
