"""Original production read-list contract on synthetic native-test records only."""
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service
from erp_extensions.tests import test_migration_store as store_tests


class OriginalProductionViewTests(unittest.TestCase):
    setUpClass = classmethod(store_tests.HistoricalStoreTests.setUpClass.__func__)
    setUp = store_tests.HistoricalStoreTests.setUp
    _cleanup = store_tests.HistoricalStoreTests._cleanup

    def record(self, native, *, fields=None, **changes):
        value = self.values(namespace='knitpack.production', family='production',
            native_id=str(native), original_reference=None, original_date_raw='2026-11-13',
            business_data={'fields': fields or {}, 'tables': []})
        return service.store_record(self.scope, {**value, **changes})['name']

    def job_reference(self, native, *, header_company='1', label='SYN/26', **changes):
        return self.record(native, namespace='knitpack.job', family='job',
            business_data={'fields': {}, 'tables': [], 'original_business': {
                'job_ledger': {'job': {'id': str(native), 'companymas_id': header_company}, 'pjobno': label}}}, **changes)

    def linked_record(self, native, job, *, company='1', header_id=None, source_book='0'):
        return self.record(native, source_book=source_book, business_data={'fields': {'job': 'SYN-RAW'}, 'tables': [],
            'original_business': {'header': {'id': str(native if header_id is None else header_id),
                'companymas_id': company, 'jobmas_id': str(job)}}})

    def test_page_preserves_exact_safe_fields_without_raw_or_money(self):
        name = self.record(12, fields={'job': 'SYN-2', 'party': 'Synthetic party',
            'description': 'Synthetic fabric', 'dia': '32', 'net_kg': '0.000', 'rolls': 0,
            'machine': 'Machine-1', 'operator': 'Synthetic employee', 'shift': 'Night',
            'source_id': 'different-print-number', 'rate': '123.45', 'amount': '678.90'})
        with patch.object(api, 'financial_access', return_value=False):
            page = api.records(self.companies[0], 'production')
        row = page['rows'][0]
        self.assertEqual(row['name'], name)
        self.assertEqual(row.get('native_id'), '12')
        self.assertEqual(row['original_date'], '2026-11-13')
        self.assertEqual(row.get('production_fields'), {'job': 'SYN-2', 'party': 'Synthetic party',
            'description': 'Synthetic fabric', 'dia': '32', 'net_kg': '0.000', 'rolls': 0,
            'machine': 'Machine-1', 'operator': 'Synthetic employee', 'shift': 'Night'})
        self.assertFalse({'record_data', 'business_data', 'original_business', 'rate', 'amount', 'source_scope'} & row.keys())

    def test_numeric_source_order_precedes_paging_and_other_families_keep_order(self):
        huge = '1' + '0' * 80
        names = {native: self.record(native) for native in ('2', '10', huge, '0010', 'other', 'A-3')}
        latest = self.record('1', original_date_raw='2026-11-14')
        expected_same_ten = sorted((names[native], native) for native in ('10', '0010'))
        expected_tail = sorted((names[native], native) for native in ('other', 'A-3'))
        rows = []
        for start in (0, 2, 4, 6):
            page = api.records(self.companies[0], 'production', start=start, page_length=2)
            self.assertEqual(page['row_count'], 7)
            rows.extend(page['rows'])
        self.assertEqual(rows[0]['name'], latest)
        self.assertEqual([r['name'] for r in rows], [latest, names[huge],
            *[name for name, _ in expected_same_ten], names['2'], *[name for name, _ in expected_tail]])
        self.assertEqual([r.get('native_id') for r in rows], ['1', huge, *[n for _, n in expected_same_ten], '2', *[n for _, n in expected_tail]])
        other = [self.record(native, family='job', namespace='knitpack.job') for native in ('10', '2')]
        jobs = api.records(self.companies[0], 'job')['rows']
        self.assertEqual([r['name'] for r in jobs], sorted(other))
        self.assertTrue(all('production_fields' not in r and 'native_id' not in r for r in jobs))

    def test_shift_choices_and_rows_are_exact_scoped_and_filtered_before_paging(self):
        self.record('100', fields={'shift': 'Other'})
        self.record('10', fields={'shift': 'Night_%', 'job': 'SYN-A'})
        first = self.record('11', fields={'shift': 'Night_%', 'job': 'SYN-A'})
        self.record('12', fields={'shift': 'night_%', 'job': 'SYN-A'})
        self.record('200', fields={'shift': 'Hidden'}, source_company_id='2')
        page = api.records(self.companies[0], 'production', filters={'shift': 'Night_%', 'job': 'SYN-A'}, page_length=1)
        self.assertEqual(page['row_count'], 2)
        self.assertTrue(page['has_more'])
        self.assertEqual([r['name'] for r in page['rows']], [first])
        self.assertIn('shift', page['available_filters'])
        options = api.filter_options(self.companies[0], 'production', 'shift', query='_%', filters={'job': 'SYN-A'})
        self.assertEqual([r['value'] for r in options['rows']], ['Night_%', 'night_%'])
        self.assertEqual(api.records(self.companies[1], 'production')['row_count'], 1)
        with patch.object(api, '_member', return_value=False), self.assertRaises(frappe.PermissionError):
            api.records(self.companies[0], 'production')
        with patch.object(api, '_member', return_value=False), self.assertRaises(frappe.PermissionError):
            api.filter_options(self.companies[0], 'production', 'shift')

    def test_missing_values_are_null_and_corrupt_payload_is_rejected(self):
        name = self.record('1')
        row = api.records(self.companies[0], 'production')['rows'][0]
        self.assertEqual(row.get('production_fields'), {k: None for k in
            ('job', 'party', 'description', 'dia', 'net_kg', 'rolls', 'machine', 'operator', 'shift')})
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', ('0' * 64, name))
        with self.assertRaises(frappe.ValidationError):api.records(self.companies[0], 'production')

    def test_production_dimensions_filter_before_paging_with_exact_scoped_choices(self):
        fields = {'machine': '00_1%', 'operator': 'Employee A', 'description': 'Rib / 2x2', 'dia': '0'}
        first = self.record('301', fields=fields)
        self.record('300', fields=fields)
        self.record('302', fields={**fields, 'operator': 'employee a'})
        self.record('303', fields={**fields, 'machine': 'Other'})
        self.record('304', fields={**fields, 'operator': 'Hidden'}, source_company_id='2')
        page = api.records(self.companies[0], 'production', filters=fields, page_length=1)
        self.assertEqual(page['row_count'], 2)
        self.assertTrue(page['has_more'])
        self.assertEqual(page['rows'][0]['name'], first)
        self.assertTrue(set(fields) <= set(page['available_filters']))
        choices = api.filter_options(self.companies[0], 'production', 'operator', filters=fields)
        self.assertEqual([row['value'] for row in choices['rows']], ['Employee A', 'employee a'])
        self.assertEqual(api.filter_options(self.companies[0], 'production', 'dia', filters=fields)['rows'],
                         [{'value': '0', 'label': '0'}])
        with patch.object(api, '_member', return_value=False), self.assertRaises(frappe.PermissionError):
            api.filter_options(self.companies[0], 'production', 'operator', filters=fields)

    def test_full_reference_uses_one_verified_scoped_lookup_with_raw_fallback(self):
        self.job_reference('42')
        self.job_reference('43', header_company='2', source_company_id='2', label='HIDDEN/26')
        self.job_reference('44', header_company='2', label='WRONG/26')
        good = {self.linked_record('20', '42'), self.linked_record('21', '42')}
        missing = {self.linked_record('22', '43'), self.linked_record('23', '44'),
            self.linked_record('24', '42', company='2'), self.linked_record('25', '404'),
            self.linked_record('26', '42', header_id='wrong'), self.record('27', fields={'job': 'SYN-RAW'})}
        with patch.object(frappe, 'get_all', wraps=frappe.get_all) as reads:
            page = api.records(self.companies[0], 'production')
        for row in page['rows']:
            self.assertEqual(row['production_fields']['job'], 'SYN-RAW')
            if row['name'] in good:self.assertEqual(row.get('job_reference_display'), 'SYN/26')
            else:
                self.assertIn(row['name'], missing)
                self.assertNotIn('job_reference_display', row)
        source_job_reads = [call for call in reads.call_args_list if call.args and call.args[0] == service.RECORD]
        self.assertEqual(len(source_job_reads), 1)
        self.assertEqual(source_job_reads[0].kwargs['filters']['company'], self.companies[0])
        self.assertEqual(source_job_reads[0].kwargs['filters']['source_scope'], self.scope)

    def test_ambiguous_reference_falls_back_and_corrupt_job_fails_integrity(self):
        job = self.job_reference('42')
        self.job_reference('42', source_book='1', label='OTHER/26')
        self.linked_record('1', '42', source_book=None)
        row = api.records(self.companies[0], 'production')['rows'][0]
        self.assertNotIn('job_reference_display', row)
        self.assertEqual(row['production_fields']['job'], 'SYN-RAW')
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', ('0' * 64, job))
        with self.assertRaises(frappe.ValidationError):api.records(self.companies[0], 'production')
