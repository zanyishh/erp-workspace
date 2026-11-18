"""Exact production dimensions remain scoped parameters, not inferred master IDs."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps/erp_extensions'))
from erp_extensions.migration import filtering


class ProductionFilterContractTests(unittest.TestCase):
    def test_saved_dimensions_remain_exact_bound_parameters(self):
        values = {'machine': '00_1%', 'operator': "O'Brien", 'description': 'Rib / 2x2', 'dia': '0'}
        self.assertTrue(set(values) <= set(filtering.FIELDS))
        where, params = filtering.predicate('synthetic-scope', 'Synthetic Company', 'production', values)
        self.assertIn('family=%(family)s', where)
        self.assertEqual(params['family'], 'production')
        self.assertEqual(params['scope'], 'synthetic-scope')
        self.assertEqual(params['company'], 'Synthetic Company')
        for key, value in values.items():
            self.assertEqual(params[key], value)
            self.assertIn('BINARY %(' + key + ')s', where)
        self.assertNotIn("O'Brien", where)
        self.assertNotIn('00_1%', where)

    def test_only_normalized_known_dimensions_are_accepted(self):
        for field in ('machine', 'operator', 'description', 'dia'):
            self.assertIn(field, filtering.FIELDS)
            self.assertIn('$.business_data.fields.' + field, filtering.expression(field))
        for values in ({'employee_id': '1'}, {'original_business': 'x'}, {'machine': []},
                       {'operator': ''}, {'dia': 0}, {'description': 'x\0y'}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                filtering.parse(values)

    def test_production_dimensions_do_not_change_other_record_family_filters(self):
        for family in ('job', 'invoice', 'voucher', 'shared_cash'):
            with self.subTest(family=family), self.assertRaises(ValueError):
                filtering.predicate('scope', 'company', family, {'machine': '1'})


if __name__ == '__main__':
    unittest.main()
