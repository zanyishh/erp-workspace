"""Synthetic commercial corrections; every write is confined to native-test.localhost."""
import json

import frappe

from erp_extensions.knitting import permissions
from erp_extensions.tests import test_knitting as fixtures


class CommercialRevisionTests(fixtures.KnittingTests):
    def imported_programme(self):
        self.fixtures()
        lines = [{"id": "synthetic-source-fabric-7-size-9", "fabric": "Synthetic preserved fabric",
            "source_fabric_id": "7", "source_size_id": "9", "dia": "", "gauge": "",
            "gsm": ["0"], "ll": [], "target_kg": "0.000", "excess_percent": "0"},
            {"id": "synthetic-source-fabric-8-size-10", "fabric": "", "source_fabric_id": "8",
             "source_size_id": "10", "dia": "15", "gsm": [], "ll": ["0"], "target_kg": "0.000"}]
        # Deliberately retain whitespace as well as values to catch a programme reserialization.
        programme = json.dumps(lines, indent=2)
        with permissions.service_write():
            job = frappe.get_doc("Knitting Job", self.job)
            job.programme = programme
            job.target_kg = "0.000"
            job.save()
        return programme

    def test_rate_only_keeps_byte_equivalent_source_programme_and_target(self):
        programme = self.imported_programme()
        result = self.call("revise_job", {"job": self.job, "rate": "125.50", "reason": "Synthetic rate agreement"})
        job = frappe.get_doc("Knitting Job", self.job)
        self.assertEqual(job.programme, programme)
        self.assertEqual(job.target_kg, "0.000")
        self.assertEqual(frappe.parse_json(job.pricing), {
            "synthetic-source-fabric-7-size-9": "125.50", "synthetic-source-fabric-8-size-10": "125.50"})
        payload = frappe.parse_json(frappe.db.get_value("Knitting Event", result["event"], "payload"))
        self.assertEqual(payload, {"job": self.job, "rate": "125.50", "reason": "Synthetic rate agreement"})
        with self.assertRaises(frappe.ValidationError):
            self.call("revise_job", {"job": self.job, "programme": frappe.parse_json(programme),
                "reason": "Synthetic full programme still requires native validation"})
        self.assertEqual(frappe.db.get_value("Knitting Job", self.job, "programme"), programme)

    def test_stale_rate_revision_cannot_overwrite_agreed_price_or_original_programme(self):
        programme = self.imported_programme()
        old_version = str(frappe.db.get_value("Knitting Job", self.job, "modified"))
        self.call("revise_job", {"job": self.job, "rate": "125.50", "reason": "Synthetic first agreement"})
        before = frappe.get_doc("Knitting Job", self.job).as_dict()
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call("revise_job", {"job": self.job, "rate": "900", "reason": "Synthetic stale agreement"},
                modified=old_version)
        self.assertEqual(frappe.get_doc("Knitting Job", self.job).as_dict(), before)
        self.assertEqual(frappe.db.get_value("Knitting Job", self.job, "programme"), programme)

    def test_later_rate_does_not_reprice_existing_delivery_or_invoice(self):
        self.fixtures()
        rolls = self.produce(self.receive())
        self.release(rolls)
        delivery = self.call("deliver", {"job": self.job, "rolls": [rolls[0]]})
        frozen_delivery = frappe.db.get_value("Knitting Event", delivery["event"], "result")
        self.call("revise_job", {"job": self.job, "rate": "125.50", "reason": "Synthetic later deliveries agreement"})
        invoice = self.call("invoice", {"job": self.job, "deliveries": [delivery["event"]]})
        self.assertEqual(frappe.db.get_value("Knitting Event", delivery["event"], "result"), frozen_delivery)
        self.assertEqual(frappe.get_doc("Sales Invoice", invoice["data"]["invoice"]).items[0].rate, 100)
        next_delivery = self.call("deliver", {"job": self.job, "rolls": [rolls[1]]})
        next_invoice = self.call("invoice", {"job": self.job, "deliveries": [next_delivery["event"]]})
        self.assertEqual(frappe.get_doc("Sales Invoice", next_invoice["data"]["invoice"]).items[0].rate, 125.5)


for name in vars(fixtures.KnittingTests):
    if name.startswith("test_"):
        setattr(CommercialRevisionTests, name, None)
