"""Synthetic knitting scenarios; refuse any site other than the isolated test site."""
import importlib
import os
import unittest

import frappe

COMPANY = "ERP Native Verification"


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

