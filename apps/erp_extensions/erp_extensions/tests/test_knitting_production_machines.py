"""Original machine attribution; synthetic native-test.localhost writes only."""
import copy
from unittest.mock import patch

import frappe

from erp_extensions.knitting import api, domain, permissions
from erp_extensions.knitting import machines
from erp_extensions.migration import api as history, service
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_knitting_production_operators import ProductionOperatorTests
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests


class ProductionMachineTests(ProductionOperatorTests):
    def machine_record(self, native_id='7', label='Synthetic circular machine', code='007', **changes):
        value = HistoricalContractTests().record(namespace='knitpack.machine',
            family='master', native_id=native_id, source_company_id=None, source_book=None, shared_reference=True,
            business_data={'original_business': {'header': {'id': native_id, 'mc_name': label, 'mc_code': code,
                'dia': '30', 'gauge': '1,2', 'capacity': ''}}})
        return service.store_record(self.scope, {**value, **changes})['name']

    def machine_payload(self):
        payload = self.prepare()
        payload.pop('production_operator')
        self.original_machine = self.machine_record()
        return {**payload, 'production_machine': self.original_machine}

    def test_machine_picker_and_measured_result_preserve_identity_name_and_code(self):
        payload = self.machine_payload()
        choices = api.lookup(fixtures.COMPANY, 'ProductionMachine', query='007', job=self.job)['rows']
        self.assertEqual(choices, [{'name': self.original_machine, 'title': 'Synthetic circular machine', 'machine_code': '007'}])
        before = {doctype: frappe.db.count(doctype) for doctype in ('Knitting Machine', 'Workstation', 'Knitting Component')}
        frappe.set_user('knit-operator@example.invalid')
        posted = self.call('produce_batch', {**payload, 'production_operator': self.person})
        result = posted['data']
        for value in (result, result['batch_snapshot']):
            self.assertEqual(value['production_machine_record'], self.original_machine)
            self.assertEqual(value['production_machine_label'], 'Synthetic circular machine')
            self.assertEqual(value['production_machine_code'], '007')
        self.assertIsNone(result['batch_snapshot']['machine'])
        self.assertEqual(result['batch_snapshot']['operator'], 'knit-operator@example.invalid')
        self.assertEqual(result['production_operator_record'], self.person)
        frappe.set_user('Administrator')
        self.assertEqual(before, {doctype: frappe.db.count(doctype) for doctype in before})

    def test_duplicate_codes_remain_distinct_and_search_is_literal(self):
        self.machine_payload()
        second = self.machine_record('8', 'Other circular machine', '007')
        choices = api.lookup(fixtures.COMPANY, 'ProductionMachine', query='007')['rows']
        self.assertEqual({row['name'] for row in choices}, {self.original_machine, second})
        self.assertEqual(api.lookup(fixtures.COMPANY, 'ProductionMachine', query='%')['rows'], [])
        self.assertEqual(api.lookup(fixtures.COMPANY, 'ProductionMachine', query='circular')['rows'], choices)

    def test_individual_roll_and_bulk_entries_keep_original_machine_separate(self):
        payload = self.machine_payload()
        second = self.machine_record('8', 'Other circular machine', '008')
        entries = []
        for token in (self.original_machine, second):
            entries.append({'programme_line': 'P1', 'weights_kg': ['44.000'], 'loss_kg': '1.000',
                'production_machine': token, 'inputs': [{'lot': self.lot, 'quantity_kg': '45.000', 'units': '1'}]})
        posted = self.call('produce_bulk', {'job': self.job, 'entries': entries})
        self.assertEqual([row['production_machine_record'] for row in posted['data']['entries']],
            [self.original_machine, second])
        self.assertEqual([row['production_machine_code'] for row in posted['data']['entries']], ['007', '008'])
        for roll in posted['data']['rolls']:
            self.assertIsNone(frappe.db.get_value('Knitting Roll', roll, 'machine'))
            self.assertNotIn('production_machine', frappe.db.get_value('Knitting Roll', roll, 'specification'))

    def test_single_individual_roll_result_and_read_guard(self):
        payload = self.machine_payload()
        payload.pop('quantity_kg');payload.pop('rolls')
        posted = self.call('produce', {**payload, 'weights_kg': ['88.000']})
        self.assertEqual(posted['data']['production_machine_record'], self.original_machine)
        roll = frappe.get_doc('Knitting Roll', posted['data']['rolls'][0])
        self.assertTrue(permissions.source_scope(roll))
        with patch.object(history, '_member', return_value=False):
            self.assertFalse(permissions.source_scope(roll))
            with self.assertRaises(frappe.PermissionError):
                self.call('cancel_event', {'job': self.job, 'event': posted['event'], 'reason': 'Revoked original machine'})

    def test_atomic_rows_keep_each_machine_and_replay_scope_for_ordinary_staff(self):
        payload = self.machine_payload()
        second_machine = self.machine_record('8', 'Other circular machine', '008')
        line = domain.json_value(frappe.db.get_value('Knitting Job', self.job, 'programme'))
        second_job = self.call('create_job', {'customer': self.customer, 'target_kg': '88.000',
            'material_mode': 'Customer', 'programme': line, 'rate': '100'})['data']['job']
        first_job = self.job;self.job = second_job
        second_lot = self.receive('90.000');self.job = first_job
        rows = []
        for job, lot, token in ((first_job, self.lot, self.original_machine), (second_job, second_lot, second_machine)):
            rows.append({'job': job, 'modified': str(frappe.db.get_value('Knitting Job', job, 'modified')),
                'programme_line': 'P1', 'quantity_kg': '88.000', 'rolls': '7', 'loss_kg': '2.000',
                'inputs': [{'lot': lot, 'quantity_kg': '90.000', 'units': '2'}], 'production_machine': token})
        frappe.set_user('knit-operator@example.invalid')
        request = 'synthetic-machines-parent'
        posted = self.call('produce_batches', {'entries': rows}, request)
        self.assertEqual([row['result']['production_machine_record'] for row in posted['data']['children']],
            [self.original_machine, second_machine])
        self.assertEqual(self.call('produce_batches', {'entries': rows}, request), posted)
        self.assertEqual(api.command_status(fixtures.COMPANY, request), posted)
        with patch.object(history, '_member', return_value=False):
            with self.assertRaises(frappe.PermissionError):
                api.command_status(fixtures.COMPANY, request)

    def test_native_and_original_machine_cannot_be_selected_together(self):
        payload = self.machine_payload()
        machine = self.machine()
        with self.assertRaises(frappe.ValidationError):
            self.call('produce_batch', {**payload, 'machine': machine})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_spoofed_output_fields_and_unsupported_bulk_header_are_rejected(self):
        payload = self.machine_payload()
        for field in ('production_machine_record', 'production_machine_label', 'production_machine_code'):
            with self.subTest(field=field), self.assertRaises(frappe.ValidationError):
                self.call('produce_batch', {**payload, field: 'Invented value'})
        with self.assertRaises(frappe.ValidationError):
            self.call('produce_bulk', {'job': self.job, 'production_machine': self.original_machine,
                'entries': [{'programme_line': 'P1', 'weights_kg': ['88.000'], 'loss_kg': '2.000',
                    'inputs': [{'lot': self.lot, 'quantity_kg': '90.000', 'units': '2'}]}]})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_wrong_namespace_header_and_hash_fail_without_storage_effects(self):
        payload = self.machine_payload()
        wrong = self.machine_record('8', namespace='KNITPACK.MACHINE')
        bad = self.machine_record('9', business_data={'original_business': {'header': {'id': '10', 'mc_name': 'Mismatch'}}})
        for token in (wrong, bad, 'missing-record', False, [], {'name': self.original_machine}):
            with self.subTest(token=token), self.assertRaises((frappe.PermissionError, frappe.ValidationError)):
                self.call('produce_batch', {**payload, 'production_machine': token})
        frappe.db.set_value(service.RECORD, self.original_machine, 'data_sha256', '0' * 64)
        with self.assertRaises((frappe.PermissionError, frappe.ValidationError)):
            self.call('produce_batch', payload)
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_scope_revocation_denies_machine_receipts_and_batch_reads_even_for_admin(self):
        payload = self.machine_payload()
        modified = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        posted = self.call('produce_batch', payload, 'synthetic-machine-replay', modified)
        batch = frappe.get_doc('Knitting Fabric Batch', posted['data']['batch'])
        with patch.object(history, '_member', return_value=False):
            with self.assertRaises(frappe.PermissionError):
                self.call('produce_batch', payload, 'synthetic-machine-replay', modified)
            self.assertFalse(permissions.source_scope(batch))

    def test_subcontract_receipt_does_not_infer_factory_machine_attribution(self):
        payload = self.machine_payload()
        subcontract = self.call('create_subcontract', {'job': self.job, 'supplier': self.supplier(),
            'target_kg': '88.000', 'rate': '10.00'})['data']['subcontract']
        self.call('subcontract_issue', {'job': self.job, 'subcontract': subcontract, 'lot': self.lot,
            'quantity_kg': '90.000'})
        payload.pop('quantity_kg');payload.pop('rolls')
        with self.assertRaises(frappe.ValidationError):
            self.call('subcontract_receive', {**payload, 'subcontract': subcontract, 'weights_kg': ['88.000']})
        self.assertEqual(domain.lot_balance(self.lot, self.job, 'SC:' + subcontract), 90)

    def test_revoked_machine_blocks_admin_batch_review_before_state_change(self):
        posted = self.call('produce_batch', self.machine_payload())
        batch = posted['data']['batch']
        with patch.object(history, '_member', return_value=False):
            with self.assertRaises(frappe.PermissionError):
                self.call('review_batch', {'job': self.job, 'batch': batch,
                    'decision': 'Released', 'remarks': 'Revoked original machine access'})
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', batch, 'state'), 'Awaiting review')

    def test_foreign_scope_and_reindexed_identity_cannot_authorize_machine(self):
        payload = self.machine_payload()
        scope = service.get_scope(self.scope)
        other_scope = service.create_scope({key: value for key, value in scope.items() if key != 'name'} |
            {'source_instance': 'synthetic-foreign-machine-' + frappe.generate_hash(),
             'allowed_users': ['knit-accountant@example.invalid']})
        record = HistoricalContractTests().record(namespace='knitpack.machine', family='master', native_id='8',
            source_company_id=None, source_book=None, shared_reference=True,
            business_data={'original_business': {'header': {'id': '8', 'mc_name': 'Foreign machine', 'mc_code': '008'}}})
        accountant = frappe.get_doc('User', 'knit-accountant@example.invalid')
        had_manager = any(role.role == 'System Manager' for role in accountant.roles)
        if not had_manager:
            accountant.add_roles('System Manager')
        try:
            frappe.set_user(accountant.name)
            foreign = service.store_record(other_scope, record)['name']
        finally:
            frappe.set_user('Administrator')
            if not had_manager:
                accountant.remove_roles('System Manager')
            frappe.clear_cache(user=accountant.name)
        frappe.db.set_value(service.RECORD, foreign, 'source_scope', self.scope)
        with self.assertRaises(frappe.PermissionError):
            self.call('produce_batch', {**payload, 'production_machine': foreign})
        frappe.db.set_value(service.RECORD, self.original_machine, 'native_id', '999')
        with self.assertRaises(frappe.PermissionError):
            self.call('produce_batch', payload)
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_malformed_header_and_tampered_saved_machine_metadata_fail_closed(self):
        payload = self.machine_payload()
        malformed = self.machine_record('8', business_data={'original_business': {'header': []}})
        with self.assertRaises(frappe.PermissionError):
            self.call('produce_batch', {**payload, 'production_machine': malformed})
        posted = self.call('produce_batch', payload)
        original = domain.json_value(frappe.db.get_value('Knitting Event', posted['event'], 'result'))
        for location in ('result', 'snapshot'):
            changed = copy.deepcopy(original)
            target = changed if location == 'result' else changed['batch_snapshot']
            target['production_machine_code'] = 'Invented code'
            frappe.db.set_value('Knitting Event', posted['event'], 'result', frappe.as_json(changed))
            with self.subTest(location=location):
                self.assertFalse(permissions.source_scope(frappe.get_doc('Knitting Event', posted['event'])))

    def test_zero_and_unrecorded_codes_preserve_identity_without_invented_values(self):
        self.machine_payload()
        zero = self.machine_record('8', 'Zero code machine', '0')
        missing = self.machine_record('9', 'Unrecorded code machine', None)
        self.assertEqual(machines.resolve(fixtures.COMPANY, zero)['production_machine_code'], '0')
        self.assertNotIn('production_machine_code', machines.resolve(fixtures.COMPANY, missing))
        rows = api.lookup(fixtures.COMPANY, 'ProductionMachine')['rows']
        self.assertEqual(next(row for row in rows if row['name'] == zero)['machine_code'], '0')
        self.assertNotIn('machine_code', next(row for row in rows if row['name'] == missing))

    def test_empty_optional_machine_does_not_require_original_scope(self):
        payload = self.machine_payload()
        with patch.object(history, '_member', return_value=False):
            posted = self.call('produce_batch', {**payload, 'production_machine': ''})
        self.assertNotIn('production_machine_record', posted['data'])
        self.assertNotIn('production_machine_record', posted['data']['batch_snapshot'])


for cls in (fixtures.KnittingTests, ProductionOperatorTests):
    for name in vars(cls):
        if name.startswith('test_'):
            setattr(ProductionMachineTests, name, None)
