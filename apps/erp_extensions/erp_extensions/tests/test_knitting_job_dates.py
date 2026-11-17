"""Historical order dates with rollback-only fixtures on native-test.localhost."""
from datetime import date, datetime
from unittest.mock import patch

import frappe

from erp_extensions.tests import test_knitting as fixtures


class JobDateTests(fixtures.KnittingTests):
    def job_values(self):
        event = frappe.get_doc("Knitting Event", {"job": self.job, "kind": "create_job"})
        return frappe.parse_json(event.payload)

    def test_default_order_date_uses_event_date_and_preserves_audit_timestamps(self):
        self.fixtures()
        occurred = datetime(2020, 2, 29, 15, 45)
        with patch("erp_extensions.knitting.api.now_datetime", return_value=occurred):
            result = self.call("create_job", self.job_values())
        job = frappe.get_doc("Knitting Job", result["data"]["job"])
        event = frappe.get_doc("Knitting Event", result["event"])
        self.assertEqual(job.get("job_date"), date(2020, 2, 29))
        self.assertEqual(event.occurred_at, occurred)
        self.assertGreater(job.creation, occurred)
        self.assertGreater(event.creation, occurred)
        self.assertEqual(frappe.get_meta("Knitting Job").get_field("job_date").label, "Order date")
        before = job.creation, job.modified, event.creation, event.modified
        page = self.knitting().register(fixtures.COMPANY, "jobs", job=job.name)
        self.assertEqual(page["rows"][0].job_date, date(2020, 2, 29))
        job.reload()
        event.reload()
        self.assertEqual((job.creation, job.modified, event.creation, event.modified), before)

    def test_historical_order_is_included_on_its_date_despite_later_creation(self):
        self.fixtures()
        result = self.call("create_job", {**self.job_values(), "job_date": "2020-02-29"})
        job = frappe.get_doc("Knitting Job", result["data"]["job"])
        self.assertGreater(job.creation, datetime(2020, 3, 1))
        before = job.creation, job.modified
        for mode, finish, expected in (("as_of", "2020-02-28", []), ("as_of", "2020-02-29", [job.name]),
                                       ("period", "2020-02-29", [job.name])):
            with self.subTest(mode=mode, finish=finish):
                report = self.knitting().report(fixtures.COMPANY, "jobs", {
                    "job": job.name, "mode": mode, "from_date": finish, "to_date": finish})
                self.assertEqual([row["job"] for row in report["rows"]], expected)
        job.reload()
        self.assertEqual((job.creation, job.modified), before)

    def test_legacy_job_without_order_date_keeps_creation_date_cutoff(self):
        self.fixtures()
        self.assertTrue(frappe.get_meta("Knitting Job").has_field("job_date"))
        frappe.db.set_value("Knitting Job", self.job,
                            {"job_date": None, "creation": datetime(2020, 2, 29, 23, 59)}, update_modified=False)
        for finish, expected in (("2020-02-28", []), ("2020-02-29", [self.job])):
            with self.subTest(finish=finish):
                report = self.knitting().report(fixtures.COMPANY, "jobs", {"job": self.job, "to_date": finish})
                self.assertEqual([row["job"] for row in report["rows"]], expected)

    def test_invalid_explicit_order_date_rejects_the_whole_command(self):
        self.fixtures()
        counts = tuple(frappe.db.count(dt, {"company": fixtures.COMPANY}) for dt in ("Knitting Job", "Knitting Event"))
        for value in (None, "", "2020-2-29", "2020-02-30", " 2020-02-29", "2020-02-29T00:00:00", 20200229, True):
            with self.subTest(value=value):
                with self.assertRaises(frappe.ValidationError):
                    self.call("create_job", {**self.job_values(), "job_date": value})
                self.assertEqual(tuple(frappe.db.count(dt, {"company": fixtures.COMPANY})
                                       for dt in ("Knitting Job", "Knitting Event")), counts)


# The shared base's original scenarios run in test_knitting.
for name in vars(fixtures.KnittingTests):
    if name.startswith("test_"):
        setattr(JobDateTests, name, None)
