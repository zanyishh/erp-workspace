"""Framework-free parser checks; SQL integration is tested on native-test."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'apps/erp_extensions'))
from erp_extensions.migration import filtering


class FilterContractTests(unittest.TestCase):
    def test_default_preserves_undated_and_range_defaults_original(self):
        self.assertEqual(filtering.parse(None),{})
        self.assertEqual(filtering.parse({'from_date':'2026-11-01'})['date_basis'],'original')
        self.assertEqual(filtering.parse({'source_book':None}),{'source_book':None})

    def test_rejects_unknown_invalid_and_ambiguous_values(self):
        for value in ({'unknown':'x'},{'party':[]},{'source_book':True},{'party':''},
                {'from_date':'2026-02-30'},{'date_basis':'no_original','to_date':'2026-01-01'},
                {'from_date':'2026-01-02','to_date':'2026-01-01'}):
            with self.subTest(value=value),self.assertRaises(ValueError):filtering.parse(value)

    def test_exact_values_are_parameters_not_sql(self):
        where,params=filtering.predicate('scope','company','job',{'party':"O'Brien_%",'source_book':None})
        self.assertNotIn("O'Brien",where)
        self.assertIn("O'Brien_%",params.values())
        self.assertIn('source_book is null',where)
        self.assertIn('shared_reference=1',where)

if __name__=='__main__':unittest.main()
