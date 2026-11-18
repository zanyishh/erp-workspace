"""Synthetic source replay and aggregate backup/restore, preserving original ERP stock/GL."""
import gzip
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import frappe
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.knitting import api, domain


class RecoveryTests(fixtures.KnittingTests):
    def test_synthetic_import_crosswalk_and_fixture_backup_restore_preserve_stock_and_gl(self):
        if frappe.local.site != "native-test.localhost":
            raise RuntimeError("Refusing any non-test site")
        self.fixtures(mode="Owned")
        source_key = "synthetic-import-" + frappe.generate_hash(length=20)
        payload = {"job": self.job, "item": self.items["yarn"], "material_owner": "Owned", "quantity_kg": "100.000",
                   "warehouse": self.warehouse, "valuation_rate": "10.00", "source_lot": "SYNTHETIC-SOURCE-1"}
        version = str(frappe.db.get_value("Knitting Job", self.job, "modified"))
        first = api.command(fixtures.COMPANY, "receive_yarn", payload, source_key, version)
        replay = api.command(fixtures.COMPANY, "receive_yarn", payload, source_key, version)
        self.assertEqual(first, replay)
        lot = first["data"]["lot"]
        self.produce(lot)
        expected = api.snapshot(fixtures.COMPANY, self.job)["jobs"][0]["balances"]
        vouchers = [e.voucher_name for e in frappe.get_all("Knitting Event", filters={"job": self.job}, fields=["voucher_name"]) if e.voucher_name]
        gl = frappe.get_all("GL Entry", filters={"voucher_no": ["in", vouchers]}, fields=["name", "debit", "credit"], order_by="name")
        stock = frappe.get_all("Stock Ledger Entry", filters={"voucher_no": ["in", vouchers]}, fields=["name", "actual_qty", "stock_value_difference"], order_by="name")
        specs = [("Knitting Job", {"name": self.job}), ("Knitting Material Lot", {"name": lot}),
                 *[(kind, {"job": self.job}) for kind in ("Knitting Event", "Knitting Ledger Entry", "Knitting Roll", "Knitting QC", "Knitting Plan")]]
        bundle = {kind: frappe.db.get_values(kind, filters, "*", as_dict=True) for kind, filters in specs}
        encoded = frappe.as_json({"purpose": "synthetic-fixture", "site": frappe.local.site, "records": bundle}).encode()
        with TemporaryDirectory(prefix="knitting-recovery-") as folder:
            path = Path(folder) / "synthetic-fixture.json.gz"
            path.write_bytes(gzip.compress(encoded))
            for kind, filters in reversed(specs):
                frappe.db.delete(kind, filters)
            self.assertFalse(frappe.db.exists("Knitting Job", self.job))
            recovered = json.loads(gzip.decompress(path.read_bytes()))
            self.assertEqual(recovered["purpose"], "synthetic-fixture")
            with domain.permissions.service_write():
                for kind, _ in specs:
                    for row in recovered["records"][kind]:
                        frappe.get_doc({"doctype": kind, **row}).db_insert()
        self.assertEqual(api.snapshot(fixtures.COMPANY, self.job)["jobs"][0]["balances"], expected)
        self.assertEqual(api.command_status(fixtures.COMPANY, source_key), first)
        self.assertEqual(frappe.get_all("GL Entry", filters={"voucher_no": ["in", vouchers]}, fields=["name", "debit", "credit"], order_by="name"), gl)
        self.assertEqual(frappe.get_all("Stock Ledger Entry", filters={"voucher_no": ["in", vouchers]}, fields=["name", "actual_qty", "stock_value_difference"], order_by="name"), stock)

for name in list(vars(fixtures.KnittingTests)):
    if name.startswith("test_"):
        setattr(RecoveryTests, name, None)
