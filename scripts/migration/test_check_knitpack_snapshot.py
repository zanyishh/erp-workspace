"""Offline synthetic tests; never reads the customer archive or contacts a service."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("check_knitpack_snapshot.py")


class SnapshotCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.entries = []
        self.add("years.json", "knitpack/masters/getFinYearSB",
                 [{"value": "1", "name": "23-24"}, {"value": "2", "name": "24-25"}])

    def add(self, filename, endpoint, result, filters=None, *, response=None):
        data = json.dumps(response if response is not None else {
            "isLogin": True, "mode": "development", "result": result,
            "rc_session": "SYNTHETIC-SECRET-MUST-NOT-APPEAR",
        }).encode()
        (self.source / filename).write_bytes(data)
        self.entries.append({"file": filename, "path": endpoint,
                             "method": "POST" if filters is not None else "GET",
                             "filters": filters, "bytes": len(data),
                             "sha256": hashlib.sha256(data).hexdigest()})

    def index(self, filename, company, ids, *, start=0, limit=100):
        self.add(filename, "knitpack/inward/getInwardListForProgChart",
                 {"items": [{"id": value, "partyjobno": "PRIVATE-CUSTOMER-TEXT"} for value in ids],
                  "selected_items": [], "search_items": []},
                 {"pageing": True, "currentPage": start // limit, "pageSize": limit,
                  "limit_from": start, "limit_to": limit, "searchKeyword": "",
                  "getParams": json.dumps({"companymas_id": company, "from_date": "2023-04-01",
                                           "to_date": "2025-03-31", "type": "all", "partymas_id": "null"})})

    def full(self, filename, source_id, company, year="1", date="2023-08-01"):
        self.add(filename, f"knitpack/inward/getInward/{source_id}",
                 {"id": str(source_id), "companymas_id": str(company), "finyear": year,
                  "jobdate": date, "job_fabrics": [], "partymas_id": "PRIVATE-PARTY"})

    def run_check(self):
        (self.source / "manifest.jsonl").write_text("\n".join(json.dumps(e) for e in self.entries) + "\n")
        report = self.root / "report.json"
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.source), "--report", str(report)],
                                capture_output=True, text=True)
        self.assertTrue(report.exists(), "Checker must write an audit report even when an entry is invalid")
        value = json.loads(report.read_text())
        public_and_report = result.stdout + result.stderr + report.read_text()
        self.assertNotIn("SYNTHETIC-SECRET", public_and_report)
        self.assertNotIn("PRIVATE-CUSTOMER-TEXT", public_and_report)
        self.assertNotIn("PRIVATE-PARTY", public_and_report)
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)
        return result, value

    def test_partial_archive_counts_only_verified_full_jobs_not_failed_responses(self):
        self.index("index-a.json", 1, [10, 11])
        self.index("index-b.json", 2, [20])
        self.full("full-a.json", 10, 1)
        self.full("full-b.json", 20, 2, "2", "2024-08-01")
        self.add("failed.json", "knitpack/inward/getInward/11", None,
                 response={"msg": "Invalid rCloud License!"})
        result, report = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(report["integrity"]["valid"])
        self.assertEqual(report["failed_api_responses"]["count"], 1)
        self.assertEqual(report["companies"]["1"]["indexed_distinct_jobs"], 2)
        self.assertEqual(report["companies"]["1"]["verified_full_distinct_jobs"], 1)
        self.assertEqual(report["companies"]["1"]["indexed_without_verified_full"], 1)
        self.assertEqual(report["companies"]["2"]["verified_full_distinct_jobs"], 1)
        self.assertFalse(report["all_source_data_complete"])

    def test_error_envelope_with_valid_job_fields_is_archived_only(self):
        self.index("index.json", 1, [10])
        self.add("failure.json", "knitpack/inward/getInward/10", None, response={
            "rc_error": True, "result": {"id": 10, "companymas_id": 1, "finyear": 1,
                                         "jobdate": "2023-08-01", "job_fabrics": []}})
        result, report = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(report["verified_response_files"], 3)
        self.assertEqual(report["failed_api_responses"]["count"], 1)
        self.assertEqual(report["companies"]["1"]["indexed_without_verified_full"], 1)

    def test_tampered_missing_and_unmanifested_files_are_not_trusted(self):
        self.index("index.json", 1, [10])
        self.full("tampered.json", 10, 1)
        (self.source / "tampered.json").write_text('{"result": {"id": "10"}}')
        self.full("missing.json", 11, 1)
        (self.source / "missing.json").unlink()
        (self.source / "untracked.json").write_text("{}")
        result, report = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertFalse(report["integrity"]["valid"])
        self.assertEqual(report["integrity"]["hash_mismatch"]["count"], 1)
        self.assertEqual(report["integrity"]["missing_files"]["count"], 1)
        self.assertEqual(report["integrity"]["unmanifested_files"]["count"], 1)
        self.assertEqual(report["companies"]["1"]["verified_full_distinct_jobs"], 0)

    def test_mismatched_company_year_and_requested_id_exclude_full_records(self):
        self.index("index.json", 1, [10, 11, 12])
        self.full("wrong-company.json", 10, 2)
        self.full("wrong-year.json", 11, 1, "1", "2024-08-01")
        self.full("wrong-id.json", 999, 1)
        self.entries[-1]["path"] = "knitpack/inward/getInward/12"
        result, report = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["identity"]["company_mismatch"]["count"], 1)
        self.assertEqual(report["identity"]["fiscal_year_date_mismatch"]["count"], 1)
        self.assertEqual(report["identity"]["requested_id_mismatch"]["count"], 1)
        self.assertEqual(report["companies"]["1"]["indexed_without_verified_full"], 3)

    def test_duplicate_full_records_are_counted_once_and_index_overlap_is_disclosed(self):
        self.index("index-a.json", 1, [10, 11])
        self.index("index-b.json", 1, [10, 11])
        self.full("full-a.json", 10, 1)
        self.full("full-copy.json", 10, 1)
        result, report = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(report["companies"]["1"]["indexed_distinct_jobs"], 2)
        self.assertEqual(report["companies"]["1"]["verified_full_distinct_jobs"], 1)
        self.assertEqual(report["duplicates"]["full_source_ids"]["count"], 1)
        self.assertEqual(report["duplicates"]["index_observations"], 2)

    def test_escape_paths_and_symlinks_are_rejected_without_reading_external_data(self):
        self.entries.append({"file": "../outside.json", "path": "knitpack/inward/getInward/10",
                             "bytes": 0, "sha256": "0" * 64})
        (self.source / "link.json").symlink_to(self.root / "outside.json")
        self.entries.append({"file": "link.json", "path": "knitpack/inward/getInward/11",
                             "bytes": 0, "sha256": "0" * 64})
        result, report = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["integrity"]["unsafe_paths"]["count"], 2)

    def test_unterminated_index_pages_never_establish_complete_enumeration(self):
        self.index("page.json", 1, [10, 11], limit=2)
        self.full("full-a.json", 10, 1)
        self.full("full-b.json", 11, 1)
        _, report = self.run_check()
        self.assertFalse(report["companies"]["1"]["observed_index_enumeration_terminated"])
        self.assertFalse(report["all_source_data_complete"])

    def test_readable_report_marks_zero_index_as_unproven_and_excludes_private_values(self):
        self.index("empty-index.json", 4, [])
        self.run_check()
        report = self.root / "report.md"
        self.assertTrue(report.exists(), "The private audit must include a readable report")
        text = report.read_text()
        self.assertIn("not proof that a company is empty", text)
        self.assertNotIn("SYNTHETIC-SECRET", text)
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)

    def test_conflicting_full_identity_and_malformed_request_context_fail_closed(self):
        self.index("index.json", 1, [10])
        self.full("copy-a.json", 10, 1)
        self.full("copy-b.json", 10, 1, "2", "2024-08-01")
        self.add("bad-context.json", 1234, {})
        result, report = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["identity"]["conflicting_full_identity"]["count"], 2)
        self.assertEqual(report["integrity"]["invalid_manifest_entry"]["count"], 1)
        self.assertEqual(report["companies"]["1"]["verified_full_distinct_jobs"], 0)


if __name__ == "__main__":
    unittest.main()
