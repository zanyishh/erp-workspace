"""Pure original-production projection and filter checks; no source or database."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps/erp_extensions'))
from erp_extensions.migration import contracts, filtering


class ProductionListContractTests(unittest.TestCase):
    def test_projection_excludes_unreviewed_and_financial_values(self):
        projection = getattr(contracts, 'production_fields', None)
        self.assertIsNotNone(projection, 'Production needs a bounded list projection')
        result = projection({'fields': {'job': 'SYN-12', 'party': 'Synthetic party',
            'description': 'Synthetic fabric', 'dia': '30', 'net_kg': '0.000', 'rolls': 0,
            'machine': 'M-1', 'operator': 'Synthetic employee', 'shift': 'Night',
            'source_id': 'not-the-canonical-id', 'rate': '999', 'phone': 'not-for-the-list'},
            'original_business': {'header': {'remarks': 'not-for-the-list'}}})
        self.assertEqual(result, {'job': 'SYN-12', 'party': 'Synthetic party',
            'description': 'Synthetic fabric', 'dia': '30', 'net_kg': '0.000', 'rolls': 0,
            'machine': 'M-1', 'operator': 'Synthetic employee', 'shift': 'Night'})

    def test_missing_values_stay_null_and_nested_fields_fail_closed(self):
        projection = getattr(contracts, 'production_fields', None)
        self.assertIsNotNone(projection, 'Production needs a bounded list projection')
        self.assertEqual(projection({'fields': {'rolls': None}}),
            {key: None for key in ('job', 'party', 'description', 'dia', 'net_kg', 'rolls', 'machine', 'operator', 'shift')})
        with self.assertRaises(ValueError):projection({'fields': {'machine': {'private': 'value'}}})

    def test_shift_is_exact_bounded_parameterized_normalized_filter(self):
        try:
            where, params = filtering.predicate('scope', 'company', 'production', {'shift': "Night_%'"})
        except ValueError as error:
            self.fail('Captured Shift must be supported: ' + str(error))
        self.assertEqual(params['shift'], "Night_%'")
        self.assertNotIn("Night_%'", where)
        self.assertIn('$.business_data.fields.shift', where)
        for value in ('', '\x00', ['Night'], 'x' * 4097):
            with self.subTest(value=value), self.assertRaises(ValueError):filtering.parse({'shift': value})


if __name__ == '__main__':
    unittest.main()
