import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from audit_knitpack_native_deliveries import audit, validate_dc


class NativeDeliveryTests(unittest.TestCase):
    def fixture(self):
        return ({"isLogin": True, "mode": "success", "result": {
            "id": 12, "companymas_id": 2, "job_no": 7, "dc_date": "2024-03-31", "dc_no": "0009",
            "eway_id": "0", "cancelled": "0", "invoice_id": 3, "total_dlvry_kgs": "0.3", "total_dlvry_rolls": 2,
            "fabric_dia_details": [{"id": 91, "dc_id": 12, "fabric_id": 101, "jobdia_id": 102,
                "dlvry_kgs": "0.1", "dlvry_rolls": 1}, {"id": 92, "dc_id": 12, "fabric_id": 101,
                "jobdia_id": 102, "dlvry_kgs": "0.2", "dlvry_rolls": 1}]}},
            {"id": "12", "companymas_id": "2", "job_no": "7", "dates": ["2024-03-31"], "numbers": ["0009"]},
            {("101", "102"): {("2", "7")}})

    def test_exact_parent_child_dates_numbers_and_decimal_quantities(self):
        p, e, owners = self.fixture()
        before = copy.deepcopy(p)
        r = validate_dc(p, e, owners)
        self.assertEqual(r["identity_status"], "passed")
        self.assertEqual(r["original_number"], "0009")
        self.assertEqual(r["date_observation_agreement"], "passed")
        self.assertEqual(r["number_observation_agreement"], "passed")
        self.assertTrue(all(c["status"] == "passed" for c in r["header_quantity_diagnostics"].values()))
        self.assertEqual(p, before)

    def test_cross_company_dimension_and_wrong_parent_never_corroborate(self):
        p, e, owners = self.fixture()
        owners[("101", "102")] = {("3", "7")}
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")
        p, e, owners = self.fixture()
        p["result"]["fabric_dia_details"][0]["dc_id"] = 13
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")

    def test_duplicate_child_ids_are_rejected(self):
        p, e, owners = self.fixture()
        p["result"]["fabric_dia_details"][1]["id"] = 91
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")

    def test_explicit_empty_availability_choice_is_not_a_persisted_event(self):
        p, e, owners = self.fixture()
        p["result"]["fabric_dia_details"].append({"id": "", "dc_id": "", "fabric_id": 101,
            "jobdia_id": 102, "dlvry_kgs": 0, "dlvry_rolls": 0})
        r = validate_dc(p, e, owners)
        self.assertEqual(r["identity_status"], "passed")
        self.assertEqual(len(r["persisted_children"]), 2)
        self.assertEqual(len(r["empty_availability_choices"]), 1)
        p["result"]["fabric_dia_details"][-1]["dlvry_kgs"] = None
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")

    def test_failed_response_cannot_supply_valid_shaped_header(self):
        p, e, owners = self.fixture()
        p["isLogin"] = False
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")

    def test_source_dates_and_numbers_are_not_repaired(self):
        p, e, owners = self.fixture()
        p["result"]["dc_date"] = "31/03/2024"
        self.assertEqual(validate_dc(p, e, owners)["identity_status"], "unknown")
        p, e, owners = self.fixture()
        p["result"]["dc_no"] = "9"
        self.assertEqual(validate_dc(p, e, owners)["number_observation_agreement"], "different")

    def test_null_control_and_nonpositive_eway_are_never_inferred_zero(self):
        p, e, owners = self.fixture()
        p["result"]["total_dlvry_kgs"] = None
        p["result"]["eway_id"] = "-2"
        r = validate_dc(p, e, owners)
        self.assertEqual(r["header_quantity_diagnostics"]["dlvry_kgs"]["status"], "unknown")
        self.assertEqual(r["eway_id_status"], "invalid_or_unproved")

    def test_bounded_driver_joins_finite_plan_and_exact_ledger_witness(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            reports, source = root / "reports", root / "source"
            reports.mkdir()
            source.mkdir()
            (source / "manifest.jsonl").write_text("")
            payload, expected, _ = self.fixture()
            documents = [
                ("unavailable-context.json", "knitpack/Subcontract/getJobInfos/88", {}, {"result": {"job": [], "fabs": []}}),
                ("context.json", "knitpack/Subcontract/getJobInfos/7", {}, {"result": {
                    "job": {"id": 7, "companymas_id": 2, "jobdate": "2024-01-01"},
                    "fabs": [{"id": 101, "jobmas_id": 7, "dias": [{"id": 102, "jobfabric_id": 101}]}]}}),
                ("native.json", "knitpack/fabricdelivery/getFabricdelivery/12", expected, payload),
                ("ledger.json", "print/ViewJobLedgerreport/template", {"id": 7}, {"root": {
                    "job": {"id": 7, "companymas_id": 2}, "deliveries": [{"id": 12, "dc_date": "2024-03-31",
                    "dc_no": "0009", "fabric_id": 101, "jobdia_id": 102, "dlvry_kgs": "0.3", "dlvry_rolls": 2}]}}),
            ]
            entries = []
            for name, path, filters, data in documents:
                raw = json.dumps(data).encode()
                (reports / name).write_bytes(raw)
                entries.append({"file": name, "path": path, "filters": filters, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
            plan = root / "plan.json"
            plan.write_text(json.dumps({"known_parent_count": 1, "already_captured": [], "reads": [{
                "expected": expected, "observed_original_dates": expected["dates"], "observed_numbers": expected["numbers"],
                "id_sources": [{"kind": "validated_job_ledger", "file": "reports/ledger.json", "sha256": entries[-1]["sha256"]}]}]}))
            invoices = root / "invoices.json"
            invoices.write_text('{"invoices":[]}')
            manifest = ("\n".join(json.dumps(e) for e in entries) + "\n").encode()
            result = audit(reports, source, manifest, plan, invoices, root / "details.jsonl")
            self.assertEqual(result["counts"]["native_parents"], 1)
            self.assertEqual(result["checks"]["validated_job_ledger_quantities"], {"passed": 2})
            self.assertEqual(result["checks"]["validated_job_ledger_dimension_quantities"], {"passed": 2})
            self.assertEqual(result["missing_native_parent_ids"], [])
            self.assertEqual(result["integrity_issues"], [])
            self.assertFalse(result["import_allowed"])
            native_entry = next(e for e in entries if e["file"] == "native.json")
            native_entry["filters"] = {"id": "12", "companymas_id": "2", "source_job_id": "7"}
            plan.write_text(json.dumps({"known_parent_count": 1, "reads": [], "already_captured": [
                {"file": "reports/native.json", "sha256": native_entry["sha256"]}]}))
            manifest = ("\n".join(json.dumps(e) for e in entries) + "\n").encode()
            result = audit(reports, source, manifest, plan, invoices, root / "earlier-details.jsonl")
            self.assertEqual(result["checks"]["identity"], {"passed": 1})


if __name__ == "__main__":
    unittest.main()
