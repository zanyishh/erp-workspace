"""Customer navigation scope with synthetic framework rows; no site or network."""
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class Row(dict):
    __getattr__ = dict.get


class CustomerWorkspaceScopeTests(unittest.TestCase):
    def setUp(self):
        self.company = 'Customer Mill'
        self.member = True
        self.denied = set()
        self.types = [Row(name=name, module=module, issingle=0) for name, module in (
            ('Knitting Job', 'ERP Extensions'), ('Customer', 'Selling'),
            ('Sales Invoice', 'Accounts'), ('Payment Entry', 'Accounts'),
            ('Purchase Order', 'Buying'), ('Workstation', 'Manufacturing'),
            ('Employee', 'HR'), ('Project', 'Projects'), ('Lead', 'CRM'),
            ('Asset', 'Assets'), ('Website Settings', 'Website'))]
        self.reports = [Row(name=name, module='Accounts', ref_doctype=doctype, report_type='Script Report')
            for name, doctype in (('General Ledger', 'GL Entry'),
                ('Accounts Receivable', 'Sales Invoice'), ('Stock Balance', 'Stock Ledger Entry'),
                ('Project Summary', 'Project'), ('Employee Attendance', 'Employee'))]
        framework = SimpleNamespace(whitelist=lambda **kwargs: lambda fn: fn,
            session=SimpleNamespace(user='owner'), local=SimpleNamespace(site='synthetic.localhost'),
            db=SimpleNamespace(exists=lambda *args: True),
            defaults=SimpleNamespace(get_user_default=lambda key: None),
            get_all=self.get_all, get_roles=lambda: ['Knitting Manager'],
            has_permission=lambda doctype, *args, **kwargs: doctype not in self.denied,
            get_doc=lambda *args: SimpleNamespace(is_permitted=lambda: True),
            parse_json=json.loads)
        self.permissions = SimpleNamespace(companies=lambda: [Row(name=self.company)],
            company_allowed=lambda company: company == self.company,
            profile=lambda company: Row(state='Active', revision=1, settings='{}'),
            capabilities=lambda: {'overview', 'jobs', 'billing'},
            visible_type=lambda *args: True,
            is_pack=lambda doctype: doctype.startswith('Knitting '))
        team = SimpleNamespace(membership=lambda: None,
            COMPANY_REPORTS={'General Ledger', 'Accounts Receivable', 'Stock Balance'})
        self.modules = {
            'frappe': framework, 'frappe.permissions': SimpleNamespace(get_doc_permissions=lambda doc: {}),
            'frappe.utils': SimpleNamespace(cint=int, flt=float, get_datetime=lambda value: value),
            'erp_extensions': SimpleNamespace(team_scope=team,
                operations=SimpleNamespace(available=lambda: True),
                master_import=SimpleNamespace(allowed=lambda dt: False, GROUPS=set())),
            'erp_extensions.knitting': SimpleNamespace(permissions=self.permissions),
            'erp_extensions.knitting.permissions': self.permissions,
            'erp_extensions.onboarding': SimpleNamespace(can_manage_team=lambda company: False, membership=lambda: None),
            'erp_extensions.team_scope': team,
            'erp_extensions.reconciliation': SimpleNamespace(permitted=lambda: True),
            'erp_extensions.bank_matching': SimpleNamespace(permitted=lambda: True),
            'erp_extensions.pos_checkout': SimpleNamespace(permitted=lambda: False),
            'erp_extensions.migration': SimpleNamespace(contracts=SimpleNamespace(), service=SimpleNamespace(
                get_scope=lambda name: {'name':name, 'allowed_users':['owner'] if self.member else []})),
            'erp_extensions.migration.install': SimpleNamespace(SCOPE='Scope', RECORD='History', AUTHORITY='Authority'),
        }
        self.patcher = patch.dict(sys.modules, self.modules)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.history = self.load('erp_extensions.migration.api', 'migration/api.py')
        self.workspace = self.load('erp_extensions.workspace', 'workspace.py')
        self.api = self.load('erp_extensions.api', 'api.py')

    def load(self, name, path):
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions' / path
        spec = importlib.util.spec_from_file_location(name, source)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module

    def get_all(self, doctype, **kwargs):
        if doctype == 'Scope':
            return ['scope'] if self.company == 'Customer Mill' else []
        if doctype == 'History':
            return ['original']
        if doctype == 'DocType':
            return self.types
        if doctype == 'Report':
            return self.reports
        return []

    def test_scope_members_receive_knitting_navigation_and_fingerprint_revocation(self):
        # Keeping history availability fixed isolates the navigation cache contract.
        with patch.object(self.history, 'available', return_value=True):
            shown = self.workspace.context(self.company)
            self.member = False
            hidden = self.workspace.context(self.company)
        self.assertTrue(shown.get('knitting_only'))
        self.assertFalse(hidden.get('knitting_only'))
        self.assertNotEqual(shown['access_fingerprint'], hidden['access_fingerprint'])

    def test_general_and_knitting_demos_keep_general_navigation(self):
        self.company = 'Synthetic Demo'
        self.assertIs(self.workspace.context(self.company).get('knitting_only'), False)
        self.assertEqual({row['name'] for row in self.api.catalog(self.company)['types']},
            {row.name for row in self.types})

    def test_customer_navigation_requires_permitted_company_and_scope_member(self):
        for company in (None, '', 'Other Company'):
            with self.subTest(company=company):
                self.assertFalse(self.history.customer_workspace(company))
        self.member = False
        self.assertFalse(self.history.customer_workspace(self.company))

    def test_customer_catalog_keeps_operating_records_without_other_industries(self):
        catalog = self.api.catalog(self.company)
        self.assertEqual({row['name'] for row in catalog['types']},
            {'Knitting Job', 'Customer', 'Sales Invoice', 'Payment Entry', 'Purchase Order', 'Workstation'})
        self.assertEqual({row['name'] for row in catalog['reports']},
            {'General Ledger', 'Accounts Receivable', 'Stock Balance'})

    def test_customer_catalog_without_company_uses_selected_workspace_scope(self):
        self.assertEqual({row['name'] for row in self.api.catalog()['types']},
            {'Knitting Job', 'Customer', 'Sales Invoice', 'Payment Entry', 'Purchase Order', 'Workstation'})

    def test_customer_catalog_still_applies_native_permissions(self):
        self.denied.add('Sales Invoice')
        catalog = self.api.catalog(self.company)
        self.assertNotIn('Sales Invoice', {row['name'] for row in catalog['types']})
        self.assertNotIn('Accounts Receivable', {row['name'] for row in catalog['reports']})

    def test_existing_invoice_read_checks_the_register_company(self):
        invoice = Mock(company='Second Mill')
        framework = self.modules['frappe']
        framework.PermissionError = PermissionError
        def throw(message, error):
            raise error(message)

        framework.throw = throw
        with patch.object(framework, 'get_doc', return_value=invoice), \
                patch.object(self.api, '_meta', return_value=Row(issingle=False)), \
                patch.object(self.api, '_result', return_value='visible'):
            with self.assertRaises(PermissionError):
                self.api.document('Sales Invoice', 'INV-1', company='First Mill')
            invoice.run_method.assert_not_called()
            self.assertEqual(self.api.document('Sales Invoice', 'INV-1', company='Second Mill'), 'visible')
            self.assertEqual(self.api.document('Sales Invoice', 'INV-1'), 'visible')
            invoice.check_permission.side_effect = PermissionError('Read denied')
            with self.assertRaisesRegex(PermissionError, 'Read denied'):
                self.api.document('Sales Invoice', 'INV-1', company='Second Mill')


if __name__ == '__main__':
    unittest.main()
