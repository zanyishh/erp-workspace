"""Integration checks for financial review exports and period movements."""
import base64
import json
from datetime import datetime, time, timedelta
from xml.etree import ElementTree

import frappe
from frappe.utils import getdate

from erp_extensions.tests import test_knitting as fixtures


class ReportTests(fixtures.KnittingTests):
    def test_roll_and_fabric_filters_reconcile_split_weights_before_grouping_and_paging(self):
        self.fixtures()
        lot = self.receive()
        machine = self.machine()
        rolls = self.call("produce", {"job": self.job, "programme_line": "P1", "shift": "A", "machine": machine,
            "inputs": [{"lot": lot, "quantity_kg": "60.000"}], "weights_kg": ["60.000"]})["data"]["rolls"]
        self.call("split_roll", {"job": self.job, "roll": rolls[0], "weights_kg": ["20.000", "40.000"], "reason": "Split for inspection"})
        self.call("produce", {"job": self.job, "programme_line": "P1", "shift": "B",
            "inputs": [{"lot": lot, "quantity_kg": "28.000"}], "weights_kg": ["28.000"]})
        for name, trace_count in (("rolls", 3), ("fabric", 2)):
            def report(**extra):
                return self.knitting().report(fixtures.COMPANY, name, {"job": self.job, **extra})
            with self.subTest(report=name):
                subset = report(machine=machine)
                self.assertEqual((subset["row_count"], subset["summary"]["quantity_kg"]), (trace_count, "60.000"))
                grouped = report(shift="A", gauge="24", group_by="gauge")
                self.assertEqual((grouped["rows"][0]["records"], grouped["summary"]["quantity_kg"]), (trace_count, "60.000"))
                self.assertEqual(grouped["rows"][0]["weight_kg"], "60.000")
                page = report(shift="A", start=100)
                self.assertEqual((page["rows"], page["summary"]["quantity_kg"]), ([], "60.000"))
                empty = report(gauge="22")
                self.assertEqual((empty["row_count"], empty["summary"]["quantity_kg"]), (0, "0.000"))

    def test_roll_hour_and_day_groups_use_production_time_after_splitting(self):
        self.fixtures()
        lot = self.receive("90.000")
        first_day = getdate() - timedelta(days=2)
        second_day = first_day + timedelta(days=1)
        rolls = []
        for stamp in [datetime.combine(first_day, time(23, 59)), datetime.combine(second_day, time(0, 1))]:
            result = self.call("produce", {"job": self.job, "programme_line": "P1", "shift": "A",
                "inputs": [{"lot": lot, "quantity_kg": "45.000", "units": "1"}],
                "weights_kg": ["44.000"], "loss_kg": "1.000", "warehouse": self.warehouse})
            roll = result["data"]["rolls"][0]
            frappe.db.set_value("Knitting Event", result["event"], "occurred_at", stamp)
            frappe.db.set_value("Knitting Roll", roll, "produced_at", stamp)
            rolls.append(roll)
        self.call("split_roll", {"job": self.job, "roll": rolls[0],
            "weights_kg": ["20.000", "24.000"], "reason": "Synthetic split"})
        for group, expected in (
            ("day", [str(first_day), str(second_day)]),
            ("hour", [f"{first_day} 23:00", f"{second_day} 00:00"]),
        ):
            result = self.knitting().report(fixtures.COMPANY, "rolls", {"job": self.job, "group_by": group})
            self.assertEqual([(row[group], row["weight_kg"]) for row in result["rows"]],
                [(key, "44.000") for key in expected])
            self.assertEqual(result["summary"]["quantity_kg"], "88.000")

    def test_stoppage_intervals_keep_shift_godown_and_actual_period(self):
        self.fixtures()
        machine = self.machine()
        day = getdate() - timedelta(days=2)
        yesterday = day - timedelta(days=1)
        base = {"machine": machine, "job": self.job, "starts_at": f"{yesterday} 23:30",
                "ends_at": f"{day} 00:30", "reason": "Synthetic maintenance"}
        with self.assertRaises(frappe.ValidationError):
            self.call("stoppage", {**base, "shift": "Unknown"})
        self.call("stoppage", {**base, "warehouse": self.warehouse, "shift": "B"})
        self.call("stoppage", {**base, "starts_at": f"{day} 10:00", "ends_at": f"{day} 10:15"})
        period = {"job": self.job, "mode": "period", "from_date": str(day), "to_date": str(day)}
        grouped = self.knitting().report(fixtures.COMPANY, "stoppage", {**period, "group_by": "shift"})
        self.assertEqual([(r["shift"], r["minutes"]) for r in grouped["rows"]],
                         [("B", "30.00"), ("Unspecified", "15.00")])
        detail = self.knitting().report(fixtures.COMPANY, "stoppage", {**period, "warehouse": self.warehouse})
        self.assertEqual(detail["summary"]["minutes"], "30.00")
        self.assertEqual(detail["rows"][0]["shift"], "B")

    def test_yarn_inward_and_return_registers_reconcile_physical_units_with_challan(self):
        self.fixtures()
        receipt = self.call("receive_yarn", {"job": self.job, "item": self.items["yarn"],
            "material_owner": "Customer", "party": self.customer, "warehouse": self.warehouse,
            "source_lot": "0031", "party_dc_number": "0049/A", "party_dc_date": "2026-03-07",
            "quantity_kg": "10.000", "units": 3})
        lot = receipt["data"]["lot"]
        returned = self.call("return_yarn", {"job": self.job, "lot": lot, "quantity_kg": "4.000", "units": 1})
        scope = {"job": self.job, "customer": self.customer, "warehouse": self.warehouse, "source_lot": "0031"}
        for name, event, kg, units in (("yarn_inwards", receipt["event"], "10.000", "3"),
                                      ("yarn_returns", returned["event"], "4.000", "1")):
            register = self.knitting().report(fixtures.COMPANY, name, scope)
            row, = register["rows"]
            self.assertEqual((row["event"], row["lot"], row["quantity_kg"], row["units"]), (event, lot, kg, units))
            self.assertEqual(register["summary"], {"quantity_kg": kg, "units": units})
            if name == "yarn_inwards":
                self.assertEqual((row["party_dc_number"], row["party_dc_date"]), ("0049/A", "2026-03-07"))

    def test_breakage_employee_and_gauge_filters_limit_counts_and_totals(self):
        self.fixtures()
        gender = frappe.get_doc({"doctype": "Gender", "gender": "Report fixture gender"}).insert()
        employee = frappe.get_doc({"doctype": "Employee", "first_name": "Report employee", "company": fixtures.COMPANY,
            "gender": gender.name, "date_of_birth": "1990-01-01", "date_of_joining": "2020-01-01", "status": "Active"}).insert()
        for machine, who, quantity in (
            (self.machine(), employee.name, 3),
            (self.call("create_machine", {"title": "Fixture 18 gauge", "dia": "30", "gauge": "18", "knit_type": "Tubular",
                "capacity_kg": "100.000"})["data"]["machine"], None, 5),
        ):
            part = self.call("create_component", {"machine": machine, "component_type": "Needle", "boundary_kg": "100.000"})["data"]["component"]
            self.call("component_breakage", {"job": self.job, "programme_line": "P1", "component": part,
                "employee": who, "quantity": quantity, "reason": "Synthetic breakage"})
        for selected, expected in (({"employee": employee.name}, "3"), ({"gauge": "18"}, "5"), ({"employee": employee.name, "gauge": "18"}, "0")):
            with self.subTest(selected=selected):
                result = self.knitting().report(fixtures.COMPANY, "breakage", {"job": self.job, "group_by": "machine", **selected})
                self.assertEqual((result["row_count"], result["summary"]["quantity"]), (int(expected != "0"), expected))
                if result["rows"]:
                    self.assertEqual((result["rows"][0]["records"], result["rows"][0]["quantity"]), (1, expected))

    def test_next_day_reversals_reconcile_original_period_current_period_and_register(self):
        self.fixtures(mode="Owned")
        lot = self.receive("90.000", owner="Owned")
        rolls = self.produce(lot)
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": rolls})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        for name in ("billing", "margin"):
            def financial(**filters):
                result = self.knitting().report(fixtures.COMPANY, name, {"job": self.job, **filters})
                summary = result["summary"]
                return result["row_count"], summary["net_amount"], summary["posted_cost"], summary["margin_before_overhead"]
            with self.subTest(report=name, basis="filtered financial events"):
                self.assertEqual(financial(operator="Another operator"), (0, "0.00", "0.00", "0.00"))
                self.assertEqual(financial(kind="invoice"), (1, "8800.00", "0.00", "8800.00"))
                self.assertEqual(financial(kind="deliver"), (0, "0.00", "900.00", "-900.00"))
        production = frappe.db.get_value("Knitting Roll", rolls[0], "production")
        inspections = frappe.get_all("Knitting QC", filters={"job": self.job}, pluck="event")
        today = getdate()
        prior = today - timedelta(days=1)
        stamp = datetime.combine(prior, time(12))
        for row in frappe.get_all("Knitting Event", filters={"job": self.job}, pluck="name"):
            frappe.db.set_value("Knitting Event", row, "occurred_at", stamp, update_modified=False)
        corrections = {}
        for source in [invoice["event"], delivery["event"], *inspections, production]:
            corrections[source] = self.call("cancel_event", {
                "job": self.job, "event": source, "reason": "Correct yesterday's cycle",
            })["event"]

        def report(name, start, end, **filters):
            return self.knitting().report(fixtures.COMPANY, name, {
                "job": self.job, "mode": "period", "from_date": str(start), "to_date": str(end), **filters,
            })

        with self.subTest(report="yarn"):
            reversal = report("yarn", today, today)["summary"]
            self.assertEqual((reversal["quantity_kg"], reversal["units"]), ("90.000", "2"))
        with self.subTest(report="jobs"):
            reversal, = report("jobs", today, today)["rows"]
            self.assertEqual([reversal[k] for k in ("produced_kg", "consumed_kg", "loss_kg", "delivered_kg", "billed_kg", "yarn_kg")],
                             ["-88.000", "-90.000", "-2.000", "-88.000", "-88.000", "90.000"])
        with self.subTest(report="production"):
            for start, end, output in ((prior, prior, "88.000"), (today, today, "-88.000"), (prior, today, "0.000")):
                self.assertEqual(report("production", start, end)["summary"]["quantity_kg"], output)
        with self.subTest(report="billing"):
            reversal, = report("billing", today, today)["rows"]
            self.assertEqual((reversal["invoice"], reversal["event"], reversal["quantity_kg"], reversal["grand_total"]),
                             (invoice["data"]["invoice"], corrections[invoice["event"]], "-88.000", "-8800.00"))
        with self.subTest(report="margin"):
            for start, end, revenue, cost in ((prior, prior, "8800.00", "900.00"), (today, today, "-8800.00", "-900.00"),
                                               (prior, today, "0.00", "0.00")):
                summary = report("margin", start, end)["summary"]
                self.assertEqual((summary["net_amount"], summary["posted_cost"]), (revenue, cost))
        with self.subTest(report="activity"):
            audit = report("activity", today, today, kind="cancel_event")
            self.assertCountEqual([(r["reverses"], r["event"]) for r in audit["rows"]], corrections.items())

    def test_grouped_screen_exports_each_original_invoice_in_both_review_formats(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        expected = []
        for roll in rolls:
            delivery = self.call("deliver", {"job": self.job, "rolls": [roll]})
            invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
            doc = frappe.get_doc("Sales Invoice", invoice["data"]["invoice"])
            expected.append({
                "invoice": doc.name, "posting_date": str(doc.posting_date), "currency": doc.currency,
                "net_amount": "4400.00", "tax_amount": "0.00", "grand_total": "4400.00",
            })

        filters = {"report": "billing", "job": self.job, "group_by": "customer"}
        self.assertEqual(self.knitting().report(fixtures.COMPANY, "billing", filters)["row_count"], 1)
        for format in ("gst_review", "tally_review"):
            with self.subTest(format=format):
                result = self.knitting().export(fixtures.COMPANY, format, filters)
                content = base64.b64decode(result["content"])
                if format == "gst_review":
                    rows = json.loads(content)["invoices"]
                else:
                    rows = [{field.tag: field.text for field in row}
                            for row in ElementTree.fromstring(content).findall("Invoice")]
                self.assertCountEqual(rows, expected)

    def test_subcontract_period_separates_movements_from_closing_custody(self):
        self.fixtures()
        lot = self.receive()
        subcontract = self.call("create_subcontract", {
            "job": self.job, "supplier": self.supplier(), "target_kg": "88.000", "rate": "50.00",
        })
        source = {"job": self.job, "subcontract": subcontract["data"]["subcontract"], "lot": lot}
        issue = self.call("subcontract_issue", {**source, "quantity_kg": "100.000"})
        self.call("subcontract_return", {**source, "quantity_kg": "10.000"})
        today = getdate()
        yesterday = datetime.combine(today - timedelta(days=1), time(12))
        for entry in (subcontract, issue):
            frappe.db.set_value("Knitting Event", entry["event"], "occurred_at", yesterday)

        def totals(**filters):
            result = self.knitting().report(fixtures.COMPANY, "subcontract", {"job": self.job, **filters})
            row, = result["rows"]
            return row["ordered_kg"], row["issued_kg"], row["returned_kg"], row["custody_kg"]

        self.assertEqual(totals(), ("88.000", "100.000", "10.000", "90.000"))
        self.assertEqual(totals(mode="period", from_date=str(today), to_date=str(today)),
                         ("0.000", "0.000", "10.000", "90.000"))


# The shared base's original scenarios run in test_knitting.
for name in vars(fixtures.KnittingTests):
    if name.startswith("test_"):
        setattr(ReportTests, name, None)
