"""Offline conversion safeguards, using only synthetic source records."""
from decimal import Decimal
from pathlib import Path
import hashlib
import tempfile
import unittest
from erp_extensions.migration import normalize


class SourceNormalizationTests(unittest.TestCase):
    def test_allowlisted_business_tree_retains_exact_values_and_dates_only(self):
        row={'id':'7','amt':Decimal('1.20'),'created_time':'2020-01-01 03:00:00',
            'created_by':'private','session_id':'private','children':[{'id':'9','amt':'0.00'}]}
        clean=normalize.clean_business(row,{'id','amt','created_time','children'})
        self.assertEqual(clean,{'id':'7','amt':'1.20','created_time':'2020-01-01 03:00:00','children':[{'id':'9','amt':'0.00'}]})
        with self.assertRaises(ValueError):normalize.clean_business({'unexpected_business_field':'x'},{'id'})

    def test_manifest_hash_and_failure_envelope_are_checked_before_payload(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'fixture.json';raw=b'{"mode":"success","result":{"id":"7","amt":1.20}}';p.write_bytes(raw)
            entry={'file':p.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
            value,ref=normalize.read_artifact(Path(d),entry)
            self.assertEqual(value['result']['amt'],Decimal('1.20'));self.assertEqual(ref['sha256'],entry['sha256'])
            p.write_bytes(raw+b' ')
            with self.assertRaises(ValueError):normalize.read_artifact(Path(d),entry)
            self.assertFalse(normalize.success({'mode':'error','result':{'id':'7'}}))
            self.assertFalse(normalize.success({'isLogin':False,'result':{'id':'7'}}))
            self.assertFalse(normalize.success({'rc_error':True,'result':{'id':'7'}}))

    def test_print_items_require_actual_source_quantity_rate_and_amount(self):
        self.assertIsNone(normalize.print_line({'qty':'2','amount':'8'},quantity='qty',rate='price',amount='amount',description='item_disc'))
        line=normalize.print_line({'qty':'2','price':'4','amount':'8','item_disc':'Original service'},
            quantity='qty',rate='price',amount='amount',description='item_disc')
        self.assertEqual(line,{'item_name':'Original service','description':'Original service','qty':'2','rate':'4','amount':'8'})

    def test_saved_blank_description_prints_blank_without_inventing_a_line_label(self):
        header={'id':'1','companymas_id':'1','party_id':'7','inv_date':'2023-04-01','invoice_value':'8','r_invoice_value':'8',
            'item_details':[{'id':'10','item_disc':{'fab_name':'Original service'},'qty':'2','price':'4','total':'8'},
                {'id':'11','item_disc':{'fab_name':''},'qty':'0','price':'0','total':'0'}],
            'cgst_value':'0','sgst_value':'0','igst_value':'0'}
        projection=normalize.general_invoice_projection(header,{'id':'1','name':'Synthetic company'},
            {'id':'7','party_name':'Synthetic party'},currency='INR')
        self.assertEqual(projection['items'][1]['item_name'],'')
        self.assertEqual(projection['items'][1]['description'],'')
        self.assertEqual(projection['items'][1]['amount'],'0')
        self.assertIn('blank',projection['terms'])
        with self.assertRaises(ValueError):
            normalize.general_invoice_projection(header,{'id':'2','name':'Other'}, {'id':'7','party_name':'Party'},currency='INR')

