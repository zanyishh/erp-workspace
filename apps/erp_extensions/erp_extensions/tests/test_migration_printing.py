"""Synthetic operational source copies; isolated native-test database only."""
import unittest
from unittest.mock import patch

import frappe
from erp_extensions.migration import api, service
from erp_extensions.tests import test_migration_store as store_fixtures


class HistoricalPrintingTests(unittest.TestCase):
    setUpClass = classmethod(store_fixtures.HistoricalStoreTests.setUpClass.__func__)
    setUp = store_fixtures.HistoricalStoreTests.setUp
    _cleanup = store_fixtures.HistoricalStoreTests._cleanup

    def original(self, family='job', **changes):
        return service.store_record(self.scope, self.values(namespace='synthetic.'+family, family=family,
            business_data={'fields': {'quantity': '0.000', 'amount': '22.500', 'description': None},
                'tables': [{'kind': 'items', 'rows': [{'quantity': '0', 'rate': '2.500', 'description': 'Synthetic line'}]}],
                'original_business': {'header': {'private_source_field': 'not a print projection'}}}, **changes))['name']

    def test_supported_families_preserve_projection_and_original_digest(self):
        from erp_extensions.migration import printing
        for family in ('job', 'yarn_receipt', 'yarn_return', 'production', 'delivery', 'subcontract'):
            with self.subTest(family=family):
                name=self.original(family); before=service.get_record(name)
                result=printing.record_data(self.companies[0], name)
                self.assertEqual(set(result), {'version','company','source_record','source_copy','document_label',
                    'title','reference','original_date','effective_date','date_basis','review_status','fields','tables','review_notes'})
                self.assertEqual(result['source_record'], name)
                self.assertTrue(result['source_copy'])
                self.assertIn({'label':'Quantity','value':'0.000'}, result['fields'])
                self.assertEqual(result['tables'][0]['rows'][0]['rate'], '2.500')
                self.assertEqual(service.get_record(name), before)
                self.assertTrue(api.detail(self.companies[0],name)['record_printable'])
                self.assertFalse(api.detail(self.companies[0],name)['printable'])

    def test_nonfinancial_copy_masks_money_and_keeps_missing_dates_and_zero(self):
        from erp_extensions.migration import printing
        name=self.original(original_date_raw='0000-00-00')
        with patch.object(api, 'financial_access', return_value=False):
            result=printing.record_data(self.companies[0],name)
        self.assertIsNone(result['original_date'])
        self.assertIsNone(result['effective_date'])
        self.assertEqual(result['date_basis'],'undated_review')
        self.assertEqual({f['label']:f['value'] for f in result['fields']}, {'Quantity':'0.000','Description':None})
        self.assertEqual(result['tables'][0]['rows'],[{'description':'Synthetic line','quantity':'0'}])
        self.assertTrue(result['review_notes'])

    def test_financial_only_source_table_remains_masked_printable_and_immutable(self):
        from erp_extensions.migration import printing
        name=service.store_record(self.scope,self.values(namespace='synthetic.delivery',family='delivery',
            business_data={'fields':{},'tables':[{'kind':'items','rows':[{'amount':'22.500','rate':'2.500'}]}]}))['name']
        before=service.get_record(name)
        with patch.object(api,'financial_access',return_value=False):
            result=printing.record_data(self.companies[0],name)
            self.assertTrue(api.detail(self.companies[0],name)['record_printable'])
        self.assertEqual(result['fields'],[])
        self.assertEqual(result['tables'],[{'title':'Items','columns':[],'rows':[{}]}])
        self.assertNotIn('22.500',frappe.as_json(result))
        self.assertNotIn('2.500',frappe.as_json(result))
        self.assertEqual(service.get_record(name)['data_sha256'],before['data_sha256'])
        self.assertEqual(service.get_record(name),before)

    def test_print_scope_and_revoked_membership_are_checked_on_every_request(self):
        from erp_extensions.migration import printing
        name=self.original()
        with self.assertRaises(frappe.PermissionError):printing.record_data(self.companies[1],name)
        with patch.object(api,'_member',return_value=False):
            with self.assertRaises(frappe.PermissionError):printing.record_data(self.companies[0],name)
        original=frappe.has_permission
        for doctype,family in (('Knitting Job','job'),('Knitting Event','delivery')):
            name=self.original(family,native_id='denied-'+family)
            with patch.object(frappe,'has_permission',side_effect=lambda dt,ptype,*a,**k:
                    False if dt==doctype and ptype=='print' else original(dt,ptype,*a,**k)):
                self.assertFalse(api.detail(self.companies[0],name)['record_printable'])
                with self.assertRaises(frappe.PermissionError):printing.record_data(self.companies[0],name)

    def test_unsupported_family_cannot_use_operational_renderer(self):
        from erp_extensions.migration import printing
        for family in ('invoice','voucher','master','adjustment','stock_state'):
            name=self.original(family)
            self.assertFalse(api.detail(self.companies[0],name)['record_printable'])
            with self.assertRaises(frappe.PermissionError):printing.record_data(self.companies[0],name)

    def test_managed_route_is_exact_and_cashiers_remain_denied(self):
        from erp_extensions import team_scope
        def request(method, role='accountant'):
            with patch.object(team_scope,'membership',return_value=frappe._dict(team_role=role)), \
                    patch.object(frappe,'request',frappe._dict(path='/api/method/'+method)), \
                    patch.object(frappe,'form_dict',frappe._dict()):team_scope.guard_request()
        route='erp_extensions.migration.printing.record_data'
        request(route)
        for method,role in ((route,'cashier'),(route+'.other','accountant'),
                            ('erp_extensions.migration.printing.can_print','accountant')):
            with self.assertRaises(frappe.PermissionError):request(method,role)
