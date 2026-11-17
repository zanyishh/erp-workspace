"""Synthetic offline fixtures only; no customer files or services are accessed."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("reconcile_knitpack_balances.py")


class BalanceGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.entries = []
        self.add("companies.json", "masters/masters/listCompany",
                 [{"id": str(i), "name": "PRIVATE-COMPANY"} for i in range(1, 5)])
        self.add("years.json", "knitpack/masters/getFinYearSB",
                 [{"value": str(i), "name": f"{22+i}-{23+i}"} for i in range(1, 5)])

    def add(self, filename, route, result, filters=None):
        raw = json.dumps({"result": result, "isLogin": True,
                          "rc_session": "SYNTHETIC-SECRET", "mode": "development"}).encode()
        (self.source / filename).write_bytes(raw)
        self.entries.append({"file": filename, "path": route, "filters": filters,
                             "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})

    def full(self, filename="job.json", *, company="1", quantity="0.300", date="2023-08-01"):
        self.add(filename, "knitpack/inward/getInward/10", {
            "id": "10", "companymas_id": company, "finyear": "1", "jobdate": date,
            "partymas_id": "PRIVATE-PARTY", "job_fabrics": [{
                "id": "20", "jobmas_id": "10", "dias": [{
                    "id": "30", "jobfabric_id": "20", "programqty": quantity,
                    "stock_kgs": "12.00000000000000000001"}]}]})

    def status(self, *, company="1", quantity="0.3", date="2023-08-01", duplicate=False):
        row = {"companymas_id": company, "jobmasid": "10", "jobdfabricid": "20", "jobdiaid": "30",
               "jobmas_id": "10", "jobfabric_id": "20", "finyear": "1", "jobdate": date,
               "programqty": quantity, "stock_kgs": "12.00000000000000000001", "partyname": "PRIVATE-PARTY"}
        self.add("status.json", "knitpack/reports/getJobOrderStatus", [row, row] if duplicate else [row],
                 {"companymas_id": company})

    def run_gate(self):
        (self.source / "manifest.jsonl").write_text("\n".join(json.dumps(e) for e in self.entries) + "\n")
        before = {p.name: p.read_bytes() for p in self.source.iterdir()}
        destination = self.root / "private" / "balances.json"
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.source), "--report", str(destination)],
                                capture_output=True, text=True)
        self.assertTrue(destination.exists(), "The balance gate must produce a private report")
        report = json.loads(destination.read_text())
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.source.iterdir()})
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        self.assertEqual(destination.with_suffix(".md").stat().st_mode & 0o777, 0o600)
        combined = result.stdout + result.stderr + destination.read_text() + destination.with_suffix(".md").read_text()
        for value in ("SYNTHETIC-SECRET", "PRIVATE-PARTY", "PRIVATE-COMPANY"):
            self.assertNotIn(value, combined)
        self.assertFalse(report["import_allowed"])
        self.assertEqual(result.returncode, 2)
        return report

    def test_decimal_equality_corroborates_overlap_without_claiming_balance_reconciliation(self):
        self.full()
        self.status()
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["numeric_checks"], {"passed": 2, "mismatched": 0, "unknown": 24})
        self.assertEqual(report["cross_export"]["matched_distinct_size_records"], 1)
        self.assertEqual(len(report["company_fiscal_year_coverage"]), 16)
        for cell in report["company_fiscal_year_coverage"]:
            self.assertTrue(all(value == "unknown" for value in cell["balances"].values()))

    def test_missing_and_invalid_numeric_fields_never_become_zero(self):
        for quantity in (None, "", "NaN", "Infinity", True):
            with self.subTest(quantity=quantity):
                self.full(quantity=quantity)
                self.status(quantity="0")
                report = self.run_gate()
                self.assertEqual(report["cross_export"]["numeric_checks"]["passed"], 1)
                self.assertEqual(report["cross_export"]["numeric_checks"]["unknown"], 25)
                self.assertEqual(report["cross_export"]["numeric_checks"]["mismatched"], 0)
                self.entries = self.entries[:2]

    def test_exact_difference_is_detected_without_binary_float_rounding(self):
        self.full(quantity="0.30000000000000000001")
        self.status(quantity="0.30000000000000000002")
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["numeric_checks"]["mismatched"], 1)
        self.assertEqual(report["cross_export"]["findings"][0]["fields"], ["programqty"])

    def test_source_company_is_part_of_identity_and_empty_company_is_not_zero(self):
        self.full(company="1")
        self.status(company="2")
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["matched_distinct_size_records"], 0)
        self.assertEqual(report["cross_export"]["full_without_status"], 1)
        self.assertEqual(report["cross_export"]["status_without_full"], 1)
        self.assertEqual(report["cross_export"]["numeric_checks"]["passed"], 0)

    def test_repeated_status_rows_do_not_double_count_and_conflicting_full_copies_are_unknown(self):
        self.full()
        self.status(duplicate=True)
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["matched_distinct_size_records"], 1)
        self.assertEqual(report["cross_export"]["numeric_checks"]["passed"], 2)
        self.full("conflict.json", quantity="999")
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["ambiguous_size_records"], 1)
        self.assertEqual(report["cross_export"]["numeric_checks"]["passed"], 0)

    def test_original_date_disagreement_is_reported_without_correction(self):
        self.full(date="2023-08-01")
        self.status(date="2023-08-02")
        report = self.run_gate()
        self.assertEqual(report["cross_export"]["date_or_fiscal_year_disagreements"], 1)
        self.assertEqual(report["cross_export"]["numeric_checks"]["passed"], 0)

    def test_integrity_failure_prevents_numeric_checks(self):
        self.full()
        self.status()
        (self.source / "job.json").write_text("{}")
        report = self.run_gate()
        self.assertFalse(report["archive_checks"]["integrity_valid"])
        self.assertEqual(report["cross_export"]["status"], "not_checked")

    def test_conflicting_child_parent_or_request_company_cannot_corroborate_quantities(self):
        self.full()
        for broken in ("jobmas_id", "jobfabric_id", "request_company"):
            with self.subTest(broken=broken):
                row = {"companymas_id": "1", "jobmasid": "10", "jobdfabricid": "20", "jobdiaid": "30",
                       "jobmas_id": "10", "jobfabric_id": "20", "finyear": "1", "jobdate": "2023-08-01",
                       "programqty": "0.3", "stock_kgs": "12.00000000000000000001"}
                if broken != "request_company":
                    row[broken] = "999"
                self.add("status.json", "knitpack/reports/getJobOrderStatus", [row],
                         {"companymas_id": "2" if broken == "request_company" else "1"})
                report = self.run_gate()
                self.assertEqual(report["cross_export"]["invalid_identity_rows"], 1)
                self.assertEqual(report["cross_export"]["matched_distinct_size_records"], 0)
                self.entries = self.entries[:3]

    def test_archive_identity_failure_prevents_quantity_corroboration(self):
        self.full(date="2024-08-01")
        self.status(date="2024-08-01")
        report = self.run_gate()
        self.assertFalse(report["archive_checks"]["identity_valid"])
        self.assertEqual(report["cross_export"]["status"], "not_checked")


if __name__ == "__main__":
    unittest.main()
