"""Original people follow individual output identity; signed-in actors stay separate."""
import frappe

from erp_extensions.knitting import reports
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_knitting_production_operators import ProductionOperatorTests


class ProductionOperatorReportTests(ProductionOperatorTests):
    def numbered_person(self, native_id, number):
        return self.employee(native_id, 'Synthetic weaver', business_data={'original_business': {
            'header': {'id': native_id, 'name': 'Synthetic weaver', 'emp_no': number}}})

    def test_single_roll_reports_preserve_person_number_and_separate_signer(self):
        payload = self.prepare()
        person = self.numbered_person('2', '023')
        payload.pop('quantity_kg')
        payload.pop('rolls')
        frappe.set_user('knit-operator@example.invalid')
        self.call('produce', {**payload, 'weights_kg': ['88.000'], 'production_operator': person})
        frappe.set_user('Administrator')
        for name in ('production', 'fabric', 'rolls'):
            with self.subTest(report=name):
                result = reports.run(fixtures.COMPANY, name, {'job': self.job})
                self.assertIn('production_operator_label', [column['key'] for column in result['columns']])
                self.assertEqual(result['rows'][0].get('production_operator_record'), person)
                self.assertEqual(result['rows'][0]['production_operator_label'], 'Synthetic weaver')
                self.assertEqual(result['rows'][0]['production_operator_number'], '023')
                self.assertEqual(result['rows'][0]['operator'], 'knit-operator@example.invalid')
                self.assertEqual(result['summary']['quantity_kg'], '88.000')

    def test_same_programme_bulk_people_remain_distinct_through_split_and_filter(self):
        self.prepare()
        first = self.numbered_person('2', '023')
        second = self.numbered_person('3', '024')
        frappe.set_user('knit-operator@example.invalid')
        posted = self.call('produce_bulk', {'job': self.job, 'entries': [
            {'programme_line': 'P1', 'weights_kg': ['44.000'], 'loss_kg': '1.000',
                'production_operator': person,
                'inputs': [{'lot': self.lot, 'quantity_kg': '45.000', 'units': '1'}]}
            for person in (first, second)]})
        frappe.set_user('Administrator')
        self.call('split_roll', {'job': self.job, 'roll': posted['data']['rolls'][0],
            'weights_kg': ['20.000', '24.000'], 'reason': 'Synthetic cutting'})
        for name in ('production', 'fabric', 'rolls'):
            with self.subTest(report=name):
                result = reports.run(fixtures.COMPANY, name, {'job': self.job, 'group_by': 'production_operator'})
                by_id = {r['production_operator']: r for r in result['rows']}
                self.assertEqual(set(by_id), {first, second})
                quantity = 'weight_kg' if name == 'rolls' else 'quantity_kg'
                self.assertEqual(by_id[first][quantity], '44.000')
                self.assertEqual(by_id[second][quantity], '44.000')
                self.assertEqual(by_id[first]['production_operator_number'], '023')
                self.assertEqual(by_id[second]['production_operator_number'], '024')
                self.assertEqual(by_id[first]['production_operator_label'], by_id[second]['production_operator_label'])
        selected = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'production_operator': first})
        self.assertEqual(selected['row_count'], 2)
        self.assertEqual(selected['summary']['quantity_kg'], '44.000')
        self.assertEqual({r['operator'] for r in selected['rows']}, {'knit-operator@example.invalid'})
        self.assertEqual({r['production_operator_number'] for r in selected['rows']}, {'023'})


for cls in (fixtures.KnittingTests, ProductionOperatorTests):
    for name in vars(cls):
        if name.startswith('test_'):
            setattr(ProductionOperatorReportTests, name, None)
