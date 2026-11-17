"""Original-production source-job identity; synthetic native-test fixtures only."""
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service
from erp_extensions.migration.production_reports import summary as production_summary
from erp_extensions.tests import test_migration_store as store_tests


class ProductionSourceJobTests(unittest.TestCase):
    setUpClass = classmethod(store_tests.HistoricalStoreTests.setUpClass.__func__)
    setUp = store_tests.HistoricalStoreTests.setUp
    _cleanup = store_tests.HistoricalStoreTests._cleanup

    def production(self, native, job='A', *, fields=None, header=None, **changes):
        body = {'id': str(native), 'companymas_id': changes.get('source_company_id', '1'), 'jobmas_id': job}
        if header is not None:body.update(header)
        return service.store_record(self.scope, self.values(namespace='knitpack.production', family='production',
            native_id=str(native), source_book=None, original_date_raw='2026-11-15',
            business_data={'fields': {'job': 'SAME', 'net_kg': '1.25', 'rolls': '0.5', **(fields or {})},
                           'original_business': {'header': body}}) | changes)['name']

    def original(self, native='A', label='FULL/26', *, header=None, **changes):
        book = changes.get('source_book', '0')
        body = {'id': str(native), 'companymas_id': changes.get('source_company_id', '1'), 'sec_acc': book}
        if header is not None:body.update(header)
        return service.store_record(self.scope, self.values(namespace='knitpack.job', family='job',
            native_id=str(native), business_data={'fields': {}, 'original_business': {'job_ledger': {
                'job': body, 'pjobno': label}}}) | changes)['name']

    def choices(self, **kwargs):
        return api.filter_options(self.companies[0], 'production', 'source_job', **kwargs)

    def test_same_raw_labels_remain_separate_ids_and_report_drilldown_retains_identity(self):
        self.original('A', 'SAVED-A/26');self.original('B', 'SAVED-B/25')
        own = self.production('1', 'A', fields={'shift': 'Night'})
        self.production('2', 'B', fields={'shift': 'Night'})
        try:options = self.choices()
        except frappe.ValidationError as error:self.fail('Production needs an identity-based original job picker: ' + str(error))
        self.assertEqual(options['rows'], [{'value': 'A', 'label': 'SAVED-A/26'}, {'value': 'B', 'label': 'SAVED-B/25'}])
        page = api.records(self.companies[0], 'production', filters={'source_job': 'A', 'shift': 'Night'})
        self.assertEqual([row['name'] for row in page['rows']], [own])
        self.assertEqual(page['filter_labels'], {'source_job': 'SAVED-A/26'})
        self.assertIn('source_job', page['available_filters'])
        self.assertEqual(api.records(self.companies[0], 'production', filters={'job': 'SAME'})['row_count'], 2)
        self.assertEqual(api.records(self.companies[0], 'production', filters={'job': 'SAVED-A/26'})['row_count'], 0)
        report = production_summary(self.companies[0], filters={'source_job': 'A', 'shift': 'Night'})
        self.assertEqual(report['filter_labels'], {'source_job': 'SAVED-A/26'})
        self.assertEqual(report['totals']['quantity_kg'], '1.25')
        self.assertEqual(report['rows'][0]['filters']['source_job'], 'A')
        self.assertEqual(api.records(self.companies[0], 'production', filters=report['rows'][0]['filters'])['row_count'], 1)

    def test_missing_and_mismatched_headers_remain_unfiltered_but_never_supply_a_choice(self):
        good = self.production('1', 0)
        self.production('2', 0, header={'companymas_id': '2'})
        self.production('3', 0, header={'id': 'wrong'})
        self.production('4', True)
        self.production('5', ' bad')
        self.production('6', 'FOREIGN', source_company_id='2')
        missing = service.store_record(self.scope, self.values(namespace='knitpack.production', family='production',
            native_id='7', business_data={'fields': {'job': 'SAME'}}))['name']
        page = api.records(self.companies[0], 'production')
        self.assertEqual(page['row_count'], 6)
        self.assertIn(missing, [row['name'] for row in page['rows']])
        self.assertEqual(self.choices()['rows'], [{'value': '0', 'label': 'Original job 0'}])
        self.assertEqual([r['name'] for r in api.records(self.companies[0], 'production', filters={'source_job': 0})['rows']], [good])
        self.assertEqual(api.records(self.companies[0], 'production', filters={'source_job': 'FOREIGN'})['rows'], [])

    def test_book_resolution_is_exact_when_recorded_and_ambiguous_when_absent(self):
        self.original('A', 'BOOK-0/26', source_book='0');self.original('A', 'BOOK-1/25', source_book='1')
        self.production('1', 'A')
        self.production('2', 'A', source_book='0')
        self.production('3', 'A', source_book='1')
        self.assertEqual(self.choices()['rows'], [{'value': 'A', 'label': 'Original job A'}])
        exact = self.choices(filters={'source_book': '0'})
        self.assertEqual(exact['rows'], [{'value': 'A', 'label': 'BOOK-0/26'}])
        page = api.records(self.companies[0], 'production', filters={'source_job': 'A', 'source_book': '1'})
        self.assertEqual(page['filter_labels'], {'source_job': 'BOOK-1/25'})
        self.assertEqual(page['rows'][0]['job_reference_display'], 'BOOK-1/25')
        self.assertEqual(api.records(self.companies[0], 'production', filters={'source_job': 'A'})['filter_labels'],
                         {'source_job': 'Original job A'})

    def test_facet_other_filters_apply_before_identity_paging_and_label_search_is_literal(self):
        for i in range(53):self.production(str(i), f'{i:03}', fields={'shift': 'Night' if i < 2 else 'Day'})
        self.original('000', 'LITERAL_%/26')
        self.original('001', 'LITERAL-XX/26')
        first = self.choices();last = self.choices(start=50)
        self.assertTrue(first['has_more']);self.assertFalse(last['has_more'])
        self.assertEqual(len(first['rows']), 50);self.assertEqual([r['value'] for r in last['rows']], ['050', '051', '052'])
        self.assertEqual([r['value'] for r in self.choices(filters={'source_job': '052', 'shift': 'Night'})['rows']], ['000', '001'])
        self.assertEqual(self.choices(query='_%')['rows'], [{'value': '000', 'label': 'LITERAL_%/26'}])
        self.assertEqual(self.choices(filters={'from_date': '2026-11-16'})['rows'], [])

    def test_case_zero_and_leading_zero_ids_are_exact_and_verified_labels_are_not_guessed(self):
        for i, value in enumerate(('A', 'a', '0', '00')):
            self.production(i, value);self.original(value, 'SAVED-' + value)
        self.assertEqual([r['value'] for r in self.choices()['rows']], ['0', '00', 'A', 'a'])
        for value in ('A', 'a', '0', '00'):
            page = api.records(self.companies[0], 'production', filters={'source_job': value})
            self.assertEqual(page['row_count'], 1)
            self.assertEqual(page['filter_labels'], {'source_job': 'SAVED-' + value})

    def test_wrong_original_job_header_or_book_does_not_supply_a_full_reference(self):
        self.production('1', 'A', source_book='0')
        self.original('A', 'DO-NOT-USE/26', header={'sec_acc': '1'})
        self.assertEqual(self.choices()['rows'], [{'value': 'A', 'label': 'Original job A'}])
        self.assertEqual(api.records(self.companies[0], 'production', filters={'source_job': 'A'})['row_count'], 1)

    def test_corrupt_production_and_linked_job_fail_closed_and_never_mutate_originals(self):
        prod = self.production('1', 'A');job = self.original('A')
        before = frappe.db.get_value(service.RECORD, job, ['record_data', 'data_sha256'], as_dict=True)
        self.choices();api.records(self.companies[0], 'production', filters={'source_job': 'A'})
        self.assertEqual(frappe.db.get_value(service.RECORD, job, ['record_data', 'data_sha256'], as_dict=True), before)
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', ('0' * 64, job))
        with self.assertRaises(frappe.ValidationError):self.choices()
        with self.assertRaises(frappe.ValidationError):api.records(self.companies[0], 'production', filters={'source_job': 'A'})
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', (before.data_sha256, job))
        frappe.db.sql('update `tabHistorical Business Record` set native_id=%s where name=%s', ('wrong', prod))
        with self.assertRaises(frappe.ValidationError):self.choices()

    def test_absent_original_containers_remain_readable_with_explicit_unresolved_labels(self):
        own = self.production('1', 'A')
        missing = service.store_record(self.scope, self.values(namespace='knitpack.production', family='production',
            native_id='2', business_data={'fields': {'job': 'raw'}, 'original_business': None}))['name']
        service.store_record(self.scope, self.values(namespace='knitpack.job', family='job', native_id='A',
            business_data={'fields': {}, 'original_business': None}))
        self.assertEqual({r['name'] for r in api.records(self.companies[0], 'production')['rows']}, {own, missing})
        self.assertEqual(self.choices()['rows'], [{'value': 'A', 'label': 'Original job A'}])
        selected = api.records(self.companies[0], 'production', filters={'source_job': 'A'})
        self.assertEqual(selected['row_count'], 1)
        self.assertEqual(selected['filter_labels'], {'source_job': 'Original job A'})

    def test_empty_filtered_results_keep_known_labels_but_never_guess_unknown_or_ambiguous_ids(self):
        self.original('A', 'KNOWN/26');self.production('1', 'A')
        filters = {'source_job': 'A', 'from_date': '2026-12-01', 'machine': 'No matching machine'}
        page = api.records(self.companies[0], 'production', filters=filters)
        self.assertEqual(page['row_count'], 0)
        self.assertEqual(page['filter_labels'], {'source_job': 'KNOWN/26'})
        self.assertEqual(production_summary(self.companies[0], filters=filters)['filter_labels'],
                         {'source_job': 'KNOWN/26'})
        self.original('B', 'UNOBSERVED-IN-PRODUCTION/26')
        self.assertEqual(api.records(self.companies[0], 'production', filters={'source_job': 'B'})['filter_labels'],
                         {'source_job': 'Original job B'})
        self.original('A', 'OTHER-BOOK/25', source_book='1')
        self.assertEqual(api.records(self.companies[0], 'production', filters=filters)['filter_labels'],
                         {'source_job': 'Original job A'})
        self.production('2', 'A', source_book='0')
        self.assertEqual(api.records(self.companies[0], 'production', filters={**filters, 'source_book': '0'})['filter_labels'],
                         {'source_job': 'KNOWN/26'})

    def test_only_invalid_header_identities_do_not_advertise_an_empty_source_job_facet(self):
        self.production('1', 'bad\n');self.production('2', True)
        self.assertNotIn('source_job', api.records(self.companies[0], 'production')['available_filters'])
        self.assertEqual(self.choices()['rows'], [])

    def test_scope_membership_company_access_and_nonproduction_filters_remain_authoritative(self):
        self.production('1', 'A')
        with patch.object(api, 'financial_access', return_value=False):self.assertEqual(len(self.choices()['rows']), 1)
        with patch.object(api, '_member', return_value=False), self.assertRaises(frappe.PermissionError):self.choices()
        with self.assertRaises(frappe.PermissionError):api.filter_options('Unbound company', 'production', 'source_job')
        for family in ('job', 'invoice'):
            with self.subTest(family=family), self.assertRaises(frappe.ValidationError):
                api.records(self.companies[0], family, filters={'source_job': 'A'})
