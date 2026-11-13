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
            "fabric_kg": "0.000", "unbilled_kg": "0.000", "loss_kg": "2.000", "subcontract_kg": "0.000"})
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
