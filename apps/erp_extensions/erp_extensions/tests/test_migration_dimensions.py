"""Synthetic source dimension display; stored originals and operational rows stay unchanged."""
import copy
from unittest.mock import patch

import frappe

from erp_extensions.knitting import api, domain, permissions, reports
from erp_extensions.migration import api as history, service, printing
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests import test_migration_contracts as contracts_fixtures


class SourceDimensionTests(fixtures.KnittingTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        from erp_extensions.migration.install import install
        install()
        frappe.db.commit()

    def original_fixture(self, selector='15'):
        self.fixtures()
        other = [r.name for r in frappe.get_all('Company', fields=['name']) if r.name != fixtures.COMPANY][:3]
        self.assertEqual(len(other), 3)
        contract = contracts_fixtures.HistoricalContractTests()
        values = contract.scope()
        values.update(source_instance='synthetic-dimensions-' + frappe.generate_hash(),
            company_bindings={str(i+1): company for i, company in enumerate([fixtures.COMPANY, *other])},
            allowed_users=['Administrator', 'knit-operator@example.invalid', 'knit-accountant@example.invalid'])
        self.scope = service.create_scope(values)
        self.original = service.store_record(self.scope, contract.record(namespace='knitpack.job', family='job',
            native_id='123', business_data={'fields': {'reference': 'J-123'},
                'tables': [{'kind': 'items', 'rows': [{'source_id': '9', 'dia': selector, 'quantity': '88.000'}]}],
                'original_business': {'original_saved_job': {'id': '123', 'companymas_id': '1'},
                    'job_ledger': {'pjobno': '456/26', 'job': {'id': '123', 'companymas_id': '1'}},
                    'fabric_context': {'job': {'id': '123', 'companymas_id': '1'},
                    'fabs': [{'id': '7', 'jobmas_id': '123', 'dias': [{'id': '9', 'jobfabric_id': '7',
                        'diatype': 'circular', 'diaorsize': selector}]}]}}}))['name']
        self.master = service.store_record(self.scope, contract.record(namespace='knitpack.dia', family='master',
            native_id='15', source_company_id=None, source_book=None, shared_reference=True,
            business_data={'fields': {'description': 'Dia', 'source_id': '15'},
                'original_business': {'header': {'id': '15', 'dia': '38'}}}))['name']
        self.lines = domain.json_value(frappe.db.get_value('Knitting Job', self.job, 'programme'), [])
        self.lines[0].update(dia=selector, source_fabric_id='7', source_size_id='9')
        with permissions.service_write():
            job = frappe.get_doc('Knitting Job', self.job)
            job.source_record = self.original
            job.source_reference = '456'
            job.programme = frappe.as_json(self.lines)
            job.save()
            batch = domain.insert('Knitting Fabric Batch', company=fixtures.COMPANY, job=self.job,
                programme_line='P1', quantity_kg='88.000', rolls='7', state='Awaiting review',
                source_record=self.original, specification=frappe.as_json(self.lines[0]))
            self.batch = batch.name
            self.event = domain.insert('Knitting Event', company=fixtures.COMPANY, job=self.job,
                kind='migration_stock_initialization', request_key=frappe.generate_hash(),
                occurred_at='2026-11-01 09:00:00', result=frappe.as_json({'programme_output': [
                    {'programme_line': 'P1', 'quantity_kg': '88.000'}], 'batches': [{
                    'name': batch.name, 'job': self.job, 'programme_line': 'P1', 'quantity_kg': '88.000',
                    'rolls': '7', 'state': 'Awaiting review', 'specification': self.lines[0]}]})).name

    def projected_line(self):
        row, = api.register(fixtures.COMPANY, 'jobs', query=self.job)['rows']
        return row['programme'][0]

    def test_job_lookup_batch_report_and_original_print_resolve_without_writes(self):
        self.original_fixture()
        before = (frappe.db.get_value('Knitting Job', self.job, 'programme'),
            frappe.db.get_value('Knitting Fabric Batch', self.batch, 'specification'),
            frappe.db.get_value('Knitting Event', self.event, 'result'), service.get_record(self.original))
        line = self.projected_line()
        self.assertEqual((line['dia'], line.get('dia_display'), line.get('dia_basis')), ('15', '38', 'source_master_id'))
        lookup = api.lookup(fixtures.COMPANY, 'Job', self.job)['rows'][0]['programme'][0]
        self.assertEqual(lookup['dia_display'], '38')
        batch = api.register(fixtures.COMPANY, 'batches', job=self.job)['rows'][0]
        self.assertEqual(domain.json_value(batch['specification'], {})['dia_display'], '38')
        report = reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'dia': '38'})
        self.assertEqual((report['row_count'], report['summary']['quantity_kg']), (1, '88.000'))
        self.assertEqual((report['rows'][0]['dia'], report['rows'][0]['source_dia_id']), ('38', '15'))
        self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': self.job, 'dia': '15'})['row_count'], 0)
        for projected in (history.detail(fixtures.COMPANY, self.original), printing.record_data(fixtures.COMPANY, self.original)):
            row = projected['tables'][0]['rows'][0]
            self.assertEqual((row['dia'], row['source_dia_id']), ('38', '15'))
            self.assertIn({'key': 'source_dia_id', 'label': 'Original diameter identity'}, projected['tables'][0]['columns'])
        self.assertEqual(before, (frappe.db.get_value('Knitting Job', self.job, 'programme'),
            frappe.db.get_value('Knitting Fabric Batch', self.batch, 'specification'),
            frappe.db.get_value('Knitting Event', self.event, 'result'), service.get_record(self.original)))

    def test_native_physical_fifteen_is_not_an_original_source_master_id(self):
        self.original_fixture()
        physical = [{key: value for key, value in line.items() if not key.startswith('source_')} for line in self.lines]
        original_job = self.job
        before = frappe.db.get_value('Knitting Job', original_job, 'programme')
        with self.assertRaisesRegex(frappe.ValidationError, '[Ii]mported'):
            self.call('revise_job', {'job': original_job, 'programme': physical, 'reason': 'Unproved conversion'})
        self.assertEqual(frappe.db.get_value('Knitting Job', original_job, 'programme'), before)
        self.job = self.call('create_job', {'customer': self.customer, 'target_kg': '88.000',
            'material_mode': 'Customer', 'programme': physical, 'rate': '100'})['data']['job']
        line = self.projected_line()
        self.assertEqual((line['dia'], line['dia_display'], line['dia_basis']), ('15', '15', 'physical'))
        self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': original_job, 'dia': '38'})['row_count'], 1)

    def test_rate_only_revision_keeps_original_dimension_basis(self):
        self.original_fixture()
        self.call('revise_job', {'job': self.job, 'rate': '101', 'reason': 'Agreed rate only'})
        self.assertEqual(self.projected_line()['dia_display'], '38')
        self.assertEqual(frappe.parse_json(frappe.db.get_value('Knitting Job', self.job, 'programme'))[0]['dia'], '15')

    def test_empty_source_selector_stays_unrecorded_and_unproved_change_is_not_remapped(self):
        self.original_fixture(selector='')
        line = self.projected_line()
        self.assertEqual((line['dia_display'], line['dia_basis']), ('', 'unrecorded'))
        changed = copy.deepcopy(self.lines)
        changed[0]['dia'] = '15'
        frappe.db.set_value('Knitting Job', self.job, 'programme', frappe.as_json(changed))
        line = self.projected_line()
        self.assertIsNone(line['dia_display'])
        self.assertEqual(line['dia_basis'], 'unresolved')

    def test_scope_revocation_withholds_derived_dimension_without_cross_request_cache(self):
        self.original_fixture()
        frappe.set_user('knit-accountant@example.invalid')
        self.assertEqual(self.projected_line()['dia_display'], '38')
        with patch.object(history, '_member', return_value=False):
            line = self.projected_line()
            self.assertIsNone(line['dia_display'])
            self.assertEqual(line['dia_basis'], 'unresolved')
        self.assertEqual(self.projected_line()['dia_display'], '38')

    def test_production_and_delivery_already_display_measurements_are_unchanged(self):
        self.original_fixture()
        contract = contracts_fixtures.HistoricalContractTests()
        for namespace, family in (('knitpack.production', 'production'), ('knitpack.fabric_delivery', 'delivery')):
            name = service.store_record(self.scope, contract.record(namespace=namespace, family=family,
                business_data={'fields': {'dia': '38'}, 'tables': [{'kind': 'quantities', 'rows': [{'dia': '38'}]}]}))['name']
            detail = printing.record_data(fixtures.COMPANY, name)
            self.assertIn({'label': 'Diameter / size', 'value': '38'}, detail['fields'])
            self.assertEqual(detail['tables'][0]['rows'], [{'dia': '38'}])

    def test_batched_projection_loads_each_source_set_once_for_a_thousand_rows(self):
        from erp_extensions.migration import dimensions
        self.original_fixture()
        rows = [{'name': self.job, 'programme': copy.deepcopy(self.lines)} for _ in range(1000)]
        original = frappe.get_all
        with patch.object(frappe, 'get_all', wraps=original) as reads:
            dimensions.programmes(fixtures.COMPANY, rows)
        self.assertTrue(all(row['programme'][0]['dia_display'] == '38' for row in rows))
        historical_reads = [call for call in reads.call_args_list if call.args[0] == service.RECORD]
        self.assertEqual(len(historical_reads), 2)

    def test_wrong_company_source_and_corrupt_master_do_not_supply_measurements(self):
        self.original_fixture()
        record = service.get_record(self.original)
        data = copy.deepcopy(record['business_data'])
        data['original_business']['fabric_context']['job']['companymas_id'] = '2'
        other = service.store_record(self.scope, contracts_fixtures.HistoricalContractTests().record(
            namespace='knitpack.job', family='job', native_id='123', source_company_id='2', business_data=data))['name']
        frappe.db.set_value('Knitting Job', self.job, 'source_record', other)
        self.assertIsNone(self.projected_line()['dia_display'])
        frappe.db.set_value('Knitting Job', self.job, 'source_record', self.original)
        frappe.db.set_value(service.RECORD, self.master, 'data_sha256', '0' * 64)
        with self.assertRaises(frappe.ValidationError):
            self.projected_line()

    def test_unproved_imported_programme_revision_remains_rejected_without_changing_original(self):
        self.original_fixture()
        before = frappe.db.get_value('Knitting Job', self.job, 'programme')
        line = self.projected_line()
        submitted = {key: value for key, value in line.items() if key not in ('dia_display', 'dia_basis')}
        with self.assertRaises(frappe.ValidationError):
            self.call('revise_job', {'job': self.job, 'programme': [submitted], 'reason': 'Unproved conversion'})
        self.assertEqual(frappe.db.get_value('Knitting Job', self.job, 'programme'), before)

    def test_read_companions_do_not_enter_production_payload_or_stored_specification(self):
        self.fixtures()
        lot = self.receive('90')
        selected = api.lookup(fixtures.COMPANY, 'Job', self.job)['rows'][0]['programme'][0]
        self.assertIn('dia_display', selected)
        result = self.call('produce_batch', {'job': self.job, 'programme_line': selected['id'],
            'quantity_kg': '88', 'rolls': '7', 'loss_kg': '2',
            'inputs': [{'lot': lot, 'quantity_kg': '90', 'units': '2'}]})
        for value in (frappe.db.get_value('Knitting Fabric Batch', result['data']['batch'], 'specification'),
                frappe.db.get_value('Knitting Event', result['event'], 'payload'),
                frappe.db.get_value('Knitting Event', result['event'], 'result')):
            self.assertNotIn('dia_display', value)
            self.assertNotIn('dia_basis', value)

    def test_verified_job_reference_preserves_raw_and_covers_empty_programmes(self):
        self.original_fixture()
        row, = api.register(fixtures.COMPANY, 'jobs', query=self.job)['rows']
        self.assertEqual((row['source_reference'], row.get('source_reference_display')), ('456', '456/26'))
        frappe.db.set_value('Knitting Job', self.job, 'programme', '[]')
        row, = api.register(fixtures.COMPANY, 'jobs', query=self.job)['rows']
        self.assertEqual(row.get('source_reference_display'), '456/26')
        self.assertEqual(frappe.db.get_value('Knitting Job', self.job, 'source_reference'), '456')
        frappe.db.set_value('Knitting Job', self.job, 'source_record', None)
        row, = api.register(fixtures.COMPANY, 'jobs', query=self.job)['rows']
        self.assertEqual(row['source_reference'], '456')
        self.assertNotIn('source_reference_display', row)

    def test_individual_roll_reports_keep_origin_dimensions_after_transfer(self):
        self.original_fixture()
        with permissions.service_write():
            source = frappe.get_doc('Knitting Job', self.job)
            expanded = copy.deepcopy(self.lines)
            expanded[0]['target_kg'] = '176.000'
            source.programme, source.target_kg = frappe.as_json(expanded), '176.000'
            source.save()
        lot = self.receive('90')
        roll = self.call('produce', {'job': self.job, 'programme_line': 'P1', 'weights_kg': ['88'],
            'loss_kg': '2', 'inputs': [{'lot': lot, 'quantity_kg': '90', 'units': '2'}]})['data']['rolls'][0]
        for report, quantity in (('rolls', '88.000'), ('fabric', '176.000')):
            with self.subTest(stage='original', report=report):
                self.assertEqual(reports.run(fixtures.COMPANY, report, {'job': self.job, 'dia': '38'})['summary']['quantity_kg'], quantity)
        target_line = {k: v for k, v in self.lines[0].items() if not k.startswith('source_')}
        target = self.call('create_job', {'customer': self.customer, 'target_kg': '88', 'material_mode': 'Customer',
            'programme': [target_line], 'rate': '100'})['data']['job']
        data = copy.deepcopy(service.get_record(self.original)['business_data'])
        context = data['original_business']['fabric_context']
        context['job']['id'] = '124'
        context['fabs'][0].update(id='17', jobmas_id='124')
        context['fabs'][0]['dias'][0].update(id='19', jobfabric_id='17')
        record = service.store_record(self.scope, contracts_fixtures.HistoricalContractTests().record(
            namespace='knitpack.job', family='job', native_id='124', business_data=data))['name']
        with permissions.service_write():
            destination = frappe.get_doc('Knitting Job', target)
            target_line.update(source_fabric_id='17', source_size_id='19')
            destination.source_record, destination.programme = record, frappe.as_json([target_line])
            destination.save()
        self.call('transfer_fabric', {'job': self.job, 'target_job': target,
            'target_modified': str(destination.modified), 'target_programme_line': 'P1',
            'rolls': [roll], 'reason': 'Synthetic matching original dimensions'})
        for report in ('rolls', 'fabric'):
            with self.subTest(stage='transferred', report=report):
                value = reports.run(fixtures.COMPANY, report, {'job': target, 'dia': '38'})
                self.assertEqual(value['summary']['quantity_kg'], '88.000')
                self.assertEqual(value['rows'][0]['job'], target)
                self.assertNotIn('_dimension_job', value['rows'][0])
                self.assertNotIn('_dimension_spec', value['rows'][0])


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(SourceDimensionTests, name, None)
