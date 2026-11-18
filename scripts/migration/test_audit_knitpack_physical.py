"""Synthetic physical quantity evidence; never reads customer data."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_physical.py")


class PhysicalAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.reports = self.root / "source", self.root / "reports"
        self.source.mkdir()
        self.reports.mkdir()
        self.add(self.source, "companies.json", "masters/masters/listCompany", {"result": [{"id": str(i)} for i in range(1, 5)]})

    def add(self, folder, name, route, payload, filters=None):
        payload["currentUserinfo"] = {"token": "PRIVATE-TOKEN"}
        data = json.dumps(payload).encode()
        (folder / name).write_bytes(data)
        with (folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": name, "path": route, "filters": filters,
                                    "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}) + "\n")

    def report(self, name, route, root, filters=None):
        self.add(self.reports, name, "x/" + route + "/x", {"root": root}, filters or {"companymas_id": "1"})

    def ledger(self, *, date="2026-11-14", quantity="0.3", filename="job.json"):
        self.report(filename, "ViewJobLedgerreport", {
            "job": {"id": "10", "companymas_id": "1", "jobdate": "2026-11-14", "total_grn_net_kgs": quantity,
                    "total_grn_bags": "2", "total_grn_cones": "3"},
            "reciepts": [{"id": "20", "det_id": "30", "yarnmas_id": "40", "grndate": date,
                          "partydcdate": "2026-11-14", "grnnetkgs": quantity, "grnbags": "2", "grncones": "3"}],
            "deliveries": [], "returns": [], "yarn_grn_total": quantity, "fabdc_total": "0",
            "yarn_return_total": "0", "balance": "-2"}, {"id": "10"})

    def grn(self, quantity="0.3"):
        self.report("grn.json", "getYarnGRNRegPrint", {"yarnreceipts": [{
            "companymas_id": "1", "godown_id": "1", "jobmas_id": "10", "jobyarngrn_id": "20", "deatid": "30", "yarnmas_id": "40",
            "grndate": "2026-11-14", "partydcdate": "2026-11-14", "grnnetkgs": quantity, "grnbags": "2", "grncones": "3"}]},
            {"companymas_id": "1", "godown_id": "1"})

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "Physical quantity auditor must exist")
        spec = importlib.util.spec_from_file_location("physical_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.audit(self.source, self.reports)
        self.assertFalse(result["import_allowed"])
        self.assertFalse(result["physical_balances_reconciled"])
        self.assertNotIn("PRIVATE-TOKEN", json.dumps(result))
        self.assertNotIn("PRIVATE-PARTY", json.dumps(result))
        return result

    def test_native_production_is_not_counted_again_as_summary_events(self):
        rows = [{"id": str(i), "companymas_id": "1", "jobmas_id": "10", "fabric_id": "20", "dia_id": "30",
                 "date": "2026-11-14", "prodkgs": amount, "prodrolls": "1", "party_name": "PRIVATE-PARTY"}
                for i, amount in enumerate(("0.1", "0.2"), 1)]
        root = {"prodreports": rows}
        for group in ("mc_wise", "dia_wise", "fab_var_wise"):
            root[group] = [{"sum_prodkgs": "0.3", "sum_prodrolls": "2"}]
        self.report("production.json", "getProductionReg", root)
        result = self.audit()
        self.assertEqual(result["companies"]["1"]["production_native_rows"], 2)
        self.assertEqual(result["checks"]["production_summary_controls"]["passed"], 6)

    def test_native_grn_detail_keys_link_without_using_display_numbers(self):
        self.ledger()
        self.grn()
        result = self.audit()
        self.assertEqual(result["checks"]["grn_ledger_overlap"]["passed"], 3)
        self.assertEqual(result["companies"]["1"]["grn_detail_overlap"], 1)
        self.assertEqual(result["job_ledger_observations"][0]["original_signed_balance"], "-2")

    def test_unknown_receipt_amount_never_becomes_zero(self):
        self.ledger()
        self.grn(None)
        self.assertEqual(self.audit()["checks"]["grn_ledger_overlap"]["unknown"], 1)

    def test_original_transaction_date_disagreement_blocks_quantity_corroboration(self):
        self.ledger(date="2026-11-13")
        self.grn()
        result = self.audit()
        self.assertEqual(result["checks"]["grn_ledger_overlap"]["passed"], 0)
        self.assertTrue(any(x["kind"] == "original_receipt_date_conflict" for x in result["identity_issues"]))

    def test_formatted_ledger_date_is_preserved_as_unresolved_without_guessing_iso_date(self):
        self.ledger(date="14-Nov-26")
        self.grn()
        result = self.audit()
        self.assertEqual(result["checks"]["grn_ledger_overlap"]["passed"], 3)
        self.assertEqual(result["date_observations"][0]["status"], "unknown_source_date_encoding")
        self.assertEqual(result["date_observations"][0]["ledger_grndate"], "14-Nov-26")

    def test_snapshot_quantity_difference_is_exact_and_not_a_stock_conservation_claim(self):
        self.report("programme.json", "programChart", {"prgm_chart": [{
            "job_id": "10", "fabric_id": "20", "diaorsize": "40", "stock_kgs": "0.3", "prod_qty": "1"}]})
        self.report("stock.json", "getjobfabricstock", {"jobfabricstocks": [{
            "companymas_id": "1", "jobmas_id": "10", "jobfabric_id": "20", "fab_id": "20", "jobdiaid": "30",
            "diaorsize": "40", "jobdate": "2026-11-14", "stock_kgs": "0.30000000000000000001", "stock_rolls": "1"}]})
        result = self.audit()
        self.assertEqual(result["checks"]["fabric_stock_programme_overlap"]["different"], 1)
        finding = next(f for f in result["findings"] if f["check"] == "fabric_stock_programme_overlap")
        self.assertEqual(finding["absolute_difference"], "0.00000000000000000001")
        self.assertEqual(result["companies"]["1"]["physical_balance_status"], "unknown")

    def test_missing_root_and_empty_scopes_do_not_establish_empty_company(self):
        self.add(self.reports, "failed.json", "x/ViewJobLedgerreport/x", {"msg": "PRIVATE-PARTY"}, {"id": "10"})
        result = self.audit()
        self.assertEqual(len(result["unusable_report_files"]), 1)
        self.assertEqual(len(result["companies"]), 4)
        self.assertTrue(all(c["physical_balance_status"] == "unknown" for c in result["companies"].values()))

    def test_invalid_programme_dimension_does_not_create_partial_job_total_difference(self):
        self.report("production.json", "getProductionReg", {"prodreports": [
            {"id": "1", "companymas_id": "1", "jobmas_id": "10", "fabric_id": "20", "dia_id": "30",
             "date": "2026-11-14", "prodkgs": "2", "prodrolls": "2"}]})
        self.report("programme.json", "programChart", {"prgm_chart": [
            {"job_id": "10", "fabric_id": "20", "diaorsize": "40", "prod_qty": "1"},
            {"job_id": "10", "fabric_id": "20", "diaorsize": None, "prod_qty": "1"}]})
        result = self.audit()
        self.assertEqual(result["checks"]["production_programme_overlap"]["different"], 0)
        self.assertEqual(result["checks"]["production_programme_overlap"]["unknown"], 1)

    def test_conflicting_job_versions_remain_missing_usable_evidence(self):
        self.add(self.source, "index.json", "knitpack/inward/getInwardListForProgChart", {"result": {"items": [{"id": "10"}]}},
                 {"limit_from": 0, "limit_to": 100, "searchKeyword": "", "getParams": {
                     "companymas_id": "1", "type": "all", "partymas_id": None, "from_date": "2023-04-01", "to_date": "2027-03-31"}})
        self.ledger()
        self.ledger(filename="changed.json", quantity="0.4")
        result = self.audit()
        self.assertEqual(result["companies"]["1"]["historical_job_ids_without_usable_ledger"], ["10"])
        self.assertEqual(result["companies"]["1"]["job_ledgers"], 0)

    def test_return_quantities_use_explicit_parent_and_yarn_ids_not_flattened_id(self):
        self.report("returns.json", "getYarnReturnRegPrint", {"yarnreturns": [{
            "id": "999", "companymas_id": "1", "jobmas_id": "10", "yarn_dc_id": "20", "dc_id": "20",
            "yarnmas_id": "40", "dc_date": "2026-11-14", "net_kgs": "0.3", "bags": "2", "cons": "3"}]})
        self.report("job.json", "ViewJobLedgerreport", {"job": {"id": "10", "companymas_id": "1", "jobdate": "2026-11-14"},
            "reciepts": [], "deliveries": [], "returns": [{"id": "20", "det_id": "30", "yarnmas_id": "40",
                "dc_date": "14-Nov-26", "net_kgs": "0.3", "bags": "2", "cons": "3"}]}, {"id": "10"})
        result = self.audit()
        self.assertEqual(result["checks"].get("yarn_return_ledger_overlap", {}).get("passed"), 3)


if __name__ == "__main__":
    unittest.main()
