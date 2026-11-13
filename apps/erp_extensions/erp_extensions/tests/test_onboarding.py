"""Real, transaction-rolled-back signup and staff journeys on the isolated site."""
import hashlib
import os
import secrets
import unittest

import frappe

from erp_extensions import workspace


class OnboardingTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        self.suffix = secrets.token_hex(5)
        self.company = 'New workspace ' + self.suffix
        self.owner = 'owner-' + self.suffix + '@example.invalid'
        self.staff = 'staff-' + self.suffix + '@example.invalid'
        self.password = secrets.token_urlsafe(20)
        from erp_extensions import onboarding
        self.service = onboarding
        frappe.set_user('Guest')

    def signup(self, industry='general'):
        result = self.service.register_owner('Business Owner', self.owner, self.password, self.company, industry)
        self.assertEqual(result, {'company': self.company, 'email': self.owner})
        self.assertEqual(frappe.session.user, 'Guest')
        frappe.set_user(self.owner)
        return workspace.context()

    def test_general_owner_and_knitting_scope(self):
        context = self.signup('knitting')
        self.assertEqual([c.name for c in context['companies']], [self.company])
        self.assertTrue(context['knitting_enabled'])
        self.assertTrue(all(row['ready'] for row in context['readiness']))
        self.assertTrue(context['can_manage_team'])
        self.assertNotIn('System Manager', frappe.get_roles())
        self.assertEqual(frappe.get_list('User', pluck='name'), [self.owner])
        self.assertEqual(frappe.get_list('Customer', pluck='name'), [])
        self.assertEqual(len(frappe.get_list('Item', pluck='name')), 2)
        with self.assertRaises(frappe.PermissionError):
            frappe.get_doc('Item', 'DEMO-KNIT-FABRIC').check_permission('read')
        with self.assertRaises(frappe.PermissionError):
            self.service.team('ERP Native Verification')

    def test_staff_invites_are_bound_to_one_company_email_and_role(self):
        context = self.signup()
        self.assertFalse(context['needs_industry_selection'])
        self.assertFalse(context['knitting_enabled'])
        with self.assertRaises(frappe.ValidationError):
            self.service.invite_member(self.company, self.staff, 'System Manager')
        with self.assertRaises(frappe.ValidationError):
            self.service.invite_member(self.company, self.staff, 'operator')
        first = self.service.invite_member(self.company, self.staff, 'sales')
        second = self.service.invite_member(self.company, self.staff, 'accounts')
        invites = self.service.team(self.company)['invitations']
        self.assertEqual(len(invites), 1)
        digest = frappe.db.get_value('Workspace Staff Invitation', invites[0]['name'], 'token_digest')
        self.assertEqual(digest, hashlib.sha256(second['token'].encode()).hexdigest())
        frappe.set_user('Guest')
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(first['token'], 'Worker', self.staff, self.password)
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(second['token'], 'Worker', self.owner, self.password)
        result = self.service.accept_invite(second['token'], 'Worker', self.staff, self.password)
        self.assertEqual(result['email'], self.staff)
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(second['token'], 'Worker', self.staff, self.password)
        frappe.set_user(self.staff)
        self.assertFalse(workspace.context()['can_manage_team'])
        self.assertEqual({r.name for r in workspace.context()['companies']}, {self.company})
        self.assertIn('Accounts User', frappe.get_roles())
        self.assertNotIn('Sales User', frappe.get_roles())
        with self.assertRaises(frappe.PermissionError):
            self.service.team(self.company)
        frappe.set_user(self.owner)
        self.assertEqual({r['email'] for r in self.service.team(self.company)['members']}, {self.owner, self.staff})
        self.assertEqual(self.service.team(self.company)['invitations'], [])

    def test_existing_login_expiry_and_revocation(self):
        self.signup('knitting')
        email = self.staff
        frappe.set_user('Administrator')
        frappe.get_doc({'doctype':'User','email':email,'first_name':'Unassigned','user_type':'Website User','send_welcome_email':0,'new_password':self.password}).insert()
        frappe.set_user(self.owner)
        invite = self.service.invite_member(self.company, email, 'checker')
        frappe.set_user('Guest')
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(invite['token'], 'Replacement', email, self.password)
        frappe.set_user(self.owner)
        row = self.service.team(self.company)['invitations'][0]
        self.service.revoke_invite(self.company, row['name'])
        frappe.set_user(email)
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(invite['token'])
        frappe.set_user(self.owner)
        expired = self.service.invite_member(self.company, email, 'checker')
        row = self.service.team(self.company)['invitations'][0]
        frappe.db.set_value('Workspace Staff Invitation', row['name'], 'expires_at', '2020-01-01')
        frappe.set_user(email)
        with self.assertRaises(frappe.ValidationError):
            self.service.accept_invite(expired['token'])
        frappe.set_user(self.owner)
        valid = self.service.invite_member(self.company, email, 'checker')
        frappe.set_user(email)
        result = self.service.accept_invite(valid['token'])
        self.assertEqual(result['email'], email)
        self.assertEqual(frappe.session.user, email)
        self.assertIn('Knitting Checker', frappe.get_roles())
        self.assertFalse(workspace.context()['can_manage_team'])

    def test_managed_native_documents_and_reports(self):
        from erp_extensions import api
        self.signup()
        group = frappe.db.get_value('Customer Group', {'is_group':0}, 'name')
        territory = frappe.db.get_value('Territory', {'is_group':0}, 'name')
        name = 'New customer ' + self.suffix
        doc = api.save({'doctype':'Customer','__islocal':1,'customer_name':name,'customer_type':'Company','customer_group':group,'territory':territory})['doc']
        customer = doc['name']
        self.assertEqual([r['name'] for r in api.records('Customer')], [customer])
        self.assertEqual([r['value'] for r in api.search_link('Customer')], [customer])
        with self.assertRaises(frappe.PermissionError):
            api.document('Customer', 'Demo Knitting Mills')
        with self.assertRaises(frappe.PermissionError):
            api.document('Workspace Staff Invitation', self.suffix)
        invite = self.service.invite_member(self.company, self.staff, 'sales')
        frappe.set_user('Guest')
        self.service.accept_invite(invite['token'], 'Sales worker', self.staff, self.password)
        frappe.set_user(self.staff)
        self.assertEqual(api.document('Customer', customer)['doc']['customer_name'], name)
        self.assertEqual([r['value'] for r in api.search_link('Customer')], [customer])
        with self.assertRaises(frappe.PermissionError):
            api.records('Sales Invoice')
        frappe.set_user(self.owner)
        self.assertEqual(api.records('Sales Invoice'), [])
        catalog = api.catalog(self.company)
        reports = {row.name for row in catalog['reports']}
        for report in ('General Ledger','Accounts Receivable','Accounts Payable','Stock Ledger','Stock Balance',
                       'Sales Order Analysis','Purchase Order Analysis','Trial Balance','Profit and Loss Statement','Balance Sheet'):
            with self.subTest(report=report):
                self.assertIn(report, reports)
                settings = api.report_definition(report, self.company)['defaults']
                result = api.run_report(report, settings)
                self.assertIsInstance(result['result'], list)
                self.assertNotIn('ERP Native Verification', frappe.as_json(result['result']))
                self.assertNotIn('Demo Knitting Mills', frappe.as_json(result['result']))
                with self.assertRaises(frappe.PermissionError):
                    api.run_report(report, {**settings, 'company':'ERP Native Verification'})
        with self.assertRaises(frappe.PermissionError):
            api.run_report('System Health Report', {})

    def test_stock_clerk_and_owner_master_permissions(self):
        self.signup()
        for kind in ('Supplier','Customer','Item','Item Price','Warehouse'):
            self.assertTrue(frappe.has_permission(kind, 'create'), kind)
        for kind in ('Sales Order','Delivery Note','Sales Invoice','Purchase Order','Purchase Receipt','Purchase Invoice','Payment Entry'):
            self.assertTrue(frappe.has_permission(kind, 'submit'), kind)
        invite = self.service.invite_member(self.company, self.staff, 'stock')
        frappe.set_user('Guest')
        self.service.accept_invite(invite['token'], 'Store clerk', self.staff, self.password)
        frappe.set_user(self.staff)
        self.assertTrue(frappe.has_permission('Stock Entry', 'read'))
        self.assertTrue(frappe.has_permission('Stock Entry', 'create'))
        self.assertFalse(self.service.can_manage_team(self.company))
        self.assertNotIn('Item Manager', frappe.get_roles())

    def test_signup_gate_is_server_controlled_and_hosted_claim_requires_an_empty_site(self):
        from unittest.mock import patch
        with patch.dict(frappe.conf, {'native_owner_signup':0}):
            with self.assertRaisesRegex(frappe.ValidationError, 'closed'):
                self.service.register_owner('Owner', self.owner, self.password, self.company, 'general')
        # Model a dedicated host using real rows on the local DB, never contacting another site.
        original_site = frappe.local.site
        try:
            frappe.local.site = 'fresh-company.example.invalid'
            with patch.object(frappe.db, 'get_value', return_value=None):
                self.service._check_hosted_company()
            with self.assertRaisesRegex(frappe.ValidationError, 'already belongs'):
                self.service._check_hosted_company()
        finally:
            frappe.local.site = original_site

    def test_duplicate_names_and_existing_erp_accounts_keep_original_access(self):
        self.signup()
        frappe.set_user('Guest')
        with self.assertRaisesRegex(frappe.ValidationError, 'name is in use'):
            self.service.register_owner('Other owner', self.staff, self.password, self.company, 'general')
        self.assertFalse(frappe.db.exists('User', self.staff))
        with self.assertRaisesRegex(frappe.ValidationError, 'already exists'):
            self.service.register_owner('Another person', self.owner, self.password, self.company + ' Other', 'knitting')
        self.assertFalse(frappe.db.exists('Company', self.company + ' Other'))
        frappe.set_user(self.owner)
        email = 'knit-operator@example.invalid'
        invite = self.service.invite_member(self.company, email, 'sales')
        frappe.set_user(email)
        with self.assertRaisesRegex(frappe.ValidationError, 'already has ERP access'):
            self.service.accept_invite(invite['token'])
        self.assertNotIn('Sales User', frappe.get_roles())
        self.assertFalse(self.service.membership())
