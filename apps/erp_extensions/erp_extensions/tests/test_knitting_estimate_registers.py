"""Permission-scoped knitting estimate history on the rollback-only native test site."""
from datetime import datetime

import frappe

from erp_extensions.tests import test_knitting as fixtures


class EstimateRegisterTests(fixtures.KnittingTests):
    def staff(self, role, *, sales=True):
        return frappe.get_doc({"doctype": "User", "email": "estimate-" + frappe.generate_hash(length=12) + "@example.invalid",
            "first_name": "Synthetic estimate reader", "send_welcome_email": 0,
            "roles": [{"role": role}, *([{"role": "Sales User"}] if sales else [])]}).insert()

    def estimate(self):
        return self.call("create_estimate", {"customer": self.customer, "target_kg": "10.000", "rate": "120.00",
            "programme": [{"id": "P1", "target_kg": "10.000", "fabric_item": self.items["fabric"]}],
            "service_item": self.items["service"]})["data"]["quotation"]

    def seed_quote(self, name, **values):
        if frappe.local.site != "native-test.localhost":
            raise RuntimeError("Synthetic estimates require native-test.localhost")
        frappe.get_doc({"doctype": "Quotation", "name": name, "company": fixtures.COMPANY,
            "creation": datetime(2020, 1, 1), "modified": datetime(2020, 1, 1),
            "owner": "Administrator", "modified_by": "Administrator", "quotation_to": "Customer",
            "party_name": self.customer, "transaction_date": "2026-11-15", "status": "Draft", "docstatus": 0,
            "currency": "INR", "grand_total": 1200, **values}).db_insert()
        return name

    def test_workspace_exposes_estimates_only_with_existing_quotation_read_access(self):
        self.fixtures()
        owner = self.staff("System Manager", sales=False)
        owner.add_roles("Sales Manager")
        frappe.get_doc({"doctype": "User Permission", "user": owner.name, "allow": "Company",
            "for_value": fixtures.COMPANY, "apply_to_all_doctypes": 1}).insert()
        frappe.set_user(owner.name)
        self.assertTrue(frappe.has_permission("Quotation", "read"))
        context = self.workspace().context(fixtures.COMPANY)
        self.assertIn("Quotation", context["readable_records"])
        self.assertIn("Quotation", context["creatable_records"])
        self.assertNotIn("create_estimate", context["unavailable_knitting_actions"])
        self.assertNotIn("accept_estimate", context["unavailable_knitting_actions"])
        frappe.set_user("Administrator")
        reader = self.staff("Knitting Operator", sales=False)
        frappe.set_user(reader.name)
        self.assertNotIn("Quotation", self.workspace().context(fixtures.COMPANY)["readable_records"])

    def test_workspace_estimate_actions_follow_quotation_create_and_submit_permissions(self):
        self.fixtures()
        manager = self.staff("Knitting Manager", sales=False)
        frappe.set_user(manager.name)
        context = self.workspace().context(fixtures.COMPANY)
        self.assertIn("create_estimate", context["unavailable_knitting_actions"])
        self.assertIn("accept_estimate", context["unavailable_knitting_actions"])
        self.assertIn("job_from_estimate", context["unavailable_knitting_actions"])
        frappe.set_user("Administrator")
        role = "Synthetic quote creator " + frappe.generate_hash(length=8)
        frappe.get_doc({"doctype": "Role", "role_name": role}).insert()
        from frappe.permissions import add_permission, update_permission_property
        add_permission("Quotation", role)
        for permission in ("read", "create"):
            update_permission_property("Quotation", role, 0, permission, 1)
        manager.add_roles(role)
        frappe.set_user(manager.name)
        context = self.workspace().context(fixtures.COMPANY)
        self.assertIn("Quotation", context["readable_records"])
        self.assertNotIn("job_from_estimate", context["unavailable_knitting_actions"])
        self.assertNotIn("create_estimate", context["unavailable_knitting_actions"])
        self.assertIn("accept_estimate", context["unavailable_knitting_actions"])

        frappe.set_user("Administrator")
        update_permission_property("Quotation", role, 0, "submit", 1)
        frappe.set_user(manager.name)
        self.assertFalse(frappe.has_permission("Quotation", "write"))
        self.assertIn("accept_estimate", self.workspace().context(fixtures.COMPANY)["unavailable_knitting_actions"])
        frappe.set_user("Administrator")
        update_permission_property("Quotation", role, 0, "write", 1)
        frappe.set_user(manager.name)
        self.assertNotIn("accept_estimate", self.workspace().context(fixtures.COMPANY)["unavailable_knitting_actions"])

    def test_estimates_filter_and_count_only_knitting_quotes_before_paging(self):
        self.fixtures()
        estimate = self.estimate()
        event = frappe.db.get_value("Quotation", estimate, "knitting_event")
        prefix = "SYN-EST-PAGE-" + frappe.generate_hash(length=7)
        names = [self.seed_quote(f"{prefix}-{n:04}", knitting_event=event,
            status="Open" if n == 0 else "Draft", docstatus=1 if n == 0 else 0) for n in range(103)]
        self.seed_quote(prefix + "-ordinary")
        self.seed_quote(prefix + "-other-company", company="ERP Native Verification", knitting_event=event)
        self.seed_quote(prefix + "-lead", quotation_to="Lead", knitting_event=event)
        found = []
        for start, count in ((0, 100), (100, 3)):
            page = self.knitting().register(fixtures.COMPANY, "estimates", start=start, query=prefix)
            self.assertEqual(page["page"], {"start": start, "limit": 100, "has_more": start == 0, "total": 103})
            self.assertEqual(len(page["rows"]), count)
            found.extend(row.name for row in page["rows"])
        self.assertEqual(found, list(reversed(names)))
        filtered = self.knitting().register(fixtures.COMPANY, "estimates", query=prefix, state="Open")
        self.assertEqual([row.name for row in filtered["rows"]], [names[0]])
        self.assertEqual(filtered["page"]["total"], 1)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query="' OR 1=1 --")["rows"], [])
        for kwargs in ({"state": "Running"}, {"start": -1}, {"query": "x" * 121}):
            with self.subTest(kwargs=kwargs), self.assertRaises(frappe.ValidationError):
                self.knitting().register(fixtures.COMPANY, "estimates", **kwargs)

    def test_estimate_date_range_is_inclusive_and_filters_before_paging(self):
        self.fixtures()
        estimate = self.estimate()
        event = frappe.db.get_value("Quotation", estimate, "knitting_event")
        prefix = "SYN-EST-DATES-" + frappe.generate_hash(length=7)
        names = [self.seed_quote(f"{prefix}-{n:04}", knitting_event=event,
            transaction_date="2026-11-01" if n == 0 else "2026-11-15" if n == 102 else "2026-11-08")
            for n in range(103)]
        self.seed_quote(prefix + "-ZZ-before", knitting_event=event, transaction_date="2026-10-31")
        self.seed_quote(prefix + "-ZZ-after", knitting_event=event, transaction_date="2026-11-16")
        found = []
        for start, count in ((0, 100), (100, 3)):
            page = self.knitting().register(fixtures.COMPANY, "estimates", query=prefix, start=start,
                from_date="2026-11-01", to_date="2026-11-15")
            self.assertEqual((page["from_date"], page["to_date"]), ("2026-11-01", "2026-11-15"))
            self.assertEqual(page["page"], {"start": start, "limit": 100, "has_more": start == 0, "total": 103})
            self.assertEqual(len(page["rows"]), count)
            found.extend(row.name for row in page["rows"])
        self.assertEqual(found, list(reversed(names)))
        on_day = self.knitting().register(fixtures.COMPANY, "estimates", query=prefix,
            from_date="2026-11-01", to_date="2026-11-01")
        self.assertEqual([row.name for row in on_day["rows"]], [names[0]])
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=prefix,
            from_date="2026-11-15")["page"]["total"], 2)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=prefix,
            to_date="2026-11-01")["page"]["total"], 2)

    def test_estimate_date_range_rejects_invalid_or_inapplicable_inputs(self):
        self.fixtures()
        for values in ({"from_date": "2026-02-30"}, {"to_date": "2026-13-01"},
                       {"from_date": "2026-1-01"}, {"to_date": ""}, {"from_date": True},
                       {"to_date": ["2026-11-15"]}, {"from_date": "2026-11-16", "to_date": "2026-11-15"}):
            with self.subTest(values=values), self.assertRaises(frappe.ValidationError):
                self.knitting().register(fixtures.COMPANY, "estimates", **values)
        with self.assertRaises(frappe.ValidationError):
            self.knitting().register(fixtures.COMPANY, "machines", from_date="2026-11-15")

    def test_estimate_customer_permission_scoped_to_quotation_filters_rows_and_counts(self):
        self.fixtures()
        visible = self.estimate()
        allowed = self.customer
        self.fixtures()
        hidden = self.estimate()
        hidden_title = frappe.db.get_value("Customer", self.customer, "customer_name")
        for context in ("Quotation", "Customer"):
            with self.subTest(context=context):
                frappe.set_user("Administrator")
                user = self.staff("Knitting Accountant")
                frappe.get_doc({"doctype": "User Permission", "user": user.name, "allow": "Customer",
                    "for_value": allowed, "apply_to_all_doctypes": 0, "applicable_for": context}).insert()
                frappe.set_user(user.name)
                page = self.knitting().register(fixtures.COMPANY, "estimates")
                self.assertEqual([row.name for row in page["rows"]], [visible])
                self.assertEqual(page["page"]["total"], 1)
                self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=hidden)["rows"], [])
                self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=hidden_title)["page"]["total"], 0)

    def test_estimates_project_readable_party_money_and_converted_job(self):
        self.fixtures()
        name = self.estimate()
        title = "Synthetic readable estimate party"
        frappe.db.set_value("Customer", self.customer, "customer_name", title)
        page = self.knitting().register(fixtures.COMPANY, "estimates", query=title)
        row = page["rows"][0]
        self.assertEqual(row.name, name)
        self.assertEqual((row.party_name, row.customer_name, row.status, row.docstatus), (self.customer, title, "Draft", 0))
        self.assertEqual((row.grand_total, row.currency, row.get("job")), ("1200.00", "INR", None))
        self.assertFalse(row.converted)
        self.assertNotIn("knitting_programme", row)
        self.assertNotIn("knitting_event", row)
        accepted = self.call("accept_estimate", {"quotation": name, "quotation_modified": str(row.modified)})["data"]
        job = self.call("job_from_estimate", {"quotation": name, "quotation_modified": accepted["modified"]})["data"]["job"]
        converted = self.knitting().register(fixtures.COMPANY, "estimates", query=name)["rows"][0]
        self.assertEqual((converted.docstatus, converted.job, converted.converted), (1, job, True))
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", job=job)["rows"][0].name, name)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", job=self.job)["rows"], [])
        with self.assertRaises(frappe.ValidationError):
            self.call("job_from_estimate", {"quotation": name, "quotation_modified": str(converted.modified)})

    def test_converted_state_never_reveals_a_restricted_job_identity(self):
        self.fixtures()
        name = self.estimate()
        quote = frappe.get_doc("Quotation", name)
        accepted = self.call("accept_estimate", {"quotation": name, "quotation_modified": str(quote.modified)})["data"]
        hidden_job = self.call("job_from_estimate", {"quotation": name, "quotation_modified": accepted["modified"]})["data"]["job"]
        user = self.staff("Knitting Operator")
        frappe.get_doc({"doctype": "User Permission", "user": user.name, "allow": "Knitting Job",
            "for_value": self.job, "apply_to_all_doctypes": 1}).insert()
        frappe.set_user(user.name)
        self.assertFalse(frappe.has_permission("Knitting Job", "read", doc=hidden_job))
        row = self.knitting().register(fixtures.COMPANY, "estimates", query=name)["rows"][0]
        self.assertTrue(row.converted)
        self.assertIsNone(row.job)
        self.assertNotIn(hidden_job, frappe.as_json(row))

    def test_estimates_require_company_capability_and_quotation_read_access(self):
        self.fixtures()
        name = self.estimate()
        user = self.staff("Knitting Operator", sales=False)
        frappe.set_user(user.name)
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register(fixtures.COMPANY, "estimates")
        self.assertNotIn("estimates", self.knitting().snapshot(fixtures.COMPANY))
        frappe.set_user("Administrator")
        user.add_roles("Sales User")
        frappe.get_doc({"doctype": "User Permission", "user": user.name, "allow": "Company",
            "for_value": fixtures.COMPANY, "apply_to_all_doctypes": 1}).insert()
        frappe.set_user(user.name)
        rows = self.knitting().register(fixtures.COMPANY, "estimates", query=name)["rows"]
        self.assertEqual([row.name for row in rows], [name])
        self.assertNotIn("grand_total", rows[0])
        self.assertNotIn("currency", rows[0])
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register("ERP Native Verification", "estimates")
        frappe.set_user("Guest")
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register(fixtures.COMPANY, "estimates")

    def test_estimate_search_and_counts_respect_customer_row_permissions(self):
        self.fixtures()
        visible = self.estimate()
        allowed = self.customer
        self.fixtures()
        hidden = self.estimate()
        hidden_customer = self.customer
        hidden_title = frappe.db.get_value("Customer", hidden_customer, "customer_name")
        user = self.staff("Knitting Accountant")
        frappe.get_doc({"doctype": "User Permission", "user": user.name, "allow": "Customer",
            "for_value": allowed, "apply_to_all_doctypes": 1}).insert()
        frappe.set_user(user.name)
        rows = self.knitting().register(fixtures.COMPANY, "estimates")
        self.assertEqual([row.name for row in rows["rows"]], [visible])
        self.assertEqual(rows["page"]["total"], 1)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=hidden)["page"]["total"], 0)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, "estimates", query=hidden_title)["rows"], [])


for name in list(vars(fixtures.KnittingTests)):
    if name.startswith("test_"):
        setattr(EstimateRegisterTests, name, None)
