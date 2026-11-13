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
