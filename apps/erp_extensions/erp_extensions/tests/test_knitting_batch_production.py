"""Measured aggregate output: synthetic custody only, never inferred roll weights."""
from decimal import Decimal
from unittest.mock import patch

import frappe

from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.knitting import api, domain, permissions, reports


class BatchProductionTests(fixtures.KnittingTests):
    def test_schema_only_upgrade_is_idempotent_and_keeps_audit_versions(self):
        from erp_extensions.knitting import install
        self.assertTrue(callable(getattr(install, 'upgrade_batch_production_schema', None)),
            'The destination needs a schema-only batch updater without full install side effects')
        audit = frappe.get_doc({'doctype': 'Version', 'ref_doctype': 'Knitting Fabric Batch',
            'docname': 'SYNTHETIC-BATCH-UPGRADE-AUDIT', 'data': '{}'}).insert()
        before = frappe.db.count('Version')
        self.assertFalse(install.upgrade_batch_production_schema()['changed'])
        self.assertEqual(frappe.db.count('Version'), before)
        self.assertTrue(frappe.db.exists('Version', audit.name))
        meta = frappe.get_meta('Knitting Fabric Batch')
        self.assertEqual(meta.get_field('production').options, 'Knitting Event')
        self.assertIn('Cancelled', meta.get_field('state').options.splitlines())

    def prepare(self, target='88.000'):
        self.fixtures(target=target)
        self.lot = self.receive('90.000')
        return {'job': self.job, 'programme_line': 'P1', 'quantity_kg': '88.000', 'rolls': '7',
            'inputs': [{'lot': self.lot, 'quantity_kg': '90.000', 'units': '2'}],
            'loss_kg': '2.000', 'warehouse': self.warehouse, 'shift': 'A', 'remarks': 'Measured together'}

    def post_batch(self, payload=None):
        return self.call('produce_batch', payload or self.prepare())

    def test_measured_batch_conserves_custody_without_inventing_rolls(self):
        result = self.post_batch()
        batch = frappe.get_doc('Knitting Fabric Batch', result['data']['batch'])
        self.assertEqual((batch.quantity_kg, batch.rolls, batch.state), ('88.000', '7', 'Awaiting review'))
        self.assertEqual(batch.production, result['event'])
        self.assertEqual(frappe.db.count('Knitting Roll', {'job': self.job}), 0)
        self.assertEqual(domain.lot_balance(self.lot, self.job), 0)
        self.assertEqual(domain.lot_units(self.lot, self.job), 0)
        balances = domain.balances(self.job)
        self.assertEqual({k: balances[k] for k in ('produced_kg', 'consumed_kg', 'loss_kg', 'fabric_kg')},
            {'produced_kg': '88.000', 'consumed_kg': '90.000', 'loss_kg': '2.000', 'fabric_kg': '88.000'})
        self.assertNotIn('rolls', result['data'])
        self.assertEqual(result['data']['roll_count'], '7')
        self.assertIsNone(result['data'].get('voucher'))

    def test_zero_count_and_same_request_replay_preserve_one_output(self):
        payload = {**self.prepare(), 'rolls': '0'}
        version = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        first = self.call('produce_batch', payload, 'aggregate-repeat', version)
        self.assertEqual(first, self.call('produce_batch', payload, 'aggregate-repeat', version))
        self.assertEqual(first['data']['roll_count'], '0')
        self.assertEqual(frappe.db.count('Knitting Fabric Batch', {'job': self.job}), 1)
        with self.assertRaises(frappe.ValidationError):
            self.call('produce_batch', {**payload, 'rolls': '1'}, 'aggregate-repeat', version)

    def test_invalid_quantities_and_unavailable_input_roll_back_all_effects(self):
        payload = self.prepare()
        before = {d: frappe.db.count(d, {'job': self.job}) for d in
            ('Knitting Event', 'Knitting Ledger Entry', 'Knitting Fabric Batch', 'Knitting Roll')}
        cases = [{'rolls': value} for value in ('-1', '1.5', True, None)] + [
            {'quantity_kg': '88.0001'}, {'quantity_kg': 'NaN'}, {'quantity_kg': '0'},
            {'loss_kg': '2.001'}, {'remarks': 'x' * 1001}, {'shift': {'untrusted': 'value'}},
            {'inputs': [{'lot': self.lot, 'quantity_kg': '90.001'}]},
            {'inputs': [{'lot': self.lot, 'quantity_kg': '45'}, {'lot': self.lot, 'quantity_kg': '45'}]},
            {'inputs': [{'lot': self.lot, 'quantity_kg': '90', 'units': '1'}]}]
        for changes in cases:
            with self.subTest(changes=changes), self.assertRaises(frappe.ValidationError):
                self.post_batch({**payload, **changes})
            self.assertEqual(before, {d: frappe.db.count(d, {'job': self.job}) for d in before})
            self.assertEqual(domain.lot_balance(self.lot, self.job), Decimal('90'))

    def test_aggregate_rejects_owned_and_mixed_material_without_stock_effects(self):
        payload = self.prepare()
        with permissions.service_write():
            lot = frappe.get_doc('Knitting Material Lot', self.lot)
            lot.material_owner = 'Owned'; lot.save()
        with self.assertRaisesRegex(frappe.ValidationError, 'customer-owned'):
            self.post_batch(payload)
        with permissions.service_write():
            lot.material_owner = 'Customer'; lot.save()
            job = frappe.get_doc('Knitting Job', self.job)
            job.material_mode = 'Owned'; job.save()
        with self.assertRaisesRegex(frappe.ValidationError, 'customer-owned'):
            self.post_batch(payload)
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))

    def test_failure_after_consumption_rolls_back_batch_event_and_custody(self):
        payload = self.prepare()
        original = domain.insert
        def fail_batch(doctype, **values):
            if doctype == 'Knitting Fabric Batch':
                frappe.throw('Synthetic storage failure after consuming yarn')
            return original(doctype, **values)
        before = frappe.db.count('Knitting Event', {'job': self.job})
        with patch.object(domain, 'insert', side_effect=fail_batch), self.assertRaisesRegex(frappe.ValidationError, 'Synthetic storage'):
            self.post_batch(payload)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), before)
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))
        self.assertEqual(domain.lot_balance(self.lot, self.job), Decimal('90'))
        self.assertEqual(domain.lot_units(self.lot, self.job), Decimal('2'))

    def test_aggregate_permissions_owner_and_stale_version_are_enforced(self):
        payload = self.prepare()
        frappe.set_user('knit-accountant@example.invalid')
        with self.assertRaises(frappe.PermissionError): self.post_batch(payload)
        frappe.set_user('Administrator')
        with self.assertRaises(frappe.TimestampMismatchError): self.call('produce_batch', payload, modified='2000-01-01')
        other = frappe.copy_doc(frappe.get_doc('Customer', self.customer))
        other.customer_name = 'Different synthetic owner'; other.insert()
        with permissions.service_write():
            lot = frappe.get_doc('Knitting Material Lot', self.lot); lot.party = other.name; lot.save()
        with self.assertRaisesRegex(frappe.ValidationError, 'owner'): self.post_batch(payload)
        with permissions.service_write(): lot.party = self.customer; lot.save()
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid',
            'allow': 'Customer', 'for_value': other.name, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError): self.post_batch(payload)

    def test_operator_can_record_custody_without_financial_permission(self):
        payload = self.prepare()
        frappe.set_user('knit-operator@example.invalid')
        result = self.post_batch(payload)
        self.assertEqual(result['data']['quantity_kg'], '88.000')
        self.assertNotIn('rate', frappe.as_json(result))

    def test_imported_and_individual_output_constrain_batch_allowance(self):
        payload = self.prepare(target='100.000')
        with permissions.service_write():
            domain.insert('Knitting Event', company=fixtures.COMPANY, job=self.job,
                kind='migration_stock_initialization', request_key=frappe.generate_hash(),
                result=frappe.as_json({'programme_output': [{'programme_line': 'P1', 'quantity_kg': '10.000'}]}))
        self.call('produce', {'job': self.job, 'programme_line': 'P1', 'weights_kg': ['3.000'],
            'inputs': [{'lot': self.lot, 'quantity_kg': '3.000'}], 'loss_kg': '0'})
        with self.assertRaisesRegex(frappe.ValidationError, 'programme'):
            self.post_batch(payload)
        payload.update(quantity_kg='85.000', inputs=[{'lot': self.lot, 'quantity_kg': '87.000', 'units': '2'}])
        self.post_batch(payload)
        self.assertEqual(domain.programme_produced(frappe.get_doc('Knitting Job', self.job), 'P1'), Decimal('98'))

    def test_unused_batch_cancel_restores_custody_and_historical_reports(self):
        result = self.post_batch()
        self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'Wrong measured entry'})
        batch = frappe.get_doc('Knitting Fabric Batch', result['data']['batch'])
        self.assertEqual((batch.quantity_kg, batch.rolls, batch.state), ('0.000', '0', 'Cancelled'))
        self.assertEqual(domain.lot_balance(self.lot, self.job), Decimal('90'))
        self.assertEqual(domain.lot_units(self.lot, self.job), Decimal('2'))
        self.assertEqual(domain.balances(self.job)['produced_kg'], '0.000')
        for report in ('jobs', 'fabric', 'production'):
            reports.run(fixtures.COMPANY, report, {'job': self.job, 'mode': 'as_of'})
        flow = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'mode': 'period'})
        self.assertEqual(flow['summary']['quantity_kg'], '0.000')
        with self.assertRaises(frappe.ValidationError):
            self.call('review_batch', {'job': self.job, 'batch': batch.name, 'decision': 'Released', 'remarks': 'No'})

    def test_cancellation_period_and_as_of_keep_original_batch_timing(self):
        result = self.post_batch()
        cancellation = self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'Measured incorrectly'})
        frappe.db.set_value('Knitting Event', result['event'], 'occurred_at', '2026-11-05 09:00:00')
        frappe.db.set_value('Knitting Event', cancellation['event'], 'occurred_at', '2026-11-07 09:00:00')
        for day, quantity in (('2026-11-04', '0.000'), ('2026-11-05', '88.000'), ('2026-11-07', '0.000')):
            self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'to_date': day})['summary']['quantity_kg'], quantity)
        reversal = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'mode': 'period',
            'from_date': '2026-11-07', 'to_date': '2026-11-07'})
        self.assertEqual(reversal['summary']['quantity_kg'], '-88.000')
        self.assertEqual(reversal['rows'][0]['roll_count'], '-7')

    def test_machine_progress_reverses_only_in_dependency_order(self):
        payload = self.prepare()
        machine = self.machine()
        component = self.call('create_component', {'machine': machine, 'component_type': 'Needle', 'boundary_kg': '100'})['data']['component']
        plan = self.call('plan', {'job': self.job, 'programme_line': 'P1', 'machine': machine,
            'starts_at': '2026-11-18 08:00:00', 'ends_at': '2026-11-18 16:00:00', 'quantity_kg': '88'})['data']['plan']
        payload.update(machine=machine, quantity_kg='44', rolls='3', loss_kg='1', inputs=[{'lot': self.lot, 'quantity_kg': '45'}])
        first, last = self.post_batch(payload), self.post_batch(payload)
        with self.assertRaises(frappe.ValidationError):
            self.call('cancel_event', {'job': self.job, 'event': first['event'], 'reason': 'Earlier run'})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 0)
        for result in (last, first):
            self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'Reverse run'})
        self.assertEqual(frappe.db.get_value('Knitting Plan', plan, ['state', 'produced_kg']), ('Planned', '0.000'))
        self.assertEqual(frappe.db.get_value('Knitting Component', component, 'run_kg'), '0.000')
        self.assertEqual(domain.lot_balance(self.lot, self.job), Decimal('90'))

    def test_reviewed_or_delivered_batch_cannot_cancel_even_after_return(self):
        result = self.post_batch(); batch = result['data']['batch']
        self.call('review_batch', {'job': self.job, 'batch': batch, 'decision': 'Released', 'remarks': 'Checked'})
        with self.assertRaises(frappe.ValidationError):
            self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'No'})
        delivery = self.call('deliver_batch', {'job': self.job, 'batch': batch, 'quantity_kg': '21.300', 'rolls': '2'})
        invoice = self.call('invoice', {'job': self.job, 'deliveries': [delivery['event']]})
        stock = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job})
        self.assertEqual(stock['summary'], {'quantity_kg': '66.700', 'roll_count': '5'})
        self.call('credit_invoice', {'job': self.job, 'invoice_event': invoice['event'], 'quantity_kg': '21.300', 'reason': 'Return'})
        self.call('return_batch', {'job': self.job, 'batch': batch, 'delivery': delivery['event'],
            'quantity_kg': '21.300', 'rolls': '2', 'reason': 'Return'})
        with self.assertRaises(frappe.ValidationError):
            self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'No'})
        self.assertEqual(domain.balances(self.job)['fabric_kg'], '88.000')
        self.call('review_batch', {'job': self.job, 'batch': batch, 'decision': 'Released', 'remarks': 'Rechecked return'})
        redelivery = self.call('deliver_batch', {'job': self.job, 'batch': batch, 'quantity_kg': '88.000', 'rolls': '7'})
        self.call('invoice', {'job': self.job, 'deliveries': [redelivery['event']]})
        self.call('close_job', {'job': self.job})
        self.assertEqual(frappe.db.get_value('Knitting Job', self.job, 'status'), 'Completed')
        final = domain.balances(self.job)
        self.assertTrue(all(final[k] == '0.000' for k in ('yarn_kg', 'fabric_kg', 'unbilled_kg')))

    def test_batch_history_uses_event_snapshot_and_day_projection(self):
        result = self.post_batch()
        initial = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job})
        self.assertEqual(initial['summary'], {'quantity_kg': '88.000', 'roll_count': '7'})
        with permissions.service_write():
            doc = frappe.get_doc('Knitting Fabric Batch', result['data']['batch'])
            doc.quantity_kg = '1.000'; doc.save()
        self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': self.job})['summary'], initial['summary'])
        day = str(frappe.db.get_value('Knitting Event', result['event'], 'occurred_at'))[:10]
        events = api.register(fixtures.COMPANY, 'events', job=self.job, production_date=day)
        self.assertEqual([r.name for r in events['rows']], [result['event']])
        self.assertTrue(any(Decimal(r['quantity_kg']) >= 88 for r in api.overview(fixtures.COMPANY)['production']))
        self.assertEqual(reports.run(fixtures.COMPANY, 'production', {'job': self.job})['summary']['quantity_kg'], '88.000')

    def test_new_batch_fabric_filters_keep_proved_production_dimensions(self):
        payload = self.prepare()
        machine = self.machine()
        self.post_batch({**payload, 'machine': machine})
        for key, value in {'machine': machine, 'operator': 'Administrator', 'shift': 'A',
                'fabric': 'Single jersey', 'dia': '30'}.items():
            with self.subTest(dimension=key):
                self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, key: value})['summary']['quantity_kg'], '88.000')

    def test_numeric_roll_count_remains_a_count_in_production_report(self):
        self.post_batch({**self.prepare(), 'rolls': 7})
        rows = reports.run(fixtures.COMPANY, 'production', {'job': self.job})['rows']
        self.assertEqual(rows[0]['roll_count'], '7')

    def test_job_picker_provides_ownership_for_batch_form_without_preselected_job(self):
        self.prepare()
        row = next(r for r in api.lookup(fixtures.COMPANY, 'Job', self.job)['rows'] if r.name == self.job)
        self.assertEqual(row.get('material_mode'), 'Customer')

    def test_guided_batch_cohorts_use_full_authorized_job_not_first_page(self):
        result = self.post_batch()
        with permissions.service_write():
            for i in range(103):
                domain.insert('Knitting Fabric Batch', company=fixtures.COMPANY, job=self.job, programme_line='P1',
                    quantity_kg='1.000', rolls='0', state='Released' if i == 102 else 'On Hold',
                    source_record=f'SYNTHETIC-CAPTURE-{i}', captured_at='2026-11-01 09:00:00')
        snapshot = api.snapshot(fixtures.COMPANY, self.job)
        workflow = snapshot['jobs'][0]['workflow']
        self.assertEqual(workflow['batch_inspection'], {'count': 1, 'only': result['data']['batch']})
        self.assertEqual(workflow['batch_held']['count'], 102)
        self.assertEqual(workflow['batch_released']['count'], 1)
        self.assertIsNotNone(workflow['batch_released']['only'])
        self.assertEqual(len(snapshot['batches']), 100)
        # A denied batch cannot become a falsely unique visible next action.
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid',
            'allow': 'Knitting Fabric Batch', 'for_value': result['data']['batch'], 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            api.snapshot(fixtures.COMPANY, self.job)


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(BatchProductionTests, name, None)
