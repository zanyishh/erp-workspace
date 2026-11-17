"""Synthetic native database contract tests; never target a customer site."""
import os
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests


class HistoricalStoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('NATIVE_TEST_SITE','native-test.localhost')!='native-test.localhost':
            raise RuntimeError('Historical tests require native-test.localhost')
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost',sites_path='.')
        frappe.connect();frappe.set_user('Administrator')
        try:
            from erp_extensions.migration.install import install
            install();frappe.db.commit()
        finally:frappe.destroy()

    def setUp(self):
        if os.environ.get('NATIVE_TEST_SITE','native-test.localhost')!='native-test.localhost':
            self.fail('Historical tests require native-test.localhost')
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost',sites_path='.')
        frappe.connect();frappe.set_user('Administrator')
        self.addCleanup(self._cleanup)
        self.companies=['ERP Native Verification','ERP Knitting Verification']
        for i in (3,4):
            suffix=frappe.generate_hash(length=6)
            doc=frappe.get_doc({'doctype':'Company','company_name':f'Synthetic Migration {i} {suffix}',
                'abbr':f'M{i}{suffix}','default_currency':'INR','country':'India'}).insert()
            self.companies.append(doc.name)
        fixture=HistoricalContractTests()
        self.values=fixture.record
        scope=fixture.scope();scope.update(source_instance='synthetic-'+frappe.generate_hash(length=10),
            company_bindings={str(i+1):name for i,name in enumerate(self.companies)},allowed_users=['Administrator'])
        self.scope=service.create_scope(scope)

    def _cleanup(self):
        frappe.db.rollback();frappe.clear_cache(user='Administrator');frappe.destroy()

    def test_repeat_is_idempotent_and_changed_original_is_rejected(self):
        first=service.store_record(self.scope,self.values())
        second=service.store_record(self.scope,self.values())
        self.assertEqual(first['name'],second['name']);self.assertFalse(second['created'])
        with self.assertRaises(frappe.ValidationError):
            service.store_record(self.scope,self.values(summary='Changed original'))
        row=service.get_record_for_effect(first['name'],self.companies[0],'financial')
        self.assertEqual(row['original_date_raw'],'2020-02-29')
        self.assertEqual(row['effective_date'],'2020-02-29')

    def test_generic_mutation_and_deletion_are_rejected(self):
        name=service.store_record(self.scope,self.values())['name']
        doc=frappe.get_doc(service.RECORD,name);doc.title='Changed'
        with self.assertRaises(frappe.PermissionError):doc.save(ignore_permissions=True)
        with self.assertRaises(frappe.PermissionError):frappe.delete_doc(service.RECORD,name,ignore_permissions=True)

    def test_cross_company_records_never_enter_a_page_or_detail(self):
        first=service.store_record(self.scope,self.values())['name']
        service.store_record(self.scope,self.values(source_company_id='2',native_id='44'))
        page=api.records(self.companies[0],'voucher',page_length=1)
        self.assertEqual([r['name'] for r in page['rows']],[first]);self.assertFalse(page['has_more'])
        with self.assertRaises(frappe.PermissionError):api.detail(self.companies[1],first)
        searched=api.records(self.companies[0],'voucher',query='R-0042')
        self.assertEqual([r['name'] for r in searched['rows']],[first])

    def test_shared_cash_appears_once_in_scope_and_never_company_totals(self):
        name=service.store_record(self.scope,self.values(family='cash_opening',shared_cash=True,
            source_company_id=None,original_date_raw='0000-00-00'))['name']
        for company in self.companies:
            self.assertNotIn('cash_opening',[f['key'] for f in api.summary(company)['families']])
            page=api.shared_cash(company)
            self.assertEqual([r['name'] for r in page['rows']],[name])
            self.assertEqual(set(page['shared_scope']['companies']),set(self.companies))
        detail=api.detail(self.companies[0],name)
        self.assertEqual(detail['effective_date'],'2023-04-01');self.assertIsNone(detail['original_date'])

    def test_shared_register_ignores_the_operator_default_and_repairs_only_verified_index_on_replay(self):
        def with_default(original):
            def new_doc(doctype, *args, **kwargs):
                doc = original(doctype, *args, **kwargs)
                if doctype == service.RECORD and kwargs.get('as_dict'):
                    doc['company'] = self.companies[0]
                return doc
            return new_doc

        for family, flags in [('master', {'shared_reference': True}), ('cash_opening', {'shared_cash': True})]:
            with self.subTest(family=family):
                values = self.values(family=family, native_id=family, source_company_id=None, **flags)
                with patch.object(frappe, 'new_doc', side_effect=with_default(frappe.new_doc)):
                    name = service.store_record(self.scope, values)['name']
                self.assertIsNone(frappe.db.get_value(service.RECORD, name, 'company'))
                original = service.get_record(name)
                frappe.db.set_value(service.RECORD, name, 'company', self.companies[0], update_modified=False)
                with self.assertRaises(frappe.ValidationError):
                    service.store_record(self.scope, {**values, 'title': 'Different title'})
                self.assertEqual(frappe.db.get_value(service.RECORD, name, 'company'), self.companies[0])
                self.assertFalse(service.store_record(self.scope, values)['created'])
                self.assertIsNone(frappe.db.get_value(service.RECORD, name, 'company'))
                self.assertEqual(original, service.get_record(name))

    def test_nonfinancial_role_cannot_read_vouchers_or_original_business(self):
        self.assertFalse(api.available(self.companies[0]))
        name=service.store_record(self.scope,self.values())['name']
        self.assertTrue(api.available(self.companies[0]))
        with patch.object(api,'financial_access',return_value=False):
            self.assertFalse(api.available(self.companies[0]))
            self.assertFalse(api.summary(self.companies[0])['families'])
            with self.assertRaises(frappe.PermissionError):api.detail(self.companies[0],name)
            with self.assertRaises(frappe.PermissionError):api.records(self.companies[0],'voucher')
        detail=api.detail(self.companies[0],name)
        for key in ('provenance','data_sha256','business_data','original_business'):
            self.assertNotIn(key,detail)

    def test_non_member_and_invalid_transaction_date_cannot_post(self):
        name=service.store_record(self.scope,self.values(original_date_raw='2020-02-30'))['name']
        with self.assertRaises(frappe.ValidationError):service.get_record_for_effect(name,self.companies[0],'financial')
        with patch.object(api,'_member',return_value=False):
            with self.assertRaises(frappe.PermissionError):api.summary(self.companies[0])

    def test_generic_read_also_requires_explicit_scope_membership(self):
        name=service.store_record(self.scope,self.values())['name']
        doc=frappe.get_doc(service.RECORD,name)
        self.assertTrue(service.has_permission(doc,'read'))
        scope=service.get_scope(self.scope);scope['allowed_users']=[]
        with patch.object(service,'get_scope',return_value=scope):
            self.assertFalse(service.has_permission(doc,'read'))

    def test_manager_scope_membership_is_required_for_original_and_effect_writes(self):
        from erp_extensions.migration import finance, settlements
        name=service.store_record(self.scope,self.values())['name']
        scope=service.get_scope(self.scope);scope['allowed_users']=[]
        books=[{'source_company_id':str(c),'source_book':str(b),
                'finance_book':f'Denied {self.scope} {c} {b}'} for c in range(1,5) for b in range(3)]
        actions=(lambda:service.store_record(self.scope,self.values()),
                 lambda:service.get_record_for_effect(name,self.companies[0],'financial'),
                 lambda:service.bind_authority(name,'financial','synthetic-key','Journal Entry','not-created','a'*64),
                 lambda:finance.configure_books(self.scope,books),
                 lambda:settlements.apply_component(self.scope,'denied',{name:{'company':self.companies[0]}},[],'a'*64))
        with patch.object(service,'get_scope',return_value=scope):
            for action in actions:
                with self.subTest(action=action),self.assertRaises(frappe.PermissionError):
                    action()

    def test_scope_membership_does_not_bypass_company_permissions(self):
        from erp_extensions.knitting import permissions
        name=service.store_record(self.scope,self.values())['name']
        with patch.object(permissions,'company_allowed',return_value=False):
            with self.assertRaises(frappe.PermissionError):service.store_record(self.scope,self.values())
            with self.assertRaises(frappe.PermissionError):service.get_record_for_effect(name,self.companies[0],'financial')

    def test_shared_import_and_book_setup_require_all_bound_companies_before_writing(self):
        from erp_extensions.knitting import permissions
        from erp_extensions.migration import finance
        books=[{'source_company_id':str(c),'source_book':str(b),
                'finance_book':f'Denied {self.scope} {c} {b}'} for c in range(1,5) for b in range(3)]
        with patch.object(permissions,'company_allowed',side_effect=lambda c,user=None:c==self.companies[0]):
            with self.assertRaises(frappe.PermissionError):
                service.store_record(self.scope,self.values(family='cash_opening',shared_cash=True,
                    source_company_id=None,original_date_raw='0000-00-00'))
            with self.assertRaises(frappe.PermissionError):finance.configure_books(self.scope,books)
        self.assertFalse(frappe.db.exists('Finance Book',books[0]['finance_book']))

    def test_authorized_single_company_import_does_not_require_other_company_access(self):
        from erp_extensions.knitting import permissions
        with patch.object(permissions,'company_allowed',side_effect=lambda c,user=None:c==self.companies[0]):
            result=service.store_record(self.scope,self.values())
            self.assertTrue(result['created'])
            self.assertEqual(service.get_record_for_effect(result['name'],self.companies[0],'financial')['company'],self.companies[0])

    def test_named_manager_respects_real_company_and_scope_permissions(self):
        user='scope-security-'+frappe.generate_hash(length=10)+'@example.invalid'
        frappe.get_doc({'doctype':'User','email':user,'first_name':'Synthetic scope manager',
            'send_welcome_email':0,'roles':[{'role':'System Manager'}]}).insert()
        frappe.get_doc({'doctype':'User Permission','user':user,'allow':'Company',
            'for_value':self.companies[0],'apply_to_all_doctypes':1}).insert()
        values=service.get_scope(self.scope)
        values.pop('name')
        values.update(source_instance='authorized-'+frappe.generate_hash(length=10),allowed_users=['Administrator',user])
        allowed=service.create_scope(values)
        try:
            frappe.set_user(user)
            result=service.store_record(allowed,self.values())
            self.assertEqual(service.get_record_for_effect(result['name'],self.companies[0],'financial')['company'],self.companies[0])
            with self.assertRaises(frappe.PermissionError):
                service.store_record(allowed,self.values(source_company_id='2',native_id='43'))
            with self.assertRaises(frappe.PermissionError):service.store_record(self.scope,self.values())
        finally:
            frappe.set_user('Administrator')
            frappe.clear_cache(user=user)

    def test_customer_catalog_preserves_operations_and_hides_unrelated_modules(self):
        from erp_extensions import api as native_api, workspace
        company = self.companies[0]
        self.assertTrue(workspace.context(company)['knitting_only'])
        names = {row['name'] for row in native_api.catalog(company)['types']}
        self.assertTrue({'Customer', 'Sales Invoice', 'Payment Entry', 'Workstation', 'Holiday List'} <= names)
        self.assertFalse({'Employee', 'Project', 'Lead', 'Asset', 'Website Settings'} & names)
        with patch.object(service, 'get_scope', side_effect=frappe.ValidationError('Corrupt scope')):
            with self.assertRaises(frappe.ValidationError):
                native_api.catalog(company)

    def test_invoice_target_link_lookup_requires_exact_namespace_company_and_book(self):
        value=self.values()
        value['business_data']['financial'].update(invoice_namespace='kpinvoice',invoice_native_id='901')
        native=service.store_record(self.scope,value)['name']
        service.store_record(self.scope,{**value,'native_id':'43','source_book':'1'})
        service.store_record(self.scope,{**value,'native_id':'44','source_company_id':'2'})
        invoice=service.store_record(self.scope,self.values(namespace='knitpack.invoice',native_id='901',family='invoice',business_data={}))['name']
        self.assertEqual(api._invoice_vouchers(service.get_record(invoice)),[native])

    def test_managed_route_guard_allows_only_history_reads_and_keeps_cashiers_restricted(self):
        from erp_extensions import team_scope
        service.store_record(self.scope,self.values())
        self.assertTrue(api.available(self.companies[0]))
        with patch.object(team_scope,'membership',return_value=frappe._dict(team_role='cashier')):
            self.assertFalse(api.available(self.companies[0]))
        def request(method,role='accountant'):
            with patch.object(team_scope,'membership',return_value=frappe._dict(team_role=role)), \
                    patch.object(frappe,'request',frappe._dict(path='/api/method/'+method)), \
                    patch.object(frappe,'form_dict',frappe._dict()):
                team_scope.guard_request()
        for operation in ('summary','records','detail','shared_cash','invoice_print_data'):
            request('erp_extensions.migration.api.'+operation)
        for method in ('erp_extensions.migration.service.store_record','erp_extensions.migration.finance.post_record',
                       'erp_extensions.migration.operations.apply_job','erp_extensions.migration.api.unknown'):
            with self.subTest(method=method),self.assertRaises(frappe.PermissionError):request(method)
        with self.assertRaises(frappe.PermissionError):request('erp_extensions.migration.api.summary','cashier')

    def test_original_invoice_tax_print_fields_preserve_exact_saved_amounts(self):
        projection={'seller_name':'Synthetic seller','customer_name':'Synthetic customer','currency':'INR',
            'posting_date':'2020-02-29','total':'100.00','net_total':'105.00','grand_total':'105.00',
            'items':[{'item_name':'Service','qty':'10','rate':'10','amount':'100'}],
            'taxes':[{'description':'CGST','tax_amount':'2.50'},
                {'description':'SGST','tax_amount':'2.50'},{'description':'IGST','tax_amount':'0'}]}
        name=service.store_record(self.scope,self.values(namespace='knitpack.invoice',family='invoice',
            business_data={'invoice_print':projection,'original_business':{'fabric_context':{'samplerates':[
                {'dlvry_kgs':'10','billrate':'10','fabric_value':'100','kgs':'0','rate':'0'}]}}}))['name']
        before=service.get_record(name)
        printed=api.invoice_print_data(self.companies[0],name)
        self.assertEqual([(row['label'],row['amount']) for row in printed['taxes']],
            [('CGST (recorded)','2.50'),('SGST (recorded)','2.50'),('IGST (recorded)','0')])
        self.assertEqual(printed['source_net_total_label'],'Recorded source total')
        self.assertTrue(printed['source_tax_breakdown'])
        self.assertEqual(printed['net_total'],'105.00')
        self.assertEqual(printed['total'],'100.00')
        self.assertEqual(printed['grand_total'],'105.00')
        self.assertEqual(service.get_record(name),before)

    def test_original_regular_delivery_and_sample_price_roles_are_separate(self):
        projection={'seller_name':'Synthetic seller','customer_name':'Synthetic customer','currency':'INR',
            'posting_date':'2020-02-29','grand_total':'349','taxes':[],
            'items':[{'item_name':'Delivery','qty':'27.4','rate':'0','amount':'274'},
                {'item_name':'Sample group','qty':'10','rate':'25','amount':'75'}]}
        source=[{'dlvry_kgs':'27.4','billrate':'10.00','fabric_value':'274','kgs':'0','rate':'0'},
            {'dlvry_kgs':'10','billrate':'10','fabric_value':'75','kgs':'5','rate':'25'}]
        name=service.store_record(self.scope,self.values(namespace='knitpack.invoice',family='invoice',
            business_data={'invoice_print':projection,'original_business':{'fabric_context':{'samplerates':source}}}))['name']
        before=service.get_record(name)
        result=api.invoice_print_data(self.companies[0],name)
        self.assertEqual([(row['qty'],row['rate'],row['amount']) for row in result['items']],
            [('27.4','10.00','274'),('10','10','75')])
        self.assertIn('flat sample price 25 INR',result['terms'])
        self.assertEqual(service.get_record(name),before)

