"""Synthetic knitting scenarios; refuse any site other than the isolated test site."""
import importlib
import os
import unittest

import frappe

COMPANY = "ERP Knitting Verification"


def optional_module(name):
    try:
        return importlib.import_module(name)
    except ModuleNotFoundError as error:
        if error.name == name or name.startswith(error.name + "."):
            return None
        raise


class KnittingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("NATIVE_TEST_SITE", "native-test.localhost") != "native-test.localhost":
            raise RuntimeError("Knitting tests require native-test.localhost")
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site="native-test.localhost", sites_path=".")
        frappe.connect()
        frappe.set_user("Administrator")
        if not frappe.db.exists("Company", COMPANY):
            from erpnext.setup.setup_wizard.operations.install_fixtures import install_company
            install_company(frappe._dict(company_name=COMPANY, company_abbr="KTEST", currency="INR", country="India",
                chart_of_accounts="Standard", fy_start_date="2026-04-01", fy_end_date="2027-03-31", fiscal_year="2026-2027"))
        module = optional_module("erp_extensions.knitting.install")
        if module:
            module.install()
            for role, email in (("Knitting Operator", "knit-operator@example.invalid"),
                                ("Knitting Accountant", "knit-accountant@example.invalid")):
                if not frappe.db.exists("User", email):
                    frappe.get_doc({"doctype": "User", "email": email, "first_name": role,
                                    "send_welcome_email": 0, "roles": [{"role": role}]}).insert()
            frappe.db.commit()

    def setUp(self):
        frappe.set_user("Administrator")

    def tearDown(self):
        frappe.set_user("Administrator")
        frappe.db.rollback()

    @classmethod
    def tearDownClass(cls):
        frappe.destroy()

    def workspace(self):
        module = optional_module("erp_extensions.workspace")
        self.assertTrue(module and callable(getattr(module, "context", None)),
                        "Company-enabled industry context is not implemented")
        return module

    def enable(self, **settings):
        return self.workspace().configure(COMPANY, {"state": "Active", "shifts": ["A", "B"],
                                                    **settings})

    def test_general_context_keeps_core_without_enabling_knitting(self):
        workspace = self.workspace()
        workspace.configure(COMPANY, {"state": "Inactive"})
        result = workspace.context(COMPANY)
        self.assertEqual(result["company"], COMPANY)
        self.assertIn(COMPANY, [c["name"] for c in result["companies"]])
        self.assertEqual(result["capabilities"], [])
        self.assertFalse(result["knitting_enabled"])
        from erp_extensions import api
        self.assertTrue(any(t["name"] == "Sales Invoice" for t in api.catalog()["types"]))

    def test_operator_and_accountant_receive_different_capabilities(self):
        workspace = self.workspace()
        self.enable()
        frappe.set_user("knit-operator@example.invalid")
        operator = workspace.context(COMPANY)
        self.assertIn("production", operator["capabilities"])
        self.assertNotIn("billing", operator["capabilities"])
        self.assertNotIn("financial_read", operator["capabilities"])
        frappe.set_user("knit-accountant@example.invalid")
        accountant = workspace.context(COMPANY)
        self.assertIn("billing", accountant["capabilities"])
        self.assertIn("financial_read", accountant["capabilities"])
        self.assertNotIn("production", accountant["capabilities"])
        with self.assertRaises(frappe.PermissionError):
            workspace.configure(COMPANY, {"state": "Active"})

    def test_guest_unknown_company_and_disabled_pack_are_denied(self):
        workspace = self.workspace()
        self.enable()
        with self.assertRaises(frappe.PermissionError):
            workspace.context("Missing company")
        frappe.set_user("Guest")
        with self.assertRaises(frappe.PermissionError):
            workspace.context(COMPANY)
        frappe.set_user("Administrator")
        workspace.configure(COMPANY, {"state": "Inactive"})
        permissions = optional_module("erp_extensions.knitting.permissions")
        self.assertIsNotNone(permissions)
        with self.assertRaises(frappe.PermissionError):
            permissions.require(COMPANY, "production")

    def test_pack_revocation_is_rechecked_and_direct_generic_write_is_blocked(self):
        workspace = self.workspace()
        self.enable()
        permissions = importlib.import_module("erp_extensions.knitting.permissions")
        self.assertTrue(permissions.require(COMPANY, "production"))
        with self.assertRaises(frappe.PermissionError):
            frappe.get_doc({"doctype": "Knitting Job", "company": COMPANY,
                            "target_kg": "88.000"}).insert()
        workspace.configure(COMPANY, {"state": "Closing"})
        with self.assertRaises(frappe.PermissionError):
            permissions.require(COMPANY, "new_job")
        workspace.configure(COMPANY, {"state": "Inactive"})
        with self.assertRaises(frappe.PermissionError):
            permissions.require(COMPANY, "production")

    def test_operator_cannot_read_another_company(self):
        workspace = self.workspace()
        self.enable()
        permission = frappe.get_doc({"doctype": "User Permission", "user": "knit-operator@example.invalid",
                                     "allow": "Company", "for_value": COMPANY,
                                     "apply_to_all_doctypes": 1}).insert()
        frappe.set_user("knit-operator@example.invalid")
        self.assertEqual([c["name"] for c in workspace.context()["companies"]], [COMPANY])
        with self.assertRaises(frappe.PermissionError):
            workspace.context("ERP Evaluation")

    def test_schema_install_reloads_cached_guards(self):
        self.enable()
        install = importlib.import_module("erp_extensions.knitting.install")
        frappe.local.doc_events_hooks = {"*": {}}
        install.install()
        with self.assertRaises(frappe.PermissionError):
            frappe.get_doc({"doctype": "Knitting Job", "company": COMPANY}).insert()

    def test_foreign_permission_query_uses_requested_users_company_scope(self):
        self.enable()
        permissions = importlib.import_module("erp_extensions.knitting.permissions")
        frappe.get_doc({"doctype": "User Permission", "user": "knit-operator@example.invalid",
                        "allow": "Company", "for_value": COMPANY,
                        "apply_to_all_doctypes": 1}).insert()
        self.assertTrue(permissions.company_allowed(COMPANY, "knit-operator@example.invalid"))
        self.assertFalse(permissions.company_allowed("ERP Evaluation", "knit-operator@example.invalid"))

    def test_general_catalog_does_not_offer_inactive_industry_record_types(self):
        self.enable()
        from erp_extensions import api
        workspace = self.workspace()
        workspace.configure(COMPANY, {"state": "Inactive"})
        self.assertIn("company", __import__("inspect").signature(api.catalog).parameters,
                      "Native catalogue must use the selected business context")
        result = api.catalog(company=COMPANY)
        self.assertFalse(any(t["name"].startswith("Knitting ") for t in result["types"]))
        workspace.configure(COMPANY, {"state": "Active"})
        self.assertTrue(any(t["name"] == "Knitting Job" for t in api.catalog(company=COMPANY)["types"]))

    def knitting(self):
        module = optional_module("erp_extensions.knitting.api")
        self.assertTrue(module and callable(getattr(module, "command", None)),
                        "Transactional knitting commands are not implemented")
        return module

    def fixtures(self, mode="Customer", target="88.000", lycra_charge="Included"):
        suffix = frappe.generate_hash(length=8)
        group = frappe.db.get_value("Customer Group", {"is_group": 0}, "name")
        territory = frappe.db.get_value("Territory", {"is_group": 0}, "name")
        self.customer = frappe.get_doc({"doctype": "Customer", "customer_name": "Knit test " + suffix,
                                       "customer_type": "Company", "customer_group": group, "territory": territory}).insert().name
        if not frappe.db.exists("UOM", "Kg"):
            frappe.get_doc({"doctype": "UOM", "uom_name": "Kg", "must_be_whole_number": 0}).insert()
        group = frappe.db.get_value("Item Group", {"is_group": 0}, "name")
        self.items = {}
        for key, stock in (("yarn", 1), ("fabric", 1), ("lycra", 1), ("service", 0), ("material_charge", 0)):
            self.items[key] = frappe.get_doc({"doctype": "Item", "item_code": "KNIT-" + key + "-" + suffix,
                "item_name": "Synthetic knitting " + key, "item_group": group, "stock_uom": "Kg",
                "is_stock_item": stock, "is_sales_item": 1, "is_purchase_item": 1}).insert().name
        self.warehouse = frappe.db.get_value("Warehouse", {"company": COMPANY, "is_group": 0}, "name")
        self.enable(warehouse=self.warehouse, service_item=self.items["service"], fabric_item=self.items["fabric"],
                    lycra_charge=lycra_charge)
        self.job = self.call("create_job", {"customer": self.customer, "kind": "Order", "material_mode": mode,
            "target_kg": target, "rate": "100.00", "service_item": self.items["service"],
            "programme": [{"id": "P1", "fabric": "Single jersey", "colour": "Natural", "gsm": [180],
                           "ll": ["2.70"], "gauge": "24", "dia": "30", "knit_type": "Tubular",
                           "target_kg": target, "fabric_item": self.items["fabric"]}]})["data"]["job"]

    def call(self, action, values, request_id=None, modified=None):
        if values.get("job") and modified is None:
            modified = str(frappe.db.get_value("Knitting Job", values["job"], "modified"))
        return self.knitting().command(COMPANY, action, values, request_id or frappe.generate_hash(length=20), modified)

    def receive(self, kg="100.000", owner="Customer", item="yarn"):
        return self.call("receive_yarn", {"job": self.job, "item": self.items[item], "quantity_kg": kg,
            "material_owner": owner, "party": self.customer if owner == "Customer" else None,
            "warehouse": self.warehouse, "source_lot": "SYNTHETIC-LOT", "units": 2,
            "valuation_rate": "50.00" if item == "lycra" else "10.00"})["data"]["lot"]

    def produce(self, lot, inputs=None, weights=None):
        return self.call("produce", {"job": self.job, "programme_line": "P1", "shift": "A",
            "inputs": inputs or [{"lot": lot, "quantity_kg": "90.000"}],
            "loss_kg": "2.000", "weights_kg": weights or ["44.000", "44.000"],
            "warehouse": self.warehouse})["data"]["rolls"]

    def release(self, rolls):
        for roll in rolls:
            self.call("quality", {"job": self.job, "roll": roll, "decision": "Released", "remarks": "Synthetic check"})

    def test_customer_job_to_invoice_exact_balances_and_closure(self):
        self.knitting()
        self.fixtures()
        lot = self.receive()
        rolls = self.produce(lot)
        self.assertEqual(len(set(rolls)), 2)
        self.call("quality", {"job": self.job, "roll": rolls[1], "decision": "On Hold"})
        with self.assertRaises(frappe.ValidationError):
            self.call("deliver", {"job": self.job, "rolls": [rolls[1]]})
        self.release(rolls)
        deliveries = [self.call("deliver", {"job": self.job, "rolls": [roll]})["event"] for roll in rolls]
        self.call("return_yarn", {"job": self.job, "lot": lot, "quantity_kg": "5.000"})
        invoices = [self.call("invoice", {"job": self.job, "deliveries": [delivery]})["data"]["invoice"] for delivery in deliveries]
        for name in invoices:
            invoice = frappe.get_doc("Sales Invoice", name)
            self.assertEqual(invoice.docstatus, 1)
            self.assertEqual(invoice.grand_total, 4400)
            rows = frappe.get_all("GL Entry", filters={"voucher_no": name, "is_cancelled": 0}, fields=["debit", "credit"])
            self.assertAlmostEqual(sum(r.debit - r.credit for r in rows), 0)
        snapshot = self.knitting().snapshot(COMPANY)
        job = next(j for j in snapshot["jobs"] if j["name"] == self.job)
        self.assertEqual(job["balances"], {"received_kg": "100.000", "consumed_kg": "90.000", "returned_kg": "5.000",
            "yarn_kg": "5.000", "produced_kg": "88.000", "delivered_kg": "88.000", "billed_kg": "88.000",
            "fabric_kg": "0.000", "unbilled_kg": "0.000", "loss_kg": "2.000", "subcontract_kg": "0.000",
            "fabric_transfer_in_kg": "0.000", "fabric_transfer_out_kg": "0.000", "yarn_transfer_in_kg": "0.000", "yarn_transfer_out_kg": "0.000"})
        self.assertEqual(frappe.db.count("Stock Ledger Entry", {"item_code": self.items["yarn"]}), 0)
        with self.assertRaises(frappe.ValidationError):
            self.call("close_job", {"job": self.job})
        self.call("return_yarn", {"job": self.job, "lot": lot, "quantity_kg": "5.000"})
        self.workspace().configure(COMPANY, {"state": "Closing"})
        self.call("close_job", {"job": self.job})
        self.assertEqual(frappe.db.get_value("Knitting Job", self.job, "status"), "Completed")
        self.assertEqual(frappe.get_doc("Sales Invoice", invoices[0]).outstanding_amount, 4400)

    def test_idempotency_rejects_changed_payload_and_stale_source(self):
        self.knitting()
        self.fixtures()
        values = {"job": self.job, "item": self.items["yarn"], "quantity_kg": "100.000", "material_owner": "Customer",
                  "party": self.customer, "warehouse": self.warehouse}
        modified = str(frappe.db.get_value("Knitting Job", self.job, "modified"))
        first = self.call("receive_yarn", values, "synthetic-repeat", modified)
        self.assertEqual(self.call("receive_yarn", values, "synthetic-repeat", modified), first)
        with self.assertRaises(frappe.ValidationError):
            self.call("receive_yarn", {**values, "quantity_kg": "200.000"}, "synthetic-repeat", modified)
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call("receive_yarn", values, "synthetic-stale", modified)
        self.assertEqual(self.knitting().command_status(COMPANY, "synthetic-repeat"), first)
        self.assertEqual(frappe.db.count("Knitting Material Lot", {"company": COMPANY}), 1)

    def test_production_rejects_excess_nonfinite_and_overspending(self):
        self.knitting()
        self.fixtures()
        lot = self.receive()
        for weights, consumed, loss in ((["89.000"], "91.000", "2.000"), (["NaN"], "90.000", "2.000"),
                                        (["44.000", "44.000"], "101.000", "13.000")):
            with self.assertRaises(frappe.ValidationError):
                self.call("produce", {"job": self.job, "programme_line": "P1", "inputs": [{"lot": lot, "quantity_kg": consumed}],
                    "weights_kg": weights, "loss_kg": loss, "warehouse": self.warehouse, "shift": "A"})
        self.assertEqual(frappe.db.count("Knitting Roll", {"job": self.job}), 0)
        self.produce(lot)
        with self.assertRaises(frappe.ValidationError):
            self.produce(lot)

    def test_owned_material_posts_real_stock_and_fabric_invoice_once(self):
        self.knitting()
        self.fixtures(mode="Owned")
        lot = self.receive(owner="Owned")
        rolls = self.produce(lot)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["yarn"], "warehouse": self.warehouse}, "actual_qty"), 10)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["fabric"], "warehouse": self.warehouse}, "actual_qty"), 88)
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": [rolls[0]]})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", invoice["data"]["invoice"]).update_stock, 0)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["fabric"], "warehouse": self.warehouse}, "actual_qty"), 44)

    def test_mixed_lycra_separate_charge_does_not_issue_stock_twice(self):
        self.knitting()
        self.fixtures(target="90.000", lycra_charge="Separate")
        yarn = self.receive("90.000")
        lycra = self.receive("2.000", "Owned", "lycra")
        rolls = self.produce(yarn, [{"lot": yarn, "quantity_kg": "90.000"},
                                  {"lot": lycra, "quantity_kg": "2.000", "charge_item": self.items["material_charge"], "charge_rate": "50.00"}],
                             ["45.000", "45.000"])
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", invoice["data"]["invoice"]).grand_total, 9100)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["lycra"], "warehouse": self.warehouse}, "actual_qty"), 0)
        self.assertEqual(frappe.db.count("Stock Ledger Entry", {"item_code": self.items["lycra"], "is_cancelled": 0}), 2)

    def test_failed_production_rolls_back_event_and_custody(self):
        self.knitting()
        self.fixtures()
        lot = self.receive()
        before = frappe.db.count("Knitting Event", {"company": COMPANY})
        with self.assertRaises(frappe.ValidationError):
            self.call("produce", {"job": self.job, "programme_line": "P1", "inputs": [{"lot": lot, "quantity_kg": "90.000"}],
                                  "weights_kg": ["44.000", "44.000"], "loss_kg": "1.000", "warehouse": self.warehouse})
        self.assertEqual(frappe.db.count("Knitting Event", {"company": COMPANY}), before)
        self.assertEqual(frappe.db.count("Knitting Roll", {"job": self.job}), 0)
        self.assertEqual(self.knitting().snapshot(COMPANY)["jobs"][0]["balances"]["yarn_kg"], "100.000")

    def test_invoice_cancel_restores_billable_quantity_and_protects_standard_source(self):
        self.knitting()
        self.fixtures()
        lot = self.receive()
        rolls = self.produce(lot)
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": [rolls[0]]})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        doc = frappe.get_doc("Sales Invoice", invoice["data"]["invoice"])
        with self.assertRaises(frappe.PermissionError):
            doc.cancel()
        self.call("cancel_event", {"job": self.job, "event": invoice["event"], "reason": "Synthetic correction"})
        self.assertEqual(frappe.db.get_value("Sales Invoice", doc.name, "docstatus"), 2)
        replacement = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", replacement["data"]["invoice"]).grand_total, 4400)

    def test_general_allocation_repack_and_job_transfer_conserve_owner_and_kg(self):
        self.knitting()
        self.fixtures()
        lot = self.call("receive_yarn", {"item": self.items["yarn"], "quantity_kg": "100.000", "material_owner": "Customer",
            "party": self.customer, "warehouse": self.warehouse})["data"]["lot"]
        self.call("allocate_yarn", {"job": self.job, "lot": lot, "quantity_kg": "100.000"})
        transformed = self.call("repack_yarn", {"job": self.job, "lot": lot, "input_kg": "10.000",
            "output_kg": "9.500", "loss_kg": "0.500", "output_units": 10})["data"]["lot"]
        target = self.call("create_job", {"customer": self.customer, "target_kg": "10.000", "rate": "100.00",
            "programme": [{"id": "P1", "target_kg": "10.000", "fabric_item": self.items["fabric"]}]})["data"]["job"]
        self.call("transfer_yarn", {"job": self.job, "lot": transformed, "target_job": target,
            "target_modified": str(frappe.db.get_value("Knitting Job", target, "modified")), "quantity_kg": "5.000"})
        snapshot = self.knitting().snapshot(COMPANY)
        values = {j["name"]: j["balances"]["yarn_kg"] for j in snapshot["jobs"]}
        self.assertEqual(values[self.job], "94.500")
        self.assertEqual(values[target], "5.000")
        self.assertEqual(frappe.db.get_value("Knitting Material Lot", transformed, "party"), self.customer)

    def test_roll_split_preserves_total_and_delivery_rate_is_frozen(self):
        self.knitting()
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        split = self.call("split_roll", {"job": self.job, "roll": rolls[0], "weights_kg": ["20.000", "24.000"],
                                        "reason": "Synthetic packing split"})["data"]["rolls"]
        delivery = self.call("deliver", {"job": self.job, "rolls": split})
        self.call("revise_job", {"job": self.job, "rate": "150.00", "reason": "New commercial rate for later deliveries"})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", invoice["data"]["invoice"]).grand_total, 4400)
        self.assertEqual(frappe.db.get_value("Knitting Roll", rolls[0], "state"), "Split")
        self.assertEqual(self.knitting().snapshot(COMPANY)["jobs"][0]["balances"]["produced_kg"], "88.000")

    def test_operator_cannot_read_or_inject_financial_production_values(self):
        self.knitting()
        self.fixtures()
        yarn = self.receive()
        production = self.call("produce", {"job": self.job, "programme_line": "P1", "inputs": [{"lot": yarn, "quantity_kg": "90.000"}],
            "weights_kg": ["44.000", "44.000"], "loss_kg": "2.000", "warehouse": self.warehouse})
        self.call("revise_job", {"job": self.job, "rate": "150.00", "reason": "Synthetic commercial revision"})
        frappe.set_user("knit-operator@example.invalid")
        snapshot = self.knitting().snapshot(COMPANY)
        self.assertNotIn("rate", snapshot["jobs"][0])
        self.assertFalse(any(e["kind"] == "revise_job" for e in snapshot["events"]))
        from erp_extensions import api
        self.assertIsNone(api.document("Knitting Event", production["event"])["doc"].get("payload"))
        with self.assertRaises(frappe.PermissionError):
            self.call("produce", {"job": self.job, "programme_line": "P1", "inputs": [{"lot": yarn, "quantity_kg": "1.000",
                "charge_item": self.items["material_charge"], "charge_rate": "999.00"}], "weights_kg": ["1.000"],
                "loss_kg": "0.000", "warehouse": self.warehouse})

    def machine(self):
        return self.call("create_machine", {"title": "Synthetic circular machine", "dia": "30", "gauge": "24",
            "knit_type": "Tubular", "capacity_kg": "120.000"})["data"]["machine"]

    def test_planning_blocks_holidays_overlap_and_incompatible_machine(self):
        self.fixtures()
        machine = self.machine()
        self.call("holiday", {"machine": machine, "date": "2026-11-14", "description": "Synthetic shutdown"})
        plan = {"job": self.job, "machine": machine, "programme_line": "P1", "quantity_kg": "88.000",
                "starts_at": "2026-11-13 08:00:00", "ends_at": "2026-11-13 16:00:00"}
        created = self.call("plan", plan)["data"]["plan"]
        with self.assertRaises(frappe.ValidationError):
            self.call("plan", plan)
        with self.assertRaises(frappe.ValidationError):
            self.call("plan", {**plan, "starts_at": "2026-11-14 08:00:00", "ends_at": "2026-11-14 16:00:00"})
        bad = self.call("create_machine", {"title": "Incompatible", "dia": "20", "gauge": "18", "knit_type": "Tubular", "capacity_kg": "120.000"})["data"]["machine"]
        with self.assertRaises(frappe.ValidationError):
            self.call("plan", {**plan, "machine": bad})
        self.call("plan", {**plan, "plan": created, "plan_modified": str(frappe.db.get_value("Knitting Plan", created, "modified")),
                           "starts_at": "2026-11-13 16:00:00", "ends_at": "2026-11-14 00:00:00"})
        self.assertEqual(str(frappe.db.get_value("Knitting Plan", created, "starts_at")), "2026-11-13 16:00:00")

    def supplier(self):
        return frappe.get_doc({"doctype": "Supplier", "supplier_name": "Synthetic SC " + frappe.generate_hash(length=7),
            "supplier_type": "Company", "supplier_group": frappe.db.get_value("Supplier Group", {}, "name")}).insert().name

    def subcontract_cycle(self, owned=False):
        self.fixtures(mode="Owned" if owned else "Customer")
        lot = self.receive(owner="Owned" if owned else "Customer")
        sc = self.call("create_subcontract", {"job": self.job, "supplier": self.supplier(), "target_kg": "88.000", "rate": "50.00"})["data"]["subcontract"]
        self.call("subcontract_issue", {"job": self.job, "subcontract": sc, "lot": lot, "quantity_kg": "100.000"})
        produced = self.call("subcontract_receive", {"job": self.job, "subcontract": sc, "programme_line": "P1",
            "inputs": [{"lot": lot, "quantity_kg": "90.000"}], "loss_kg": "2.000", "weights_kg": ["44.000", "44.000"],
            "warehouse": self.warehouse})
        with self.assertRaises(frappe.ValidationError):
            self.call("close_subcontract", {"job": self.job, "subcontract": sc})
        self.call("subcontract_return", {"job": self.job, "subcontract": sc, "lot": lot, "quantity_kg": "10.000"})
        bill = self.call("subcontract_bill", {"job": self.job, "subcontract": sc})["data"]["invoice"]
        self.assertEqual(frappe.get_doc("Purchase Invoice", bill).grand_total, 4400)
        self.call("close_subcontract", {"job": self.job, "subcontract": sc})
        self.assertEqual(frappe.db.get_value("Knitting Subcontract", sc, "status"), "Completed")
        self.assertEqual(self.knitting().snapshot(COMPANY)["jobs"][0]["balances"]["subcontract_kg"], "0.000")
        self.assertEqual(next(s for s in self.knitting().snapshot(COMPANY)["subcontracts"] if s["name"] == sc)["status"], "Completed")
        return produced

    def test_customer_subcontract_roundtrip_bill_and_custody_close(self):
        self.subcontract_cycle()
        self.assertEqual(self.knitting().snapshot(COMPANY)["jobs"][0]["balances"]["yarn_kg"], "10.000")

    def test_owned_subcontract_includes_agreed_service_in_fabric_valuation(self):
        self.subcontract_cycle(owned=True)
        value = frappe.db.get_value("Bin", {"item_code": self.items["fabric"], "warehouse": self.warehouse}, "stock_value")
        self.assertAlmostEqual(value, 5300, places=2)

    def test_component_usage_replacement_stoppage_and_consumable_return(self):
        self.fixtures()
        machine = self.machine()
        component = self.call("create_component", {"machine": machine, "component_type": "Needle", "boundary_kg": "100.000"})["data"]["component"]
        lot = self.receive()
        self.call("produce", {"job": self.job, "programme_line": "P1", "machine": machine,
            "inputs": [{"lot": lot, "quantity_kg": "90.000"}], "weights_kg": ["44.000", "44.000"], "loss_kg": "2.000", "warehouse": self.warehouse})
        self.assertEqual(frappe.db.get_value("Knitting Component", component, "run_kg"), "88.000")
        self.call("replace_component", {"machine": machine, "component": component, "reason": "Synthetic planned replacement"})
        self.assertEqual(frappe.db.get_value("Knitting Component", component, "run_kg"), "0.000")
        self.assertEqual(next(c for c in self.knitting().snapshot(COMPANY)["components"] if c["name"] == component)["remaining_kg"], "100.000")
        self.call("stoppage", {"machine": machine, "starts_at": "2026-11-13 10:00:00", "ends_at": "2026-11-13 10:30:00", "reason": "Needle replacement"})
        material = self.receive("5.000", "Owned", "lycra")
        issue = self.call("issue_consumable", {"job": self.job, "lot": material, "item": self.items["lycra"],
            "quantity": "2.000", "warehouse": self.warehouse, "machine": machine, "reason": "Synthetic use"})
        self.call("return_consumable", {"job": self.job, "event": issue["event"], "quantity": "1.000", "reason": "Unused"})
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["lycra"], "warehouse": self.warehouse}, "actual_qty"), 4)

    def test_estimate_has_no_posting_and_converts_trusted_quote_once(self):
        self.fixtures()
        estimate = self.call("create_estimate", {"customer": self.customer, "target_kg": "10.000", "rate": "120.00",
            "programme": [{"id": "P1", "target_kg": "10.000", "fabric_item": self.items["fabric"]}],
            "service_item": self.items["service"]})["data"]["quotation"]
        quote = frappe.get_doc("Quotation", estimate)
        self.assertEqual(quote.docstatus, 0)
        self.assertEqual(quote.grand_total, 1200)
        self.assertEqual(frappe.db.count("GL Entry", {"voucher_no": quote.name}), 0)
        accepted = self.call("accept_estimate", {"quotation": quote.name, "quotation_modified": str(quote.modified)})["data"]
        created = self.call("job_from_estimate", {"quotation": quote.name, "quotation_modified": accepted["modified"]})["data"]["job"]
        self.assertEqual(frappe.db.get_value("Knitting Job", created, "quotation"), quote.name)
        with self.assertRaises(frappe.ValidationError):
            self.call("job_from_estimate", {"quotation": quote.name, "quotation_modified": accepted["modified"]})

    def test_rate_lookup_by_fabric_count_gauge_prices_programme_lines_separately(self):
        self.fixtures()
        self.enable(rate_lookup="FabricCountGauge")
        for count, rate in (("20", "100.00"), ("30", "120.00")):
            self.call("create_rate", {"customer": self.customer, "fabric": "Single jersey", "yarn_count": count,
                "gauge": "24", "rate": rate, "effective_from": "2026-01-01"})
        lines = [{"id": "P1", "fabric": "Single jersey", "yarn_count": "20", "gauge": "24", "target_kg": "18.000", "fabric_item": self.items["fabric"]},
                 {"id": "P2", "fabric": "Single jersey", "yarn_count": "30", "gauge": "24", "target_kg": "70.000", "fabric_item": self.items["fabric"]}]
        self.call("revise_job", {"job": self.job, "programme": lines, "refresh_rates": True, "reason": "Apply agreed party rates"})
        lot = self.receive()
        rolls = []
        for line, used, loss in (("P1", "20.000", "2.000"), ("P2", "70.000", "0.000")):
            result = self.call("produce", {"job": self.job, "programme_line": line, "inputs": [{"lot": lot, "quantity_kg": used}],
                "weights_kg": ["18.000" if line == "P1" else "70.000"], "loss_kg": loss, "warehouse": self.warehouse})
            rolls.extend(result["data"]["rolls"])
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", invoice["data"]["invoice"]).grand_total, 10200)

    def test_number_prefix_and_restricted_event_results(self):
        self.fixtures()
        self.enable(number_prefix="DEMO")
        created = self.call("create_job", {"customer": self.customer, "target_kg": "1.000", "rate": "25.00",
            "programme": [{"id": "P1", "target_kg": "1.000"}]})
        self.assertTrue(created["data"]["job"].startswith("DEMO-"))
        self.assertNotEqual(created["data"]["job"], self.job)
        lot = self.receive()
        event = self.call("produce", {"job": self.job, "programme_line": "P1", "inputs": [{"lot": lot, "quantity_kg": "90.000"}],
            "weights_kg": ["44.000", "44.000"], "loss_kg": "2.000", "warehouse": self.warehouse})
        frappe.set_user("knit-operator@example.invalid")
        from erp_extensions import api
        self.assertIsNone(api.document("Knitting Event", event["event"])["doc"].get("result"))
        self.assertEqual(next(e for e in self.knitting().snapshot(COMPANY)["events"] if e["name"] == event["event"])["result"]["quantity_kg"], "88.000")


    def test_setup_validates_scoped_defaults_and_stale_policy_revision(self):
        self.fixtures()
        before = self.workspace().context(COMPANY)
        with self.assertRaises(frappe.ValidationError):
            self.workspace().configure(COMPANY, {"state": "Active", "allow_production_excess_pct": "NaN"})
        with self.assertRaises(frappe.ValidationError):
            self.workspace().configure(COMPANY, {"state": "Active", "revision": before["revision"] - 1})
        with self.assertRaises(frappe.ValidationError):
            self.workspace().configure(COMPANY, {"state": "Active", "service_item": self.items["yarn"]})

    def test_scoped_selector_is_bounded_and_never_accepts_arbitrary_types(self):
        self.fixtures()
        api = self.knitting()
        self.assertEqual(api.lookup(COMPANY, "Job", self.job)["rows"][0]["name"], self.job)
        with self.assertRaises(frappe.ValidationError):
            api.lookup(COMPANY, "User", "")
        with self.assertRaises(frappe.PermissionError):
            api.lookup("Another business", "Job", "")
        with self.assertRaises(frappe.ValidationError):
            api.lookup(COMPANY, "Job", "", -1)

    def test_operational_reports_reconcile_asof_period_and_financial_scope(self):
        self.fixtures()
        lot = self.receive()
        rolls = self.produce(lot)
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        api = self.knitting()
        self.assertTrue(callable(getattr(api, "report", None)), "Operational reporting is not implemented")
        filters = {"job": self.job, "mode": "as_of", "to_date": "2026-11-13"}
        report = api.report(COMPANY, "jobs", filters)
        row = report["rows"][0]
        self.assertEqual(row["yarn_kg"], "10.000")
        self.assertEqual(row["billed_kg"], "88.000")
        grouped = api.report(COMPANY, "production", {**filters, "group_by": "operator"})
        self.assertEqual(grouped["rows"][0]["quantity_kg"], "88.000")
        self.assertEqual(grouped["rows"][0]["operator"], "Administrator")
        self.assertEqual(api.report(COMPANY, "activity", {**filters, "kind": "receive_yarn"})["row_count"], 1)
        self.assertEqual(api.report(COMPANY, "yarn", filters)["summary"]["quantity_kg"], "10.000")
        for name in ("fabric", "rolls", "planning", "production", "quality", "subcontract", "components", "stoppage", "billing", "margin"):
            result = api.report(COMPANY, name, filters)
            self.assertIn("columns", result)
            self.assertIn("rows", result)
        empty = api.report(COMPANY, "production", {**filters, "mode": "period", "from_date": "2026-01-01", "to_date": "2026-01-02"})
        self.assertEqual(empty["summary"]["quantity_kg"], "0.000")
        frappe.set_user("knit-operator@example.invalid")
        with self.assertRaises(frappe.PermissionError):
            api.report(COMPANY, "margin", filters)
        with self.assertRaises(frappe.PermissionError):
            api.export(COMPANY, "csv", {**filters, "report": "jobs"})

    def test_exports_are_deterministic_escaped_and_roll_print_is_valid_pdf(self):
        self.fixtures()
        lot = self.receive()
        rolls = self.produce(lot)
        api = self.knitting()
        self.assertTrue(callable(getattr(api, "export", None)), "Knitting export is not implemented")
        import base64
        value = api.export(COMPANY, "csv", {"report": "jobs", "job": self.job})
        text = base64.b64decode(value["content"]).decode("utf-8-sig")
        self.assertIn(self.job, text)
        self.assertIn("10.000", text)
        self.assertEqual(value, api.export(COMPANY, "csv", {"report": "jobs", "job": self.job}))
        pdf = api.export(COMPANY, "roll_label", {"roll": rolls[0]})
        self.assertTrue(base64.b64decode(pdf["content"]).startswith(b"%PDF-"))
        for kind in ("gst_review", "tally_review"):
            export = api.export(COMPANY, kind, {"job": self.job})
            self.assertTrue(base64.b64decode(export["content"]))
        from erp_extensions.knitting.exports import safe_cell, fiscal_token, roll_token
        self.assertEqual(safe_cell("=1+1"), "'=1+1")
        self.assertEqual(fiscal_token("2026-04-01"), "2026-27")
        self.assertEqual(fiscal_token("2026-03-31"), "2025-26")
        self.assertEqual(roll_token(self.job, "P1", "44.000"), self.job + "|P1|44.000kg")

    def test_native_source_drilldowns_do_not_offer_forbidden_generic_actions(self):
        self.fixtures()
        from erp_extensions import api as native
        result = native.document("Knitting Job", self.job)
        for action in ("write", "create", "submit", "cancel", "amend"):
            self.assertFalse(result["permissions"].get(action))
        record = next(t for t in native.catalog(company=COMPANY)["types"] if t["name"] == "Knitting Job")
        self.assertFalse(record["create"])

    def test_review_export_golden_contracts(self):
        from pathlib import Path
        from erp_extensions.knitting.exports import gst_review, tally_review
        row = {"invoice": "SYNTH-INV-1", "posting_date": "2026-11-13", "currency": "INR", "net_amount": "100.00", "tax_amount": "18.00", "grand_total": "118.00"}
        folder = Path(__file__).parent / "golden"
        self.assertEqual(gst_review("Synthetic Mills", [row]), (folder / "gst-review.json").read_text().strip())
        self.assertEqual(tally_review("Synthetic Mills", [row]), (folder / "tally-review.xml").read_text().strip())

    def test_asof_roll_state_uses_correction_time_and_keeps_prior_decision(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        hold = self.call("quality", {"job": self.job, "roll": rolls[0], "decision": "On Hold"})
        release = self.call("quality", {"job": self.job, "roll": rolls[0], "decision": "Released"})
        for row in frappe.get_all("Knitting Event", filters={"job": self.job}, fields=["name", "kind"]):
            stamp = "2026-11-10 10:00:00"
            if row.name == hold["event"]:
                stamp = "2026-11-11 10:00:00"
            if row.name == release["event"]:
                stamp = "2026-11-12 10:00:00"
            frappe.db.set_value("Knitting Event", row.name, "occurred_at", stamp, update_modified=False)
        for roll in rolls:
            frappe.db.set_value("Knitting Roll", roll, "produced_at", "2026-11-10 10:00:00", update_modified=False)
        correction = self.call("cancel_event", {"job": self.job, "event": release["event"], "reason": "Synthetic correction timing"})
        frappe.db.set_value("Knitting Event", correction["event"], "occurred_at", "2026-11-13 10:00:00", update_modified=False)
        api = self.knitting()
        for day, state in (("2026-11-10", "Awaiting QC"), ("2026-11-11", "On Hold"), ("2026-11-12", "Released"), ("2026-11-13", "On Hold")):
            result = api.report(COMPANY, "rolls", {"job": self.job, "to_date": day})
            row = next(r for r in result["rows"] if r["name"] == rolls[0])
            self.assertEqual(row["state"], state)

    def test_bulk_production_is_atomic_and_correction_restores_custody(self):
        self.fixtures(target="88.000")
        lot = self.receive()
        row = {"programme_line": "P1", "weights_kg": ["44.000"], "inputs": [{"lot": lot, "quantity_kg": "45.000"}], "loss_kg": "1.000", "warehouse": self.warehouse}
        result = self.call("produce_bulk", {"job": self.job, "entries": [row, row]})
        self.assertEqual(result["data"]["quantity_kg"], "88.000")
        self.assertEqual(len(result["data"]["rolls"]), 2)
        self.call("cancel_event", {"job": self.job, "event": result["event"], "reason": "Wrong roll weights in synthetic entry"})
        value = self.knitting().snapshot(COMPANY, self.job)["jobs"][0]["balances"]
        self.assertEqual(value["yarn_kg"], "100.000")
        self.assertEqual(value["produced_kg"], "0.000")
        before = frappe.db.count("Knitting Event")
        with self.assertRaises(frappe.ValidationError):
            self.call("produce_bulk", {"job": self.job, "entries": [row, {**row, "weights_kg": ["45.000"]}]})
        self.assertEqual(frappe.db.count("Knitting Event"), before)
        self.assertEqual(self.knitting().snapshot(COMPANY, self.job)["jobs"][0]["balances"]["yarn_kg"], "100.000")

    def test_reviewed_stock_adjustment_and_industry_masters_are_scoped(self):
        self.fixtures()
        lot = self.receive()
        self.call("adjust_yarn", {"job": self.job, "lot": lot, "quantity_kg": "-1.000", "reason": "Synthetic physical count"})
        self.assertEqual(self.knitting().snapshot(COMPANY, self.job)["jobs"][0]["balances"]["yarn_kg"], "99.000")
        self.call("save_master", {"category": "QC defect", "title": "Needle line", "settings": {"severity": "Major"}})
        masters = self.knitting().lookup(COMPANY, "Master", "Needle line")["rows"]
        self.assertEqual(masters[0]["title"], "Needle line")
        frappe.set_user("knit-operator@example.invalid")
        with self.assertRaises(frappe.PermissionError):
            self.call("adjust_yarn", {"job": self.job, "lot": lot, "quantity_kg": "1.000", "reason": "Not authorised"})

    def test_fabric_transfer_keeps_owner_requires_reinspection_and_reconciles_both_jobs(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        original = frappe.get_doc("Knitting Job", self.job)
        target = self.call("create_job", {"customer": self.customer, "target_kg": "88.000", "material_mode": "Customer", "rate": "100.00", "programme": frappe.parse_json(original.programme)})["data"]["job"]
        result = self.call("transfer_fabric", {"job": self.job, "target_job": target, "target_modified": str(frappe.db.get_value("Knitting Job", target, "modified")), "target_programme_line": "P1", "rolls": rolls, "reason": "Synthetic order reassignment"})
        snap = self.knitting().snapshot(COMPANY, target)["jobs"][0]
        self.assertEqual(snap["balances"]["fabric_transfer_in_kg"], "88.000")
        self.assertEqual(snap["balances"]["fabric_kg"], "88.000")
        self.assertEqual(frappe.db.get_value("Knitting Roll", rolls[0], "state"), "Awaiting QC")
        with self.assertRaises(frappe.ValidationError):
            self.call("produce", {"job": self.job, "programme_line": "P1", "weights_kg": ["1.000"], "inputs": [{"lot": frappe.db.get_value("Knitting Material Lot", {"company": COMPANY, "party": self.customer}, "name"), "quantity_kg": "1.000"}], "loss_kg": "0.000", "warehouse": self.warehouse})
        with self.assertRaises(frappe.ValidationError):
            self.call("cancel_event", {"job": self.job, "event": frappe.db.get_value("Knitting Roll", rolls[0], "production"), "reason": "Transferred roll depends on production"})
        report = self.knitting().report(COMPANY, "jobs", {"job": target})
        self.assertEqual(report["rows"][0]["fabric_kg"], "88.000")
        self.call("cancel_event", {"job": self.job, "event": result["event"], "reason": "Undo reassignment before inspection"})
        self.assertEqual(frappe.db.get_value("Knitting Roll", rolls[0], "job"), self.job)

    def test_machine_progress_replan_and_production_correction_remain_consistent(self):
        from frappe.utils import add_days, now_datetime
        self.fixtures()
        lot = self.receive()
        machine = self.call("create_machine", {"title": "Progress test", "dia": "30", "gauge": "24", "knit_type": "Tubular", "capacity_kg": "200.000"})["data"]["machine"]
        starts = add_days(now_datetime(), 2)
        plan = self.call("plan", {"job": self.job, "programme_line": "P1", "machine": machine, "starts_at": str(starts), "ends_at": str(add_days(starts, 1)), "quantity_kg": "88.000", "required_yarn_kg": "90.000"})["data"]["plan"]
        production = self.call("produce", {"job": self.job, "programme_line": "P1", "machine": machine, "weights_kg": ["44.000", "44.000"], "inputs": [{"lot": lot, "quantity_kg": "90.000"}], "loss_kg": "2.000", "warehouse": self.warehouse})
        record = frappe.get_doc("Knitting Plan", plan)
        self.assertEqual(record.state, "Completed")
        self.assertEqual(record.produced_kg, "88.000")
        with self.assertRaises(frappe.ValidationError):
            self.call("plan", {"job": self.job, "programme_line": "P1", "machine": machine, "starts_at": str(add_days(starts, 3)), "ends_at": str(add_days(starts, 4)), "quantity_kg": "1.000"})
        self.call("cancel_event", {"job": self.job, "event": production["event"], "reason": "Correct synthetic production"})
        self.assertEqual(frappe.db.get_value("Knitting Plan", plan, "state"), "Planned")
        self.assertEqual(frappe.db.get_value("Knitting Plan", plan, "produced_kg"), "0.000")

    def test_source_invoice_keeps_native_payment_action_and_partial_credit_reopens_only_credited_kg(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        from erp_extensions import api as native
        source = native.document("Sales Invoice", invoice["data"]["invoice"])
        self.assertIn("Payment Entry", source["related_actions"])
        self.assertNotIn("Duplicate", source["related_actions"])
        credit = self.call("credit_invoice", {"job": self.job, "invoice_event": invoice["event"], "quantity_kg": "44.000", "reason": "Synthetic partial credit"})
        self.assertEqual(credit["data"]["amount"], "-4400.00")
        self.assertEqual(self.knitting().snapshot(COMPANY, self.job)["jobs"][0]["balances"]["unbilled_kg"], "44.000")
        with self.assertRaises(frappe.ValidationError):
            self.call("credit_invoice", {"job": self.job, "invoice_event": invoice["event"], "quantity_kg": "45.000", "reason": "Over credit"})
        self.call("return_fabric", {"job": self.job, "delivery": delivery["event"], "rolls": [rolls[0]], "reason": "Synthetic fabric return"})
        balances = self.knitting().snapshot(COMPANY, self.job)["jobs"][0]["balances"]
        self.assertEqual(balances["fabric_kg"], "44.000")
        self.assertEqual(balances["unbilled_kg"], "0.000")
        self.assertTrue(frappe.get_doc("Sales Invoice", credit["data"]["invoice"]).is_return)

    def test_knitting_invoice_native_payment_settles_receivable_through_original_controller(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})["data"]["invoice"]
        from erp_extensions import api as native
        source = frappe.get_doc("Sales Invoice", invoice)
        mapped = native.new_from("Sales Invoice", invoice, "Payment Entry", str(source.modified))
        values = mapped["doc"]
        cash = frappe.db.get_value("Account", {"company": COMPANY, "account_type": "Cash", "is_group": 0}, "name")
        values.update(paid_to=cash, paid_to_account_currency="INR", reference_no="SYNTHETIC-PAYMENT", reference_date=frappe.utils.today())
        def payload(schema, data):
            result = {k: data[k] for k in ("doctype", "name", "modified", "__islocal", "__native_origin") if k in data}
            for field in schema["fields"]:
                key = field["fieldname"]
                if key not in data or field["read_only"] or field["hidden"]:
                    continue
                result[key] = [payload(schema["children"][field["options"]], row) for row in data[key]] if field["fieldtype"] in ("Table", "Table MultiSelect") else data[key]
            return result
        payment = native.save(payload(native.schema("Payment Entry"), values), "Submit")
        self.assertEqual(payment["doc"]["docstatus"], 1)
        self.assertEqual(frappe.db.get_value("Sales Invoice", invoice, "outstanding_amount"), 0)
        rows = frappe.get_all("GL Entry", filters={"voucher_no": payment["doc"]["name"], "is_cancelled": 0}, fields=["debit", "credit"])
        self.assertEqual(sum(r.debit - r.credit for r in rows), 0)

    def test_current_planning_outlook_uses_declared_input_demand(self):
        from frappe.utils import now_datetime, add_to_date
        self.fixtures()
        self.receive("80.000")
        machine = self.call("create_machine", {"title": "Coverage test", "dia": "30", "gauge": "24", "knit_type": "Tubular", "capacity_kg": "200.000"})["data"]["machine"]
        start = add_to_date(now_datetime(), hours=1)
        self.call("plan", {"job": self.job, "programme_line": "P1", "machine": machine, "starts_at": str(start), "ends_at": str(add_to_date(start, hours=8)), "quantity_kg": "88.000", "required_yarn_kg": "90.000"})
        coverage = self.knitting().report(COMPANY, "shortages", {"job": self.job})["rows"][0]
        self.assertEqual(coverage["shortage_kg"], "10.000")
        self.assertEqual(coverage["coverage"], "Short")
        plan = self.knitting().report(COMPANY, "unplanned", {"job": self.job})["rows"][0]
        self.assertEqual(plan["unplanned_kg"], "0.000")
        self.assertEqual(plan["status"], "Fully planned")

    def test_yarn_purchase_receipt_and_bill_use_original_purchase_controllers_once(self):
        self.fixtures(mode="Owned")
        supplier = frappe.get_doc({"doctype": "Supplier", "supplier_name": "Synthetic yarn supplier " + frappe.generate_hash(length=8), "supplier_type": "Company", "supplier_group": frappe.db.get_value("Supplier Group", {"is_group": 0}, "name")}).insert().name
        order = self.call("create_yarn_order", {"supplier": supplier, "item": self.items["yarn"], "quantity_kg": "100.000", "rate": "10.00"})
        receipt = self.call("receive_yarn", {"job": self.job, "item": self.items["yarn"], "material_owner": "Owned", "quantity_kg": "100.000", "warehouse": self.warehouse, "purchase_order": order["data"]["purchase_order"]})
        self.assertEqual(receipt["data"]["voucher_type"], "Purchase Receipt")
        bill = self.call("bill_yarn", {"receipt": receipt["event"], "quantity_kg": "100.000"})
        self.assertEqual(frappe.get_doc("Purchase Invoice", bill["data"]["invoice"]).docstatus, 1)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["yarn"], "warehouse": self.warehouse}, "actual_qty"), 100)
        with self.assertRaises(frappe.ValidationError):
            self.call("bill_yarn", {"receipt": receipt["event"], "quantity_kg": "1.000"})
        self.assertEqual(frappe.db.get_value("Purchase Order Item", {"parent": order["data"]["purchase_order"]}, "received_qty"), 100)

    def test_auxiliary_charge_defaults_and_delivered_prices_survive_policy_changes(self):
        self.fixtures(target="90.000", lycra_charge="Separate")
        yarn = self.receive("90.000")
        lycra = self.call("receive_yarn", {"job": self.job, "item": self.items["lycra"], "material_owner": "Owned", "quantity_kg": "2.000", "valuation_rate": "50.00", "warehouse": self.warehouse, "charge_item": self.items["material_charge"], "charge_rate": "50.00"})["data"]["lot"]
        production = self.call("produce", {"job": self.job, "programme_line": "P1", "weights_kg": ["45.000", "45.000"], "inputs": [{"lot": yarn, "quantity_kg": "90.000"}, {"lot": lycra, "quantity_kg": "2.000"}], "loss_kg": "2.000", "warehouse": self.warehouse})
        self.release(production["data"]["rolls"])
        delivery = self.call("deliver", {"job": self.job, "rolls": production["data"]["rolls"]})
        self.enable(lycra_charge="Included")
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(invoice["data"]["amount"], "9100.00")

    def test_invoice_preview_uses_original_totals_without_writing_and_confirm_checks_preview(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        api = self.knitting()
        self.assertTrue(callable(getattr(api, "invoice_preview", None)), "A non-writing invoice review is required")
        payload = {"job": self.job, "deliveries": [delivery["event"]]}
        before = {kind: frappe.db.count(kind) for kind in ("Sales Invoice", "GL Entry", "Knitting Event", "Item Price")}
        modified = str(frappe.db.get_value("Knitting Job", self.job, "modified"))
        preview = api.invoice_preview(COMPANY, payload, modified)
        self.assertEqual(preview["grand_total"], "8800.00")
        self.assertEqual(preview["currency"], "INR")
        self.assertEqual({kind: frappe.db.count(kind) for kind in before}, before)
        with self.assertRaises(frappe.ValidationError):
            self.call("invoice", {**payload, "preview_hash": "wrong-preview"})
        invoice = self.call("invoice", {**payload, "preview_hash": preview["preview_hash"]})
        self.assertEqual(invoice["data"]["amount"], preview["grand_total"])

    def test_revised_programme_uses_the_same_public_schema_as_a_new_job(self):
        self.fixtures()
        line = frappe.parse_json(frappe.get_doc("Knitting Job", self.job).programme)[0]
        with self.assertRaises(frappe.ValidationError):
            self.call("revise_job", {"job": self.job, "reason": "Schema check", "programme": [{**line, "rate": "private value"}]})
        with self.assertRaises(frappe.ValidationError):
            self.call("revise_job", {"job": self.job, "reason": "Schema check", "programme": [{**line, "gsm": ["NaN"]}]})

    def test_owned_fabric_credit_return_restores_stock_once_and_reconciles_margin(self):
        self.fixtures(mode="Owned")
        rolls = self.produce(self.receive(owner="Owned"))
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.call("credit_invoice", {"job": self.job, "invoice_event": invoice["event"], "quantity_kg": "44.000", "reason": "Synthetic owned return"})
        self.call("return_fabric", {"job": self.job, "delivery": delivery["event"], "rolls": [rolls[0]], "reason": "Synthetic owned return"})
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["fabric"], "warehouse": self.warehouse}, "actual_qty"), 44)
        self.assertEqual(frappe.db.get_value("Bin", {"item_code": self.items["yarn"], "warehouse": self.warehouse}, "actual_qty"), 10)
        margin = self.knitting().report(COMPANY, "margin", {"job": self.job})["summary"]
        self.assertEqual(margin["net_amount"], "4400.00")
        self.assertEqual(margin["posted_cost"], "450.00")

    def test_multi_job_completion_is_one_version_checked_atomic_action(self):
        self.fixtures(target="1.000")
        first = self.job
        second = self.call("create_job", {"customer": self.customer, "target_kg": "1.000", "rate": "100.00", "programme": [{"id": "P1", "fabric": "Single jersey", "target_kg": "1.000"}]})["data"]["job"]
        for job in (first, second):
            lot = self.call("receive_yarn", {"job": job, "item": self.items["yarn"], "material_owner": "Customer", "party": self.customer, "quantity_kg": "1.000", "warehouse": self.warehouse})["data"]["lot"]
            roll = self.call("produce", {"job": job, "programme_line": "P1", "weights_kg": ["1.000"], "inputs": [{"lot": lot, "quantity_kg": "1.000"}], "loss_kg": "0.000", "warehouse": self.warehouse})["data"]["rolls"][0]
            self.call("quality", {"job": job, "roll": roll, "decision": "Released"})
            delivery = self.call("deliver", {"job": job, "rolls": [roll]})
            self.call("invoice", {"job": job, "deliveries": [delivery["event"]]})
        rows = [{"job": job, "modified": str(frappe.db.get_value("Knitting Job", job, "modified"))} for job in (first, second)]
        self.call("revise_job", {"job": second, "reason": "Stale batch test", "rate": "110.00"})
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call("close_jobs", {"jobs": rows})
        self.assertEqual(frappe.db.get_value("Knitting Job", first, "status"), "Running")
        rows[1]["modified"] = str(frappe.db.get_value("Knitting Job", second, "modified"))
        result = self.call("close_jobs", {"jobs": rows})
        self.assertEqual(len(result["data"]["completed"]), 2)
        for job in (first, second):
            self.assertEqual(frappe.db.get_value("Knitting Job", job, "status"), "Completed")
            self.assertEqual(frappe.db.count("Knitting Event", {"job": job, "kind": "close_job"}), 1)
