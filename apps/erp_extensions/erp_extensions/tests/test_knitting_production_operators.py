"""Synthetic original-employee attribution, independent of the signing account."""
from unittest.mock import patch

import frappe

from erp_extensions.knitting import api, domain, permissions, reports
from erp_extensions.migration import api as history, service
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests import test_migration_contracts as contracts_fixtures


class ProductionOperatorTests(fixtures.KnittingTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        from erp_extensions.migration.install import install
        install()
        frappe.db.commit()

    def prepare(self):
        self.fixtures()
        other = [r.name for r in frappe.get_all('Company', fields=['name']) if r.name != fixtures.COMPANY][:3]
        contract = contracts_fixtures.HistoricalContractTests()
        values = contract.scope()
        values.update(source_instance='synthetic-operators-' + frappe.generate_hash(),
            company_bindings={str(i+1): company for i, company in enumerate([fixtures.COMPANY, *other])},
            allowed_users=['Administrator', 'knit-operator@example.invalid', 'knit-accountant@example.invalid'])
        self.scope = service.create_scope(values)
        self.person = self.employee('1', 'Synthetic weaver')
        self.lot = self.receive('90.000')
        return {'job': self.job, 'programme_line': 'P1', 'quantity_kg': '88.000', 'rolls': '7',
            'inputs': [{'lot': self.lot, 'quantity_kg': '90.000', 'units': '2'}],
            'loss_kg': '2.000', 'warehouse': self.warehouse, 'shift': 'A', 'production_operator': self.person}

    def employee(self, native_id, label, **changes):
        value = contracts_fixtures.HistoricalContractTests().record(namespace='masters.employee', family='master',
            native_id=native_id, source_company_id=None, source_book=None, shared_reference=True,
            business_data={'fields': {'description': label},
                'original_business': {'header': {'id': native_id, 'name': label}}})
        return service.store_record(self.scope, {**value, **changes})['name']

    def test_selected_person_is_distinct_from_signer_and_reported_by_identity(self):
        payload = self.prepare()
        choice = api.lookup(fixtures.COMPANY, 'ProductionOperator', query='weaver', job=self.job)['rows']
        self.assertEqual(choice, [{'name': self.person, 'title': 'Synthetic weaver'}])
        frappe.set_user('knit-operator@example.invalid')
        posted = self.call('produce_batch', payload)
        self.assertEqual(posted['data']['production_operator_record'], self.person)
        self.assertEqual(posted['data']['production_operator_label'], 'Synthetic weaver')
        self.assertEqual(posted['data']['batch_snapshot']['operator'], 'knit-operator@example.invalid')
        frappe.set_user('Administrator')
        result = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'production_operator': self.person})
        self.assertEqual(result['summary']['quantity_kg'], '88.000')
        self.assertEqual(result['rows'][0]['operator'], 'knit-operator@example.invalid')
        self.assertEqual(result['rows'][0]['production_operator_record'], self.person)
        grouped = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'group_by': 'production_operator'})
        self.assertEqual(grouped['rows'][0]['production_operator'], self.person)
        self.assertEqual(grouped['rows'][0]['production_operator_label'], 'Synthetic weaver')

    def test_same_labels_remain_distinct_and_literal_query_does_not_expand_wildcards(self):
        self.prepare()
        second = self.employee('2', 'Synthetic weaver')
        choices = api.lookup(fixtures.COMPANY, 'ProductionOperator', query='weaver')['rows']
        self.assertEqual({r['name'] for r in choices}, {self.person, second})
        self.assertEqual(api.lookup(fixtures.COMPANY, 'ProductionOperator', query='%')['rows'], [])

    def test_wrong_namespace_invalid_identity_and_corrupt_hash_cannot_post(self):
        payload = self.prepare()
        wrong = self.employee('2', 'Wrong namespace', namespace='masters.machine')
        mismatch = self.employee('3', 'Bad identity', business_data={'original_business': {'header': {'id': '4', 'name': 'Bad identity'}}})
        for person in (wrong, mismatch, 'missing-record', {'name': self.person}):
            with self.subTest(person=person), self.assertRaises((frappe.ValidationError, frappe.PermissionError)):
                self.call('produce_batch', {**payload, 'production_operator': person})
        frappe.db.set_value(service.RECORD, self.person, 'data_sha256', '0' * 64)
        with self.assertRaises((frappe.ValidationError, frappe.PermissionError)):
            self.call('produce_batch', payload)
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))

    def test_revoked_scope_blocks_post_replay_register_and_reports_even_for_administrator(self):
        payload = self.prepare()
        modified = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        posted = self.call('produce_batch', payload, 'person-replay-key', modified)
        with patch.object(history, '_member', return_value=False):
            with self.assertRaises(frappe.PermissionError):
                self.call('produce_batch', payload, 'person-replay-key', modified)
            with self.assertRaises(frappe.PermissionError):
                reports.run(fixtures.COMPANY, 'production', {'job': self.job})
            # Frappe itself grants Administrator unconditional generic access; app scopes remain explicit.
            self.assertFalse(permissions.source_scope(frappe.get_doc('Knitting Event', posted['event'])))
            self.assertFalse(permissions.source_scope(frappe.get_doc('Knitting Fabric Batch', posted['data']['batch'])))
            self.assertEqual(api.register(fixtures.COMPANY, 'batches', job=self.job)['rows'], [])

    def test_reversal_keeps_original_person_and_signer_separate_from_correcting_actor(self):
        payload = self.prepare()
        frappe.set_user('knit-operator@example.invalid')
        posted = self.call('produce_batch', payload)
        frappe.set_user('Administrator')
        corrected = self.call('cancel_event', {'job': self.job, 'event': posted['event'], 'reason': 'Wrong synthetic entry'})
        frappe.db.set_value('Knitting Event', posted['event'], 'occurred_at', '2026-11-05 09:00:00')
        frappe.db.set_value('Knitting Event', corrected['event'], 'occurred_at', '2026-11-07 09:00:00')
        report = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'mode': 'period',
            'from_date': '2026-11-07', 'to_date': '2026-11-07', 'production_operator': self.person})
        self.assertEqual(report['summary']['quantity_kg'], '-88.000')
        self.assertEqual(report['rows'][0]['production_operator_label'], 'Synthetic weaver')
        self.assertEqual(report['rows'][0]['operator'], 'knit-operator@example.invalid')
        activity = reports.run(fixtures.COMPANY, 'activity', {'job': self.job, 'mode': 'period',
            'from_date': '2026-11-07', 'to_date': '2026-11-07'})
        self.assertEqual(activity['rows'][0]['operator'], 'Administrator')

    def test_client_cannot_inject_authoritative_person_fields(self):
        payload = self.prepare()
        payload.pop('production_operator')
        for fields in ({'production_operator_label': 'Invented person'}, {'production_operator_number': 'Invented number'},
                {'production_operator_record': self.person, 'production_operator_label': 'Synthetic weaver'},
                {'batch_snapshot': {'production_operator_record': self.person, 'production_operator_label': 'Synthetic weaver'}}):
            with self.subTest(fields=fields), self.assertRaises(frappe.ValidationError):
                self.call('produce_batch', {**payload, **fields})
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))

    def test_case_variant_namespace_and_foreign_scope_identity_are_not_operator_authority(self):
        from erp_extensions.knitting import operators
        payload = self.prepare()
        wrong_case = self.employee('2', 'Case variant', namespace='MASTERS.EMPLOYEE')
        with self.assertRaises(frappe.PermissionError):
            self.call('produce_batch', {**payload, 'production_operator': wrong_case})
        # A different immutable scope's row cannot become local merely by changing its SQL index.
        values = service.get_scope(self.scope)
        values.pop('name')
        values['source_instance'] = 'foreign-operators-' + frappe.generate_hash()
        foreign_scope = service.create_scope(values)
        old_scope = self.scope
        self.scope = foreign_scope
        foreign = self.employee('3', 'Foreign person')
        self.scope = old_scope
        frappe.db.set_value(service.RECORD, foreign, 'source_scope', old_scope)
        with patch.object(operators, '_scope', return_value=service.get_scope(old_scope)), self.assertRaises(frappe.PermissionError):
            operators.resolve(fixtures.COMPANY, foreign)

    def test_malformed_original_header_is_rejected_without_storage_effects(self):
        payload = self.prepare()
        malformed = self.employee('2', 'Malformed', business_data={'original_business': {'header': []}})
        with self.assertRaises((frappe.ValidationError, frappe.PermissionError)):
            self.call('produce_batch', {**payload, 'production_operator': malformed})
        with self.assertRaises((frappe.ValidationError, frappe.PermissionError)):
            api.lookup(fixtures.COMPANY, 'ProductionOperator')
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))

    def test_old_payload_only_label_is_not_reported_as_verified_attribution(self):
        payload = self.prepare()
        payload.pop('production_operator')
        posted = self.call('produce_batch', payload)
        frappe.db.set_value('Knitting Event', posted['event'], 'payload', frappe.as_json(
            {**payload, 'production_operator_label': 'Unverified old label'}))
        report = reports.run(fixtures.COMPANY, 'production', {'job': self.job})
        self.assertIsNone(report['rows'][0]['production_operator_record'])
        self.assertIsNone(report['rows'][0]['production_operator_label'])
        grouped = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'group_by': 'production_operator'})
        self.assertEqual(grouped['rows'][0]['production_operator_label'], 'Unrecorded')

    def test_saved_employee_numbers_distinguish_equal_names_in_picker_and_reports(self):
        payload = self.prepare()
        person = self.employee('2', 'Synthetic weaver', business_data={'original_business': {
            'header': {'id': '2', 'name': 'Synthetic weaver', 'emp_no': '023'}}})
        choices = api.lookup(fixtures.COMPANY, 'ProductionOperator', query='weaver')['rows']
        self.assertEqual(next(r for r in choices if r['name'] == person)['employee_number'], '023')
        posted = self.call('produce_batch', {**payload, 'production_operator': person})
        self.assertEqual(posted['data']['production_operator_number'], '023')
        self.assertEqual(posted['data']['batch_snapshot']['production_operator_number'], '023')
        report = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'group_by': 'production_operator'})
        self.assertEqual(report['rows'][0]['production_operator_number'], '023')
        self.assertEqual(api.lookup(fixtures.COMPANY, 'ProductionOperator', query='023')['rows'][0]['name'], person)
        event = frappe.get_doc('Knitting Event', posted['event'])
        changed = frappe.parse_json(event.result)
        changed['production_operator_number'] = '24'
        event.result = frappe.as_json(changed)
        self.assertFalse(permissions.source_scope(event))
