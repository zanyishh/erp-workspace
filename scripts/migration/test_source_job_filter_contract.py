"""Saved source-job identity selector; pure fixtures only, no source requests."""
import importlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps/erp_extensions'))
from erp_extensions.migration import filtering


class SourceJobFilterContractTests(unittest.TestCase):
    def helper(self):
        name = 'erp_extensions.migration.production_jobs'
        self.assertIsNotNone(importlib.util.find_spec(name), 'Production needs a saved source-job identity helper')
        return importlib.import_module(name)

    def production(self, job='A', *, book=None, **header):
        return {'name': 'p', 'source_scope': 'scope', 'company': 'Company', 'namespace': 'knitpack.production',
            'family': 'production', 'native_id': '7', 'source_company_id': '1', 'source_book': book,
            'shared_cash': False, 'shared_reference': False, 'business_data': {'fields': {'job': 'same'},
                'original_business': {'header': {'id': '7', 'companymas_id': '1', 'jobmas_id': job, **header}}}}

    def job(self, native='A', *, book='0', label='FULL/26', **header):
        return {'name': 'job-' + str(native) + '-' + str(book), 'source_scope': 'scope', 'company': 'Company',
            'namespace': 'knitpack.job', 'family': 'job', 'native_id': native, 'source_company_id': '1',
            'source_book': book, 'business_data': {'original_business': {'job_ledger': {
                'job': {'id': native, 'companymas_id': '1', 'sec_acc': book, **header}, 'pjobno': label}}}}

    def test_filter_accepts_exact_canonical_strings_and_integer_identity_only(self):
        try:parsed = filtering.parse({'source_job': 0, 'job': 'same'})
        except ValueError as error:self.fail('Saved production job identity must be selectable: ' + str(error))
        self.assertEqual(parsed, {'source_job': '0', 'job': 'same'})
        self.assertEqual(filtering.parse({'source_job': '00'})['source_job'], '00')
        for value in (None, True, 1.5, [], {}, '', ' A', 'A ', 'A\0B', 'x' * 141):
            with self.subTest(value=value), self.assertRaises(ValueError):filtering.parse({'source_job': value})

    def test_predicate_binds_saved_header_identity_and_rejects_nonproduction(self):
        try:where, params = filtering.predicate('scope', 'Company', 'production', {'source_job': 'A_0'})
        except ValueError as error:self.fail('Production needs its explicit saved-identity predicate: ' + str(error))
        self.assertEqual(params['source_job'], 'A_0')
        self.assertNotIn('A_0', where)
        self.assertIn('$.business_data.original_business.header.jobmas_id', where)
        self.assertIn('$.business_data.original_business.header.companymas_id', where)
        self.assertIn('$.business_data.original_business.header.id', where)
        for family in ('job', 'invoice', 'shared_cash'):
            with self.subTest(family=family), self.assertRaises(ValueError):
                filtering.predicate('scope', 'Company', family, {'source_job': 'A'})

    def test_missing_or_mismatched_headers_cannot_supply_a_source_job_identity(self):
        helper = self.helper()
        self.assertEqual(helper.source_job(self.production(0)), '0')
        self.assertEqual(helper.source_job(self.production('00')), '00')
        for record in (self.production(id='other'), self.production(companymas_id='2'),
                       self.production(True), self.production(' bad'),
                       {**self.production(), 'namespace': 'other.production'},
                       {**self.production(), 'business_data': {'fields': {'job': 'same'}}}):
            with self.subTest(record=record):self.assertIsNone(helper.source_job(record))

    def test_missing_original_containers_are_unresolved_without_hiding_records(self):
        helper = self.helper()
        for original in (None, [], {}):
            missing = {**self.production(), 'business_data': {'original_business': original}}
            try:identity = helper.source_job(missing)
            except AttributeError as error:self.fail('Missing original containers must stay unresolved: ' + str(error))
            self.assertIsNone(identity)
        for original in (None, {'job_ledger': None}, {'job_ledger': []}):
            job = {**self.job(), 'business_data': {'original_business': original}}
            self.assertEqual(helper.resolved_labels([self.production()], [job]), {'A': None})

    def test_labels_require_exact_scope_company_book_and_verified_header_without_year_guessing(self):
        helper = self.helper()
        prod = self.production('A', book='0')
        self.assertEqual(helper.resolved_labels([prod], [self.job()]), {'A': 'FULL/26'})
        self.assertEqual(helper.resolved_labels([prod], [self.job(book='1', label='WRONG/25')]), {'A': None})
        for bad in ({**self.job(), 'source_scope': 'other'}, {**self.job(), 'company': 'Other'},
                    self.job(id='other'), self.job(companymas_id='2'), self.job(sec_acc='1')):
            with self.subTest(bad=bad):self.assertEqual(helper.resolved_labels([prod], [bad]), {'A': None})
        # Production books were not captured on original imports: only a unique original is resolvable.
        self.assertEqual(helper.resolved_labels([self.production()], [self.job()]), {'A': 'FULL/26'})
        self.assertEqual(helper.resolved_labels([self.production()], [self.job(), self.job(book='1')]), {'A': None})
        self.assertEqual(helper.resolved_labels([prod, self.production(book='1')], [self.job(), self.job(book='1')]), {'A': None})
        self.assertEqual(helper.resolved_labels([self.production('a')], [self.job('A')]), {'a': None})
        self.assertEqual(helper.resolved_labels([prod], []), {'A': None})


if __name__ == '__main__':unittest.main()
