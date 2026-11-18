"""The source-copy response must match the existing PDF field contract."""
import copy
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class OriginalPrintTests(unittest.TestCase):
    def response(self, taxes, *, samplerates=None, items=None, namespace='knitpack.invoice'):
        path=Path(__file__).resolve().parents[1]/'apps/erp_extensions/erp_extensions/migration/api.py'
        spec=importlib.util.spec_from_file_location('synthetic_print.api',path)
        api=importlib.util.module_from_spec(spec)
        modules={'frappe':SimpleNamespace(whitelist=lambda:lambda fn:fn,has_permission=lambda *args:True,
                throw=lambda message:(_ for _ in ()).throw(ValueError(message))),
            'synthetic_print':SimpleNamespace(contracts=SimpleNamespace(),service=SimpleNamespace()),
            'synthetic_print.install':SimpleNamespace(SCOPE='Scope',RECORD='Record',AUTHORITY='Authority'),
            'erp_extensions.knitting.permissions':SimpleNamespace(company_allowed=lambda company:True),
            'erp_extensions.invoices':SimpleNamespace(DEFAULT_STYLE='standard')}
        samplerates=samplerates if samplerates is not None else [{'dlvry_kgs':'10','billrate':'10','fabric_value':'100','kgs':'0','rate':'0'}]
        record={'namespace':namespace,'original_reference':'INV-1','native_id':'1',
            'business_data':{'original_business':{'fabric_context':{'samplerates':samplerates}}}}
        projection={'taxes':taxes,'currency':'INR','net_total':'105.00','grand_total':'105',
            'items':items if items is not None else [
            {'qty':'10','rate':'0','amount':'100','taxes':taxes}]}
        original=copy.deepcopy(projection)
        with patch.dict(sys.modules,modules):
            spec.loader.exec_module(api)
            with patch.object(api,'_visible_record',return_value=({},record)), \
                    patch.object(api,'_projection',return_value=projection), \
                    patch.object(api,'_printable',return_value=True), \
                    patch.object(api,'financial_access',return_value=True):
                result=api.invoice_print_data('Synthetic company','source-record')
        self.assertEqual(projection,original,'Printing must not rewrite the immutable projection')
        return result

    def test_source_tax_labels_and_exact_zero_and_nonzero_amounts_reach_pdf_fields(self):
        result=self.response([{'description':'CGST','tax_amount':'12.34','included_in_print_rate':0},
            {'description':'IGST','account_head':'Tax account','tax_amount':'0'}])
        rows=result['taxes']
        self.assertEqual(rows[0]['label'],'CGST (recorded)')
        self.assertEqual(rows[0]['amount'],'12.34')
        self.assertEqual(rows[0]['included_in_price'],0)
        self.assertEqual(rows[1]['account'],'Tax account')
        self.assertEqual(rows[1]['amount'],'0')
        self.assertEqual(result['items'][0]['taxes'][0]['label'],'CGST')
        self.assertEqual(result['items'][0]['taxes'][0]['amount'],rows[0]['amount'])

    def test_explicit_null_and_zero_are_not_replaced_by_fallback_amounts(self):
        rows=self.response([{'description':'First','amount':None,'tax_amount':'9'},
            {'description':'Second','amount':'0','tax_amount_after_discount_amount':'8','tax_amount':'9'},
            {'description':'Third','tax_amount_after_discount_amount':None,'tax_amount':'9'},
            {'description':'Missing'}])['taxes']
        self.assertIsNone(rows[0]['amount'])
        self.assertEqual(rows[1]['amount'],'0')
        self.assertIsNone(rows[2]['amount'])
        self.assertNotIn('amount',rows[3])

    def test_delivery_rate_uses_explicit_billrate_not_sample_price(self):
        result=self.response([],samplerates=[{'dlvry_kgs':'27.4','billrate':'10.00','fabric_value':'274','kgs':'0','rate':'0.00'}],
            items=[{'qty':'27.4','rate':'0.00','amount':'274','description':'Source fabric'}])
        self.assertEqual(result['items'][0]['rate'],'10.00')
        self.assertEqual(result['items'][0]['qty'],'27.4')
        self.assertEqual(result['items'][0]['amount'],'274')
        self.assertEqual(result['source_rate_label'],'Delivery rate')
        self.assertEqual(result['source_quantity_label'],'Delivered kg')

    def test_sample_flat_price_and_unrecalculated_group_amount_remain_explicit(self):
        result=self.response([],samplerates=[{'dlvry_kgs':'10','billrate':'10','fabric_value':'75','kgs':'5','rate':'25'}],
            items=[{'qty':'10','rate':'25','amount':'75','description':'Source fabric'}])
        self.assertEqual(result['items'][0]['rate'],'10')
        self.assertEqual(result['items'][0]['amount'],'75')
        self.assertIn('sample quantity 5 kg',result['terms'])
        self.assertIn('flat sample price 25 INR',result['terms'])
        self.assertIn('differs from delivered kg',result['terms'])

    def test_missing_delivery_rate_is_never_inferred_from_amount_and_quantity(self):
        with self.assertRaises(ValueError):
            self.response([],samplerates=[{'dlvry_kgs':'10','fabric_value':'100','kgs':'0','rate':'0'}])

    def test_recorded_regular_total_is_not_mislabeled_as_a_pretax_amount(self):
        result=self.response([{'description':'CGST','tax_amount':'2.50'}])
        self.assertEqual(result['net_total'],'105.00')
        self.assertEqual(result['grand_total'],'105')
        self.assertEqual(result['source_net_total_label'],'Recorded source total')
        self.assertTrue(result['source_tax_breakdown'])
        general=self.response([],namespace='knitpack.general_invoice')
        self.assertNotIn('source_net_total_label',general)
        self.assertEqual(general['net_total'],'105.00')


if __name__=='__main__':unittest.main()
