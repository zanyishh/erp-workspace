"""Synthetic native invoice, child, and explicit voucher-link checks."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from audit_knitpack_native_invoices import audit, compare_party_business


class NativeInvoiceTests(unittest.TestCase):
    def test_duplicate_party_business_fields_exclude_only_identity_and_audit_metadata(self):
        left = {"id": "1", "party_name": "Example", "gstin": "SYNTHETIC", "bill_address1": "Example address", "updated_time": "old"}
        right = {**left, "id": "2", "updated_time": "new"}
        result = compare_party_business(left, right)
        self.assertTrue(result["exact_business_record_duplicate"])
        self.assertTrue(result["saved_gstin_equal"])
        self.assertFalse(result["merge_authorized"])
        right["tax_preference"] = "different"
        self.assertFalse(compare_party_business(left, right)["exact_business_record_duplicate"])

    def test_blank_party_fields_are_not_claimed_as_shared_business_identity(self):
        result = compare_party_business({"id": "1", "gstin": "", "party_name": "A"}, {"id": "2", "gstin": "", "party_name": "B"})
        self.assertIsNone(result["saved_gstin_equal"])
        self.assertIsNone(result["saved_billing_address_equal"])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def add(self, name, route, result, filters=None, is_login=True):
        raw = json.dumps({"result": result, "isLogin": is_login, "currentUserinfo": {"token": "PRIVATE"}}).encode()
        (self.folder / name).write_bytes(raw)
        with (self.folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"file": name, "path": route, "filters": filters, "bytes": len(raw),
                                    "sha256": hashlib.sha256(raw).hexdigest(), "retrieved_at_utc": "2026-11-14T00:00:00Z"}) + "\n")

    def header(self, family="regular", book="1"):
        return {"id": "10", "companymas_id": "1", "sec_acc": book, "party_id": "20", "invoice_date": "2026-11-14",
                "inv_date": "2026-11-14", "invoice_value": "0.3", "r_invoice_value": "0", "total_kgs": "0.3",
                "total_rolls_pcs": "2", "total_value": "0.3", "tax_lists": [], "invoice_add_less": [], "dc_details": [],
                "item_details": [], "tax_value": [], "party_name": "PRIVATE PARTY"}

    def voucher(self, kind="kpinvoice", book="1"):
        return {"id": "50", "companymas_id": "1", "sec_acc": book, "party_id": "20", "v_date": "2026-11-14",
                "acc_ref_type": kind, "acc_ref_code": "10", "amt": "0.3"}

    def result(self):
        value = audit(self.folder)
        self.assertFalse(value["import_allowed"])
        self.assertNotIn("PRIVATE", json.dumps(value))
        return value

    def test_explicit_link_preserves_book1_and_compares_original_date_party_amount(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("voucher.json", "accv2/accounts/getvoucher/50", self.voucher())
        link = self.result()["voucher_links"][0]
        self.assertEqual(link["status"], "passed")
        self.assertEqual(link["invoice_key"], ["regular", "1", "10", "1"])

    def test_module_namespace_prevents_general_regular_id_collision(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("general.json", "knitpack/general_invoice/getinvoice/10", self.header("general"))
        self.add("voucher.json", "accv2/accounts/getvoucher/50", self.voucher("kpgeninvoice"))
        value = self.result()
        self.assertEqual(len(value["invoices"]), 2)
        self.assertEqual(value["voucher_links"][0]["invoice_key"][0], "general")

    def test_child_parent_disagreement_is_not_repaired(self):
        value = self.header()
        value["tax_lists"] = [{"id": "60", "invoice_id": "99"}]
        self.add("invoice.json", "knitpack/inv/getinvoice/10", value)
        self.assertTrue(any(i["kind"] == "child_parent_or_id_conflict" for i in self.result()["identity_issues"]))

    def test_saved_dc_and_fabric_native_children_require_actual_ids(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("dc.json", "knitpack/inv/getUpdateDcJobinfoByJobNo/10", {"dcinfo": [
            {"invoice_id": "10", "dc_id": "30", "jobmas_id": "40", "dc_date": "2026-11-14", "dlvry_kgs": "0.3", "dlvry_rolls": "2"}]})
        self.add("fabric.json", "knitpack/inv/getFabDetail/30/10", {"samplerates": [{"invoice_id": "10", "jobmas_id": "40", "jobfabric_id": "41", "fabric_value": "0.3", "dc_list": [{"dc_id": "30", "dc_det_id": "31", "dlvry_kgs": "0.3"}]}]})
        value = self.result()["invoices"][0]
        self.assertEqual(value["saved_dc_children"]["status"], "passed")
        self.assertEqual(value["saved_fabric_children"]["status"], "passed")
        self.assertEqual(value["diagnostics"]["saved_dc_kgs_vs_header"]["status"], "passed")

    def test_missing_quantity_and_wrong_original_date_remain_unknown_or_different(self):
        inv = self.header(); inv["invoice_value"] = None
        self.add("invoice.json", "knitpack/inv/getinvoice/10", inv)
        voucher = self.voucher(); voucher["v_date"] = "2026-11-13"
        self.add("voucher.json", "accv2/accounts/getvoucher/50", voucher)
        link = self.result()["voucher_links"][0]
        self.assertEqual(link["amount"]["status"], "unknown")
        self.assertFalse(link["original_date_agrees"])
        self.assertNotEqual(link["status"], "passed")

    def test_different_company_or_book_is_not_joined_by_invoice_number(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header(book="0"))
        self.add("voucher.json", "accv2/accounts/getvoucher/50", self.voucher(book="1"))
        self.assertEqual(self.result()["voucher_links"][0]["status"], "unknown_missing_native_invoice")

    def test_general_item_total_uses_total_field_and_preserves_add_less_tax_tcs_stages(self):
        inv = self.header("general")
        inv.update(item_details=[{"id": "60", "inv_id": "10", "amount": "99", "total": "0.3"}],
                   total_item_val="0.3", nettotal_value="0.3", tax_total_value="0.1", grandtotal_value="0.4",
                   tcs_value="0.02", invoice_value="0.42")
        self.add("general.json", "knitpack/general_invoice/getinvoice/10", inv)
        controls = self.result()["invoices"][0]["diagnostics"]
        self.assertEqual(controls["item_total_vs_total_item_val"]["status"], "passed")
        self.assertEqual(controls["net_plus_tax_vs_grandtotal"]["status"], "passed")
        self.assertEqual(controls["grandtotal_plus_tcs_vs_invoice_value"]["status"], "passed")
        self.assertNotIn("item_total_vs_grandtotal_value", controls)

    def test_unproved_samplerate_invoice_field_does_not_override_native_dc_parent(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("dc.json", "knitpack/inv/getUpdateDcJobinfoByJobNo/10", {"dcinfo": [
            {"invoice_id": "10", "dc_id": "30", "jobmas_id": "40", "dc_date": "2026-11-14", "dlvry_kgs": "0.3", "dlvry_rolls": "2"}]})
        self.add("fabric.json", "knitpack/inv/getFabDetail/30/10", {"samplerates": [{"invoice_id": "999", "jobmas_id": "40", "jobfabric_id": "41", "fabric_value": "0.3", "dc_list": [{"dc_id": "30", "dc_det_id": "31", "dlvry_kgs": "0.3"}]}]})
        value = self.result()["invoices"][0]["saved_fabric_children"]
        self.assertEqual(value["status"], "passed")
        self.assertEqual(value["children"][0]["original_invoice_id_field"], "999")

    def test_cancelled_state_disagreement_cannot_pass_link_checks(self):
        inv = self.header(); inv["cancelled"] = "1"
        voucher = self.voucher(); voucher["cancelled"] = "0"
        self.add("invoice.json", "knitpack/inv/getinvoice/10", inv)
        self.add("voucher.json", "accv2/accounts/getvoucher/50", voucher)
        self.assertNotEqual(self.result()["voucher_links"][0]["status"], "passed")

    def test_party_id_json_representation_difference_is_not_a_conflict(self):
        inv = self.header(); voucher = self.voucher(); voucher["party_id"] = 20
        self.add("invoice.json", "knitpack/inv/getinvoice/10", inv)
        self.add("voucher.json", "accv2/accounts/getvoucher/50", voucher)
        self.assertTrue(self.result()["voucher_links"][0]["source_party_agrees"])

    def test_malformed_saved_child_is_unknown_without_zero_or_crash(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("dc.json", "knitpack/inv/getUpdateDcJobinfoByJobNo/10", {"dcinfo": [None]})
        self.assertEqual(self.result()["invoices"][0]["saved_dc_children"]["status"], "unknown")

    def test_multiple_vouchers_referencing_same_invoice_are_reported(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header())
        self.add("voucher.json", "accv2/accounts/getvoucher/50", self.voucher())
        other = self.voucher(); other["id"] = "51"
        self.add("other.json", "accv2/accounts/getvoucher/51", other)
        self.assertEqual(len(self.result()["reference_collisions"]), 1)

    def test_hash_valid_authentication_failure_does_not_create_native_invoice(self):
        self.add("invoice.json", "knitpack/inv/getinvoice/10", self.header(), is_login=False)
        self.assertEqual(self.result()["invoices"], [])


if __name__ == "__main__":
    unittest.main()
