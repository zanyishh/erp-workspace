"""Original employees on individual and bulk production; synthetic native-test only."""
from unittest.mock import patch

import frappe

from erp_extensions.knitting import domain, permissions
from erp_extensions.migration import api as history
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_knitting_production_operators import ProductionOperatorTests


class ProductionRollOperatorTests(ProductionOperatorTests):
    def person_reference(self, native_id='2', number='023'):
        return self.employee(native_id, 'Synthetic weaver', business_data={
            'original_business': {'header': {'id': native_id, 'name': 'Synthetic weaver', 'emp_no': number}}})

    def roll_payload(self):
        payload = self.prepare()
        payload.pop('quantity_kg');payload.pop('rolls')
        self.recorded_person = self.person_reference()
        return {**payload, 'production_operator': self.recorded_person, 'weights_kg': ['88.000']}

    def test_individual_result_preserves_original_employee_number_and_signer(self):
        payload = self.roll_payload()
        frappe.set_user('knit-operator@example.invalid')
        posted = self.call('produce', payload)
        self.assertEqual(posted['data']['production_operator_record'], self.recorded_person)
        self.assertEqual(posted['data']['production_operator_label'], 'Synthetic weaver')
        self.assertEqual(posted['data']['production_operator_number'], '023')
        roll = frappe.get_doc('Knitting Roll', posted['data']['rolls'][0])
        self.assertEqual(roll.operator, 'knit-operator@example.invalid')
        self.assertNotIn('production_operator', roll.specification)

    def test_bulk_rows_keep_distinct_equal_name_people_by_exact_source_identity(self):
        self.roll_payload()
        second = self.person_reference('3', '024')
        entries = [{'programme_line': 'P1', 'weights_kg': ['44.000'], 'loss_kg': '1.000',
            'inputs': [{'lot': self.lot, 'quantity_kg': '45.000', 'units': '1'}],
            'production_operator': person} for person in (self.recorded_person, second)]
        posted = self.call('produce_bulk', {'job': self.job, 'entries': entries})
        self.assertEqual([entry['production_operator_record'] for entry in posted['data']['entries']],
            [self.recorded_person, second])
        self.assertEqual([entry['production_operator_number'] for entry in posted['data']['entries']], ['023', '024'])

    def test_invalid_original_employee_is_checked_before_material_effects(self):
        payload = self.roll_payload()
        with patch.object(domain, 'ledger', side_effect=AssertionError('Material effects began before attribution validation')):
            with self.assertRaises(frappe.PermissionError):
                self.call('produce', {**payload, 'production_operator': 'missing-original-person'})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_individual_output_metadata_cannot_be_supplied_by_client(self):
        payload = self.roll_payload()
        for field in ('production_operator_record', 'production_operator_label', 'production_operator_number'):
            with self.subTest(field=field), self.assertRaises(frappe.ValidationError):
                self.call('produce', {**payload, field: 'Invented value'})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_bulk_employee_is_selected_per_row_not_ignored_on_parent(self):
        payload = self.roll_payload()
        entry = {key: value for key, value in payload.items() if key not in ('job', 'production_operator')}
        for extra in ({'production_operator': self.recorded_person}, {'production_operator_label': 'Invented name'},
                {'production_operator_number': '999'}, {'production_operator_record': self.recorded_person}):
            with self.subTest(extra=extra), self.assertRaises(frappe.ValidationError):
                self.call('produce_bulk', {'job': self.job, 'entries': [entry], **extra})
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_revoked_employee_blocks_admin_roll_quality_before_state_change(self):
        posted = self.call('produce', self.roll_payload())
        roll = posted['data']['rolls'][0]
        with patch.object(history, '_member', return_value=False):
            self.assertFalse(permissions.source_scope(frappe.get_doc('Knitting Roll', roll)))
            with self.assertRaises(frappe.PermissionError):
                self.call('quality', {'job': self.job, 'roll': roll, 'decision': 'Released', 'remarks': 'Revoked original person'})
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'state'), 'Awaiting QC')

    def test_subcontract_receipt_does_not_infer_factory_employee_attribution(self):
        payload = self.roll_payload()
        subcontract = self.call('create_subcontract', {'job': self.job, 'supplier': self.supplier(),
            'target_kg': '88.000', 'rate': '10.00'})['data']['subcontract']
        self.call('subcontract_issue', {'job': self.job, 'subcontract': subcontract, 'lot': self.lot,
            'quantity_kg': '90.000'})
        with self.assertRaises(frappe.ValidationError):
            self.call('subcontract_receive', {**payload, 'subcontract': subcontract})
        self.assertEqual(domain.lot_balance(self.lot, self.job, 'SC:' + subcontract), 90)

    def test_empty_optional_employee_does_not_require_original_scope(self):
        payload = self.roll_payload()
        with patch.object(history, '_member', return_value=False):
            posted = self.call('produce', {**payload, 'production_operator': ''})
        self.assertNotIn('production_operator_record', posted['data'])


for cls in (fixtures.KnittingTests, ProductionOperatorTests):
    for name in vars(cls):
        if name.startswith('test_'):
            setattr(ProductionRollOperatorTests, name, None)
