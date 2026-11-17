import unittest
from erp_extensions.migration import cash


class SharedCashTests(unittest.TestCase):
    def test_scope_cash_counts_once_and_matches_exact_source_controls(self):
        controls=[{'cash_book_id':'1','label':'Shared category','opening_debit':'10','opening_credit':'0',
            'movement_debit':'2','movement_credit':'3','closing_net':'9','opening_count':1,'movement_count':2}]
        rows=[{'source_key':'open','family':'cash_opening','business_data':{'fields':{'cash_book':'1','debit':'10','credit':'0'}}},
            {'source_key':'move1','family':'cash_movement','business_data':{'fields':{'cash_book':'1','debit':'2','credit':'0','native_amount':'2.49'}}},
            {'source_key':'move2','family':'cash_movement','business_data':{'fields':{'cash_book':'1','debit':'0','credit':'3'}}}]
        result=cash.summarize(rows+rows,controls)
        self.assertEqual(result[0]['net'],'9');self.assertTrue(result[0]['verified'])
        self.assertEqual(result[0]['movement_count'],2)
        incomplete=cash.summarize(rows[:-1],controls)[0]
        self.assertFalse(incomplete['verified']);self.assertEqual(incomplete['net'],'12')

    def test_missing_or_changed_cash_direction_is_not_assumed_zero(self):
        controls=[{'cash_book_id':'1','label':'Shared category','opening_debit':'0','opening_credit':'0',
            'movement_debit':'2','movement_credit':'0','closing_net':'2','opening_count':0,'movement_count':1}]
        row={'source_key':'movement','family':'cash_movement','business_data':{'fields':{'cash_book':'1','amount':'2'}}}
        with self.assertRaises(ValueError):cash.summarize([row],controls)
        row['business_data']['fields'].update(debit='2',credit='0')
        second={**row,'business_data':{'fields':{'cash_book':'1','debit':'3','credit':'0'}}}
        with self.assertRaises(ValueError):cash.summarize([row,second],controls)

