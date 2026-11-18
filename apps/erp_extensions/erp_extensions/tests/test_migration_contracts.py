"""Pure synthetic contract checks; no Frappe connection or customer data."""
import copy
import unittest

from erp_extensions.migration import contracts


class HistoricalContractTests(unittest.TestCase):
    def scope(self):
        return contracts.normalize_scope({'source_instance':'synthetic', 'company_bindings':
            {str(i):f'Synthetic Company {i}' for i in range(1,5)}, 'allowed_users':['fixture@example.invalid'],
            'opening_effective_date':'2023-04-01', 'physical_posting_mode':'closing_initialization',
            'manifest_sha256':'a'*64, 'policy_evidence_sha256':'b'*64})

    def record(self, **changes):
        value={'namespace':'accv2.voucher', 'source_company_id':'1','source_book':'0','native_id':'42',
            'family':'voucher','original_reference':'R-0042','original_date_raw':'2020-02-29',
            'title':'Synthetic receipt','summary':'Synthetic account receipt',
            'business_data':{'fields':{'party':'Synthetic party'},'tables':[],
                'financial':{'amount':'12.50','currency':'INR','entry_type':'credit','voucher_type':'receipt','cancelled':False}},
            'provenance':[{'file':'voucher.json','sha256':'c'*64,'pointer':'/result'}]}
        return {**value,**changes}

    def test_scope_requires_four_distinct_companies_and_explicit_members(self):
        scope=self.scope(); self.assertEqual(len(scope['company_bindings']),4)
        for change in ({'company_bindings':{'1':'One'}},{'allowed_users':[]},
                       {'company_bindings':{str(i):'Same' for i in range(1,5)}}):
            with self.subTest(change=change),self.assertRaises(ValueError):contracts.normalize_scope({**scope,**change})

    def test_business_identity_keeps_book_and_namespace_and_parent_scope(self):
        scope=self.scope(); original=contracts.normalize_record(scope,self.record())
        for change in ({'source_book':'1'},{'namespace':'another.voucher'},{'parent_scope':['line','1']}):
            self.assertNotEqual(original['source_key'],contracts.normalize_record(scope,self.record(**change))['source_key'])

    def test_opening_policy_preserves_raw_zero_date_in_party_and_shared_cash(self):
        scope=self.scope()
        for family,shared in (('opening',False),('cash_opening',True)):
            r=contracts.normalize_record(scope,self.record(family=family,shared_cash=shared,original_date_raw='0000-00-00'))
            self.assertEqual(r['original_date_raw'],'0000-00-00')
            self.assertEqual(r['effective_date'],'2023-04-01')
            self.assertEqual(r['date_basis'],'approved_opening')
            if shared:self.assertIsNone(r['company'])

    def test_invalid_transaction_date_is_retained_for_review_without_fallback(self):
        r=contracts.normalize_record(self.scope(),self.record(original_date_raw='2020-02-30'))
        self.assertIsNone(r['effective_date']);self.assertEqual(r['date_basis'],'undated_review')
        self.assertIn('invalid_original_date',[x['code'] for x in r['anomalies']])

    def test_master_needs_no_invented_business_date(self):
        r=contracts.normalize_record(self.scope(),self.record(family='master',source_book=None,original_date_raw=None,business_data={'fields':{},'tables':[]}))
        self.assertIsNone(r['effective_date']);self.assertEqual(r['date_basis'],'not_applicable')

    def test_raw_metadata_is_rejected_recursively_not_silently_exposed(self):
        for data in ({'fields':{'rc_session':'secret'}},{'fields':{},'tables':[{'kind':'items','rows':[{'token':'secret'}]}]},
                     {'fields':{},'financial':{'amount':'12','userinfo':{'name':'secret'}}}):
            with self.subTest(data=data),self.assertRaises(ValueError):contracts.normalize_record(self.scope(),self.record(business_data=data))

    def test_shared_cash_is_one_group_record_and_regular_transactions_cannot_claim_shared_visibility(self):
        scope=self.scope();r=contracts.normalize_record(scope,self.record(family='cash_movement',shared_cash=True))
        self.assertIsNone(r['company']);self.assertTrue(r['shared_cash'])
        with self.assertRaises(ValueError):contracts.normalize_record(scope,self.record(shared_cash=True))

    def test_canonical_provenance_order_is_idempotent_but_business_changes_are_not(self):
        scope=self.scope();value=self.record();value['provenance'].append({'file':'other.json','sha256':'d'*64,'pointer':'/root/0'})
        first=contracts.normalize_record(scope,value);again=copy.deepcopy(value);again['provenance'].reverse()
        self.assertEqual(first['data_sha256'],contracts.normalize_record(scope,again)['data_sha256'])
        again['business_data']['financial']['amount']='12.51'
        self.assertNotEqual(first['data_sha256'],contracts.normalize_record(scope,again)['data_sha256'])

    def test_incomplete_print_quantities_are_not_fabricated(self):
        data={'items':[{'qty':'1','amount':'2'}],'taxes':[],'grand_total':'2','currency':'INR'}
        self.assertFalse(contracts.print_projection_ready(data))

    def test_exact_original_business_children_are_retained_but_metadata_is_rejected(self):
        original={'header':{'id':'42','v_date':'0000-00-00','amt':'12.50','_fore_color':'#000000'},'lines':[{'id':'7','voucher_id':'42','taxable_value':'0'}]}
        r=contracts.normalize_record(self.scope(),self.record(business_data={'original_business':original}))
        self.assertEqual(r['business_data']['original_business'],original)
        for field in ('userinfo','session_token','auth','created_by','request','response','Variables','PASS'):
            with self.subTest(field=field),self.assertRaises(ValueError):
                contracts.normalize_record(self.scope(),self.record(business_data={'original_business':{'header':{field:'sensitive'}}}))


if __name__=='__main__':unittest.main()
