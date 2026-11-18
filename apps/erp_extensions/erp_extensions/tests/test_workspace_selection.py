"""Native login uses the signed-in user's last permitted company."""
import os
import unittest
from unittest.mock import patch

import frappe
from erp_extensions import workspace


class WorkspaceSelectionTests(unittest.TestCase):
    def setUp(self):
        if os.environ.get("NATIVE_TEST_SITE", "native-test.localhost") != "native-test.localhost":
            self.fail("Workspace tests require native-test.localhost")
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site="native-test.localhost", sites_path=".")
        frappe.connect()
        frappe.set_user("Administrator")

    def tearDown(self):
        frappe.db.rollback()
        frappe.clear_cache(user="Administrator")
        frappe.destroy()

    def test_factory_actions_respect_underlying_core_permissions(self):
        company = "ERP Native Verification"
        staff = frappe.get_doc({"doctype": "User", "email": "factory-access-" + frappe.generate_hash(length=8) + "@example.invalid",
            "first_name": "Factory worker", "user_type": "System User", "send_welcome_email": 0,
            "roles": [{"role": name} for name in ("Knitting Manager", "Accounts User", "Stock User", "Sales User")]}).insert()
        frappe.set_user(staff.name)
        original = workspace.context(company)
        self.assertIn("factory", original["capabilities"])
        self.assertIn("Sales Order", original["readable_records"])
        self.assertIn("Item", original["readable_records"])
        blocked = original["unavailable_knitting_actions"]
        self.assertIn("create_machine", blocked)
        self.assertIn("create_subcontract", blocked)
        self.assertIn("create_yarn_order", blocked)
        self.assertNotIn("subcontract_bill", blocked)
        frappe.set_user("Administrator")
        staff.add_roles("Manufacturing User", "Purchase User")
        frappe.clear_cache(user=staff.name)
        frappe.set_user(staff.name)
        enabled = workspace.context(company)
        self.assertFalse(set(enabled["unavailable_knitting_actions"]) & {"create_machine", "create_subcontract", "create_yarn_order"})
        self.assertNotEqual(original["access_fingerprint"], enabled["access_fingerprint"])

    def test_selection_is_remembered_only_while_permitted(self):
        selected = "ERP Native Verification"
        other = "ERP Knitting Verification"
        original_default = frappe.defaults.get_user_default("Company")
        self.assertEqual(workspace.select_company(selected)["company"], selected)
        workspace.context(other)
        self.assertEqual(workspace.context()["company"], selected)
        self.assertEqual(frappe.defaults.get_user_default("Company"), original_default)
        with patch.object(workspace.permissions, "companies", return_value=[frappe._dict(name=other)]):
            self.assertEqual(workspace.context()["company"], other)
            with self.assertRaises(frappe.PermissionError):
                workspace.select_company(selected)

    def test_imported_history_capability_and_access_revision_follow_server_scope(self):
        company='ERP Native Verification'
        with patch('erp_extensions.migration.api.available',return_value=False):
            hidden=workspace.context(company)
        with patch('erp_extensions.migration.api.available',return_value=True):
            shown=workspace.context(company)
        self.assertFalse(hidden['can_read_imported_history'])
        self.assertTrue(shown['can_read_imported_history'])
        self.assertNotEqual(hidden['access_fingerprint'],shown['access_fingerprint'])

    def test_signed_in_user_without_company_read_gets_an_empty_workspace(self):
        user = frappe.get_doc({"doctype": "User", "email": "no-company-" + frappe.generate_hash(length=8) + "@example.invalid",
                               "first_name": "Unassigned worker", "user_type": "Website User", "send_welcome_email": 0}).insert()
        frappe.set_user(user.name)
        self.assertFalse(frappe.has_permission("Company", "read"))
        context = workspace.context()
        self.assertIsNone(context["company"])
        self.assertEqual(context["companies"], [])
        self.assertFalse(context['can_read_imported_history'])
        with self.assertRaises(frappe.PermissionError):
            workspace.context("ERP Native Verification")

    def test_customer_navigation_and_access_revision_follow_scope_membership(self):
        company = 'ERP Native Verification'
        with patch('erp_extensions.migration.api.customer_workspace', return_value=False):
            general = workspace.context(company)
        with patch('erp_extensions.migration.api.customer_workspace', return_value=True):
            customer = workspace.context(company)
        self.assertFalse(general['knitting_only'])
        self.assertTrue(customer['knitting_only'])
        self.assertNotEqual(general['access_fingerprint'], customer['access_fingerprint'])
