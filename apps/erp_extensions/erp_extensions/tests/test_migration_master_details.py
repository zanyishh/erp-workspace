"""Synthetic native Address/Tax ID enrichment; native-test lifecycle only."""
import unittest
from copy import deepcopy
from unittest.mock import patch

import frappe
from erp_extensions.migration import master_details
from erp_extensions.tests import test_migration_finance as finance_fixtures


class HistoricalMasterDetailTests(unittest.TestCase):
    setUpClass = classmethod(finance_fixtures.HistoricalFinanceTests.setUpClass.__func__)
    cleanup = finance_fixtures.HistoricalFinanceTests.cleanup

    def setUp(self):
        finance_fixtures.HistoricalFinanceTests.setUp(self)
        enabled = patch.dict(frappe.conf, {"erp_customer_migration_enabled": True})
        enabled.start()
        self.addCleanup(enabled.stop)

    def fixture(self):
        customer = frappe.get_doc({"doctype": "Customer", "customer_name": "Synthetic master " + self.suffix,
            "customer_type": "Company", "customer_group": frappe.db.get_value("Customer Group", {"is_group": 0}, "name"),
            "territory": frappe.db.get_value("Territory", {"is_group": 0}, "name")}).insert(set_name="KP-PARTY-7")
        supplier = frappe.get_doc({"doctype": "Supplier", "supplier_name": "Synthetic master supplier " + self.suffix,
            "supplier_type": "Company", "supplier_group": frappe.db.get_value("Supplier Group", {"is_group": 0}, "name")}).insert(set_name="KP-SUPPLIER-7")
        source = {"id": "7", "party_name": "Synthetic source master", "gstin": "33ABCDE1234F1Z5",
            "email": "master-detail@example.invalid",
            "bill_address1": "1 Example Road", "bill_address2": "Block A", "bill_city": "Example City",
            "bill_country": "India", "bill_state": "Tamil Nadu", "bill_zip_code": "600001"}
        entity = master_details.party_details(source, self.scope, supplier=True, countries={"India"})
        from erp_extensions.migration import service
        return customer, supplier, {"scope": self.scope, "manifest_sha256": service.get_scope(self.scope)["manifest_sha256"], "entities": [entity]}

    def test_native_address_tax_and_both_links_are_idempotent(self):
        customer, supplier, package = self.fixture()
        original = deepcopy(package)
        first = master_details.apply_enrichment(self.scope, package)
        self.assertEqual(package, original)
        second = master_details.apply_enrichment(self.scope, package)
        self.assertEqual(first["addresses_created"], 1)
        self.assertEqual(second["addresses_created"], 0)
        self.assertEqual(second["addresses_reused"], 1)
        self.assertEqual(second["master_updates"], 0)
        address = package["entities"][0]["addresses"][0]["name"]
        customer.reload()
        supplier.reload()
        self.assertEqual(customer.tax_id, "33ABCDE1234F1Z5")
        self.assertEqual(supplier.tax_id, customer.tax_id)
        self.assertEqual(customer.customer_primary_address, address)
        self.assertEqual(supplier.supplier_primary_address, address)
        self.assertTrue(customer.customer_primary_contact)
        self.assertEqual(supplier.supplier_primary_contact, customer.customer_primary_contact)
        self.assertEqual(customer.email_id, "master-detail@example.invalid")
        self.assertEqual(first["business_contacts_created"], 1)
        self.assertEqual(second["business_contacts_reused"], 1)
        self.assertEqual(frappe.db.get_value("Address", address, "city"), "Example City")

    def test_existing_conflicting_tax_identifier_is_never_overwritten(self):
        customer, _, package = self.fixture()
        customer.tax_id = "EXISTING-TAX-ID"
        customer.save()
        with self.assertRaises(frappe.ValidationError):
            master_details.apply_enrichment(self.scope, package)
        customer.reload()
        self.assertEqual(customer.tax_id, "EXISTING-TAX-ID")
        self.assertFalse(frappe.db.exists("Address", package["entities"][0]["addresses"][0]["name"]))

    def test_optional_service_tax_templates_use_native_accounts_and_retry_without_defaults(self):
        from erp_extensions.migration import service, tax_templates
        scope = service.get_scope(self.scope)
        originals = {}
        for native_id, company in scope["company_bindings"].items():
            frappe.db.set_value("Company", company, {"tax_id": "33ABCDE1234F1Z5", "country": "India"})
            originals[native_id] = {"id": native_id, "country": "India", "gstin": "33ABCDE1234F1Z5"}
        package = tax_templates.compile_options(scope=self.scope, manifest_sha256=scope["manifest_sha256"],
            hsns=[{"id": "7", "hsn_type": "service", "hsn": "999999", "status": "1",
                   "cgst": "2.5", "sgst": "2.5", "igst": "5", "percentage": "5"}],
            companies=originals, company_bindings=scope["company_bindings"],
            evidence=[{"file": "synthetic.json", "sha256": "b" * 64}])
        before = deepcopy(package)
        first = tax_templates.apply_options(self.scope, package)
        second = tax_templates.apply_options(self.scope, package)
        self.assertEqual(package, before)
        self.assertEqual(first["templates_created"], 8)
        self.assertEqual(second["templates_reused"], 8)
        self.assertEqual(second["accounts_reused"], 12)
        self.assertEqual(second["default_templates_assigned"], 0)
        for entry in package["companies"]:
            for template in entry["templates"]:
                name = frappe.db.get_value("Sales Taxes and Charges Template", {"company": entry["company"], "title": template["title"]}, "name")
                doc = frappe.get_doc("Sales Taxes and Charges Template", name)
                self.assertFalse(doc.is_default)
                self.assertEqual(len(doc.taxes), len(template["rates"]))
                self.assertTrue(all(row.cost_center == frappe.db.get_value("Company", entry["company"], "cost_center") for row in doc.taxes))
        doc.taxes[0].cost_center = None
        doc.save()
        with self.assertRaises(frappe.ValidationError):
            tax_templates.apply_options(self.scope, package)
        doc.taxes[0].cost_center = frappe.db.get_value("Company", doc.company, "cost_center")
        doc.save()
        frappe.db.set_value("Company", self.company, "tax_id", "33DIFFR1234F1Z5")
        with self.assertRaises(frappe.ValidationError):
            tax_templates.apply_options(self.scope, package)
