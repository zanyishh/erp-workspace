"""Cross-command corrections against the isolated site's real stock and accounts."""
from decimal import Decimal
from unittest.mock import patch

import frappe
from erp_extensions.knitting import domain
from erp_extensions.tests import test_knitting as base


class WorkflowTests(base.KnittingTests):
    def cancel(self, source, **context):
        return self.call("cancel_event", {**context, "event": source["event"], "reason": "Synthetic correction"})

    def post(self, action, **values):
        return self.call(action, {"job": self.job, **values})

    def stock(self, item, warehouse=None):
        return frappe.db.get_value("Bin", {"item_code": self.items[item], "warehouse": warehouse or self.warehouse}, "actual_qty") or 0

    def check_zero_gl(self, vouchers):
        rows = frappe.db.sql("""select account, sum(debit-credit) from `tabGL Entry`
            where company=%s and voucher_no in %s and is_cancelled=0 group by account""", (base.COMPANY, tuple(vouchers)))
        self.assertTrue(all(balance == 0 for _, balance in rows), rows)

    def test_specification_revision_preserves_agreed_prices_until_explicit_repricing(self):
        self.fixtures()
        original, = frappe.parse_json(frappe.db.get_value("Knitting Job", self.job, "programme"))
        lines = [dict(original, target_kg="44"), dict(original, id="P2", target_kg="44")]
        self.post("revise_job", programme=lines, pricing={"P1": "112", "P2": "126"}, reason="Agreed rates")
        self.call("create_rate", {"customer": self.customer, "fabric": original["fabric"], "rate": "150", "effective_from": "2026-01-01"})
        self.post("revise_job", programme=[dict(line, colour="Blue") for line in lines], reason="Confirm colour")

        def prices():
            return frappe.parse_json(frappe.db.get_value("Knitting Job", self.job, "pricing"))

        self.assertEqual(prices(), {"P1": "112.00", "P2": "126.00"})
        self.post("revise_job", pricing={"P2": "131"}, reason="Amend only second line")
        self.assertEqual(prices(), {"P1": "112.00", "P2": "131.00"})
        self.post("revise_job", refresh_rates=True, reason="Accept current rate schedule")
        self.assertEqual(prices(), {"P1": "150.00", "P2": "150.00"})

    def test_adjusting_customer_yarn_cannot_place_it_on_an_owned_job(self):
        self.fixtures(mode="Owned")
        receipt = self.call("receive_yarn", {"party": self.customer, "item": self.items["yarn"],
            "warehouse": self.warehouse, "quantity_kg": "8", "units": 2, "material_owner": "Customer"})
        lot = receipt["data"]["lot"]
        with self.assertRaises(frappe.ValidationError):
            self.post("adjust_yarn", lot=lot, quantity_kg="2", units=1, reason="Count reconciliation")
        self.assertEqual((domain.lot_balance(lot), domain.lot_balance(lot, self.job)), (8, 0))

    def test_fabric_transfer_checks_weight_and_loop_specifications_before_reassignment(self):
        self.fixtures()
        roll = self.produce(self.receive())[0]
        line, = frappe.parse_json(frappe.db.get_value("Knitting Job", self.job, "programme"))
        target = self.call("create_job", {"customer": self.customer, "target_kg": "88", "programme": [dict(line, gsm=[220], ll=["3.1"])]})["data"]["job"]
        with self.assertRaises(frappe.ValidationError):
            self.post("transfer_fabric", target_job=target, target_modified=str(frappe.db.get_value("Knitting Job", target, "modified")),
                      target_programme_line="P1", rolls=[roll], reason="Reassign required fabric")
        self.assertEqual(frappe.db.get_value("Knitting Roll", roll, "job"), self.job)

    def test_job_purchase_order_cannot_be_received_outside_its_job(self):
        self.fixtures(mode="Owned")
        order = self.post("create_yarn_order", supplier=self.supplier(), item=self.items["yarn"], quantity_kg="8", rate="5")
        payload = dict(item=self.items["yarn"], warehouse=self.warehouse, material_owner="Owned",
                       quantity_kg="8", purchase_order=order["data"]["purchase_order"])
        with self.assertRaises(frappe.ValidationError):
            self.call("receive_yarn", payload)
        self.post("receive_yarn", **payload)
        self.assertEqual(self.stock("yarn"), 8)

    def test_manual_owned_receipt_and_partial_supplier_bills_clear_goods_received_account(self):
        self.fixtures(mode="Owned")
        receipt = self.post("receive_yarn", item=self.items["yarn"], material_owner="Owned", warehouse=self.warehouse,
                            quantity_kg="10", valuation_rate="12")
        supplier = self.supplier()
        clearing = frappe.get_cached_value("Company", base.COMPANY, "stock_received_but_not_billed")
        vouchers = [receipt["data"]["voucher"]]

        def clearing_balance():
            return frappe.db.sql("""select coalesce(sum(credit-debit),0) from `tabGL Entry`
                where company=%s and account=%s and voucher_no in %s and is_cancelled=0""",
                (base.COMPANY, clearing, tuple(vouchers)))[0][0]

        self.assertEqual(clearing_balance(), 120)
        partial = self.post("bill_yarn", receipt=receipt["event"], supplier=supplier, quantity_kg="4")
        vouchers.append(partial["data"]["voucher"])
        self.assertEqual(clearing_balance(), 72)
        final = self.post("bill_yarn", receipt=receipt["event"], supplier=supplier)
        vouchers.append(final["data"]["voucher"])
        self.assertEqual(clearing_balance(), 0)
        self.assertEqual(self.stock("yarn"), 10)
        self.cancel(final, job=self.job)
        self.assertEqual(clearing_balance(), 72)

    def test_unbilled_legacy_manual_receipt_clears_its_original_difference_account(self):
        from erp_extensions.knitting import posting
        self.fixtures(mode="Owned")
        original_stock = posting.stock
        adjustment = frappe.get_cached_value("Company", base.COMPANY, "stock_adjustment_account")

        def legacy_stock(event, purpose, rows):
            return original_stock(event, purpose, [{**r, "expense_account": adjustment} for r in rows])

        with patch.object(posting, "stock", side_effect=legacy_stock):
            receipt = self.post("receive_yarn", item=self.items["yarn"], material_owner="Owned", warehouse=self.warehouse,
                                quantity_kg="10", valuation_rate="12")
        bill = self.post("bill_yarn", receipt=receipt["event"], supplier=self.supplier())
        amount = frappe.db.get_value("GL Entry", {"company": base.COMPANY, "account": adjustment,
            "voucher_no": bill["data"]["invoice"], "is_cancelled": 0}, "debit")
        self.assertEqual(amount, 120)

    def test_pack_closing_retains_unbilled_manual_receipts_after_yarn_is_consumed(self):
        self.fixtures(mode="Owned")
        receipt = self.post("receive_yarn", item=self.items["yarn"], material_owner="Owned",
                            warehouse=self.warehouse, quantity_kg="90", valuation_rate="10")
        rolls = self.produce(receipt["data"]["lot"])
        self.release(rolls)
        delivery = self.post("deliver", rolls=rolls)
        self.post("invoice", deliveries=[delivery["event"]])
        supplier = self.supplier()
        self.post("bill_yarn", receipt=receipt["event"], supplier=supplier, quantity_kg="20")
        self.post("close_job")
        self.workspace().configure(base.COMPANY, {"state": "Closing"})
        with self.assertRaises(frappe.ValidationError):
            self.workspace().configure(base.COMPANY, {"state": "Inactive"})
        self.post("reopen_job", reason="Settle the remaining supplier invoice")
        self.post("bill_yarn", receipt=receipt["event"], supplier=supplier)
        self.post("close_job")
        self.assertEqual(self.workspace().configure(base.COMPANY, {"state": "Inactive"})["setup_state"], "Inactive")

    def test_owned_credit_return_redelivery_rebill_and_complete_unwind(self):
        self.fixtures(mode="Owned", target="88.000")
        receipt = self.post("receive_yarn", item=self.items["yarn"], material_owner="Owned",
                            warehouse=self.warehouse, quantity_kg="90.000", units=3, valuation_rate="10.00")
        lot = receipt["data"]["lot"]
        made = self.post("produce", programme_line="P1", inputs=[{"lot": lot, "quantity_kg": "90.000"}],
                         weights_kg=["88.000"], loss_kg="2.000", warehouse=self.warehouse)
        rolls = made["data"]["rolls"]
        qc = self.post("quality", roll=rolls[0], decision="Released")
        delivered = self.post("deliver", rolls=rolls)
        billed = self.post("invoice", deliveries=[delivered["event"]])
        billed_doc = frappe.get_doc("Sales Invoice", billed["data"]["voucher"])
        self.assertEqual((billed_doc.grand_total, billed_doc.outstanding_amount), (8800, 8800))
        self.assertEqual(frappe.db.get_value("GL Entry", {"voucher_no": billed_doc.name, "party": self.customer, "is_cancelled": 0}, "debit"), 8800)
        self.post("close_job")
        with self.assertRaises(frappe.ValidationError):
            self.post("credit_invoice", invoice_event=billed["event"], quantity_kg="88.000", reason="Needs reopening")
        self.post("reopen_job", reason="Review returned goods")
        credit = self.post("credit_invoice", invoice_event=billed["event"], quantity_kg="88.000", reason="Returned goods")
        self.assertEqual(credit["data"]["amount"], "-8800.00")
        self.check_zero_gl([billed_doc.name, credit["data"]["voucher"]])
        returned = self.post("return_fabric", delivery=delivered["event"], rolls=rolls, reason="Received in warehouse")
        self.assertEqual((self.stock("fabric"), self.stock("yarn"), domain.lot_units(lot, self.job)), (88, 0, 0))
        with self.assertRaises(frappe.ValidationError):
            self.cancel(credit, job=self.job)
        qc2 = self.post("quality", roll=rolls[0], decision="Released")
        again = self.post("deliver", rolls=rolls)
        rebill = self.post("invoice", deliveries=[again["event"]])
        self.assertEqual((rebill["data"]["amount"], self.stock("fabric")), ("8800.00", 0))
        for source in (rebill, again, qc2, returned, credit, billed, delivered, qc, made):
            self.cancel(source, job=self.job)
        self.assertEqual((self.stock("fabric"), self.stock("yarn"), domain.lot_units(lot, self.job)), (0, 90, 3))
        self.cancel(receipt, job=self.job)
        for source in (receipt, made, delivered, billed, credit, returned, again, rebill):
            self.assertEqual(frappe.db.get_value(source["data"]["voucher_type"], source["data"]["voucher"], "docstatus"), 2)
        self.check_zero_gl([s["data"]["voucher"] for s in (receipt, made, delivered, billed, credit, returned, again, rebill)])
        self.assertEqual((self.stock("fabric"), self.stock("yarn"), domain.lot_units(lot, self.job)), (0, 0, 0))
        self.assertTrue(all(Decimal(value) == 0 for value in domain.balances(self.job).values()))

    def test_full_credit_keeps_active_invoice_source_dependency(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        delivery = self.post("deliver", rolls=rolls)
        bill = self.post("invoice", deliveries=[delivery["event"]])
        credit = self.post("credit_invoice", invoice_event=bill["event"], quantity_kg="88.000", reason="Full credit")
        with self.assertRaises(frappe.ValidationError):
            self.cancel(delivery, job=self.job)
        self.cancel(credit, job=self.job)
        self.cancel(bill, job=self.job)
        self.cancel(delivery, job=self.job)

    def test_second_physical_return_cannot_hide_later_work_on_roll(self):
        self.fixtures()
        roll = self.produce(self.receive())[0]
        self.release([roll])
        first = self.post("deliver", rolls=[roll])
        returned = self.post("return_fabric", delivery=first["event"], rolls=[roll], reason="First return")
        self.release([roll])
        second = self.post("deliver", rolls=[roll])
        self.post("return_fabric", delivery=second["event"], rolls=[roll], reason="Second return")
        with self.assertRaises(frappe.ValidationError):
            self.cancel(returned, job=self.job)
        with self.assertRaises(frappe.ValidationError):
            self.cancel({"event": frappe.db.get_value("Knitting Roll", roll, "production")}, job=self.job)
        self.assertEqual(frappe.db.get_value("Knitting Roll", roll, "state"), "Awaiting QC")

    def test_general_purchase_corrections_respect_dependencies_and_reconcile_units(self):
        self.fixtures(mode="Owned")
        order = self.call("create_yarn_order", {"supplier": self.supplier(), "item": self.items["yarn"], "quantity_kg": "20.000", "rate": "10.00"})
        receipt = self.call("receive_yarn", {"item": self.items["yarn"], "purchase_order": order["data"]["voucher"],
            "material_owner": "Owned", "warehouse": self.warehouse, "quantity_kg": "20.000", "units": 2})
        bill = self.call("bill_yarn", {"receipt": receipt["event"]})
        with self.assertRaises(frappe.ValidationError):
            self.cancel(receipt)
        with self.assertRaises(frappe.ValidationError):
            self.cancel(order)
        self.assertEqual((self.stock("yarn"), domain.lot_units(receipt["data"]["lot"])), (20, 2))
        for source in (bill, receipt, order):
            self.cancel(source)
            self.assertEqual(frappe.db.get_value(source["data"]["voucher_type"], source["data"]["voucher"], "docstatus"), 2)
        self.assertEqual((self.stock("yarn"), domain.lot_balance(receipt["data"]["lot"]), domain.lot_units(receipt["data"]["lot"])), (0, 0, 0))
        self.check_zero_gl([receipt["data"]["voucher"], bill["data"]["voucher"]])

    def test_owned_godown_transfer_and_consumable_source_version(self):
        self.fixtures(mode="Owned")
        destination = frappe.get_doc({"doctype": "Warehouse", "company": base.COMPANY, "is_group": 0,
                                     "warehouse_name": "Synthetic transfer " + frappe.generate_hash(length=8)}).insert().name
        lot = self.receive("5.000", "Owned")
        moved = self.post("move_yarn", lot=lot, quantity_kg="3.000", units=1, target_warehouse=destination, reason="Supply factory")
        new_lot = moved["data"]["lot"]
        self.assertEqual((domain.lot_balance(lot, self.job), domain.lot_units(lot, self.job),
                          self.stock("yarn"), self.stock("yarn", destination)), (2, 1, 2, 3))
        issue = self.post("issue_consumable", item=self.items["yarn"], lot=new_lot, quantity="3", warehouse=destination, reason="Use at machine")
        selector = self.knitting().lookup(base.COMPANY, "ConsumableIssue", query=issue["event"])["rows"][0]
        self.assertEqual(selector.job, self.job)
        self.post("revise_job", reason="Advance job version", rate="101")
        values = {"event": issue["event"], "quantity": "3", "reason": "Unused"}
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call("return_consumable", values, modified=str(selector.job_modified))
        returned = self.call("return_consumable", values)
        self.assertEqual(frappe.db.get_value("Knitting Event", returned["event"], "job"), self.job)
        self.assertEqual((domain.lot_balance(new_lot, self.job), domain.lot_units(new_lot, self.job), self.stock("yarn", destination)), (3, 1, 3))

    def test_source_only_yarn_bill_honours_review_and_closed_job(self):
        self.fixtures(mode="Owned")
        receipt = self.post("receive_yarn", item=self.items["yarn"], material_owner="Owned", warehouse=self.warehouse,
                            quantity_kg="90.000", valuation_rate="10.00")
        row = self.knitting().lookup(base.COMPANY, "YarnReceipt", query=receipt["event"])["rows"][0]
        self.assertEqual(row.job_modified, frappe.db.get_value("Knitting Job", self.job, "modified"))
        rolls = self.produce(receipt["data"]["lot"])
        values = {"receipt": receipt["event"], "supplier": self.supplier()}
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call("bill_yarn", values, modified=str(row.job_modified))
        self.release(rolls)
        delivery = self.post("deliver", rolls=rolls)
        self.post("invoice", deliveries=[delivery["event"]])
        self.post("close_job")
        with self.assertRaises(frappe.ValidationError):
            self.call("bill_yarn", values)
        self.post("reopen_job", reason="Supplier bill arrived")
        version = frappe.db.get_value("Knitting Job", self.job, "modified")
        billed = self.call("bill_yarn", values, modified=str(version))
        self.assertEqual(billed["data"]["amount"], "900.00")
        self.assertNotEqual(version, frappe.db.get_value("Knitting Job", self.job, "modified"))
        with self.assertRaises(frappe.ValidationError):
            self.post("reopen_job", reason="Already running")

    def test_reopen_partly_short_closed_subcontract_and_correct_source_bill(self):
        self.fixtures(target="88.000")
        lot = self.receive("30.000")
        sub = self.post("create_subcontract", supplier=self.supplier(), target_kg="88", rate="10")["data"]["subcontract"]
        po = frappe.db.get_value("Knitting Subcontract", sub, "purchase_order")
        self.post("subcontract_issue", subcontract=sub, lot=lot, quantity_kg="30")
        received = self.post("subcontract_receive", subcontract=sub, programme_line="P1", inputs=[{"lot": lot, "quantity_kg": "30"}],
                             loss_kg="0", weights_kg=["30"], warehouse=self.warehouse)
        bill = self.post("subcontract_bill", subcontract=sub)
        self.post("short_close_subcontract", subcontract=sub, reason="Release unused commitment")
        self.assertEqual(frappe.db.get_value("Purchase Order", po, "status"), "Closed")
        self.post("reopen_subcontract", subcontract=sub, reason="Correct the supplier bill")
        self.assertNotEqual(frappe.db.get_value("Purchase Order", po, "status"), "Closed")
        # Reopening for corrections must preserve the reduced commitment.
        self.assertEqual(frappe.db.get_value("Knitting Subcontract", sub, "target_kg"), "30.000")
        with self.assertRaises(frappe.ValidationError):
            self.cancel(received, job=self.job)
        self.cancel(bill, job=self.job)
        corrected = self.post("subcontract_bill", subcontract=sub)
        self.assertEqual(corrected["data"]["amount"], "300.00")
        self.post("close_subcontract", subcontract=sub)
        self.assertEqual(frappe.db.get_value("Purchase Order", po, "status"), "Closed")
        self.post("reopen_subcontract", subcontract=sub, reason="Review returned material")
        self.cancel(corrected, job=self.job)
        self.cancel(received, job=self.job)
        self.assertEqual(domain.lot_balance(lot, self.job, "SC:" + sub), 30)
        self.post("subcontract_return", subcontract=sub, lot=lot, quantity_kg="30")
        self.assertEqual((domain.lot_balance(lot, self.job), domain.lot_units(lot, self.job)), (30, 2))

    def test_sequential_production_corrections_restore_machine_counters_and_allocation(self):
        self.fixtures()
        machine = self.machine()
        component = self.call("create_component", {"machine": machine, "component_type": "Needle", "boundary_kg": "100"})["data"]["component"]
        plan = self.post("plan", programme_line="P1", machine=machine, starts_at="2026-11-18 08:00:00",
                         ends_at="2026-11-18 16:00:00", quantity_kg="88")["data"]["plan"]
        lot = self.receive("88.000")
        batches = [self.post("produce", machine=machine, programme_line="P1", inputs=[{"lot": lot, "quantity_kg": "44"}],
                            loss_kg="0", weights_kg=["44"], warehouse=self.warehouse) for _ in range(2)]
        with self.assertRaises(frappe.ValidationError):
            self.cancel(batches[0], job=self.job)
        for batch in reversed(batches):
            self.cancel(batch, job=self.job)
        self.assertEqual(frappe.db.get_value("Knitting Component", component, "run_kg"), "0.000")
        self.assertEqual(frappe.db.get_value("Knitting Plan", plan, ["state", "produced_kg"]), ("Planned", "0.000"))
        self.assertEqual(domain.lot_balance(lot, self.job), 88)

    def test_replanning_an_active_run_preserves_its_machine_and_reviewed_schedule_after_correction(self):
        self.fixtures()
        machine, other = self.machine(), self.machine()
        values = dict(programme_line="P1", machine=machine, starts_at="2026-11-18 08:00:00",
                      ends_at="2026-11-18 16:00:00", quantity_kg="88")
        plan = self.post("plan", **values)["data"]["plan"]
        lot = self.receive("88")
        batch = self.post("produce", machine=machine, programme_line="P1", inputs=[{"lot": lot, "quantity_kg": "44"}],
                          loss_kg="0", weights_kg=["44"], warehouse=self.warehouse)
        updated = dict(values, plan=plan, plan_modified=str(frappe.db.get_value("Knitting Plan", plan, "modified")),
                       starts_at="2026-11-19 08:00:00", ends_at="2026-11-19 16:00:00")
        with self.assertRaises(frappe.ValidationError):
            self.post("plan", **dict(updated, machine=other))
        self.post("plan", **updated)
        self.cancel(batch, job=self.job)
        allocation = frappe.get_doc("Knitting Plan", plan)
        self.assertEqual((allocation.state, allocation.produced_kg, str(allocation.starts_at)),
                         ("Planned", "0.000", "2026-11-19 08:00:00"))

    def test_reopened_job_can_correct_production_after_its_unused_plan_was_released(self):
        self.fixtures()
        machine = self.machine()
        plan = self.post("plan", programme_line="P1", machine=machine, starts_at="2026-11-18 08:00:00",
                         ends_at="2026-11-18 16:00:00", quantity_kg="88")["data"]["plan"]
        lot = self.receive("88")
        values = dict(programme_line="P1", inputs=[{"lot": lot, "quantity_kg": "44"}], loss_kg="0",
                      weights_kg=["44"], warehouse=self.warehouse)
        planned = self.post("produce", machine=machine, **values)
        other = self.post("produce", **values)
        roll = planned["data"]["rolls"][0]
        quality = self.post("quality", roll=roll, decision="Released")
        self.release(other["data"]["rolls"])
        delivery = self.post("deliver", rolls=[roll, *other["data"]["rolls"]])
        billed = self.post("invoice", deliveries=[delivery["event"]])
        self.post("close_job")
        self.assertEqual(frappe.db.get_value("Knitting Plan", plan, "state"), "Cancelled")
        self.post("reopen_job", reason="Correct production, keep released capacity available")
        for source in (billed, delivery, quality, planned):
            self.cancel(source, job=self.job)
        self.assertEqual(frappe.db.get_value("Knitting Plan", plan, ["state", "produced_kg"]), ("Cancelled", "0.000"))
        self.assertEqual(domain.lot_balance(lot, self.job), 44)


# The base fixture's own cases already run in test_knitting.
for name in vars(base.KnittingTests):
    if name.startswith("test_"):
        setattr(WorkflowTests, name, None)
