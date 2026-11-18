"""Rollback-only operational migration checks on the isolated native test site."""
from copy import deepcopy
from datetime import datetime, time, timedelta
from decimal import Decimal
from unittest.mock import patch

import frappe
from frappe.utils import getdate, get_datetime
from erp_extensions.migration import operations, service, finance
from erp_extensions.knitting import api, domain, reports
from erp_extensions.tests.test_migration_store import HistoricalStoreTests


class HistoricalOperationsTests(HistoricalStoreTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        try:
            frappe.set_user('Administrator')
            from erp_extensions.knitting.install import install
            install(); finance.install(); frappe.db.commit()
        finally:
            frappe.destroy()

    def setUp(self):
        super().setUp()
        self.flag = patch.dict(frappe.conf, {'erp_customer_migration_enabled': True})
        self.flag.start(); self.addCleanup(self.flag.stop)
        self.company = self.companies[1]
        self.suffix = frappe.generate_hash(length=8)
        self.customer = frappe.get_doc({'doctype': 'Customer', 'customer_name': 'Synthetic custody '+self.suffix,
            'customer_type': 'Company', 'customer_group': frappe.db.get_value('Customer Group', {'is_group': 0}, 'name'),
            'territory': frappe.db.get_value('Territory', {'is_group': 0}, 'name')}).insert().name
        self.warehouse = frappe.db.get_value('Warehouse', {'company': self.company, 'is_group': 0}, 'name')
        self.items = {}
        for name, stock in (('service', 0), ('fabric', 1)):
            self.items[name] = frappe.get_doc({'doctype': 'Item', 'item_code': 'MIG-'+name+'-'+self.suffix,
                'item_name': 'Synthetic '+name, 'item_group': frappe.db.get_value('Item Group', {'is_group': 0}, 'name'),
                'stock_uom': 'Kg', 'is_stock_item': stock}).insert().name
        from erp_extensions import workspace
        workspace.configure(self.company, {'state': 'Active', 'shifts': ['A'], 'warehouse': self.warehouse,
            'service_item': self.items['service'], 'fabric_item': self.items['fabric']})
        finance.configure_books(self.scope, [{'source_company_id': str(c), 'source_book': str(b),
            'finance_book': f'Synthetic operations {self.suffix} {c}/{b}'} for c in range(1, 5) for b in range(3)])
        self.book = f'Synthetic operations {self.suffix} 2/0'
        self.record = service.store_record(self.scope, self.values(namespace='knitpack.job', family='job',
            source_company_id='2', original_date_raw='2020-02-29', business_data={'fields': {}, 'tables': [],
                'original_business': {'fabric_context': {'fabs': [{'id': '10', 'jobmas_id': '42', 'uoms': 'KGS',
                    'billrate': '100', 'dias': [{'id': '100', 'jobfabric_id': '10'}]}]}}}))['name']
        self.cutoff = datetime.combine(getdate()-timedelta(days=1), time(12))
        self.job = 'MIG-JOB-'+self.suffix
        self.payload = {'source_company_id': '2', 'source_job_id': '42', 'source_book': '0',
            'job': {'name': self.job, 'company': self.company, 'customer': self.customer,
                'billing_customer': self.customer, 'fabric_owner': self.customer, 'job_date': '2020-02-29',
                'kind': 'Order', 'material_mode': 'Customer', 'status': 'Running', 'target_kg': '88.000',
                'revision': 1, 'charge_policy': 'Included', 'pricing': {'P1': '100.00'},
                'programme': [{'id': 'P1', 'fabric': 'Synthetic jersey', 'target_kg': '88.000', 'dia': '30', 'gauge': '24',
                    'source_fabric_id': '10', 'source_size_id': '100'}]},
            'batches': [], 'yarn': [], 'physical_basis': 'Synthetic captured stock, no historical movements inferred.'}
        self.add_batch('P1', '88.000', '7', produced='88.000')
        self.add_yarn('positive', '7.125', '2')

    def add_batch(self, line, quantity, rolls, produced='0.000'):
        if line != 'P1':
            self.payload['job']['programme'].append({'id': line, 'fabric': 'Synthetic '+line, 'target_kg': '0.000'})
        self.payload['batches'].append({'name': 'MIG-BATCH-'+self.suffix+'-'+line, 'job': self.job,
            'company': self.company, 'programme_line': line, 'quantity_kg': quantity, 'rolls': rolls,
            'produced_kg': produced, 'state': 'Awaiting review', 'source_reference': 'Synthetic original '+line,
            'specification': deepcopy(self.payload['job']['programme'][-1])})

    def add_yarn(self, key, quantity, units):
        self.payload['yarn'].append({'name': 'MIG-LOT-'+self.suffix+'-'+key, 'company': self.company, 'job': self.job,
            'item_code': 'MIG-YARN-'+self.suffix+'-'+key, 'item_name': 'Synthetic yarn '+key,
            'source_lot': key, 'party': self.customer, 'quantity_kg': quantity, 'units': units, 'specification': {}})

    def apply(self, payload=None, **changes):
        return operations.apply_job(self.record, payload or self.payload,
            **{'service_item': self.items['service'], 'warehouse': self.warehouse,
               'finance_book': self.book, 'cutoff': str(self.cutoff), **changes})

    def call(self, action, values, **kwargs):
        if action == 'invoice' and 'tax_template' not in values and 'no_tax' not in values:
            values = {**values, 'no_tax': True}
        return api.command(self.company, action, {'job': self.job, **values},
            kwargs.get('request_id', frappe.generate_hash(length=20)),
            kwargs.get('modified', str(frappe.db.get_value('Knitting Job', self.job, 'modified'))))

    def report(self, name, **filters):
        return reports.run(self.company, name, {'job': self.job, **filters})

    def legacy_fixture(self):
        self.apply()
        children = [{'id': identity, 'dc_id': '77', 'fabric_id': '10', 'jobdia_id': '100',
            'dlvry_kgs': quantity, 'dlvry_rolls': rolls, 'rate': '0', 'rate_for': basis}
            for identity, quantity, rolls, basis in (('701', '12.345', '3', ''), ('702', '4.000', '1', 'kgs'))]
        source = service.store_record(self.scope, self.values(namespace='knitpack.fabric_delivery', family='delivery',
            source_company_id='2', native_id='77', original_date_raw='2020-03-02', original_reference='Original DC-77',
            business_data={'original_business': {'header': {'id': '77', 'companymas_id': '2', 'job_no': '42',
                'dc_date': '2020-03-02', 'invoice_id': '0', 'cancelled': '0', 'fabric_dia_details': children}}}))['name']
        summary = {'source_record': self.record, 'source_company_id': '2', 'native_job_id': '42', 'source_book': '0',
            'current_available': True, 'child_delivered_kgs': '56.345', 'source_billed_delivery_group_kgs': '40.000',
            'eligible_unbilled_kgs': '16.345', 'dc_count': 3}
        deliveries = [{'source_record': source, 'job_source_record': self.record, 'native_dc_id': '77',
            'original_date': '2020-03-02', 'lines': [{'native_line_id': c['id'], 'fabric_id': '10', 'jobdia_id': '100',
                'eligible_for_continuation': True, 'eligible_unbilled_kgs': c['dlvry_kgs'], 'invoice_references': []} for c in children]}]
        return summary, deliveries

    def test_legacy_billing_references_are_atomic_exact_and_do_not_replay_stock_or_invoices(self):
        summary, deliveries = self.legacy_fixture()
        insert = domain.insert
        def fail_baseline(doctype, **values):
            if values.get('kind')=='migration_billing_initialization': raise RuntimeError('Synthetic interruption')
            return insert(doctype, **values)
        with patch.object(domain, 'insert', side_effect=fail_baseline), self.assertRaises(RuntimeError):
            operations.apply_legacy_billing_refs(self.job, summary, deliveries, proof_sha256='d'*64)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job, 'kind': 'migration_delivery_reference'}), 0)
        altered = deepcopy(deliveries); altered[0]['lines'][0]['eligible_unbilled_kgs']='12.346'
        with self.assertRaises(frappe.ValidationError):
            operations.apply_legacy_billing_refs(self.job, summary, altered, proof_sha256='d'*64)
        before = {dt: frappe.db.count(dt, {'company': self.company}) for dt in ('Sales Invoice', 'Journal Entry', 'Stock Entry')}
        before_unbilled = Decimal(api.overview(self.company)['balances']['unbilled_kg'])
        result = operations.apply_legacy_billing_refs(self.job, summary, deliveries, proof_sha256='d'*64)
        self.assertTrue(result['created'])
        self.assertFalse(operations.apply_legacy_billing_refs(self.job, summary, deliveries, proof_sha256='d'*64)['created'])
        for dt, count in before.items(): self.assertEqual(frappe.db.count(dt, {'company': self.company}), count)
        totals = domain.balances(self.job)
        self.assertEqual((totals['fabric_kg'], totals['yarn_kg']), ('88.000', '7.125'))
        self.assertEqual((totals['delivered_kg'], totals['billed_kg'], totals['unbilled_kg']), ('56.345', '40.000', '16.345'))
        self.assertEqual(Decimal(api.overview(self.company)['balances']['unbilled_kg']), before_unbilled + Decimal('16.345'))
        captured = self.report('jobs')['rows'][0]
        self.assertEqual((captured['delivered_kg'], captured['captured_delivered_kg'], captured['billed_kg'], captured['unbilled_kg']),
            ('56.345', '56.345', '40.000', '16.345'))
        period = self.report('jobs', mode='period', from_date=str(getdate()), to_date=str(getdate()))['rows'][0]
        self.assertEqual((period['delivered_kg'], period['billed_kg']), ('0.000', '0.000'))
        source = frappe.get_doc('Knitting Event', {'job': self.job, 'kind': 'migration_delivery_reference'})
        self.assertEqual(str(getdate(source.occurred_at)), '2020-03-02')
        self.assertNotEqual(getdate(source.creation), getdate(source.occurred_at))
        self.assertEqual({r['legacy_line'] for r in frappe.parse_json(source.result)['sources']}, {'701', '702'})
        with self.assertRaises(frappe.ValidationError): self.call('cancel_event', {'event': source.name, 'reason': 'Cannot alter original'})

    def test_legacy_same_programme_children_bill_at_current_reviewed_rate_and_credit_exactly(self):
        summary, deliveries = self.legacy_fixture()
        operations.apply_legacy_billing_refs(self.job, summary, deliveries, proof_sha256='d'*64)
        source = frappe.db.get_value('Knitting Event', {'job': self.job, 'kind': 'migration_delivery_reference'}, 'name')
        from erp_extensions.knitting import permissions
        with permissions.service_write():
            job = frappe.get_doc('Knitting Job', self.job); job.pricing=frappe.as_json({'P1': '200.00'}); job.save()
        first = self.call('invoice', {'deliveries': [source], 'quantity_kg': '13.000'})
        doc = frappe.get_doc('Sales Invoice', first['data']['invoice'])
        self.assertEqual(Decimal(str(doc.grand_total)), Decimal('2600.00'))
        allocations = first['data']['allocations']
        self.assertEqual([(r['legacy_line'], r['quantity_kg']) for r in allocations], [('701', '12.345'), ('702', '0.655')])
        self.call('invoice', {'deliveries': [source]})
        self.assertEqual(domain.balances(self.job)['unbilled_kg'], '0.000')
        with self.assertRaises(frappe.ValidationError): self.call('invoice', {'deliveries': [source]})
        self.call('credit_invoice', {'invoice_event': first['event'], 'quantity_kg': '13.000', 'reason': 'Correct future invoice'})
        self.assertEqual(domain.balances(self.job)['unbilled_kg'], '13.000')
        self.assertEqual(domain.balances(self.job)['fabric_kg'], '88.000')
        self.assertFalse(operations.apply_legacy_billing_refs(self.job, summary, deliveries, proof_sha256='d'*64)['created'])

    def test_initialization_is_atomic_and_retry_preserves_dates_signed_stock_and_no_rolls(self):
        self.add_batch('P2', '-2.345', '-1'); self.add_batch('P3', '0.000', '0')
        self.add_yarn('negative', '-0.125', '-1'); self.add_yarn('zero', '0.000', '0')
        with patch.object(domain, 'ledger', side_effect=RuntimeError('Synthetic interruption')):
            with self.assertRaises(RuntimeError): self.apply()
        self.assertFalse(frappe.db.exists('Knitting Job', self.job))
        self.assertEqual(frappe.db.count('Knitting Fabric Batch', {'job': self.job}), 0)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), 0)
        self.assertEqual(frappe.db.count(service.AUTHORITY, {'record': self.record}), 0)
        first = self.apply(); self.assertTrue(first['created']); self.assertFalse(self.apply()['created'])
        job = frappe.get_doc('Knitting Job', self.job)
        self.assertEqual(str(job.job_date), '2020-02-29')
        self.assertNotEqual(getdate(job.creation), getdate(job.job_date))
        self.assertEqual(get_datetime(job.migration_cutoff), self.cutoff)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), 1)
        self.assertEqual(frappe.db.count('Knitting Roll', {'job': self.job}), 0)
        self.assertEqual(frappe.db.count('Knitting Material Lot', {'name': ['in', [r['name'] for r in self.payload['yarn']]]}), 3)
        self.assertEqual(domain.balances(self.job)['fabric_kg'], '85.655')
        self.assertEqual(domain.balances(self.job)['yarn_kg'], '7.000')
        self.assertEqual(domain.balances(self.job)['produced_kg'], '88.000')
        self.assertEqual(domain.balances(self.job)['captured_produced_kg'], '88.000')
        self.assertEqual(domain.programme_produced(job, 'P1'), Decimal('88.000'))
        rows = self.report('fabric', to_date=str(self.cutoff.date()))['rows']
        self.assertEqual({r['name']: (r['quantity_kg'], r['roll_count']) for r in rows},
            {r['name']: (r['quantity_kg'], r['rolls']) for r in self.payload['batches']})
        self.assertTrue(all(r['weight_kg'] is None for r in rows))
        grouped = self.report('fabric', group_by='customer')['rows'][0]
        self.assertEqual(grouped['quantity_kg'], '85.655')
        self.assertIsNone(grouped['weight_kg'])

    def test_changed_parent_book_date_precision_and_audit_fields_are_rejected_before_write(self):
        changes = [lambda p: p['job'].update(job_date='2020-03-01'),
            lambda p: p['job'].update(creation='2020-02-29 00:00:00'),
            lambda p: p.update(source_book='1'),
            lambda p: p['batches'][0].update(company=self.companies[0]),
            lambda p: p['batches'][0].update(job='Other order'),
            lambda p: p['yarn'][0].update(party='Another customer'),
            lambda p: p['yarn'][0].update(quantity_kg='0.0001'),
            lambda p: p['batches'][0].update(rolls='1.5')]
        for change in changes:
            payload = deepcopy(self.payload); change(payload)
            with self.subTest(payload=payload['source_book']), self.assertRaises(frappe.ValidationError):
                self.apply(payload)
            self.assertFalse(frappe.db.exists('Knitting Job', self.job))
        with self.assertRaises(frappe.ValidationError): self.apply(finance_book='Unbound book')

    def test_reports_before_cutoff_are_unavailable_for_job_and_company_not_zero(self):
        self.apply()
        earlier = str(self.cutoff.date()-timedelta(days=1))
        for report in ('jobs', 'fabric', 'rolls', 'yarn', 'production', 'activity'):
            for extra in ({'job': self.job}, {}):
                with self.subTest(report=report, scope=extra), self.assertRaisesRegex(frappe.ValidationError, 'Imported history'):
                    reports.run(self.company, report, {'to_date': earlier, **extra})
        with self.assertRaisesRegex(frappe.ValidationError, 'Imported history'):
            self.report('jobs', mode='period', from_date=earlier, to_date=str(getdate()))

    def test_future_partial_delivery_invoice_credit_return_and_historical_snapshot(self):
        self.apply(); batch = self.payload['batches'][0]['name']
        self.call('review_batch', {'batch': batch, 'decision': 'Released', 'remarks': 'Verified count and weight'})
        version = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        values = {'batch': batch, 'quantity_kg': '21.300', 'rolls': '2'}
        delivery = self.call('deliver_batch', values, request_id='migration-delivery-retry', modified=version)
        self.assertEqual(delivery, self.call('deliver_batch', values, request_id='migration-delivery-retry', modified=version))
        self.assertFalse(self.apply()['created'])
        current = self.report('fabric')['rows'][0]
        self.assertEqual((current['quantity_kg'], current['roll_count'], current['state']), ('66.700', '5', 'Released'))
        past = self.report('fabric', to_date=str(self.cutoff.date()))['rows'][0]
        self.assertEqual((past['quantity_kg'], past['roll_count'], past['state']), ('88.000', '7', 'Awaiting review'))
        invoice = self.call('invoice', {'deliveries': [delivery['event']], 'quantity_kg': '10.000'})
        invoice_doc = frappe.get_doc('Sales Invoice', invoice['data']['invoice'])
        self.assertEqual(invoice_doc.finance_book, self.book)
        with self.assertRaises(frappe.ValidationError):
            self.call('return_batch', {**values, 'delivery': delivery['event'], 'reason': 'Customer return'})
        self.call('credit_invoice', {'invoice_event': invoice['event'], 'quantity_kg': '10.000', 'reason': 'Customer return'})
        self.call('return_batch', {**values, 'delivery': delivery['event'], 'reason': 'Customer return'})
        current = self.report('fabric')['rows'][0]
        self.assertEqual((current['quantity_kg'], current['roll_count'], current['state']), ('88.000', '7', 'Awaiting review'))
        job = self.report('jobs')['rows'][0]
        self.assertEqual((job['fabric_kg'], job['delivered_kg'], job['billed_kg']), ('88.000', '0.000', '0.000'))
        self.assertEqual(self.report('quality')['rows'][0]['batch'], batch)
        self.assertEqual(frappe.db.count('Knitting Roll', {'job': self.job}), 0)


for name in vars(HistoricalStoreTests):
    if name.startswith('test_'):
        setattr(HistoricalOperationsTests, name, None)
