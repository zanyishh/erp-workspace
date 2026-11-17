"""Exercise roll traceability projections with synthetic rows and no configured site."""
import importlib.util
import json
import sys
import unittest
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch


class Row(dict):
    __getattr__ = dict.get
    __setattr__ = dict.__setitem__


class RollReportTests(unittest.TestCase):
    timestamps = [datetime(2026, 11, 14, 23, 59), datetime(2026, 11, 15, 0, 1)]

    def records(self, doctype, **kwargs):
        if doctype == 'Knitting Event':
            if kwargs.get('filters', {}).get('kind') == 'transfer_fabric':
                return []
            return [Row(name=f'EV{i}', company='Demo', job='JOB', kind='produce', occurred_at=stamp,
                payload='{}', result=json.dumps(dict(rolls=[f'ROLL{i}'], production_operator_record=f'EMP{i}',
                    production_operator_label='Same name', production_operator_number=f'00{i}',
                    production_machine_record=f'MC{i}', production_machine_label='Machine',
                    production_machine_code=f'0{i}'))) for i, stamp in enumerate(self.timestamps)]
        if doctype == 'Knitting Roll':
            return [Row(name=f'ROLL{i}', job='JOB', programme_line='1', weight_kg='3.500',
                machine=None, operator='signer', shift='A', produced_at=stamp, production=f'EV{i}',
                parent_roll=None, specification='{}') for i, stamp in enumerate(self.timestamps)]
        self.fail(f'Unexpected database call for {doctype}')

    def setUp(self):
        frappe = SimpleNamespace(get_all=self.records,
            db=SimpleNamespace(exists=lambda *args: False, get_value=lambda *args: 'Synthetic party'))
        domain = SimpleNamespace(ZERO=Decimal(0), kg=lambda value: format(value, '.3f'), money=lambda value: format(value, '.2f'),
            json_value=lambda value, default: json.loads(value) if value else default)
        packages = {
            'frappe': frappe, 'erpnext': ModuleType('erpnext'),
            'frappe.utils': SimpleNamespace(getdate=lambda value: value if isinstance(value, date)
                else date.fromisoformat(value), get_datetime=datetime.fromisoformat, now_datetime=datetime.now, today=lambda: '2026-11-15'),
            'erp_extensions': ModuleType('erp_extensions'),
            'erp_extensions.knitting': SimpleNamespace(domain=domain, permissions=Mock(), posting=Mock()),
            'erp_extensions.migration': ModuleType('erp_extensions.migration'),
            'erp_extensions.migration.dimensions': SimpleNamespace(report_rows=Mock()),
        }
        scope = patch.dict(sys.modules, packages)
        scope.start()
        self.addCleanup(scope.stop)
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/knitting/reports.py'
        spec = importlib.util.spec_from_file_location('erp_extensions.knitting.reports', source)
        reports = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reports)
        self.run_report = reports.run
        self.frappe = frappe
        self.domain = domain
        factory_spec = importlib.util.spec_from_file_location('erp_extensions.knitting.factory', source.with_name('factory.py'))
        self.factory = importlib.util.module_from_spec(factory_spec)
        factory_spec.loader.exec_module(self.factory)


    def test_local_calendar_buckets_and_total(self):
        for key, expected in [('hour', ['2026-11-14 23:00', '2026-11-15 00:00']),
                              ('day', ['2026-11-14', '2026-11-15'])]:
            with self.subTest(group=key):
                report = self.run_report('Demo', 'rolls', {'group_by': key})
                self.assertEqual([(r[key], r['weight_kg']) for r in report['rows']],
                    [(value, '3.500') for value in expected])
                self.assertEqual(report['summary']['quantity_kg'], '7.000')

    def test_roll_register_orders_by_time_before_reference(self):
        self.timestamps = list(reversed(self.timestamps))
        result = self.run_report('Demo', 'rolls', {})
        self.assertEqual([c['key'] for c in result['columns'][:2]], ['produced_at', 'name'])
        self.assertEqual([r['name'] for r in result['rows']], ['ROLL1', 'ROLL0'])

    def test_stoppage_register_keeps_unrecorded_shift_and_godown_separate(self):
        self.domain.reference = Mock(return_value=Row(name='MC1', shifts='[]'))
        self.domain.warehouse = Mock(return_value='Floor A')
        self.domain.settings = Mock(return_value={'shift_windows': [{'name': 'Night'}]})
        events = []
        for extra in [{'shift': 'Night', 'warehouse': 'Floor A'}, {}]:
            request = {'machine': 'MC1', 'reason': 'Maintenance', 'starts_at': '2026-11-14 23:00',
                       'ends_at': '2026-11-14 23:30', **extra}
            result = self.factory.stoppage(Row(company='Demo'), request, None)
            if extra:
                self.assertEqual((result.get('shift'), result.get('warehouse')), ('Night', 'Floor A'))
            events.append(Row(name=f'STOP-{len(events)}', kind='stoppage', occurred_at=self.timestamps[0],
                              payload=json.dumps(request), result=json.dumps(result)))
        self.domain.warehouse.assert_called_once_with('Floor A', 'Demo')
        self.frappe.get_all = lambda *args, **kwargs: [Row(row) for row in events]
        result = self.run_report('Demo', 'stoppage', {'group_by': 'shift'})
        self.assertEqual([(r['shift'], r['minutes']) for r in result['rows']],
                         [('Night', '30.00'), ('Unspecified', '30.00')])
        filtered = self.run_report('Demo', 'stoppage', {'warehouse': 'Floor A', 'shift': 'Night'})
        self.assertEqual([r['event'] for r in filtered['rows']], ['STOP-0'])
        self.assertEqual(filtered['summary']['minutes'], '30.00')

    def test_period_stoppage_counts_only_downtime_in_range_even_when_entered_later(self):
        entered = datetime(2026, 11, 16, 11)
        entries = [
            Row(name='OVERNIGHT', kind='stoppage', occurred_at=entered, payload='{}',
                result=json.dumps({'machine': 'MC1', 'starts_at': '2026-11-14 23:00',
                    'ends_at': '2026-11-15 01:00', 'minutes': '120', 'reason': 'Maintenance'})),
            Row(name='EARLIER', kind='stoppage', occurred_at=entered, payload='{}',
                result=json.dumps({'machine': 'MC1', 'starts_at': '2026-11-14 20:00',
                    'ends_at': '2026-11-15 00:00', 'minutes': '240', 'reason': 'Maintenance'})),
        ]
        def records(doctype, *, filters, **kwargs):
            self.assertEqual(doctype, 'Knitting Event')
            self.assertEqual(filters['company'], 'Demo')
            end = filters.get('occurred_at', [None, datetime.max])[1]
            return [Row(e) for e in entries if e.occurred_at < end]
        self.frappe.get_all = records
        report = self.run_report('Demo', 'stoppage', {'mode': 'period', 'from_date': '2026-11-15',
                                                      'to_date': '2026-11-15', 'group_by': 'machine'})
        self.assertEqual([(r['machine'], r['minutes']) for r in report['rows']], [('MC1', '60.00')])

    def test_yarn_registers_use_confirmed_custody_units_party_and_separate_references(self):
        stamp = self.timestamps[0]
        header = dict(company='Demo', occurred_at=stamp, payload='{}')
        movements = [
            Row(**header, name='GRN', kind='receive_yarn', result=json.dumps({'lot': 'L1',
                'party_dc_number': '0008/A', 'party_dc_date': '2026-11-01'})),
            Row(**header, name='RET', kind='return_yarn', result='{"lot":"L1"}'),
            Row(**header, name='OTHER', kind='receive_yarn', result='{"lot":"L2"}'),
            Row(**header, name='VOID', kind='receive_yarn', result='{"lot":"L2"}'),
            Row(**header, name='REV', kind='cancel_event', result='{}', reverses='VOID'),
        ]
        ledger = [Row(event=event, quantity_kg=qty, units=units, party=party, lot=lot,
                      material_owner='Customer', job=None, warehouse='Floor A')
            for event, qty, units, party, lot in [
                ('GRN', '12.500', '3', 'Alpha', 'L1'), ('RET', '-2.500', '-1', 'Alpha', 'L1'),
                ('OTHER', '5.000', '1', 'Beta', 'L2'), ('VOID', '1.000', '1', 'Alpha', 'L2')]]
        def records(doctype, *, filters, **kwargs):
            self.assertEqual(filters['company'], 'Demo')
            if doctype == 'Knitting Event':
                return [Row(e) for e in movements]
            self.assertEqual(doctype, 'Knitting Ledger Entry')
            return [Row(e) for e in ledger if e.event in filters['event'][1]]
        self.frappe.get_all = records
        self.frappe.get_list = lambda *args, **kwargs: [Row(name='L1', source_lot='007', item='Yarn'),
                                                         Row(name='L2', source_lot='B', item='Yarn')]
        self.frappe.throw = lambda message: self.fail(message)
        filters = {'customer': 'Alpha', 'warehouse': 'Floor A', 'source_lot': '007'}
        for report, reference, kg, units in [('yarn_inwards', 'GRN', '12.500', '3'),
                                             ('yarn_returns', 'RET', '2.500', '1')]:
            result = self.run_report('Demo', report, filters)
            self.assertEqual(result['summary'], {'quantity_kg': kg, 'units': units})
            row, = result['rows']
            self.assertEqual((row['event'], row['quantity_kg'], row['units']), (reference, kg, units))
            if report == 'yarn_inwards':
                self.assertEqual((row['party_dc_number'], row['party_dc_date']), ('0008/A', '2026-11-01'))
        empty = self.run_report('Demo', 'yarn_returns', {**filters, 'source_lot': '008'})
        self.assertEqual(empty['row_count'], 0)

    def test_receipt_preserves_challan_reference_and_date_without_changing_posting_date(self):
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/knitting/domain.py'
        spec = importlib.util.spec_from_file_location('erp_extensions.knitting.domain', source)
        domain = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(domain)
        domain.reference = Mock(return_value=Row(name='Yarn', is_stock_item=1, stock_uom='Kg'))
        domain.warehouse = Mock(return_value='Floor A')
        domain.insert = Mock(return_value=Row(name='LOT'))
        domain.ledger = Mock()
        self.frappe.as_json = json.dumps
        self.frappe.throw = Mock(side_effect=ValueError)
        event = Row(name='GRN', company='Demo', occurred_at=self.timestamps[0])
        receipt = {'quantity_kg': '1.250', 'units': '1', 'party': 'Alpha', 'warehouse': 'Floor A',
                   'item': 'Yarn', 'party_dc_date': '2026-11-30', 'party_dc_number': '008/A'}
        for bad in ['2026-11-31', '20261130']:
            with self.assertRaises(ValueError):
                domain.receive_yarn(event, {**receipt, 'party_dc_date': bad}, None)
        domain.ledger.assert_not_called()
        result = domain.receive_yarn(event, receipt, None)
        self.assertEqual((result['party_dc_number'], result['party_dc_date']), ('008/A', '2026-11-30'))
        self.assertEqual(event.occurred_at, self.timestamps[0])
        domain.ledger.assert_called_once()

    def test_batch_challan_uses_saved_count_and_weight_without_individual_weights(self):
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/knitting/exports.py'
        spec = importlib.util.spec_from_file_location('erp_extensions.knitting.exports', source)
        exports = importlib.util.module_from_spec(spec)
        sys.modules['erp_extensions.knitting'].reports = SimpleNamespace(filters=lambda value: value)
        spec.loader.exec_module(exports)
        render = Mock(return_value=b'synthetic renderer')
        with patch.dict(sys.modules, {'frappe.utils.pdf': SimpleNamespace(get_pdf=render)}):
            self.frappe.throw = Mock(side_effect=ValueError)
            event = Row(kind='deliver_batch', name='DC-1', company='Demo', job='JOB', occurred_at=self.timestamps[0],
                check_permission=Mock(), result=json.dumps({'quantity_kg': '21.300', 'roll_count': '2',
                    'destination': 'Finisher', 'sources': [{'batch': 'LOT&2', 'rolls': '2', 'programme_line': 'P1',
                    'quantity_kg': '21.300', 'rate': '9999'}]}))
            self.domain.reference = Mock(side_effect=[event, Row(name='JOB', customer='Party', material_mode='Customer')])
            generated = exports.render('Demo', 'delivery_challan', {'event': 'DC-1'})
            event.check_permission.assert_called_once_with('print')
            self.assertEqual(generated['name'], 'DC-1-challan.pdf')
            html = render.call_args.args[0]
            for value in ['LOT&amp;2', '21.300', 'Finisher', '2 rolls', 'P1']:
                self.assertIn(value, html)
            for invalid in ['10.650', '9999']:
                self.assertNotIn(invalid, html)
            event.cancelled = 1
            self.domain.reference = Mock(return_value=event)
            with self.assertRaises(ValueError):
                exports.render('Demo', 'delivery_challan', {'event': 'DC-1'})
            render.assert_called_once()

    def test_attribution_columns_and_exact_identity_filtering(self):
        for key, value in [('production_operator', 'EMP1'), ('production_machine', 'MC1')]:
            with self.subTest(filter=key):
                report = self.run_report('Demo', 'rolls', {key: value})
                self.assertIn(key + '_label', [column['key'] for column in report['columns']])
                self.assertEqual([row['name'] for row in report['rows']], ['ROLL1'])
                self.assertEqual(report['summary']['quantity_kg'], '3.500')
                grouped = self.run_report('Demo', 'rolls', {'group_by': key})
                self.assertEqual(grouped['row_count'], 2)


if __name__ == '__main__':
    unittest.main()
