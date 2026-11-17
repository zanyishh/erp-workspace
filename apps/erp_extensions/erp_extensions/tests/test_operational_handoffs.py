"""Native source actions preserve the actual ERPNext inspection and maintenance links."""
import os
import secrets
import unittest

import frappe
from frappe.utils import today, add_months


class OperationalHandoffs(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        from erp_extensions.onboarding import register_owner
        self.suffix = secrets.token_hex(5)
        self.email = 'operations-' + self.suffix + '@example.invalid'
        self.company = 'Operations verification ' + self.suffix
        frappe.set_user('Guest')
        register_owner('Operations owner', self.email, secrets.token_urlsafe(20), self.company, 'general')
        frappe.set_user(self.email)

    def test_receipt_row_creates_inspection_once_for_duplicate_item(self):
        from erp_extensions import operational_handoffs as service, api
        item = frappe.get_doc({'doctype':'Item','item_code':'Inspect '+self.suffix, 'item_group':frappe.db.get_value('Item Group',{'is_group':0}),
            'stock_uom':'Nos','is_stock_item':1,'inspection_required_before_purchase':1}).insert()
        supplier = frappe.get_doc({'doctype':'Supplier','supplier_name':'Inspect supplier '+self.suffix,
            'supplier_group':frappe.db.get_value('Supplier Group',{'is_group':0})}).insert()
        warehouse = frappe.get_cached_value('Company', self.company, 'default_warehouse')
        receipt = frappe.get_doc({'doctype':'Purchase Receipt','company':self.company,'supplier':supplier.name, 'posting_date':today(),
            'items':[{'item_code':item.name,'qty':qty,'rate':20,'warehouse':warehouse} for qty in (10,4)]}).insert()
        self.assertIn('Inspect receipt items', api.document('Purchase Receipt', receipt.name)['related_actions'])
        rows = service.receipt_items(receipt.name)['rows']
        self.assertEqual(len(rows),2)
        inspection = service.inspect_receipt(receipt.name, rows[1]['row'], '2', str(receipt.modified))
        self.assertEqual(frappe.get_doc('Quality Inspection',inspection['name']).child_row_reference, receipt.items[1].name)
        inspection_doc = frappe.get_doc('Quality Inspection',inspection['name'])
        inspection_doc.status = 'Accepted'
        inspection_doc.submit()
        self.assertEqual(receipt.reload().items[1].quality_inspection, inspection['name'])
        self.assertFalse(receipt.items[0].quality_inspection)
        self.assertEqual(service.inspect_receipt(receipt.name, rows[1]['row'],'2',str(receipt.modified))['name'], inspection['name'])
        self.assertEqual(frappe.db.count('Quality Inspection', {'reference_name':receipt.name}),1)
        with self.assertRaises(frappe.ValidationError):
            service.inspect_receipt(receipt.name, rows[0]['row'], '99', str(receipt.modified))

    def test_maintenance_plan_opens_due_log_and_reschedules_on_completion(self):
        from erp_extensions import operational_handoffs as service, api
        name = self.suffix
        location = frappe.get_doc({'doctype':'Location','location_name':'Test workshop '+name}).insert()
        category = frappe.get_doc({'doctype':'Asset Category','asset_category_name':'Machines '+name,'accounts':[{'company_name':self.company,'fixed_asset_account':frappe.db.get_value('Account',{'company':self.company,'account_type':'Fixed Asset','is_group':0},'name')}]}).insert()
        frappe.set_user(self.email)
        item = frappe.get_doc({'doctype':'Item','item_code':'Test machine '+name, 'item_group':frappe.db.get_value('Item Group',{'is_group':0}),
            'stock_uom':'Nos','is_stock_item':0,'is_fixed_asset':1, 'asset_category':category.name}).insert()
        asset = frappe.get_doc({'doctype':'Asset','company':self.company,'asset_name':'Test machine '+name,'item_code':item.name,'asset_category':category.name,
            'is_existing_asset':1,'purchase_date':today(),'available_for_use_date':today(),'location':location.name,'gross_purchase_amount':1000,
            'purchase_amount':1000, 'net_purchase_amount':1000,'maintenance_required':1}).insert().submit()
        pending = service.asset_plan(asset.name)
        self.assertEqual(pending['draft']['doc']['asset_name'],asset.name)
        team = frappe.get_doc({'doctype':'Asset Maintenance Team', 'company':self.company,'maintenance_team_name':'Maintainers '+name,'maintenance_manager':self.email,
            'maintenance_team_members':[{'team_member':self.email,'maintenance_role':'Quality Manager'}]}).insert()
        plan = frappe.get_doc({'doctype':'Asset Maintenance','company':self.company,'asset_name':asset.name,'maintenance_team':team.name,
            'asset_maintenance_tasks':[{'maintenance_task':'Calibration','maintenance_status':'Planned','maintenance_type':'Calibration','start_date':today(),
            'next_due_date':today(),'periodicity':'Monthly','assign_to':self.email}]}).insert()
        self.assertEqual(service.asset_plan(asset.name), {'name':plan.name})
        self.assertIn('Maintenance logs',api.document('Asset Maintenance',plan.name)['related_actions'])
        first=service.maintenance_logs(plan.name)['logs'][0]
        doc=api.document('Asset Maintenance Log',first['name'])['doc']
        self.assertEqual(doc['asset_maintenance'],plan.name)
        result=api.save({'doctype':'Asset Maintenance Log','name':doc['name'],'modified':doc['modified'],'maintenance_status':'Completed','completion_date':today(),'actions_performed':'Calibrated'},action='Submit')['doc']
        self.assertEqual(result['docstatus'],1)
        logs=service.maintenance_logs(plan.name)['logs']
        self.assertTrue(any(str(row.due_date)==str(add_months(today(),1)) and row.docstatus==0 for row in logs))
