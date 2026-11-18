"""Imported programme protection; synthetic writes on native-test.localhost only."""
import json

import frappe

from erp_extensions.knitting import permissions
from erp_extensions.tests import test_knitting as fixtures


class ImportedProgrammeGuardTests(fixtures.KnittingTests):
    def imported_job(self, *, empty=False, source_record=True):
        self.fixtures()
        programme = json.dumps([] if empty else [{
            "id": "synthetic-original-7-9", "source_fabric_id": "7", "source_size_id": "9",
            "fabric": "Synthetic original", "dia": "", "gsm": ["0"], "ll": [], "target_kg": "0.000",
        }], indent=2)
        with permissions.service_write():
            job = frappe.get_doc("Knitting Job", self.job)
            job.source_record = "SYNTHETIC-ORIGINAL" if source_record else None
            job.programme, job.target_kg = programme, "0.000"
            job.save()
        return programme

    def test_imported_zero_production_cannot_replace_original_programme(self):
        for empty, source_record in ((False, True), (True, True), (False, False)):
            with self.subTest(empty=empty, source_record=source_record):
                programme = self.imported_job(empty=empty, source_record=source_record)
                before = frappe.get_doc("Knitting Job", self.job).as_dict()
                audit = frappe.get_all("Knitting Event", filters={"job": self.job}, fields=["*"], order_by="name")
                with self.assertRaisesRegex(frappe.ValidationError, "[Ii]mported"):
                    self.call("revise_job", {"job": self.job, "rate": "900", "programme": [{
                        "id": "NEW-NATIVE-LINE", "fabric": "Replacement", "target_kg": "10.000",
                    }], "reason": "Synthetic replacement attempt"})
                self.assertEqual(frappe.get_doc("Knitting Job", self.job).as_dict(), before)
                self.assertEqual(frappe.db.get_value("Knitting Job", self.job, "programme"), programme)
                self.assertEqual(frappe.get_all("Knitting Event", filters={"job": self.job}, fields=["*"], order_by="name"), audit)

    def test_imported_rate_only_remains_available(self):
        programme = self.imported_job()
        self.call("revise_job", {"job": self.job, "rate": "125.50", "reason": "Synthetic rate agreement"})
        job = frappe.get_doc("Knitting Job", self.job)
        self.assertEqual(job.programme, programme)
        self.assertEqual(job.target_kg, "0.000")
        self.assertEqual(frappe.parse_json(job.pricing), {"synthetic-original-7-9": "125.50"})

    def test_native_programme_replacement_remains_available(self):
        self.fixtures()
        self.call("revise_job", {"job": self.job, "programme": [{
            "id": "NEW-NATIVE-LINE", "fabric": "Synthetic replacement", "target_kg": "10.000",
        }], "reason": "Synthetic native revision"})
        job = frappe.get_doc("Knitting Job", self.job)
        self.assertEqual(job.target_kg, "10.000")
        self.assertEqual(frappe.parse_json(job.programme)[0]["id"], "NEW-NATIVE-LINE")


for name in vars(fixtures.KnittingTests):
    if name.startswith("test_"):
        setattr(ImportedProgrammeGuardTests, name, None)
