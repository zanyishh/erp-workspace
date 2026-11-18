"""Grouped preserved production, synthetic native-test records only."""
import importlib.util
import json
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service, contracts
from erp_extensions.tests import test_migration_store as store_tests


class OriginalProductionReportTests(unittest.TestCase):
    setUpClass = classmethod(store_tests.HistoricalStoreTests.setUpClass.__func__)
    setUp = store_tests.HistoricalStoreTests.setUp
    _cleanup = store_tests.HistoricalStoreTests._cleanup

    def report(self, company=None, **kwargs):
        self.assertIsNotNone(importlib.util.find_spec('erp_extensions.migration.production_reports'),
                             'Original production needs a grouped report endpoint')
        from erp_extensions.migration.production_reports import summary
        return summary(company or self.companies[0], **kwargs)

    def record(self, native, *, fields=None, **changes):
        return service.store_record(self.scope, self.values(namespace='knitpack.production', family='production',
            native_id=str(native), original_date_raw='2026-11-13',
            business_data={'fields': fields or {}, 'tables': []}) | changes)['name']

    def test_company_namespace_and_nonfinancial_scope_are_enforced(self):
        self.record('1', fields={'machine': 'A', 'net_kg': '12.50', 'rolls': '1.25'})
        self.record('2', source_company_id='2', fields={'machine': 'Hidden', 'net_kg': '999'})
        self.record('3', namespace='other.production', fields={'machine': 'Wrong namespace', 'net_kg': '999'})
        self.record('4', family='job', namespace='knitpack.job', fields={'net_kg': '999'})
        with patch.object(api, 'financial_access', return_value=False):
            result = self.report(group_by='machine')
        self.assertEqual(result['company'], self.companies[0])
        self.assertEqual(result['family'], 'production')
        self.assertEqual(result['version'], 1)
        self.assertEqual(result['totals']['source_record_count'], 1)
        self.assertEqual(result['totals']['quantity_kg'], '12.50')
        self.assertEqual(result['rows'][0]['value'], 'A')
        self.assertFalse({'rate', 'amount', 'record_data', 'business_data', 'source_scope', 'provenance'} & result['rows'][0].keys())
        self.assertEqual(self.report(self.companies[1])['totals']['source_record_count'], 1)

    def test_membership_company_access_and_invalid_input_fail_closed(self):
        self.record('1')
        with patch.object(api, '_member', return_value=False), self.assertRaises(frappe.PermissionError):self.report()
        with patch.object(api, 'company_allowed', return_value=False), self.assertRaises(frappe.PermissionError):self.report()
        with self.assertRaises(frappe.PermissionError):self.report('Unbound company')
        for kwargs in ({'group_by': 'job'}, {'page_length': 101}, {'start': -1}, {'start': 1.5},
                       {'filters': {'machine': []}}, {'filters': {'from_date': '2026-02-30'}}):
            with self.subTest(kwargs=kwargs), self.assertRaises(frappe.ValidationError):self.report(**kwargs)

    def test_actual_nonmember_user_with_company_access_is_denied(self):
        self.record('1', fields={'machine': 'Private'})
        outside = frappe.get_doc({'doctype': 'User',
            'email': 'production-outside-' + frappe.generate_hash(length=8) + '@example.invalid',
            'first_name': 'Synthetic outside', 'send_welcome_email': 0,
            'roles': [{'role': 'System Manager'}]}).insert().name
        try:
            frappe.set_user(outside)
            self.assertTrue(api.company_allowed(self.companies[0]))
            with self.assertRaises(frappe.PermissionError):self.report()
        finally:
            frappe.set_user('Administrator');frappe.clear_cache(user=outside)

    def test_exact_filters_and_date_drilldowns_match_history_rows(self):
        exact = {'machine': '0', 'operator': "O'Brien_%", 'description': 'Rib / 2x2', 'dia': '0', 'shift': 'Night', 'party': 'Party'}
        for native in ('1', '2'):self.record(native, fields={**exact, 'net_kg': '0.1', 'rolls': '-0.25'})
        self.record('3', fields={**exact, 'operator': "o'brien_%", 'net_kg': '9'})
        self.record('4', original_date_raw='2026-11-14', fields=exact)
        filters = {**exact, 'from_date': '2026-11-13', 'to_date': '2026-11-13'}
        result = self.report(filters=json.dumps(filters), page_length=1)
        self.assertEqual(result['totals']['source_record_count'], 2)
        self.assertEqual(result['totals']['quantity_kg'], '0.2')
        row = result['rows'][0]
        self.assertEqual(row['value'], '2026-11-13')
        self.assertEqual(row['filters'], {**filters, 'date_basis': 'original'})
        self.assertEqual(api.records(self.companies[0], 'production', filters=row['filters'])['row_count'], 2)
        self.assertTrue(set(exact) <= set(result['available_filters']))
        for group in ('machine', 'operator', 'shift', 'party', 'description', 'dia'):
            grouped = self.report(group_by=group, filters=filters)['rows'][0]
            self.assertEqual(grouped['value'], exact[group])
            self.assertEqual(api.records(self.companies[0], 'production', filters=grouped['filters'])['row_count'], 2)

    def test_report_history_and_options_share_exact_production_population(self):
        own = self.record('1', fields={'machine': 'Own', 'net_kg': '1.5', 'rolls': '0.5'})
        self.record('2', namespace='other.production', fields={'machine': 'Wrong namespace'})
        self.record('3', namespace='KNITPACK.PRODUCTION', fields={'machine': 'Wrong case namespace'})
        shared = self.record('4', fields={'machine': 'Invalid shared flag'})
        # Production cannot validly be shared: corrupt the synthetic index to prove read exclusion.
        frappe.db.sql('update `tabHistorical Business Record` set shared_reference=1 where name=%s', shared)
        foreign = self.record('5', source_company_id='2', fields={'machine': 'Foreign shared flag'})
        frappe.db.sql('update `tabHistorical Business Record` set shared_reference=1 where name=%s', foreign)
        try:report = self.report()
        except frappe.ValidationError as error:self.fail('Non-production namespaces must be excluded before report validation: ' + str(error))
        self.assertEqual(report['totals']['source_record_count'], 1)
        history = api.records(self.companies[0], 'production', filters=report['rows'][0]['filters'])
        self.assertEqual([row['name'] for row in history['rows']], [own])
        self.assertEqual(history['row_count'], report['rows'][0]['source_record_count'])
        self.assertEqual(api.filter_options(self.companies[0], 'production', 'machine')['rows'],
                         [{'value': 'Own', 'label': 'Own'}])

    def test_case_zero_and_unrecorded_groups_preserve_missing_counts(self):
        for native, label in enumerate(('A', 'a', '0', '', None)):
            self.record(native, fields={'machine': label, 'net_kg': '0' if label == '0' else None})
        first = self.report(group_by='machine', page_length=2)
        second = self.report(group_by='machine', start=2, page_length=2)
        self.assertEqual([r['value'] for r in first['rows'] + second['rows']], ['0', 'A', 'a', None])
        self.assertEqual(first['row_count'], 4)
        self.assertTrue(first['has_more'])
        self.assertFalse(second['has_more'])
        self.assertEqual(first['totals']['missing_quantity_rows'], 4)
        self.assertEqual(first['totals']['missing_count_rows'], 5)
        self.assertIsNone(first['totals']['recorded_count'])
        self.assertFalse(second['rows'][-1]['drillable'])

    def test_ambiguous_text_and_numeric_labels_disable_inexact_drilldown_without_writes(self):
        names = [self.record(i, fields={'machine': label, 'net_kg': '0.1', 'rolls': '0.25'})
                 for i, label in enumerate(('0', 0, 'false', False))]
        before = [frappe.db.get_value(service.RECORD, name, ['record_data', 'data_sha256'], as_dict=True) for name in names]
        result = self.report(group_by='machine')
        self.assertEqual(result['row_count'], 4)
        self.assertTrue(all(not row['drillable'] and row['filters'] is None for row in result['rows']))
        self.assertEqual(result['totals']['quantity_kg'], '0.4')
        self.assertEqual(api.records(self.companies[0], 'production', filters={'machine': '0'})['row_count'], 2)
        self.assertEqual([frappe.db.get_value(service.RECORD, name, ['record_data', 'data_sha256'], as_dict=True)
                          for name in names], before)

    def test_corrupt_hash_and_mismatched_identity_columns_are_rejected(self):
        name = self.record('1')
        before = frappe.db.get_value(service.RECORD, name, 'data_sha256')
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', ('0'*64, name))
        with self.assertRaises(frappe.ValidationError):self.report()
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s,native_id=%s where name=%s', (before, 'wrong', name))
        with self.assertRaises(frappe.ValidationError):self.report()

    def test_invalid_saved_numbers_fail_closed_and_reports_never_mutate_originals(self):
        name = self.record('1', fields={'net_kg': 'NaN', 'rolls': '2'})
        before = frappe.db.get_value(service.RECORD, name, ['record_data', 'data_sha256'], as_dict=True)
        with self.assertRaises(frappe.ValidationError):self.report()
        self.assertEqual(frappe.db.get_value(service.RECORD, name, ['record_data', 'data_sha256'], as_dict=True), before)

    def test_scans_are_bounded_and_aggregate_beyond_first_batch(self):
        scope = service.get_scope(self.scope)
        rows = []
        for i in range(503):
            value = contracts.normalize_record(scope, self.values(namespace='knitpack.production', family='production',
                native_id=str(i), original_date_raw='2026-11-13', business_data={'fields': {'machine': 'A', 'net_kg': '0.01'}, 'tables': []}))
            rows.append(['history-'+value['source_key'], self.scope, *[value[k] for k in ('source_key', 'company', 'source_company_id',
                'source_book', 'namespace', 'native_id', 'family', 'original_date_raw', 'effective_date', 'date_basis',
                'shared_cash', 'shared_reference', 'data_sha256')], contracts.canonical(value)])
        frappe.db.bulk_insert(service.RECORD, ['name', 'source_scope', 'source_key', 'company', 'source_company_id', 'source_book',
            'namespace', 'native_id', 'family', 'original_date_raw', 'effective_date', 'date_basis', 'shared_cash',
            'shared_reference', 'data_sha256', 'record_data'], rows)
        with patch.object(frappe.db, 'sql', wraps=frappe.db.sql) as queries:
            result = self.report(group_by='machine', page_length=1)
        self.assertEqual(result['totals']['source_record_count'], 503)
        self.assertEqual(result['totals']['quantity_kg'], '5.03')
        scans = [call for call in queries.call_args_list if call.args and 'record_data' in call.args[0] and 'order by' in call.args[0].lower()]
        self.assertEqual(len(scans), 2)
        self.assertTrue(all(call.args[1]['limit'] == 500 for call in scans))
