"""Atomic measured production rows; synthetic fixtures on native-test.localhost only."""
import copy
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import patch

import frappe

from erp_extensions.knitting import api, batches, domain, reports
from erp_extensions.migration import api as history, service
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests


class ProductionRowsTests(fixtures.KnittingTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        from erp_extensions.migration.install import install
        install()
        frappe.db.commit()

    def prepare(self):
        self.fixtures(target='10.000')
        self.first = self.job
        line = domain.json_value(frappe.db.get_value('Knitting Job', self.job, 'programme'))[0]
        other = {**line, 'id': 'P2', 'target_kg': '5.000'}
        self.call('revise_job', {'job': self.job, 'programme': [{**line, 'target_kg': '5.000'}, other],
            'reason': 'Synthetic two-size programme'})
        self.first_lot = self.receive('10.000')
        self.second = self.call('create_job', {'customer': self.customer, 'target_kg': '10.000',
            'material_mode': 'Customer', 'programme': [line], 'rate': '100'})['data']['job']
        self.job = self.second
        self.second_lot = self.receive('10.000')
        self.job = self.first
        versions = {name: str(frappe.db.get_value('Knitting Job', name, 'modified'))
            for name in (self.first, self.second)}
        self.entries = [
            {'job': self.first, 'modified': versions[self.first], 'programme_line': 'P1',
                'quantity_kg': '3.000', 'rolls': '2', 'inputs': [{'lot': self.first_lot, 'quantity_kg': '3.000'}]},
            {'job': self.first, 'modified': versions[self.first], 'programme_line': 'P2',
                'quantity_kg': '2.000', 'rolls': '3', 'inputs': [{'lot': self.first_lot, 'quantity_kg': '2.000'}]},
            {'job': self.second, 'modified': versions[self.second], 'programme_line': 'P1',
                'quantity_kg': '4.000', 'rolls': '0', 'inputs': [{'lot': self.second_lot, 'quantity_kg': '4.000'}]},
        ]
        return {'entries': self.entries}

    def post(self, payload, request=None):
        return self.call('produce_batches', payload, request)

    def assert_no_output(self):
        self.assertEqual(domain.lot_balance(self.first_lot, self.first), domain.Decimal('10.000'))
        self.assertEqual(domain.lot_balance(self.second_lot, self.second), domain.Decimal('10.000'))
        self.assertEqual(frappe.db.count('Knitting Fabric Batch', {'job': ['in', [self.first, self.second]]}), 0)
        self.assertEqual(frappe.db.count('Knitting Event', {'company': fixtures.COMPANY,
            'kind': ['in', ['produce_batch', 'produce_batches']]}), 0)

    def test_three_measured_rows_two_jobs_make_three_children_and_count_once(self):
        payload = self.prepare()
        before = {name: str(frappe.db.get_value('Knitting Job', name, 'modified')) for name in (self.first, self.second)}
        posted = self.post(payload)
        parent = frappe.get_doc('Knitting Event', posted['event'])
        self.assertIsNone(parent.job)
        self.assertNotIn('quantity_kg', posted['data'])
        self.assertEqual(len(posted['data']['children']), 3)
        self.assertEqual(frappe.db.count('Knitting Roll', {'job': ['in', [self.first, self.second]]}), 0)
        for child in posted['data']['children']:
            event = frappe.get_doc('Knitting Event', child['event'])
            result = domain.json_value(event.result)
            self.assertEqual(event.kind, 'produce_batch')
            self.assertEqual(result['batch'], child['batch'])
            self.assertEqual(result['batch_snapshot']['production'], event.name)
            self.assertEqual(str(event.occurred_at), str(parent.occurred_at))
        for name, wanted in ((self.first, '5.000'), (self.second, '4.000')):
            self.assertEqual(domain.balances(name)['produced_kg'], wanted)
            result = reports.run(fixtures.COMPANY, 'production', {'job': name})
            self.assertEqual(result['summary']['quantity_kg'], wanted)
            self.assertNotEqual(str(frappe.db.get_value('Knitting Job', name, 'modified')), before[name])
        self.assertEqual(reports.run(fixtures.COMPANY, 'production', {})['summary']['quantity_kg'], '9.000')

    def test_parent_replay_is_idempotent_and_changed_payload_conflicts(self):
        payload = self.prepare()
        first = self.post(payload, 'synthetic-rows-replay')
        self.assertEqual(self.post(payload, 'synthetic-rows-replay'), first)
        changed = copy.deepcopy(payload)
        changed['entries'][0]['rolls'] = '9'
        with self.assertRaises(frappe.ValidationError):
            self.post(changed, 'synthetic-rows-replay')
        self.assertEqual(frappe.db.count('Knitting Fabric Batch', {'job': ['in', [self.first, self.second]]}), 3)

    def test_last_row_quantity_failure_rolls_back_all_earlier_rows(self):
        payload = self.prepare()
        payload['entries'][-1]['inputs'][0]['quantity_kg'] = '3.000'
        with self.assertRaises(frappe.ValidationError):
            self.post(payload)
        self.assert_no_output()

    def test_joint_repeated_rows_cannot_overconsume_same_lot_or_programme(self):
        payload = self.prepare()
        payload['entries'][1] = {**copy.deepcopy(payload['entries'][0]), 'quantity_kg': '3.000'}
        with self.assertRaises(frappe.ValidationError):
            self.post(payload)
        self.assert_no_output()

    def test_joint_rows_cannot_overconsume_a_shared_lot(self):
        payload = self.prepare()
        lot = self.receive('4.000')
        for row in payload['entries'][:2]:
            row['inputs'][0]['lot'] = lot
            row['modified'] = str(frappe.db.get_value('Knitting Job', self.first, 'modified'))
        with self.assertRaises(frappe.ValidationError):
            self.post(payload)
        self.assertEqual(domain.lot_balance(lot, self.first), domain.Decimal('4.000'))
        self.assert_no_output()

    def test_all_job_versions_checked_before_any_child_production(self):
        payload = self.prepare()
        payload['entries'][-1]['modified'] = '2000-01-01 00:00:00'
        with patch.object(batches, 'produce', side_effect=AssertionError('Production began before all version checks')):
            with self.assertRaises(frappe.TimestampMismatchError):
                self.post(payload)
        self.assert_no_output()

    def test_repeated_job_requires_one_consistent_expected_version(self):
        payload = self.prepare()
        payload['entries'][1]['modified'] = '2000-01-01 00:00:00'
        with self.assertRaises((frappe.ValidationError, frappe.TimestampMismatchError)):
            self.post(payload)
        self.assert_no_output()

    def test_final_batch_storage_failure_rolls_back_first_children(self):
        payload = self.prepare()
        original, count = domain.insert, 0
        def insert(doctype, **values):
            nonlocal count
            if doctype == 'Knitting Fabric Batch':
                count += 1
                if count == 3:
                    raise RuntimeError('Synthetic storage fault on last row')
            return original(doctype, **values)
        with patch.object(domain, 'insert', side_effect=insert):
            with self.assertRaisesRegex(RuntimeError, 'last row'):
                self.post(payload)
        self.assert_no_output()

    def test_hidden_second_job_rejects_entire_post(self):
        payload = self.prepare()
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid',
            'allow': 'Knitting Job', 'for_value': self.first, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.post(payload)
        frappe.set_user('Administrator')
        self.assert_no_output()

    def test_cross_company_or_non_customer_job_cannot_be_coordinated(self):
        payload = self.prepare()
        frappe.db.set_value('Knitting Job', self.second, 'material_mode', 'Owned')
        with self.assertRaises(frappe.ValidationError):
            self.post(payload)
        self.assert_no_output()
        frappe.db.set_value('Knitting Job', self.second, 'material_mode', 'Customer')
        other = next(row.name for row in frappe.get_all('Company', fields=['name']) if row.name != fixtures.COMPANY)
        frappe.db.set_value('Knitting Job', self.second, 'company', other)
        with self.assertRaises(frappe.PermissionError):
            self.post(payload)
        self.assert_no_output()

    def test_row_and_payload_bounds_do_not_create_partial_receipts(self):
        self.prepare()
        for payload in ({'entries': []}, {'entries': self.entries * 17}, {'entries': [None]},
                {'entries': [{**self.entries[0], 'job': {'name': self.first}}]},
                {'entries': [{**self.entries[0], 'weights_kg': ['3.000']}]},
                {'entries': self.entries, 'job': self.first}):
            with self.subTest(payload=payload), self.assertRaises(frappe.ValidationError):
                self.post(payload)
        self.assert_no_output()

    def test_children_keep_existing_independent_correction_and_dependency_guard(self):
        payload = self.prepare()
        posted = self.post(payload)
        first, second = posted['data']['children'][:2]
        self.call('cancel_event', {'job': first['job'], 'event': first['event'], 'reason': 'Synthetic row correction'})
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', first['batch'], 'state'), 'Cancelled')
        self.call('review_batch', {'job': second['job'], 'batch': second['batch'],
            'decision': 'Released', 'remarks': 'Synthetic check'})
        with self.assertRaises(frappe.ValidationError):
            self.call('cancel_event', {'job': second['job'], 'event': second['event'], 'reason': 'After dependent review'})
        with self.assertRaises(frappe.ValidationError):
            self.call('cancel_event', {'job': first['job'], 'event': posted['event'], 'reason': 'No parent group undo'})

    def test_two_connections_preserve_last_balance_and_parent_replay(self):
        self.prepare()
        lot = self.receive('3.000')
        row = {**copy.deepcopy(self.entries[0]), 'quantity_kg': '1.000', 'rolls': '0',
            'modified': str(frappe.db.get_value('Knitting Job', self.first, 'modified')),
            'inputs': [{'lot': lot, 'quantity_kg': '1.000'}]}
        requests = ['rows-race-' + frappe.generate_hash(length=16) for _ in range(3)]
        parent_keys = [api.request_key(fixtures.COMPANY, request) for request in requests]
        jobs, lots = [self.first, self.second], [self.first_lot, self.second_lot, lot]
        frappe.db.commit()
        try:
            barrier = Barrier(2)
            def worker(request):
                frappe.init(site='native-test.localhost', sites_path='.')
                frappe.connect()
                frappe.set_user('Administrator')
                try:
                    frappe.db.get_value('Knitting Material Lot', lot, 'name')
                    barrier.wait(timeout=20)
                    result = api.command(fixtures.COMPANY, 'produce_batches', {'entries': [row]}, request)
                    frappe.db.commit()
                    return {'ok': result}
                except Exception as error:
                    frappe.db.rollback()
                    return {'error': type(error).__name__, 'message': str(error)}
                finally:
                    frappe.destroy()
            with ThreadPoolExecutor(max_workers=2) as pool:
                replay = list(pool.map(worker, [requests[0], requests[0]]))
            self.assertTrue(all('ok' in result for result in replay), replay)
            self.assertEqual(replay[0]['ok']['event'], replay[1]['ok']['event'])
            frappe.db.rollback()
            self.assertEqual(domain.lot_balance(lot, self.first), domain.Decimal('2.000'))
            row.update(quantity_kg='2.000', modified=str(frappe.db.get_value('Knitting Job', self.first, 'modified')),
                inputs=[{'lot': lot, 'quantity_kg': '2.000'}])
            barrier = Barrier(2)
            with ThreadPoolExecutor(max_workers=2) as pool:
                contested = list(pool.map(worker, requests[1:]))
            self.assertEqual(sum('ok' in result for result in contested), 1, contested)
            self.assertEqual(sum('error' in result for result in contested), 1, contested)
            frappe.db.rollback()
            self.assertEqual(domain.lot_balance(lot, self.first), domain.Decimal('0.000'))
            self.assertEqual(domain.balances(self.first)['produced_kg'], '3.000')
        finally:
            frappe.db.rollback()
            for doctype in ('Knitting QC', 'Knitting Roll', 'Knitting Fabric Batch', 'Knitting Plan',
                    'Knitting Ledger Entry', 'Knitting Event'):
                frappe.db.delete(doctype, {'job': ['in', jobs]})
            frappe.db.delete('Knitting Event', {'request_key': ['in', parent_keys]})
            frappe.db.delete('Knitting Job', {'name': ['in', jobs]})
            frappe.db.delete('Knitting Material Lot', {'name': ['in', lots]})
            for item in self.items.values():
                frappe.delete_doc('Item', item)
            frappe.delete_doc('Customer', self.customer)
            frappe.db.commit()

    def test_operational_staff_post_replay_and_status_scope_every_child_and_person(self):
        payload = self.prepare()
        contract = HistoricalContractTests()
        other = [row.name for row in frappe.get_all('Company', fields=['name']) if row.name != fixtures.COMPANY][:3]
        values = {**contract.scope(), 'source_instance': 'synthetic-row-person-' + frappe.generate_hash(),
            'company_bindings': {str(index + 1): company for index, company in enumerate([fixtures.COMPANY, *other])},
            'allowed_users': ['Administrator', 'knit-operator@example.invalid']}
        scope = service.create_scope(values)
        person = service.store_record(scope, contract.record(namespace='masters.employee', family='master',
            native_id='9', source_company_id=None, source_book=None, shared_reference=True,
            business_data={'original_business': {'header': {'id': '9', 'name': 'Synthetic row weaver'}}}))['name']
        for row in payload['entries']:
            row['production_operator'] = person
        frappe.set_user('knit-operator@example.invalid')
        request = 'rows-staff-replay-' + frappe.generate_hash(length=12)
        posted = self.post(payload, request)
        self.assertEqual(len(posted['data']['children']), 3)
        self.assertEqual(self.post(payload, request), posted)
        self.assertEqual(api.command_status(fixtures.COMPANY, request), posted)
        for child in posted['data']['children']:
            self.assertEqual(child['result']['production_operator_record'], person)
            self.assertEqual(child['result']['batch_snapshot']['operator'], 'knit-operator@example.invalid')
        with patch.object(history, '_member', return_value=False):
            with self.assertRaises(frappe.PermissionError):
                self.post(payload, request)
            with self.assertRaises(frappe.PermissionError):
                api.command_status(fixtures.COMPANY, request)
        frappe.set_user('Administrator')
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid',
            'allow': 'Knitting Job', 'for_value': self.first, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.post(payload, request)
        with self.assertRaises(frappe.PermissionError):
            api.command_status(fixtures.COMPANY, request)


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(ProductionRowsTests, name, None)
