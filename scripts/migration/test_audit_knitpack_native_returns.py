import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from audit_knitpack_native_returns import ROUTE, audit, validate_native_return


class NativeReturnTests(unittest.TestCase):
    def payload(self):
        return {"mode": "success", "isLogin": True, "result": {
            "id": 12, "companymas_id": 2, "dc_date": "2024-03-31", "cancelled": "0",
            "total_net_kgs": "0.3", "total_gross_kgs": "0.5", "total_bags": 2, "total_cones": 3,
            "yarn_details": [
                {"id": 91, "item_id": 101, "yarnmas_id": 8, "net_kgs": "0.1", "gross_kgs": "0.2", "bags": 1, "cons": 1},
                {"id": 92, "item_id": 102, "yarnmas_id": 8, "net_kgs": "0.2", "gross_kgs": "0.3", "bags": 1, "cons": 2},
            ]}}

    def test_exact_decimal_controls_and_persisted_child_ids(self):
        result = validate_native_return(self.payload(), "12", "2")
        self.assertEqual(result["identity_status"], "passed")
        self.assertTrue(all(v["status"] == "passed" for v in result["quantity_controls"].values()))
        self.assertEqual(result["children"][0]["original_id"], 91)
        self.assertEqual(result["child_id_namespace"], "persisted_return_line_id_from_native_edit_save_contract")
        self.assertEqual(result["original_date"], "2024-03-31")

    def test_missing_control_is_unknown_and_zero_is_observed(self):
        p = self.payload()
        p["result"]["total_net_kgs"] = None
        p["result"]["total_bags"] = 0
        result = validate_native_return(p, "12", "2")
        self.assertEqual(result["quantity_controls"]["net_kgs"]["status"], "unknown")
        self.assertEqual(result["quantity_controls"]["bags"]["status"], "different")

    def test_failed_valid_shaped_payload_is_never_corroborated(self):
        for changes in ({"isLogin": False}, {"mode": "error"}, {"mode": "failed"},
                        {"rc_error": True}, {"mode": "Failure"}, {"mode": "ERROR"}):
            p = self.payload()
            p.update(changes)
            result = validate_native_return(p, "12", "2")
            self.assertEqual(result["identity_status"], "unknown")
            self.assertFalse(result["quantity_controls"])

    def test_parent_company_and_original_date_are_not_repaired(self):
        for field, value in (("id", 13), ("companymas_id", 3), ("dc_date", "31/03/2024")):
            p = self.payload()
            p["result"][field] = value
            self.assertEqual(validate_native_return(p, "12", "2")["identity_status"], "unknown")

    def test_missing_or_invalid_child_yarn_remains_unknown(self):
        for change in (None, {}, {"yarnmas_id": 0}):
            p = self.payload()
            p["result"]["yarn_details"][0] = change
            result = validate_native_return(p, "12", "2")
            self.assertEqual(result["identity_status"], "unknown")

    def test_duplicate_persisted_child_id_is_unknown(self):
        p = self.payload()
        p["result"]["yarn_details"][1]["id"] = 91
        before = copy.deepcopy(p)
        result = validate_native_return(p, "12", "2")
        self.assertEqual(result["identity_status"], "unknown")
        self.assertEqual(result["candidate_id_duplicates"], ["91"])
        self.assertEqual(result["child_id_namespace"], "persisted_return_line_id_from_native_edit_save_contract")
        self.assertEqual(p, before)

    def test_context_item_id_does_not_substitute_missing_persisted_id(self):
        p = self.payload()
        p["result"]["yarn_details"][0]["id"] = ""
        self.assertEqual(validate_native_return(p, "12", "2")["identity_status"], "unknown")

    def test_explicit_child_parent_conflict_is_not_overridden_by_containment(self):
        p = self.payload()
        p["result"]["yarn_details"][0]["yarn_dc_id"] = 99
        self.assertEqual(validate_native_return(p, "12", "2")["identity_status"], "unknown")

    def test_explicit_empty_new_line_context_is_preserved_but_not_a_persisted_event(self):
        p = self.payload()
        p["result"]["yarn_details"].append({"id": "", "yarn_dc_id": "", "item_id": 103,
            "yarnmas_id": 9, "bags": 0, "cons": 0, "net_kgs": "0.00", "gross_kgs": 0})
        result = validate_native_return(p, "12", "2")
        self.assertEqual(result["identity_status"], "passed")
        self.assertEqual(len(result["children"]), 2)
        self.assertEqual(len(result["empty_unpersisted_context_rows"]), 1)

    def archive(self, folder):
        native = self.payload()
        native["rc_session"] = "PRIVATE-SESSION"
        row = {"companymas_id": 2, "yarn_dc_id": 12, "dc_id": "12", "yarnmas_id": 8,
               "jobmas_id": 7, "id": 999, "dc_date": "2024-03-31", "cancelled": "0",
               "net_kgs": "0.3", "gross_kgs": "0.5", "bags": 2, "cons": 3}
        entries = []
        for filename, path, payload, filters in [
            ("native.json", ROUTE + "12", native, {"id": 12, "companymas_id": 2}),
            ("register.json", "print/getYarnReturnRegPrint/template", {"root": {"yarnreturns": [row]}}, {"companymas_id": 2}),
        ]:
            raw = json.dumps(payload).encode()
            (folder / filename).write_bytes(raw)
            entries.append({"file": filename, "path": path, "filters": filters, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
        return ("\n".join(json.dumps(e) for e in entries) + "\n").encode()

    def test_fixed_manifest_register_join_uses_explicit_parent_not_flattened_id(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            manifest = self.archive(folder)
            result = audit(folder, manifest)
            self.assertEqual(result["summary"]["register_overlap_controls"], {"passed": 4})
            self.assertEqual(result["summary"]["register_overlap_statuses"], {"passed": 1})
            self.assertEqual(result["coverage"]["2"]["register_parents_without_usable_native"], [])
            self.assertNotIn("PRIVATE-SESSION", json.dumps(result))
            self.assertFalse(result["import_allowed"])

    def test_changed_native_bytes_do_not_corroborate_register(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            manifest = self.archive(folder)
            (folder / "native.json").write_text("{}")
            result = audit(folder, manifest)
            self.assertEqual(result["selected_evidence_integrity"]["issues"], ["selected_file_hash_or_size_mismatch"])
            self.assertEqual(result["summary"]["register_overlap_statuses"], {"unknown": 1})
            self.assertEqual(result["coverage"]["2"]["register_parents_without_usable_native"], [["2", "12"]])


if __name__ == "__main__":
    unittest.main()
