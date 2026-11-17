"""Permission batching with synthetic rows only; no site or source connection."""
import importlib
import json
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class Row(dict):
    __getattr__ = dict.get


class PermissionBatchTests(unittest.TestCase):
    def setUp(self):
        self.visible = {'Customer': ['visible'], 'Knitting Job': ['job-1'],
                        'Knitting Ledger Entry': [], 'Knitting Roll': [],
                        'Knitting Fabric Batch': [], 'Knitting Subcontract': []}
        self.rows = {'Knitting Job': [Row(name='job-1', customer='visible')]}
        self.frappe = SimpleNamespace(session=SimpleNamespace(user='staff'), flags={},
            PermissionError=PermissionError, ValidationError=ValueError,
            whitelist=lambda: lambda fn: fn, has_permission=Mock(return_value=True),
            get_list=Mock(side_effect=self.get_list), get_all=Mock(side_effect=self.get_all),
            get_doc=Mock(side_effect=AssertionError('Per-record document loads are forbidden in batch checks')),
            get_meta=lambda doctype: SimpleNamespace(has_field=lambda field: field in
                {'customer', 'job', 'target_job', 'payload', 'result', 'voucher_type', 'voucher_name'}),
            parse_json=lambda value: json.loads(value) if isinstance(value, str) else value,
            db=SimpleNamespace(exists=Mock(side_effect=AssertionError('JSON links must be checked in batches')),
                               escape=lambda value: repr(value)),
            throw=lambda message, exc: (_ for _ in ()).throw(exc(message)))
        modules = patch.dict(sys.modules, {'frappe': self.frappe})
        modules.start()
        self.addCleanup(modules.stop)
        # Lazy sibling imports must share this test's fake framework and real package.
        for name in tuple(sys.modules):
            if name == 'erp_extensions' or name.startswith('erp_extensions.'):
                del sys.modules[name]
        self.permissions = importlib.import_module('erp_extensions.knitting.permissions')

    def get_list(self, doctype, filters=None, user=None, **kwargs):
        names = self.visible.get(doctype, []) if user == 'staff' else []
        return [n for n in names if not filters or n == filters.get('name')]

    def get_all(self, doctype, filters=None, pluck=None, **kwargs):
        rows = self.rows.get(doctype, [])
        if filters and isinstance(filters.get('name'), list):
            rows = [row for row in rows if row.name in filters['name'][1]]
        return [row.name for row in rows] if pluck else [Row(row) for row in rows]

    def test_link_sets_are_reused_only_inside_same_user_snapshot(self):
        p = self.permissions
        with p.snapshot_link_checks():
            self.assertTrue(p.link_visible('Customer', 'visible'))
            with p.snapshot_link_checks():
                self.assertFalse(p.link_visible('Customer', 'hidden'))
                self.assertTrue(p.link_visible('Customer', 'visible'))
            self.assertFalse(p.link_visible('Customer', 'visible', 'other'))
        self.assertEqual(self.frappe.get_list.call_count, 2)
        self.visible['Customer'] = []
        with p.snapshot_link_checks():
            self.assertFalse(p.link_visible('Customer', 'visible'))

    def test_aggregate_reads_source_fields_in_batches_and_still_rejects_hidden_customer(self):
        self.permissions.require_aggregate_scope('Synthetic company')
        self.frappe.get_doc.assert_not_called()
        self.rows['Knitting Job'][0]['customer'] = 'hidden'
        with self.assertRaises(PermissionError):
            self.permissions.require_aggregate_scope('Synthetic company')

    def test_nested_event_links_remain_restricted_without_per_row_loading(self):
        self.rows['Stock Entry'] = [Row(name='hidden-stock')]
        self.rows['Knitting Event'] = [Row(name='event-1', job='job-1', target_job=None,
            payload='{}', result=json.dumps({'children': [{'invoice': 'not-a-native-record'},
                 {'vouchers': [{'voucher_type': 'Stock Entry', 'voucher': 'hidden-stock'}]}]}))]
        with self.assertRaises(self.permissions.SourceReconciliationError) as error:
            self.permissions.require_event_sources([Row(name='event-1')])
        self.assertEqual(error.exception.jobs, {'job-1'})
        self.visible['Stock Entry'] = ['hidden-stock']
        self.permissions.require_event_sources([Row(name='event-1')])
        self.frappe.get_doc.assert_not_called()
        self.frappe.db.exists.assert_not_called()

    def test_event_query_filters_hidden_json_sources_using_batch_rows(self):
        self.rows['Knitting Event'] = [Row(name='visible-event', payload='{}', result='{}'),
            Row(name='hidden-event', payload='{}', result='{"nested":{"warehouse":"restricted"}}')]
        self.rows['Warehouse'] = [Row(name='restricted')]
        with patch.object(self.permissions, 'capabilities', return_value={'jobs'}), \
                patch.object(self.permissions, 'companies', return_value=[Row(name='Synthetic company')]), \
                patch.object(self.permissions, 'profile', return_value=True):
            condition = self.permissions.query_conditions(doctype='Knitting Event')
        self.assertIn('visible-event', condition)
        self.assertNotIn('hidden-event', condition)
        self.assertIn('migration_delivery_reference', condition)
        self.frappe.get_doc.assert_not_called()
        self.frappe.db.exists.assert_not_called()

    def test_roll_count_is_not_an_identifier_list_but_real_roll_lists_are_checked(self):
        for count in ('7', 7):
            event = Row(doctype='Knitting Event', payload='{}', result={'rolls': count})
            self.assertTrue(self.permissions.source_scope(event))
        event = Row(doctype='Knitting Event', payload='{}', result={'rolls': ['restricted-roll']})
        self.assertFalse(self.permissions.source_scope(event))

    def test_thousand_jobs_use_one_permission_list_per_link_type(self):
        self.rows['Knitting Job'] = [Row(name=f'job-{index}', customer='visible') for index in range(1000)]
        self.visible['Knitting Job'] = [row.name for row in self.rows['Knitting Job']]
        self.permissions.require_aggregate_scope('Synthetic company')
        self.assertEqual(self.frappe.get_list.call_count, 2)
        self.assertEqual(self.frappe.get_all.call_count, 5)

    def test_missing_event_never_becomes_a_complete_reconciliation(self):
        with self.assertRaises(self.permissions.SourceReconciliationError):
            self.permissions.require_event_sources([Row(name='missing-event')])

    def test_generic_lists_check_billing_customer_and_batch_links(self):
        with patch.object(self.permissions, 'capabilities', return_value={'jobs'}), \
                patch.object(self.permissions, 'companies', return_value=[Row(name='Synthetic company')]), \
                patch.object(self.permissions, 'profile', return_value=True), \
                patch.object(self.frappe, 'get_meta', return_value=SimpleNamespace(
                    has_field=lambda field: field in {'batch', 'billing_customer'})):
            condition = self.permissions.query_conditions(doctype='Knitting Ledger Entry')
        self.assertIn('`billing_customer` in (\'visible\')', condition)
        self.assertIn('`batch` in (NULL)', condition)

    def test_thousand_batch_origins_load_events_once_and_scope_each_users_sources(self):
        self.rows['Knitting Fabric Batch'] = [Row(name=f'batch-{n}', company='Synthetic company',
            job='job-1', production=f'event-{n}') for n in range(1000)]
        self.rows['Knitting Event'] = [Row(name=f'event-{n}', company='Synthetic company', job='job-1',
            kind='produce_batch', payload={'inputs': [{'lot': 'lot-1'}]}, result={
                'batch': f'batch-{n}', 'batch_snapshot': {'name': f'batch-{n}', 'production': f'event-{n}',
                    'job': 'job-1', 'machine': 'machine-1'}}) for n in range(1000)]
        self.rows['Knitting Machine'] = [Row(name='machine-1')]
        self.rows['Knitting Material Lot'] = [Row(name='lot-1')]
        self.visible.update({'Knitting Machine': ['machine-1'], 'Knitting Material Lot': ['lot-1']})
        with self.permissions.snapshot_link_checks():
            rows = self.permissions._source_rows('Knitting Fabric Batch', {})
            self.assertTrue(all(self.permissions.source_scope(row) for row in rows))
            self.assertFalse(self.permissions.source_scope(rows[0], 'other'))
        event_queries = [call for call in self.frappe.get_all.call_args_list if call.args[0] == 'Knitting Event']
        self.assertEqual(len(event_queries), 1)
        self.assertLessEqual(self.frappe.get_all.call_count, 6)
        self.assertLessEqual(self.frappe.get_list.call_count, 4)
        self.frappe.get_doc.assert_not_called()
        self.frappe.db.exists.assert_not_called()
        self.visible['Knitting Machine'] = []
        with self.permissions.snapshot_link_checks():
            self.assertFalse(self.permissions.source_scope(rows[0]))


if __name__ == '__main__':
    unittest.main()
