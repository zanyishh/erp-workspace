"""Imported measurement compatibility; synthetic writes on native-test.localhost only."""
import copy

import frappe

from erp_extensions.knitting import domain, permissions
from erp_extensions.migration import contracts, service
from erp_extensions.migration.install import RECORD, SCOPE
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests
from erp_extensions.tests.test_migration_dimensions import SourceDimensionTests


class ImportedCompatibilityTests(SourceDimensionTests):
    def imported_fixture(self, selector='15'):
        self.original_fixture(selector)
        self.lines[0]['target_kg'] = '176.000'
        with permissions.service_write():
            job = frappe.get_doc('Knitting Job', self.job)
            job.programme, job.target_kg = frappe.as_json(self.lines), '176.000'
            job.save()
        return self.job

    def machine(self, dia='38', gauge='24'):
        return self.call('create_machine', {'title': 'Synthetic compatibility machine', 'dia': dia,
            'gauge': gauge, 'knit_type': 'Tubular', 'capacity_kg': '120.000'})['data']['machine']

    def plan_values(self, machine):
        return {'job': self.job, 'programme_line': 'P1', 'machine': machine, 'quantity_kg': '1.000',
            'starts_at': '2026-11-18 08:00:00', 'ends_at': '2026-11-18 16:00:00'}

    def production_values(self, lot, machine=None):
        return {'job': self.job, 'programme_line': 'P1', 'weights_kg': ['1.000'],
            'inputs': [{'lot': lot, 'quantity_kg': '1.000'}], **({'machine': machine} if machine else {})}

    def native_job(self, dia):
        line = {key: copy.deepcopy(value) for key, value in self.lines[0].items() if not key.startswith('source_')}
        line.update(dia=dia, target_kg='88.000')
        return self.call('create_job', {'customer': self.customer, 'target_kg': '88.000',
            'material_mode': 'Customer', 'programme': [line], 'rate': '100'})['data']['job']

    def move_roll(self, source, target, roll):
        return self.call('transfer_fabric', {'job': source, 'target_job': target,
            'target_modified': str(frappe.db.get_value('Knitting Job', target, 'modified')),
            'target_programme_line': 'P1', 'rolls': [roll], 'reason': 'Synthetic physical compatibility'})

    def test_plan_accepts_verified_physical_dia_not_saved_selector(self):
        self.imported_fixture()
        programme = frappe.db.get_value('Knitting Job', self.job, 'programme')
        result = self.call('plan', self.plan_values(self.machine()))
        self.assertEqual(frappe.db.get_value('Knitting Plan', result['data']['plan'], 'quantity_kg'), '1.000')
        self.assertEqual(frappe.db.get_value('Knitting Job', self.job, 'programme'), programme)

    def test_plan_rejects_machine_matching_only_original_selector_id(self):
        self.imported_fixture()
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(self.machine('15')))
        self.assertEqual(frappe.db.count('Knitting Plan', {'job': self.job}), 0)

    def test_production_accepts_verified_physical_dia_and_keeps_original_spec(self):
        self.imported_fixture()
        original = frappe.db.get_value('Knitting Job', self.job, 'programme')
        result = self.call('produce', self.production_values(self.receive('2'), self.machine()))
        roll = frappe.get_doc('Knitting Roll', result['data']['rolls'][0])
        self.assertEqual(domain.json_value(roll.specification)['dia'], '15')
        self.assertEqual(domain.json_value(roll.specification)['source_size_id'], '9')
        self.assertNotIn('dia_display', roll.specification)
        self.assertEqual(frappe.db.get_value('Knitting Job', self.job, 'programme'), original)

    def test_production_rejects_machine_matching_only_original_selector_id(self):
        self.imported_fixture()
        lot = self.receive('2')
        with self.assertRaises(frappe.ValidationError):
            self.call('produce', self.production_values(lot, self.machine('15')))
        self.assertEqual(domain.lot_balance(lot, self.job), domain.Decimal('2.000'))
        self.assertEqual(frappe.db.count('Knitting Roll', {'job': self.job}), 0)

    def test_transfer_native_physical_dia_to_imported_selector(self):
        target = self.imported_fixture()
        self.job = self.native_job('38')
        roll = self.call('produce', self.production_values(self.receive('2')))['data']['rolls'][0]
        spec = frappe.db.get_value('Knitting Roll', roll, 'specification')
        self.move_roll(self.job, target, roll)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'job'), target)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'specification'), spec)

    def test_transfer_rejects_equal_raw_values_with_different_physical_dia(self):
        target = self.imported_fixture()
        self.job = self.native_job('15')
        roll = self.call('produce', self.production_values(self.receive('2')))['data']['rolls'][0]
        with self.assertRaises(frappe.ValidationError):
            self.move_roll(self.job, target, roll)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'job'), self.job)

    def test_transfer_imported_spec_to_native_and_onward_uses_immutable_origin(self):
        source = self.imported_fixture()
        first, second = self.native_job('38'), self.native_job('38')
        roll = self.call('produce', self.production_values(self.receive('2')))['data']['rolls'][0]
        spec = frappe.db.get_value('Knitting Roll', roll, 'specification')
        self.move_roll(source, first, roll)
        self.move_roll(first, second, roll)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'job'), second)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'specification'), spec)

    def test_missing_source_authority_denies_machine_but_not_machine_free_production(self):
        self.imported_fixture()
        frappe.db.set_value('Knitting Job', self.job, 'source_record', None)
        lot, machine = self.receive('2'), self.machine('15')
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(machine))
        with self.assertRaises(frappe.ValidationError):
            self.call('produce', self.production_values(lot, machine))
        roll = self.call('produce', self.production_values(lot))['data']['rolls'][0]
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'weight_kg'), '1.000')

    def test_unrecorded_or_unknown_selector_cannot_match_a_machine(self):
        for selector in ('', '0', '999'):
            with self.subTest(selector=selector):
                self.imported_fixture(selector)
                with self.assertRaises(frappe.ValidationError):
                    self.call('plan', self.plan_values(self.machine(selector or '38')))
                self.tearDown()

    def test_invalid_zero_blank_or_nonfinite_master_label_is_not_physical_authority(self):
        self.imported_fixture()
        original = frappe.parse_json(frappe.db.get_value(RECORD, self.master, 'record_data'))
        for label in ('0', '0.0', '', ' ', 'NaN', 'Infinity'):
            with self.subTest(label=label):
                record = copy.deepcopy(original)
                record.pop('data_sha256')
                record['business_data']['original_business']['header']['dia'] = label
                record['data_sha256'] = contracts.sha(record)
                frappe.db.set_value(RECORD, self.master, {'record_data': frappe.as_json(record),
                    'data_sha256': record['data_sha256']})
                with self.assertRaises(frappe.ValidationError):
                    self.call('plan', self.plan_values(self.machine(label or '38')))

    def test_corrupt_original_or_master_hash_cannot_authorize_plan(self):
        self.imported_fixture()
        machine = self.machine()
        for name in (self.original, self.master):
            with self.subTest(record=name):
                digest = frappe.db.get_value(RECORD, name, 'data_sha256')
                frappe.db.set_value(RECORD, name, 'data_sha256', '0' * 64)
                with self.assertRaisesRegex(frappe.ValidationError, 'integrity'):
                    self.call('plan', self.plan_values(machine))
                frappe.db.set_value(RECORD, name, 'data_sha256', digest)

    def test_unauthorized_source_scope_cannot_authorize_machine(self):
        self.imported_fixture()
        machine, lot = self.machine(), self.receive('2')
        scope = frappe.parse_json(frappe.db.get_value(SCOPE, self.scope, 'scope_data'))
        scope['allowed_users'] = ['Administrator']
        frappe.db.set_value(SCOPE, self.scope, {'scope_data': frappe.as_json(scope),
            'data_sha256': contracts.sha(scope)})
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.ValidationError):
            self.call('produce', self.production_values(lot, machine))

    def test_hash_valid_foreign_original_with_forged_index_cannot_authorize_machine(self):
        self.imported_fixture()
        business = copy.deepcopy(service.get_record(self.original)['business_data'])
        business['original_business']['fabric_context']['job']['companymas_id'] = '2'
        name = service.store_record(self.scope, HistoricalContractTests().record(namespace='knitpack.job',
            family='job', native_id='123', source_company_id='2', business_data=business))['name']
        # The immutable document remains foreign even if its search index is damaged.
        frappe.db.set_value(RECORD, name, 'company', fixtures.COMPANY)
        frappe.db.set_value('Knitting Job', self.job, 'source_record', name)
        machine = self.machine()
        for action in (self.projected_line, lambda: self.call('plan', self.plan_values(machine))):
            with self.assertRaises(frappe.ValidationError):
                action()

    def test_matching_diameter_does_not_bypass_gauge_capacity_or_line_balance(self):
        self.imported_fixture()
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(self.machine(gauge='18')))
        machine = self.machine()
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', {**self.plan_values(machine), 'quantity_kg': '121.000'})
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', {**self.plan_values(machine), 'quantity_kg': '89.000'})

    def test_batch_machine_validation_uses_same_physical_measurement(self):
        self.imported_fixture()
        result = self.call('produce_batch', {'job': self.job, 'programme_line': 'P1',
            'quantity_kg': '1.000', 'rolls': '1', 'machine': self.machine(),
            'inputs': [{'lot': self.receive('2'), 'quantity_kg': '1.000'}]})
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', result['data']['batch'], 'quantity_kg'), '1.000')

    def test_roll_cannot_borrow_another_valid_production_event(self):
        source = self.imported_fixture()
        target = self.native_job('38')
        lot = self.receive('3')
        first = self.call('produce', self.production_values(lot))['data']['rolls'][0]
        second = self.call('produce', self.production_values(lot))
        frappe.db.set_value('Knitting Roll', first, 'production', second['event'])
        with self.assertRaises(frappe.ValidationError):
            self.move_roll(source, target, first)

    def test_cancelled_or_foreign_roll_origin_cannot_authorize_transfer(self):
        source = self.imported_fixture()
        target = self.native_job('38')
        result = self.call('produce', self.production_values(self.receive('2')))
        roll = result['data']['rolls'][0]
        frappe.db.set_value('Knitting Event', result['event'], 'cancelled', 1)
        with self.assertRaises(frappe.ValidationError):
            self.move_roll(source, target, roll)
        frappe.db.set_value('Knitting Event', result['event'], 'cancelled', 0)
        other = next(r.name for r in frappe.get_all('Company', fields=['name']) if r.name != fixtures.COMPANY)
        frappe.db.set_value('Knitting Event', result['event'], 'company', other)
        with self.assertRaises(frappe.PermissionError):
            self.move_roll(source, target, roll)

    def test_split_imported_roll_retains_verified_origin_for_native_transfer(self):
        source = self.imported_fixture()
        target = self.native_job('38')
        lot = self.receive('3')
        roll = self.call('produce', {**self.production_values(lot), 'weights_kg': ['2.000'],
            'inputs': [{'lot': lot, 'quantity_kg': '2.000'}]})['data']['rolls'][0]
        child = self.call('split_roll', {'job': source, 'roll': roll,
            'weights_kg': ['1.000', '1.000'], 'reason': 'Synthetic split for reassignment'})['data']['rolls'][0]
        self.move_roll(source, target, child)
        self.assertEqual(frappe.db.get_value('Knitting Roll', child, 'job'), target)

    def test_native_physical_value_is_not_treated_as_original_selector(self):
        self.imported_fixture()
        self.job = self.native_job('15')
        result = self.call('plan', self.plan_values(self.machine('15')))
        self.assertEqual(frappe.db.get_value('Knitting Plan', result['data']['plan'], 'job'), self.job)

    def test_stripped_imported_provenance_cannot_make_selector_a_physical_diameter(self):
        self.imported_fixture()
        stripped = [{key: value for key, value in line.items() if not key.startswith('source_')}
            for line in self.lines]
        frappe.db.set_value('Knitting Job', self.job, 'programme', frappe.as_json(stripped))
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(self.machine('15')))

    def test_transfer_counts_captured_output_in_imported_target_programme_balance(self):
        target = self.imported_fixture()
        programme = copy.deepcopy(self.lines)
        programme[0]['target_kg'] = '88.000'
        frappe.db.set_value('Knitting Job', target, {'programme': frappe.as_json(programme), 'target_kg': '88.000'})
        self.job = self.native_job('38')
        roll = self.call('produce', self.production_values(self.receive('2')))['data']['rolls'][0]
        with self.assertRaises(frappe.ValidationError):
            self.move_roll(self.job, target, roll)
        self.assertEqual(frappe.db.get_value('Knitting Roll', roll, 'job'), self.job)

    def test_case_variant_master_namespace_cannot_authorize_diameter(self):
        self.imported_fixture()
        master = service.get_record(self.master)
        service.store_record(self.scope, HistoricalContractTests().record(namespace='KNITPACK.DIA',
            family='master', native_id='15', source_company_id=None, source_book=None,
            shared_reference=True, business_data=master['business_data']))
        frappe.db.set_value(RECORD, self.master, 'namespace', 'synthetic.hidden')
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(self.machine()))

    def test_case_variant_job_namespace_cannot_authorize_diameter(self):
        self.imported_fixture()
        original = service.get_record(self.original)
        name = service.store_record(self.scope, HistoricalContractTests().record(namespace='KNITPACK.JOB',
            family='job', native_id='123', business_data=original['business_data']))['name']
        frappe.db.set_value('Knitting Job', self.job, 'source_record', name)
        with self.assertRaises(frappe.ValidationError):
            self.call('plan', self.plan_values(self.machine()))

    def test_resolved_diameter_does_not_imply_new_numeric_format_equivalence(self):
        self.imported_fixture()
        for value in ('38.0', ' 38 '):
            with self.subTest(machine_dia=value), self.assertRaises(frappe.ValidationError):
                self.call('plan', self.plan_values(self.machine(value)))


for cls in (fixtures.KnittingTests, SourceDimensionTests):
    for name in vars(cls):
        if name.startswith('test_'):
            setattr(ImportedCompatibilityTests, name, None)
