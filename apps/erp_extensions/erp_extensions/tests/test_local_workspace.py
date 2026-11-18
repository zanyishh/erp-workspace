"""Local demos use independent owners, companies, records and invoice settings."""
import os
import unittest
from unittest.mock import patch

import frappe


class LocalWorkspaceTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        frappe.set_user('Administrator')
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)

    def test_separate_demo_companies_are_scoped_and_repeat_without_rewriting_records(self):
        from erp_extensions import api, invoices, local_workspace, workspace

        def records(company):
            return frappe.get_all('Sales Invoice', filters={'company': company},
                fields=['name', 'modified', 'docstatus', 'customer', 'grand_total', 'po_no'], order_by='name')

        original_knitting = records('Kaveri Loomworks')
        access = local_workspace.provision()
        self.assertEqual(access['company'], 'Meridian Trading')
        self.assertEqual(access['account'], 'local-general-owner@workspace.example.invalid')
        self.assertEqual([(row['company'], row['industry']) for row in access['workspaces']],
                         [('Meridian Trading', 'general'), ('Kaveri Loomworks', 'knitting')])
        self.assertTrue(access['key'] == access['workspaces'][0]['key'])
        self.assertTrue(access['secret'] == access['workspaces'][0]['secret'])
        if original_knitting:
            self.assertEqual(records('Kaveri Loomworks'), original_knitting)
        snapshots = {row['company']: records(row['company']) for row in access['workspaces']}
        second = local_workspace.provision()
        for first, repeated in zip(access['workspaces'], second['workspaces']):
            self.assertTrue(first['key'] == repeated['key'])
            self.assertTrue(first['secret'] == repeated['secret'])
            self.assertEqual(records(first['company']), snapshots[first['company']])

        general_samples = [r for r in snapshots['Meridian Trading'] if r.po_no.startswith('Local general sample invoice ')]
        self.assertEqual(len(general_samples), 3)
        self.assertEqual(sorted((r.docstatus, float(r.grand_total)) for r in general_samples),
                         [(0, 24000), (1, 7600), (1, 18000)])
        self.assertEqual(frappe.db.count('Knitting Job', {'company': 'Meridian Trading'}), 0)
        for row in access['workspaces']:
            company, account = row['company'], row['account']
            foreign = next(other['company'] for other in access['workspaces'] if other['company'] != company)
            foreign_invoice = next(r.name for r in snapshots[foreign] if r.docstatus == 1)
            frappe.set_user(account)
            current = workspace.context()
            self.assertEqual(current['company'], company)
            self.assertEqual([c.name for c in current['companies']], [company])
            self.assertEqual(current['knitting_enabled'], row['industry'] == 'knitting')
            if row['industry'] == 'general':
                self.assertFalse(current['capabilities'])
                catalogue = api.catalog(company)
                self.assertFalse([r for r in catalogue['types'] if r['name'].startswith('Knitting ')])
                self.assertFalse([r for r in catalogue['reports'] if (r['ref_doctype'] or '').startswith('Knitting ')])
            self.assertTrue(current['can_manage_team'])
            self.assertNotIn('System Manager', frappe.get_roles(account))
            self.assertEqual({r.owner for r in frappe.get_list('Customer', fields=['owner'], limit=0)}, {account})
            self.assertEqual({r.owner for r in frappe.get_list('Item', fields=['owner'], limit=0)}, {account})
            self.assertTrue(invoices.register(company)['rows'])
            for operation in (lambda: workspace.context(foreign),
                              lambda: invoices.register(foreign),
                              lambda: invoices.print_data(company, foreign_invoice),
                              lambda: invoices.get_settings(foreign),
                              lambda: invoices.set_template(company, foreign_invoice, 'ledger')):
                with self.assertRaises(frappe.PermissionError):
                    operation()
        frappe.set_user('Administrator')

    def test_provisioning_is_limited_to_the_isolated_administrator_console(self):
        from erp_extensions.local_workspace import provision
        with patch.object(frappe.local, 'site', 'frontend'):
            with self.assertRaises(RuntimeError):
                provision()
        with patch.object(frappe.local, 'request', object(), create=True):
            with self.assertRaises(RuntimeError):
                provision()
        frappe.set_user('Guest')
        with self.assertRaises(RuntimeError):
            provision()
