"""Synthetic native stock and discrepancy tracing tests; no customer archive."""
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from audit_knitpack_native_stock import context_index, trace_finding, stock_overlap, capture_order, validate_delivery


def observation(route, result, file="context.json", root=False, filters=None):
    return ({"path": route, "file": file, "sha256": "synthetic", "bytes": 1,
             "retrieved_at_utc": "2026-11-14T10:00:00Z", "filters": filters},
            {"root" if root else "result": result, "currentUserinfo": {"token": "PRIVATE"}}, "/synthetic/" + file)


def fabric():
    return {"job": {"id": "10", "companymas_id": "1", "jobdate": "2026-11-14", "partymas_id": "5",
                    "sec_acc": "0", "jobtype": "order", "updated_time": "2026-11-14 09:00:00", "total_grn_net_kgs": "0.3"},
            "fabs": [{"id": "20", "jobmas_id": "10", "dias": [{"id": "30", "jobfabric_id": "20", "diaorsize": "0",
                     "stock_kgs": "0.3", "stock_rolls": "1", "prod_qty": "0.3"}]}]}


class NativeStockTests(unittest.TestCase):
    def test_hash_valid_failed_response_cannot_prove_context_or_stock(self):
        failed = observation("knitpack/Subcontract/getJobInfos/10", fabric())
        failed[1]["isLogin"] = False
        contexts, issues = self.contexts([failed])
        self.assertFalse(contexts)
        self.assertTrue(issues)
        contexts, _ = self.contexts()
        stock = observation("x/getjobfabricstock/x", {"jobfabricstocks": [{"companymas_id": "1", "jobmas_id": "10",
            "jobfabric_id": "20", "fab_id": "20", "jobdiaid": "30", "diaorsize": "0", "jobdate": "2026-11-14",
            "stock_kgs": "0.3", "stock_rolls": "1"}]}, root=True, filters={"companymas_id": "1"})
        stock[1]["mode"] = "failed"
        result = stock_overlap(contexts, [stock], issues)
        self.assertEqual(result["checks"]["fabric_stock_kgs"]["passed"], 0)

    def test_cli_cannot_write_into_source_archives(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            response = subprocess.run([sys.executable, str(Path(__file__).with_name("audit_knitpack_native_stock.py")),
                str(folder / "source"), str(folder / "reports"), "--report", str(folder / "reports" / "output.json")],
                capture_output=True, text=True)
            self.assertEqual(response.returncode, 2)
            self.assertIn("outside", response.stderr)
            self.assertFalse((folder / "reports" / "output.json").exists())

    def contexts(self, records=None):
        issues = []
        records = records or [observation("knitpack/Subcontract/getJobInfos/10", fabric())]
        contexts = context_index(records, {"1"}, issues)
        return contexts, issues

    def test_native_primary_dia_can_ground_zero_display_selector(self):
        contexts, issues = self.contexts()
        self.assertFalse(issues)
        records = [observation("x/programChart/x", {"prgm_chart": [{"job_id": "10", "fabric_id": "20", "diaorsize": "0", "prod_qty": "0.3"}]}, root=True, filters={"companymas_id": "1"}),
                   observation("x/getProductionReg/x", {"prodreports": [{"id": "1", "companymas_id": "1", "jobmas_id": "10", "prodkgs": "0.1"}, {"id": "2", "companymas_id": "1", "jobmas_id": "10", "prodkgs": "0.2"}]}, "production.json", True, {"companymas_id": "1"})]
        trace = trace_finding({"check": "production_programme_overlap", "source_key": ["1", "10"], "paths": [r[2] for r in records], "status": "unknown"}, contexts, records)
        self.assertEqual(trace["versions"][0]["production_vs_complete_programme"]["status"], "passed")
        self.assertEqual(trace["versions"][0]["programme_native_dimension_mapping"], "unique_complete")
        self.assertFalse(trace["cause_established"])

    def test_duplicate_display_selector_does_not_invent_native_identity(self):
        value = fabric()
        value["fabs"][0]["dias"].append({**value["fabs"][0]["dias"][0], "id": "31"})
        contexts, _ = self.contexts([observation("knitpack/Subcontract/getJobInfos/10", value)])
        records = [observation("x/programChart/x", {"prgm_chart": [{"job_id": "10", "fabric_id": "20", "diaorsize": "0", "prod_qty": "0.3"}]}, root=True, filters={"companymas_id": "1"})]
        trace = trace_finding({"check": "production_programme_overlap", "source_key": ["1", "10"], "paths": [records[0][2]], "status": "unknown"}, contexts, records)
        self.assertEqual(trace["versions"][0]["programme_native_dimension_mapping"], "unknown")

    def test_explicit_blank_selector_can_map_unique_native_child_but_missing_cannot(self):
        value = fabric()
        value["fabs"][0]["dias"][0]["diaorsize"] = ""
        contexts, _ = self.contexts([observation("knitpack/Subcontract/getJobInfos/10", value)])
        row = {"job_id": "10", "fabric_id": "20", "diaorsize": "", "prod_qty": "0.3"}
        record = observation("x/programChart/x", {"prgm_chart": [row]}, root=True, filters={"companymas_id": "1"})
        finding = {"check": "production_programme_overlap", "source_key": ["1", "10"], "paths": [record[2]], "status": "unknown"}
        self.assertEqual(trace_finding(finding, contexts, [record])["versions"][0]["programme_native_dimension_mapping"], "unique_complete")
        del row["diaorsize"]
        self.assertEqual(trace_finding(finding, contexts, [record])["versions"][0]["programme_native_dimension_mapping"], "unknown")

    def test_native_parent_mismatch_and_original_date_invalid_are_rejected(self):
        value = fabric()
        value["fabs"][0]["jobmas_id"] = "99"
        contexts, issues = self.contexts([observation("knitpack/Subcontract/getJobInfos/10", value)])
        self.assertFalse(contexts)
        self.assertTrue(issues)

    def test_null_stock_stays_unknown_and_decimal_difference_is_exact(self):
        contexts, _ = self.contexts()
        rows = [{"companymas_id": "1", "jobmas_id": "10", "jobfabric_id": "20", "fab_id": "20", "jobdiaid": "30", "diaorsize": "0", "jobdate": "2026-11-14", "stock_kgs": "0.30000000000000000001", "stock_rolls": None}]
        result = stock_overlap(contexts, [observation("x/getjobfabricstock/x", {"jobfabricstocks": rows}, root=True, filters={"companymas_id": "1"})], [])
        self.assertEqual(result["checks"]["fabric_stock_kgs"]["different"], 1)
        self.assertEqual(result["checks"]["fabric_stock_rolls"]["unknown"], 1)
        self.assertEqual(result["findings"][0]["absolute_difference"], "0.00000000000000000001")

    def test_yarn_context_needs_exact_native_job_context_to_assign_company(self):
        yarn = {"id": "10", "jobdate": "2026-11-14", "partymas_id": "5", "sec_acc": "1", "jobtype": "order", "yarn_mas": []}
        contexts, issues = self.contexts([observation("knitpack/Subcontract/getJobInfos/10", fabric()), observation("knitpack/inward/getjoborderwithyarnmas/10", yarn, "yarn.json")])
        self.assertFalse(contexts[("1", "10")][0]["yarn_versions"])
        self.assertTrue(any(x["kind"] == "yarn_job_context_conflict_or_unknown" for x in issues))

    def test_changed_updated_timestamp_is_not_asserted_as_cause(self):
        contexts, _ = self.contexts()
        original = copy.deepcopy(fabric()["job"])
        original["updated_time"] = "2026-11-13 09:00:00"
        records = [observation("x/ViewJobLedgerreport/x", {"job": original}, "ledger.json", True, {"id": "10"})]
        finding = {"check": "job_ledger_header_rollups", "field": "total_grn_net_kgs", "source_key": ["1", "10"], "row_sum": "0.2", "source_control": "0.3", "paths": [records[0][2]], "status": "different"}
        trace = trace_finding(finding, contexts, records)
        self.assertEqual(trace["versions"][0]["same_job_updated_time"][0]["comparison"], "different")
        self.assertFalse(trace["cause_established"])
        self.assertEqual(trace["versions"][0]["native_vs_original_header"]["status"], "passed")

    def test_capture_order_requires_explicit_timezones_and_cannot_establish_cause(self):
        self.assertEqual(capture_order(["2026-11-14T10:00:00Z"], "2026-11-14T10:01:00+00:00")["comparison"], "after_all_originals")
        self.assertEqual(capture_order(["2026-11-14 10:00:00"], "2026-11-14T10:01:00Z")["comparison"], "unknown")
        self.assertFalse(capture_order(["2026-11-14T10:00:00Z"], "2026-11-14T10:01:00Z")["cause_established"])

    def test_native_delivery_binds_child_to_job_using_actual_fabric_and_dia_ids(self):
        contexts, _ = self.contexts()
        data = {"id": "50", "companymas_id": "1", "dc_date": "2026-11-14", "job_no": "misleading display",
                "fabric_dia_details": [{"id": "51", "dc_id": "50", "fabric_id": "20", "jobdia_id": "30", "dlvry_kgs": "0.3", "dlvry_rolls": "1"}]}
        result = validate_delivery(data, "50", "1", "10", contexts)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["original_date"], "2026-11-14")

    def test_native_delivery_does_not_accept_display_job_number_or_wrong_parent(self):
        contexts, _ = self.contexts()
        data = {"id": "50", "companymas_id": "1", "dc_date": "2026-11-14", "job_no": "10",
                "fabric_dia_details": [{"id": "51", "dc_id": "99", "fabric_id": "20", "jobdia_id": "30"}]}
        self.assertEqual(validate_delivery(data, "50", "1", "10", contexts)["status"], "unknown")

    def test_delivery_editor_empty_choices_are_not_invented_as_stored_lines(self):
        contexts, _ = self.contexts()
        data = {"id": "50", "companymas_id": "1", "dc_date": "2026-11-14",
                "fabric_dia_details": [{"id": "51", "dc_id": "50", "fabric_id": "20", "jobdia_id": "30", "dlvry_kgs": "0.3", "dlvry_rolls": "1"},
                                       {"id": "", "dc_id": "", "fabric_id": "20", "jobdia_id": "30", "dlvry_kgs": "0", "dlvry_rolls": "0"}]}
        result = validate_delivery(data, "50", "1", "10", contexts)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(len(result["children"]), 1)
        self.assertEqual(result["empty_unpersisted_context_rows"], 1)


if __name__ == "__main__":
    unittest.main()
