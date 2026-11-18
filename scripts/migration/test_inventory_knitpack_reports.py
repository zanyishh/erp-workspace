"""Synthetic completeness/identity inventory checks; no customer archive reads."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("inventory_knitpack_reports.py")


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source, self.reports = self.base / "source", self.base / "reports"
        self.source.mkdir()
        self.reports.mkdir()
        (self.reports / "manifest.jsonl").write_text("")
        self.add(self.source, "companies", "masters/masters/listCompany",
                 {"result": [{"id": str(i)} for i in range(1, 5)]})
        self.add(self.source, "index", "knitpack/inward/getInwardListForProgChart",
                 {"result": {"items": [{"id": "10"}, {"id": "11"}]}},
                 {"getParams": {"companymas_id": "1"}})

    def add(self, folder, name, route, payload, filters=None):
        raw = json.dumps(payload).encode()
        (folder / (name + ".json")).write_bytes(raw)
        with (folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": name + ".json", "path": route, "filters": filters,
                                     "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}) + "\n")

    def report(self, name, root, *, filters=None, action="JobTransHistory"):
        self.add(self.reports, name,
                 "{URI}knitpack/getprint/getdata/knit_job_mas/" + action + "/{PASS}",
                 {"root": root, "currentUserinfo": {"token": "SECRET-SESSION"}}, filters)

    def audit(self, **kwargs):
        self.assertTrue(SCRIPT.exists(), "The report inventory helper must exist")
        spec = importlib.util.spec_from_file_location("report_inventory", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.inventory(self.source, self.reports, **kwargs)
        text = json.dumps(result)
        self.assertNotIn("SECRET-SESSION", text)
        self.assertNotIn("PRIVATE-PARTY", text)
        self.assertFalse(result["import_allowed"])
        self.assertEqual(result["completeness"], "unknown")
        return result

    def test_indexed_company_and_original_dates_do_not_come_from_report_range(self):
        self.report("history", {"order_inward": [{"id": "10", "jobdate": "2023-06-01"}],
                               "production": [{"jobmas_id": "10", "date": "2023-06-02", "prodkgs": "3.5"}]},
                    filters={"jobmas_id": "10", "from_date": "2000-01-01", "to_date": "2100-12-31"})
        result = self.audit()
        self.assertEqual(result["history_coverage"]["1"]["valid_history_jobs"], 1)
        self.assertEqual(result["history_coverage"]["1"]["indexed_jobs_without_valid_history"], 1)
        self.assertEqual(result["history_coverage"]["4"]["indexed_jobs"], 0)
        self.assertFalse(result["history_coverage"]["4"]["proven_empty_company"])
        dataset = next(d for d in result["datasets"] if d["dataset"] == "production")
        self.assertEqual(dataset["company_scope"], "1")
        self.assertEqual(dataset["dates"]["date"]["min_original"], "2023-06-02")
        self.assertEqual(dataset["dates"]["date"]["valid"], 1)

    def test_joined_rows_and_repeated_exports_do_not_become_unique_transactions(self):
        rows = [{"id": "20", "jobmas_id": "10", "prodkgs": "2", "party_name": "PRIVATE-PARTY"},
                {"id": "20", "jobmas_id": "10", "prodkgs": "3", "party_name": "PRIVATE-PARTY"}]
        for name in ("first", "repeat"):
            self.report(name, {"prodreports": rows}, filters={"companymas_id": "1"}, action="getProductionReg")
        result = self.audit()
        dataset = result["datasets"][0]
        self.assertEqual(dataset["row_observations"], 4)
        self.assertEqual(dataset["distinct_row_fingerprints"], 2)
        self.assertEqual(dataset["identity_candidates"]["id"]["distinct_values"], 1)
        self.assertEqual(dataset["identity_candidates"]["id"]["values_with_different_rows"], 1)
        self.assertEqual(dataset["native_document_count"], "not_proven")

    def test_company_conflicts_and_ambiguous_job_ids_are_not_resolved_by_guessing(self):
        self.add(self.source, "index2", "knitpack/inward/getInwardListForProgChart",
                 {"result": {"items": [{"id": "10"}]}}, {"getParams": {"companymas_id": "2"}})
        self.report("ambiguous", {"order_inward": [{"id": "10", "jobdate": "2023-06-01"}]}, filters={"jobmas_id": "10"})
        self.report("wrong_company", {"company_info": {"id": "2"}, "prodreports": [{"id": "30", "companymas_id": "2"}]},
                    filters={"companymas_id": "1"}, action="getProductionReg")
        result = self.audit()
        self.assertGreater(result["identity_issues"]["ambiguous_history_company"], 0)
        self.assertGreater(result["identity_issues"]["company_context_conflict"], 0)
        self.assertEqual(result["history_coverage"]["1"]["valid_history_jobs"], 0)

    def test_captured_manifest_excludes_later_files_and_changed_bytes_are_rejected(self):
        self.report("first", {"prodreports": [{"id": "20"}]}, filters={"companymas_id": "1"}, action="getProductionReg")
        captured = (self.reports / "manifest.jsonl").read_bytes()
        self.report("later", {"prodreports": [{"id": "21"}]}, filters={"companymas_id": "1"}, action="getProductionReg")
        result = self.audit(report_manifest=captured)
        self.assertEqual(result["report_manifest"]["entries"], 1)
        self.assertEqual(result["datasets"][0]["row_observations"], 1)
        (self.reports / "first.json").write_text("{}")
        result = self.audit(report_manifest=captured)
        self.assertFalse(result["integrity"]["valid"])
        self.assertEqual(result["datasets"], [])

    def test_templates_empty_arrays_and_failed_responses_are_not_data_completeness(self):
        self.add(self.reports, "template", "templates/production_register",
                 {"result": {"Variables": {"PASS": "SECRET-SESSION"}, "DataSources": [{"id": "fake"}]}})
        self.add(self.reports, "failed", "reports/failure", {"mode": "error", "data": "SECRET-SESSION"})
        self.report("empty", {"prodreports": []}, filters={"companymas_id": "4"}, action="getProductionReg")
        result = self.audit()
        self.assertEqual(result["report_responses"]["without_structured_root"], 2)
        self.assertEqual(len(result["datasets"]), 1)
        self.assertEqual(result["datasets"][0]["row_observations"], 0)
        self.assertEqual(result["datasets"][0]["evidence_state"], "empty_observed_scope_only")

    def test_godown_transaction_context_is_distinct_from_explicit_master_binding(self):
        self.report("transaction", {"prodreports": [{"id": "20", "companymas_id": "1", "godown_id": "7"}]},
                    filters={"companymas_id": "1"}, action="getProductionReg")
        self.add(self.reports, "master", "masters/masters/getGodown/8", {"result": {"id": "8", "company_id": "2"}})
        result = self.audit()
        bindings = {row["source_godown_id"]: row for row in result["warehouse_company_evidence"]}
        self.assertEqual(bindings["7"]["binding_status"], "transaction_context_only")
        self.assertEqual(bindings["8"]["binding_status"], "explicit_master_binding_observed")
        self.assertEqual(bindings["8"]["master_company_ids"], ["2"])

    def test_invalid_dates_and_attachment_metadata_do_not_invent_files_or_rolls(self):
        self.report("history", {"order_inward": [{"id": "10", "jobdate": "2023-02-31"}],
                               "production_with_roll_no": [{"jobmas_id": "10", "qc_roll_no": "5,6", "prodkgs": "7", "date": "02/03/2023"}],
                               "company_info": {"id": "1", "cmp_logo": "private-object-reference"}}, filters={"jobmas_id": "10"})
        result = self.audit()
        ds = next(d for d in result["datasets"] if d["dataset"] == "order_inward")
        self.assertEqual(ds["dates"]["jobdate"]["invalid_or_ambiguous"], 1)
        self.assertEqual(result["attachments"]["file_bytes_verified"], 0)
        self.assertEqual(result["attachments"]["metadata_field_observations"]["cmp_logo"], 1)
        roll = result["production_and_rolls"]
        self.assertEqual(roll["history_rows_with_qc_roll_no"], 1)
        self.assertEqual(roll["individual_roll_identity_and_weight"], "not_established")

    def test_list_roots_preserve_each_ledger_group_and_nested_lines(self):
        self.add(self.reports, "ledger", "{URI}accv2/getprint/getdata/acc_entry/accountLedgerPrint/{PASS}",
                 {"root": [{"company_info": {"id": "2"}, "opbal": "1", "clbal": "3",
                            "ledg_list": [{"id": "100", "v_date": "2023-04-02"}]},
                           {"company_info": {"id": "2"}, "opbal": "0", "clbal": "0", "ledg_list": []}]},
                 {"companymas_id": "2"})
        result = self.audit()
        group = next((d for d in result["datasets"] if d["dataset"] == "root_groups"), None)
        self.assertIsNotNone(group, "List roots must retain their control groups")
        lines = next(d for d in result["datasets"] if d["dataset"] == "ledg_list")
        self.assertEqual(group["row_observations"], 2)
        self.assertEqual(lines["row_observations"], 1)
        self.assertEqual(lines["company_scope"], "2")
        self.assertEqual(result["missing_domain_updates"]["opening_and_closing_controls"]["company_scopes_with_rows"], ["2"])

    def test_master_lists_are_inventory_without_assigning_unbound_shared_godown(self):
        self.add(self.reports, "masters", "masters/masters/listGodown",
                 {"result": [{"id": "7", "company_id": ""}, {"id": "8", "company_id": "2"}]})
        for company in ("1", "3"):
            self.report("production" + company, {"prodreports": [{"id": company, "companymas_id": company, "godown_id": "7"}]},
                        filters={"companymas_id": company}, action="getProductionReg")
        result = self.audit()
        master = next((d for d in result["datasets"] if d["dataset"] == "godown_master"), None)
        self.assertIsNotNone(master, "Godown masters must appear in the structural inventory")
        self.assertEqual(master["row_observations"], 2)
        unbound = next(r for r in result["warehouse_company_evidence"] if r["source_godown_id"] == "7")
        self.assertEqual(unbound["master_records_observed"], 1)
        self.assertEqual(unbound["binding_status"], "multiple_company_transaction_context_unbound")
        self.assertFalse(unbound["usable_master_binding"])

    def test_job_ledger_original_header_is_recorded_without_replacing_failed_history(self):
        self.report("history_error", {}, filters={"jobmas_id": "10"})
        self.report("ledger", {"job": {"id": "10", "companymas_id": "1", "jobdate": "2023-06-01"},
                               "reciepts": [{"id": "20"}]}, filters={"id": "10"}, action="ViewJobLedgerreport")
        result = self.audit()
        self.assertEqual(result["history_coverage"]["1"]["valid_history_jobs"], 0)
        self.assertEqual(result["history_coverage"]["1"].get("indexed_jobs_without_valid_history_ids"), ["10", "11"])
        self.assertEqual(result["job_ledger_coverage"]["1"]["valid_original_job_headers"], 1)
        ds = next(d for d in result["datasets"] if d["dataset"] == "job")
        self.assertEqual(ds["company_scope"], "1")
        self.assertEqual(ds["dates"]["jobdate"]["min_original"], "2023-06-01")

    def test_original_job_date_disagreement_is_not_silently_corrected(self):
        self.add(self.source, "full", "knitpack/inward/getInward/10",
                 {"result": {"id": "10", "companymas_id": "1", "jobdate": "2023-06-01"}})
        self.report("history", {"order_inward": [{"id": "10", "jobdate": "2023-06-02"}]}, filters={"jobmas_id": "10"})
        result = self.audit()
        self.assertEqual(result.get("original_job_date_comparisons", {}).get("different"), 1)
        self.assertEqual(result["original_job_date_comparisons"]["matched"], 0)
        self.assertEqual(result["identity_issues"].get("original_job_date_disagreement"), 1)

    def test_identically_named_report_entities_in_different_modules_stay_separate(self):
        for module in ("knitpack", "accv2"):
            self.add(self.reports, module, "{URI}" + module + "/getprint/getdata/shared/report/{PASS}",
                     {"root": {"rows": [{"id": "1"}]}}, {"companymas_id": "1"})
        result = self.audit()
        self.assertEqual(len(result["datasets"]), 2)
        self.assertTrue(all(d["row_observations"] == 1 for d in result["datasets"]))

    def test_failed_source_index_cannot_create_a_false_company_identity(self):
        self.add(self.source, "failed_index", "knitpack/inward/getInwardListForProgChart",
                 {"isLogin": False, "result": {"items": [{"id": "10"}]}}, {"getParams": {"companymas_id": "2"}})
        self.report("history", {"order_inward": [{"id": "10", "jobdate": "2023-06-01"}]}, filters={"jobmas_id": "10"})
        result = self.audit()
        self.assertEqual(result["history_coverage"]["1"]["valid_history_jobs"], 1)

    def test_native_voucher_header_and_party_are_not_dropped_as_scalar_metadata(self):
        self.report("voucher", {"voucher": {"id": "50", "companymas_id": "2", "sec_acc": "1", "v_date": "2023-06-01"},
                                "party": {"id": "60", "party_name": "PRIVATE-PARTY"}}, action="voucher_print")
        result = self.audit()
        voucher = next((d for d in result["datasets"] if d["dataset"] == "voucher"), None)
        self.assertIsNotNone(voucher, "Native voucher identity must be inventoried separately from report totals")
        self.assertEqual(voucher["company_scope"], "2")
        self.assertEqual(voucher["identity_candidates"]["id"]["distinct_values"], 1)
        party = next(d for d in result["datasets"] if d["dataset"] == "party")
        self.assertEqual(party["role"], "embedded_master")


if __name__ == "__main__":
    unittest.main()
