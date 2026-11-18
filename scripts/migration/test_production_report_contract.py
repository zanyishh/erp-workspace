"""Exact original-production aggregation; no source or database connection."""
import importlib
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps/erp_extensions'))


class ProductionReportContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = None
        path = Path(__file__).resolve().parents[2] / 'apps/erp_extensions/erp_extensions/migration/production_reports.py'
        if path.exists():
            with patch.dict(sys.modules, {'frappe': SimpleNamespace(whitelist=lambda: lambda fn: fn)}):
                cls.report = importlib.import_module('erp_extensions.migration.production_reports')

    def summarize(self, records, group_by='machine', filters=None, start=0, page_length=100):
        self.assertIsNotNone(self.report, 'Original production needs an exact grouped report contract')
        return self.report._summarize(iter(records), group_by, filters, start, page_length)

    def record(self, fields=None, original_date='2026-11-13'):
        return {'original_date_raw': original_date, 'business_data': {'fields': fields or {}, 'tables': []}}

    def test_signed_fractional_values_are_summed_before_group_paging(self):
        records = [self.record({'machine': 'A', 'net_kg': '9999999999999999999999999999.99', 'rolls': '1.25'}),
                   self.record({'machine': 'A', 'net_kg': '-0.09', 'rolls': '-0.5'}),
                   self.record({'machine': 'B', 'net_kg': '0.10', 'rolls': 0})]
        result = self.summarize(records, page_length=1)
        self.assertEqual(result['row_count'], 2)
        self.assertTrue(result['has_more'])
        self.assertEqual(result['rows'][0]['quantity_kg'], '9999999999999999999999999999.90')
        self.assertEqual(result['rows'][0]['recorded_count'], '0.75')
        self.assertEqual(result['totals'], {'source_record_count': 3,
            'quantity_kg': '10000000000000000000000000000.00', 'recorded_count': '0.75',
            'missing_quantity_rows': 0, 'missing_count_rows': 0})
        self.assertEqual(self.summarize(records, start=1, page_length=1)['rows'][0]['value'], 'B')

    def test_missing_values_do_not_claim_recorded_zero_and_labels_remain_exact(self):
        result = self.summarize([self.record({'machine': 'a'}), self.record({'machine': 'A', 'net_kg': '', 'rolls': None}),
            self.record({'machine': '0', 'net_kg': 0, 'rolls': '0'}), self.record({'machine': ''}), self.record()])
        self.assertEqual([row['value'] for row in result['rows']], ['0', 'A', 'a', None])
        self.assertEqual(result['rows'][0]['quantity_kg'], '0')
        self.assertIsNone(result['rows'][1]['quantity_kg'])
        missing = result['rows'][-1]
        self.assertEqual(missing['label'], 'Unrecorded')
        self.assertEqual(missing['source_record_count'], 2)
        self.assertEqual(missing['missing_count_rows'], 2)
        self.assertFalse(missing['drillable'])
        self.assertIsNone(missing['filters'])
        self.assertEqual(result['totals']['missing_quantity_rows'], 4)
        self.assertIsNone(self.summarize([])['totals']['recorded_count'])

    def test_group_drilldowns_preserve_filters_and_use_actual_original_dates(self):
        filters = {'party': 'Saved party', 'machine': 'A', 'date_basis': 'effective', 'from_date': '2026-11-01'}
        result = self.summarize([self.record({'machine': 'A'})], 'original_date', filters)
        self.assertEqual(result['filters'], filters)
        self.assertEqual(result['rows'][0]['filters'], {'party': 'Saved party', 'machine': 'A',
            'date_basis': 'original', 'from_date': '2026-11-13', 'to_date': '2026-11-13'})
        self.assertEqual(self.summarize([self.record({'machine': 'a'})], filters={'party': 'P'})['rows'][0]['filters'],
                         {'party': 'P', 'machine': 'a'})
        undated = self.summarize([self.record(original_date='0000-00-00')], 'original_date')['rows'][0]
        self.assertEqual(undated['filters'], {'date_basis': 'no_original'})
        self.assertTrue(undated['drillable'])

    def test_typed_label_collisions_cannot_claim_exact_text_drilldown(self):
        result = self.summarize([self.record({'machine': '0'}), self.record({'machine': 0})])
        self.assertEqual(result['row_count'], 2)
        by_type = {type(row['value']): row for row in result['rows']}
        self.assertFalse(by_type[str]['drillable'])
        self.assertFalse(by_type[int]['drillable'])
        self.assertIsNone(by_type[int]['filters'])
        bools = self.summarize([self.record({'machine': 'false'}), self.record({'machine': False})])
        self.assertTrue(all(not row['drillable'] and row['filters'] is None for row in bools['rows']))

    def test_invalid_numeric_values_fail_closed_but_whitespace_is_missing(self):
        for value in ('NaN', 'Infinity', '-Infinity', 'oops', True, '1e9999999', '1_0', '١', {}, []):
            for field in ('net_kg', 'rolls'):
                with self.subTest(value=value, field=field), self.assertRaises(ValueError):
                    self.summarize([self.record({field: value})])
        result = self.summarize([self.record({'net_kg': '  ', 'rolls': '\t'})])
        self.assertIsNone(result['totals']['quantity_kg'])
        self.assertEqual(result['totals']['missing_count_rows'], 1)

    def test_only_supported_groups_filters_and_bounded_integer_pages_are_accepted(self):
        for group in ('job', 'amount', 'original_business', None, ['machine']):
            with self.subTest(group=group), self.assertRaises(ValueError):self.summarize([], group)
        for start, length in ((-1, 1), (1000001, 1), (0, 0), (0, 101), (1.5, 5), (False, 5), ('1.2', 5)):
            with self.subTest(start=start, length=length), self.assertRaises(ValueError):
                self.summarize([], start=start, page_length=length)
        with self.assertRaises(ValueError):self.summarize([], filters={'rate': 'secret'})
        result = self.summarize([self.record({'machine': 'X', 'rate': '99', 'amount': '123'})])
        self.assertFalse({'rate', 'amount', 'business_data', 'provenance'} & result['rows'][0].keys())


if __name__ == '__main__':
    unittest.main()
