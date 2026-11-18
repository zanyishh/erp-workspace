"""Synthetic original-history SQL filters; never connect to customer data."""
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service
from erp_extensions.tests import test_migration_store as store_tests


class HistoricalFilterTests(unittest.TestCase):
    setUpClass = classmethod(store_tests.HistoricalStoreTests.setUpClass.__func__)
    setUp = store_tests.HistoricalStoreTests.setUp
    _cleanup = store_tests.HistoricalStoreTests._cleanup

    def record(self, native, *, fields=None, **changes):
        return service.store_record(self.scope, self.values(native_id=str(native),
            business_data={'fields': fields or {}, 'tables': []}, **changes))['name']

    def test_combined_filters_precede_count_page_and_text_or(self):
        for i in range(45):
            self.record(i, original_date_raw='2026-11-15', fields={'party':'Other'})
        expected = sorted(self.record(100+i, original_date_raw='2026-11-14',
            fields={'party':"O'Brien_%", 'job':'Original-7', 'status':'Running'}) for i in range(3))
        self.record(200, source_company_id='2', fields={'party':"O'Brien_%", 'job':'Original-7', 'status':'Running'})
        self.record(201, source_book='1', fields={'party':"O'Brien_%", 'job':'Original-7', 'status':'Running'})
        filters={'party':"O'Brien_%", 'job':'Original-7', 'status':'Running', 'source_book':'0',
            'from_date':'2026-11-14', 'to_date':'2026-11-14'}
        first=api.records(self.companies[0], 'voucher', query='R-0042', filters=filters, page_length=2)
        second=api.records(self.companies[0], 'voucher', query='R-0042', filters=filters, start=2, page_length=2)
        self.assertEqual(first['row_count'],3);self.assertTrue(first['has_more'])
        self.assertFalse(second['has_more'])
        self.assertEqual([r['name'] for r in first['rows']+second['rows']],expected)
        self.assertEqual(api.records(self.companies[0],'voucher',filters={'party':'O'})['row_count'],0)

    def test_date_bases_keep_original_opening_and_undated_distinct(self):
        original=self.record(1,family='opening',original_date_raw='2023-04-01')
        opening=self.record(2,family='opening',original_date_raw='0000-00-00')
        undated=self.record(3,family='opening',original_date_raw='invalid')
        def names(**filters):return {r['name'] for r in api.records(self.companies[0],'opening',filters=filters)['rows']}
        self.assertEqual(names(),{original,opening,undated})
        self.assertEqual(names(from_date='2023-04-01',to_date='2023-04-01'),{original})
        self.assertEqual(names(date_basis='effective',from_date='2023-04-01',to_date='2023-04-01'),{original,opening})
        self.assertEqual(names(date_basis='no_original'),{opening,undated})
        for value in ({'from_date':'2023-02-30'},{'from_date':'2023-04-02','to_date':'2023-04-01'},
                {'date_basis':'no_original','to_date':'2023-04-01'},{'unknown':'x'},{'party':['x']}):
            with self.subTest(value=value),self.assertRaises(frappe.ValidationError):
                api.records(self.companies[0],'opening',filters=value)

    def test_null_book_and_missing_normalized_fields_are_explicit(self):
        null=self.record(1,family='job',source_book=None,fields={'party':'Same name'})
        known=self.record(2,family='job',fields={'party':'Same name','job':'Visible number','status':'Running'})
        self.assertEqual(api.records(self.companies[0],'job',filters={'party':'Same name'})['row_count'],2)
        self.assertEqual([r['name'] for r in api.records(self.companies[0],'job',filters={'source_book':None})['rows']],[null])
        self.assertEqual([r['name'] for r in api.records(self.companies[0],'job',filters={'job':'Visible number','status':'Running'})['rows']],[known])
        options=api.filter_options(self.companies[0],'job','source_book')
        self.assertEqual({r['value'] for r in options['rows']},{None,'0'})
        self.assertEqual(api.filter_options(self.companies[0],'job','job')['rows'],[{'value':'Visible number','label':'Visible number'}])

    def test_options_are_scoped_paged_and_treat_search_characters_literally(self):
        for i in range(53):self.record(i,fields={'party':f'Party {i:02}'})
        self.record(99,fields={'party':"O'Brien_%"})
        self.record(100,source_company_id='2',fields={'party':'Hidden company'})
        a=api.filter_options(self.companies[0],'voucher','party')
        b=api.filter_options(self.companies[0],'voucher','party',start=50)
        self.assertTrue(a['has_more']);self.assertFalse(b['has_more'])
        self.assertEqual(len(a['rows']+b['rows']),54)
        self.assertNotIn('Hidden company',[r['value'] for r in a['rows']+b['rows']])
        self.assertEqual(api.filter_options(self.companies[0],'voucher','party',query='_%')['rows'],[{'value':"O'Brien_%",'label':"O'Brien_%"}])
        self.assertEqual(api.filter_options(self.companies[0],'voucher','party',filters={'source_book':'7'})['rows'],[])

    def test_choices_counts_and_records_share_permission_boundary(self):
        self.record(1,fields={'party':'Private'})
        for method,args in ((api.records,('voucher',)),(api.filter_options,('voucher','party')),(api.shared_cash,())):
            with patch.object(api,'financial_access',return_value=False),self.assertRaises(frappe.PermissionError):
                method(self.companies[0],*args)
            with patch.object(api,'_member',return_value=False),self.assertRaises(frappe.PermissionError):
                method(self.companies[0],*args)
            with self.assertRaises(frappe.PermissionError):method('Unbound company',*args)

    def test_visible_null_text_is_distinct_from_missing_and_json_null(self):
        literal=self.record(1,fields={'party':'null','job':'null','status':'null'})
        self.record(2,fields={'party':None,'job':None,'status':None})
        self.record(3)
        for field in ('party','job','status'):
            page=api.records(self.companies[0],'voucher',filters={field:'null'})
            self.assertEqual([r['name'] for r in page['rows']],[literal])
            self.assertEqual(api.filter_options(self.companies[0],'voucher',field)['rows'],[{'value':'null','label':'null'}])

    def test_cash_filter_changes_rows_but_never_global_controls(self):
        self.record(1,family='cash_movement',shared_cash=True,fields={'party':'One'})
        self.record(2,family='cash_movement',shared_cash=True,fields={'party':'Two'})
        controls=[{'cash_book_id':'1','label':'Synthetic control','verified':True,'net':'12.50'}]
        with patch('erp_extensions.migration.cash.summarize',return_value=controls) as summarize:
            result=api.shared_cash(self.companies[0],filters={'party':'One'})
        self.assertEqual(result['row_count'],1);self.assertEqual(len(result['rows']),1)
        self.assertEqual(result['balances'],controls);self.assertTrue(result['balances_verified'])
        self.assertEqual(len(summarize.call_args.args[0]),2)

