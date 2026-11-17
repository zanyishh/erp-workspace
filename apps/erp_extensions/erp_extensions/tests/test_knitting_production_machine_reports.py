"""Original-machine report attribution; synthetic native-test.localhost data only."""
from unittest.mock import patch

import frappe

from erp_extensions.knitting import reports
from erp_extensions.migration import api as history, service
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests
from erp_extensions.tests import test_knitting as fixtures


class ProductionMachineReportTests(fixtures.KnittingTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        from erp_extensions.migration.install import install
        install()
        frappe.db.commit()

    def original_machine(self, native_id='1', label='Synthetic circular machine', code='023'):
        if not hasattr(self, 'machine_scope'):
            other = [r.name for r in frappe.get_all('Company', fields=['name']) if r.name != fixtures.COMPANY][:3]
            values = HistoricalContractTests().scope()
            values.update(source_instance='synthetic-machine-reports-' + frappe.generate_hash(),
                company_bindings={str(i + 1): company for i, company in enumerate([fixtures.COMPANY, *other])},
                allowed_users=['Administrator', 'knit-operator@example.invalid'])
            self.machine_scope = service.create_scope(values)
        value = HistoricalContractTests().record(namespace='knitpack.machine', family='master',
            native_id=native_id, source_company_id=None, source_book=None, shared_reference=True,
            business_data={'original_business': {'header': {'id': native_id, 'mc_name': label, 'mc_code': code}}})
        return service.store_record(self.machine_scope, value)['name']

    def production(self, **extra):
        signer = extra.pop('_signer', None)
        self.fixtures()
        lot = self.receive('90.000')
        payload = {'job': self.job, 'programme_line': 'P1', 'quantity_kg': '88.000', 'rolls': '7',
            'inputs': [{'lot': lot, 'quantity_kg': '90.000', 'units': '2'}], 'loss_kg': '2.000',
            'warehouse': self.warehouse, 'shift': 'A', **extra}
        if signer:
            frappe.set_user(signer)
        return payload, self.call('produce_batch', payload)

    def test_payload_only_machine_label_and_code_are_not_reported_as_verified(self):
        payload, posted = self.production()
        frappe.db.set_value('Knitting Event', posted['event'], 'payload', frappe.as_json({**payload,
            'production_machine_label': 'Unverified old machine', 'production_machine_code': '023'}))
        result = reports.run(fixtures.COMPANY, 'production', {'job': self.job})
        self.assertIn('production_machine_label', [column['key'] for column in result['columns']])
        self.assertIsNone(result['rows'][0]['production_machine_record'])
        self.assertIsNone(result['rows'][0]['production_machine_label'])
        self.assertIsNone(result['rows'][0]['production_machine_code'])
        grouped = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'group_by': 'production_machine'})
        self.assertEqual(grouped['rows'][0]['production_machine_label'], 'Unrecorded')
        self.assertIsNone(grouped['rows'][0]['production_machine_code'])
        self.assertEqual(grouped['rows'][0]['quantity_kg'], '88.000')


    def test_saved_machine_metadata_reaches_production_and_fabric_without_native_mapping(self):
        machine = self.original_machine()
        _, posted = self.production(production_machine=machine)
        for name in ('production', 'fabric'):
            with self.subTest(report=name):
                report = reports.run(fixtures.COMPANY, name, {'job': self.job})
                self.assertEqual(report['rows'][0].get('production_machine_record'), machine)
                self.assertEqual(report['rows'][0]['production_machine_label'], 'Synthetic circular machine')
                self.assertEqual(report['rows'][0]['production_machine_code'], '023')
                self.assertFalse(report['rows'][0]['machine'])
                self.assertEqual(report['summary']['quantity_kg'], '88.000')
        self.assertEqual(posted['data']['production_machine_record'], machine)

    def test_equal_labels_group_by_saved_identity_and_filter_before_count_page_and_total(self):
        first = self.original_machine()
        second = self.original_machine('2', code='024')
        self.fixtures()
        lot = self.receive('20.000')
        identities = [first] * 101 + [second] * 2
        for offset in range(0, len(identities), 50):
            modified = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
            entries = [{'job': self.job, 'modified': modified, 'programme_line': 'P1',
                'quantity_kg': '0.125', 'rolls': '0', 'inputs': [{'lot': lot, 'quantity_kg': '0.125'}],
                'production_machine': machine} for machine in identities[offset:offset + 50]]
            self.call('produce_batches', {'entries': entries})
        page = reports.run(fixtures.COMPANY, 'production', {'job': self.job,
            'production_machine': first, 'start': 100})
        self.assertEqual(page['row_count'], 101)
        self.assertEqual(len(page['rows']), 1)
        self.assertFalse(page['has_more'])
        self.assertEqual(page['summary']['quantity_kg'], '12.625')
        self.assertEqual(page['rows'][0]['production_machine_record'], first)
        for name in ('production', 'fabric'):
            with self.subTest(report=name):
                grouped = reports.run(fixtures.COMPANY, name, {'job': self.job, 'group_by': 'production_machine'})
                by_id = {r['production_machine']: r for r in grouped['rows']}
                self.assertEqual(set(by_id), {first, second})
                self.assertEqual(by_id[first]['quantity_kg'], '12.625')
                self.assertEqual(by_id[second]['quantity_kg'], '0.250')
                self.assertEqual(by_id[first]['production_machine_code'], '023')
                self.assertEqual(by_id[second]['production_machine_code'], '024')
                self.assertEqual(by_id[first]['production_machine_label'], by_id[second]['production_machine_label'])

    def test_individual_bulk_and_split_fabric_keep_each_original_machine_identity(self):
        first = self.original_machine()
        second = self.original_machine('2', code='024')
        self.fixtures()
        lot = self.receive('90.000')
        posted = self.call('produce_bulk', {'job': self.job, 'entries': [
            {'programme_line': 'P1', 'weights_kg': ['44.000'], 'loss_kg': '1.000',
                'production_machine': machine, 'inputs': [{'lot': lot, 'quantity_kg': '45.000', 'units': '1'}]}
            for machine in (first, second)]})
        grouped = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'group_by': 'production_machine'})
        self.assertEqual({r['production_machine']: r['quantity_kg'] for r in grouped['rows']},
            {first: '44.000', second: '44.000'})
        self.call('split_roll', {'job': self.job, 'roll': posted['data']['rolls'][0],
            'weights_kg': ['20.000', '24.000'], 'reason': 'Synthetic cutting'})
        fabric = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'group_by': 'production_machine'})
        self.assertEqual({r['production_machine']: r['quantity_kg'] for r in fabric['rows']},
            {first: '44.000', second: '44.000'})
        selected = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'production_machine': first})
        self.assertEqual(selected['row_count'], 2)
        self.assertEqual(selected['summary']['quantity_kg'], '44.000')
        self.assertEqual({r['production_machine_code'] for r in selected['rows']}, {'023'})

    def test_forged_single_roll_pointer_cannot_claim_another_machines_output(self):
        first = self.original_machine()
        second = self.original_machine('2', code='024')
        self.fixtures()
        lot = self.receive('90.000')
        productions = [self.call('produce', {'job': self.job, 'programme_line': 'P1',
            'weights_kg': ['44.000'], 'loss_kg': '1.000', 'production_machine': machine,
            'inputs': [{'lot': lot, 'quantity_kg': '45.000', 'units': '1'}]})
            for machine in (first, second)]
        valid = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'group_by': 'production_machine'})
        self.assertEqual({r['production_machine']: r['quantity_kg'] for r in valid['rows']},
            {first: '44.000', second: '44.000'})
        forged_roll = productions[0]['data']['rolls'][0]
        frappe.db.set_value('Knitting Roll', forged_roll, 'production', productions[1]['event'])
        report = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job})
        forged = next(r for r in report['rows'] if r['name'] == forged_roll)
        self.assertIsNone(forged['production_machine_record'])
        self.assertIsNone(forged['production_machine_label'])
        self.assertIsNone(forged['production_machine_code'])
        selected = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'production_machine': second})
        self.assertEqual(selected['row_count'], 1)
        self.assertEqual(selected['summary']['quantity_kg'], '44.000')

    def test_period_reversal_retains_machine_and_original_signer(self):
        machine = self.original_machine()
        _, posted = self.production(production_machine=machine, _signer='knit-operator@example.invalid')
        frappe.set_user('Administrator')
        corrected = self.call('cancel_event', {'job': self.job, 'event': posted['event'], 'reason': 'Wrong synthetic machine entry'})
        frappe.db.set_value('Knitting Event', posted['event'], 'occurred_at', '2026-11-05 09:00:00')
        frappe.db.set_value('Knitting Event', corrected['event'], 'occurred_at', '2026-11-07 09:00:00')
        report = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'mode': 'period',
            'from_date': '2026-11-07', 'to_date': '2026-11-07', 'production_machine': machine})
        self.assertEqual(report['summary']['quantity_kg'], '-88.000')
        self.assertEqual(report['rows'][0]['production_machine_label'], 'Synthetic circular machine')
        self.assertEqual(report['rows'][0]['production_machine_code'], '023')
        self.assertEqual(report['rows'][0]['operator'], 'knit-operator@example.invalid')
        grouped = reports.run(fixtures.COMPANY, 'production', {'job': self.job, 'mode': 'period',
            'from_date': '2026-11-07', 'to_date': '2026-11-07', 'group_by': 'production_machine'})
        self.assertEqual(grouped['rows'][0]['production_machine'], machine)
        self.assertEqual(grouped['rows'][0]['quantity_kg'], '-88.000')

    def test_revoked_original_scope_withholds_production_and_fabric_reports(self):
        machine = self.original_machine()
        self.production(production_machine=machine)
        with patch.object(history, '_member', return_value=False):
            for name in ('production', 'fabric'):
                with self.subTest(report=name), self.assertRaises(frappe.PermissionError):
                    reports.run(fixtures.COMPANY, name, {'job': self.job})


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(ProductionMachineReportTests, name, None)
