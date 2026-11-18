import importlib.util
from pathlib import Path
import unittest


class MasterDetailTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[2] / "apps/erp_extensions/erp_extensions/migration/master_details.py"
        self.assertTrue(path.exists(), "The master detail compiler is not implemented")
        spec = importlib.util.spec_from_file_location("master_details", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.party = {"id": "7", "party_name": "Synthetic business", "gstin": "33ABCDE1234F1Z5", "bill_address1": "1 Example Road",
            "bill_address2": "Block A", "bill_address3": "Second floor", "bill_city": "Example City", "bill_country": "India", "bill_state": "Tamil Nadu",
            "bill_zip_code": "600001", "shipp_address1": "", "shipp_city": "", "shipp_country": ""}

    def test_complete_original_address_links_customer_and_supplier_once(self):
        result = self.module.party_details(self.party, "scope", supplier=True, countries={"India"})
        self.assertEqual(result["updates"][0]["tax_id"], self.party["gstin"])
        self.assertEqual(len(result["addresses"]), 1)
        address = result["addresses"][0]
        self.assertEqual(address["address_line2"], "Block A\nSecond floor")
        self.assertEqual({(r["link_doctype"], r["link_name"]) for r in address["links"]}, {("Customer", "KP-PARTY-7"), ("Supplier", "KP-SUPPLIER-7")})

    def test_missing_city_is_preserved_as_unavailable_without_native_address(self):
        self.party["bill_city"] = ""
        result = self.module.party_details(self.party, "scope", countries={"India"})
        self.assertFalse(result["addresses"])
        self.assertIn("city", result["address_coverage"]["billing"]["missing"])

    def test_identical_billing_and_shipping_share_one_native_address(self):
        for key, value in list(self.party.items()):
            if key.startswith("bill_"):
                self.party["shipp_" + key[5:]] = value
        result = self.module.party_details(self.party, "scope", countries={"India"})
        self.assertEqual(len(result["addresses"]), 1)
        self.assertEqual(result["addresses"][0]["is_shipping_address"], 1)

    def test_unmapped_country_and_overlong_street_do_not_create_partial_native_address(self):
        self.party["bill_address1"] = "x" * 241
        self.assertFalse(self.module.party_details(self.party, "scope", countries={"India"})["addresses"])
        self.party["bill_address1"] = "1 Example Road"
        self.assertFalse(self.module.party_details(self.party, "scope", countries={"Elsewhere"})["addresses"])

    def test_gst_display_requires_india_and_exact_gst_shape(self):
        gst = self.party["gstin"]
        self.assertEqual(self.module.india_gstin(gst, "India"), gst)
        for value, country in (("ABCDE1234F", "India"), ("GB123456789", "India"), (gst, "United Kingdom"), (gst, None)):
            self.assertIsNone(self.module.india_gstin(value, country))

    def test_parent_business_email_creates_company_contact_without_person_name(self):
        self.party['email'] = 'source@example.invalid'
        result = self.module.party_details(self.party, 'scope', countries={'India'})
        self.assertEqual(len(result['contacts']), 1)
        contact = result['contacts'][0]
        self.assertEqual(contact['company_name'], self.party['party_name'])
        self.assertNotIn('first_name', contact)
        self.assertEqual(contact['email_ids'][0]['email_id'], 'source@example.invalid')

    def test_multiple_company_phones_do_not_imply_a_primary_address_phone(self):
        source = {'id': '1', 'name': 'Synthetic company', 'address1': '1 Example Road', 'city': 'Example City',
                  'country': 'India', 'phone_no': '1111111111 , 2222222222'}
        result = self.module.company_details(source, 'scope', 'Native Company', countries={'India'})
        self.assertEqual(result['addresses'][0]['phone'], '')
        self.assertTrue(result['address_coverage']['billing']['phone_preserved_only_in_history'])
