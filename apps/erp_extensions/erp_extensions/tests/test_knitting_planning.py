"""Verify machine changeovers from real reviewed allocations on the synthetic site."""
from datetime import timedelta

import frappe
from frappe.utils import now_datetime

from erp_extensions.tests import test_knitting as fixtures


class PlanningTests(fixtures.KnittingTests):
    def test_incoming_job_filter_preserves_the_previous_machine_allocation(self):
        self.fixtures()
        programme = frappe.parse_json(frappe.get_doc("Knitting Job", self.job).programme)
        incoming = self.call("create_job", {
            "customer": self.customer, "target_kg": "88.000", "programme": programme,
        })["data"]["job"]
        machine = self.machine()
        start = now_datetime() + timedelta(hours=1)
        for index, job in enumerate((self.job, incoming, incoming, self.job)):
            begins = start + timedelta(hours=index)
            self.call("plan", {
                "job": job, "machine": machine, "programme_line": "P1",
                "quantity_kg": "1.000", "starts_at": str(begins),
                "ends_at": str(begins + timedelta(hours=1)),
            })

        def changeovers(**filters):
            result = self.knitting().report(fixtures.COMPANY, "changes", {"machine": machine, **filters})
            return [(row["current_job"], row["job"]) for row in result["rows"]]

        self.assertCountEqual(changeovers(), [(self.job, incoming), (incoming, self.job)])
        self.assertEqual(changeovers(job=incoming), [(self.job, incoming)])
        self.assertEqual(changeovers(job=self.job), [(incoming, self.job)])


# The shared base's original scenarios run in test_knitting.
for name in vars(fixtures.KnittingTests):
    if name.startswith("test_"):
        setattr(PlanningTests, name, None)
