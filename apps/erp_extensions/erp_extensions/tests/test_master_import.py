"""Company master CSV import through the app's API on synthetic isolated fixtures."""
import os
import secrets
import unittest

import frappe
from erp_extensions import api, master_import, onboarding


class MasterImportTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        frappe.set_user('Administrator')
        self.company = 'ERP Native Verification'
        self.group = frappe.db.get_value('Customer Group', {'is_group':0}, 'name')
        self.territory = frappe.db.get_value('Territory', {'is_group':0}, 'name')
        self.header = ','.join(master_import.COLUMNS['Customer'])
        self.key = 'CSV '+secrets.token_hex(5)

    def test_customer_file_preview_replay_and_permission(self):
        frappe.set_user('Guest')
        company = self.key+' company'
        email = 'import-'+secrets.token_hex(6)+'@example.invalid'
        onboarding.register_owner('Store Owner', email, secrets.token_urlsafe(28), company, 'general')
        frappe.set_user(email)
        content = f'{self.header}\r\n"{self.key}, South",Company,{self.group},{self.territory}\r\n'
        preview = api.import_masters('Customer',company,content,'preview')
        self.assertEqual((preview['count'], preview['sample'][0][0]), (1,self.key+', South'))
        self.assertFalse(frappe.db.exists('Customer',{'customer_name':self.key+', South'}))
        api.import_masters('Customer',company,content,'confirm')
        again = api.import_masters('Customer',company,content,'confirm')
        self.assertTrue(again['already_imported'])
        self.assertEqual(frappe.db.count('Customer',{'customer_name':self.key+', South'}),1)
        with self.assertRaises(frappe.PermissionError):
            api.import_masters('Customer',self.company,content,'confirm')
        frappe.set_user('Guest')
        with self.assertRaises(frappe.PermissionError):
            api.import_masters('Customer',company,content,'preview')

    def test_csv_errors_and_arbitrary_columns_are_rejected(self):
        with self.assertRaisesRegex(frappe.ValidationError,'column headers'):
            api.import_masters('Customer',self.company,'name,owner\nX,Administrator','confirm')
        duplicate = f'{self.header}\n{self.key},Company,{self.group},{self.territory}\n{self.key},Company,{self.group},{self.territory}'
        with self.assertRaisesRegex(frappe.ValidationError,'Line 3'):
            api.import_masters('Customer',self.company,duplicate,'preview')
        with self.assertRaisesRegex(frappe.ValidationError,'Line 2'):
            api.import_masters('Customer',self.company,f'{self.header}\n{self.key},Company,missing group,{self.territory}','preview')
        self.assertFalse(frappe.db.exists('Customer',{'customer_name':self.key}))
        content = f'{self.header}\n{self.key},Company,{self.group},{self.territory}\n{self.key} missing,Company,missing group,{self.territory}'
        with self.assertRaisesRegex(frappe.ValidationError, 'Line 3'):
            api.import_masters('Customer',self.company,content,'confirm')
        self.assertFalse(frappe.db.exists('Customer',{'customer_name':self.key}))

    def test_bulk_group_changes_check_every_revision_before_writing(self):
        parent = frappe.get_doc('Customer Group',self.group).parent_customer_group
        target=frappe.get_doc({'doctype':'Customer Group','customer_group_name':self.key+' group','parent_customer_group':parent}).insert()
        customers = []
        for suffix in (' first',' second'):
            customer = frappe.get_doc({'doctype':'Customer','customer_name':self.key+suffix,'customer_type':'Company',
                'customer_group':self.group,'territory':self.territory}).insert()
            customers.append({'name':customer.name,'modified':str(customer.modified)})
        with self.assertRaises(frappe.TimestampMismatchError):
            api.reclassify_masters('Customer',self.company,[customers[0],dict(customers[1],modified='2000-01-01')],target.name)
        self.assertEqual(frappe.db.get_value('Customer',customers[0]['name'],'customer_group'),self.group)
        self.assertEqual(api.reclassify_masters('Customer',self.company,customers,target.name)['count'],2)
        self.assertTrue(all(frappe.db.get_value('Customer',r['name'],'customer_group')==target.name for r in customers))
