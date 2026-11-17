"""Aggregate fabric keeps exact kg/counts; never invents per-roll weights."""
import base64
from decimal import Decimal
import frappe
from erp_extensions.tests import test_knitting as fixtures


class FabricBatchTests(fixtures.KnittingTests):
    def call(self, action, values, **kwargs):
        if action != 'create_job':
            values = {'job':self.job,**values}
        return super().call(action, values, **kwargs)

    def batch_fixture(self):
        self.fixtures()
        from erp_extensions.knitting import domain, permissions
        with permissions.service_write():
            return domain.insert('Knitting Fabric Batch', company=fixtures.COMPANY,
                job=self.job, programme_line='P1', quantity_kg='88.000', rolls='7',
                state='Awaiting review', source_reference='Original batch 12',
                source_record='SYNTHETIC-CAPTURE-BATCH-12', captured_at='2026-11-01 09:00:00')

    def test_partial_delivery_keeps_unequal_aggregate_and_retry_is_idempotent(self):
        batch = self.batch_fixture()
        with self.assertRaises(frappe.ValidationError):
            self.call('deliver_batch', {'batch':batch.name,'quantity_kg':'21.300','rolls':'2'})
        self.call('review_batch', {'batch':batch.name,'decision':'Released','remarks':'Count and weight checked'})
        request = 'synthetic-batch-delivery-1'
        payload = {'batch':batch.name,'quantity_kg':'21.300','rolls':'2'}
        version = frappe.get_doc('Knitting Job', self.job).modified
        first = self.call('deliver_batch', payload, request_id=request, modified=version)
        self.assertEqual(first, self.call('deliver_batch', payload, request_id=request, modified=version))
        challan = self.knitting().export(fixtures.COMPANY, 'delivery_challan', {'event': first['event']})
        self.assertTrue(base64.b64decode(challan['content']).startswith(b'%PDF'))
        batch.reload()
        self.assertEqual(Decimal(batch.quantity_kg), Decimal('66.700'))
        self.assertEqual(batch.rolls, '5')
        self.assertEqual(frappe.db.count('Knitting Roll', {'job':self.job}), 0)
        from erp_extensions.knitting import domain
        self.assertEqual(domain.balances(self.job)['fabric_kg'], '66.700')
        with self.assertRaises(frappe.ValidationError):
            self.call('deliver_batch', {'batch':batch.name,'quantity_kg':'66.700','rolls':'4'})

    def test_batch_invoice_credit_then_return_preserves_both_quantities(self):
        batch = self.batch_fixture()
        self.call('review_batch', {'batch':batch.name,'decision':'Released','remarks':'Verified'})
        delivery = self.call('deliver_batch', {'batch':batch.name,'quantity_kg':'21.300','rolls':'2'})
        invoice = self.call('invoice', {'deliveries':[delivery['event']]})
        with self.assertRaises(frappe.ValidationError):
            self.call('return_batch', {'delivery':delivery['event'],'batch':batch.name,
                'quantity_kg':'21.300','rolls':'2','reason':'Return'})
        self.call('credit_invoice', {'invoice_event':invoice['event'],'quantity_kg':'21.300','reason':'Return'})
        self.call('return_batch', {'delivery':delivery['event'],'batch':batch.name,
            'quantity_kg':'21.300','rolls':'2','reason':'Return'})
        batch.reload()
        self.assertEqual(Decimal(batch.quantity_kg),Decimal('88'))
        self.assertEqual(batch.rolls,'7')
        self.assertEqual(batch.state,'Awaiting review')


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(FabricBatchTests, name, None)
