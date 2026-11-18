"""Review regressions: schema-only audit preservation and linked machine scope."""
import hashlib
from unittest.mock import patch

import frappe

from erp_extensions.knitting import api, domain, install, permissions, reports
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests import test_knitting_batch_production as batches


class AggregateReviewTests(batches.BatchProductionTests):
    def test_lost_persisted_batch_origin_rolls_back_production(self):
        payload = self.prepare()
        events = frappe.db.count('Knitting Event', {'job': self.job})
        original = domain.insert
        def lose_origin(doctype, **values):
            doc = original(doctype, **values)
            if doctype == 'Knitting Fabric Batch':
                frappe.db.set_value(doctype, doc.name, 'production', None)
            return doc
        with patch.object(domain, 'insert', side_effect=lose_origin), self.assertRaises(frappe.ValidationError):
            self.post_batch(payload)
        self.assertFalse(frappe.db.exists('Knitting Fabric Batch', {'job': self.job}))
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), events)
        self.assertEqual(domain.lot_balance(self.lot, self.job), 90)

    def test_batch_provenance_rejects_missing_mismatched_and_denied_input_sources(self):
        result = self.post_batch()
        batch, event = result['data']['batch'], result['event']
        source = frappe.get_doc('Knitting Event', event)
        original = frappe.parse_json(source.result)
        cases = [
            ('Knitting Fabric Batch', batch, 'production', 'missing-synthetic-event', event),
            ('Knitting Event', event, 'company', 'Different synthetic company', source.company),
            ('Knitting Event', event, 'job', 'Different synthetic job', source.job),
            ('Knitting Event', event, 'kind', 'review_batch', source.kind),
            ('Knitting Event', event, 'result', '{}', source.result),
            ('Knitting Event', event, 'result', frappe.as_json({**original, 'batch': 'different-batch'}), source.result),
            ('Knitting Event', event, 'result', frappe.as_json({**original, 'batch_snapshot': {
                **original['batch_snapshot'], 'production': 'different-event'}}), source.result),
        ]
        frappe.set_user('knit-accountant@example.invalid')
        for doctype, name, field, broken, valid in cases:
            with self.subTest(field=field, broken=broken):
                frappe.db.set_value(doctype, name, field, broken)
                try:
                    self.assertFalse(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
                    self.assertNotIn(batch, frappe.get_list('Knitting Fabric Batch', pluck='name'))
                finally:
                    frappe.db.set_value(doctype, name, field, valid)
        # A captured imported balance without a producing event retains its existing read contract.
        frappe.db.set_value('Knitting Fabric Batch', batch, 'production', None)
        self.assertFalse(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
        frappe.db.set_value('Knitting Fabric Batch', batch, {'source_record': 'SYNTHETIC-ORIGINAL-CAPTURE',
            'source_reference': 'Synthetic original batch', 'captured_at': '2026-11-01 09:00:00'})
        self.assertTrue(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
        self.assertIn(batch, frappe.get_list('Knitting Fabric Batch', pluck='name'))
        frappe.db.set_value('Knitting Fabric Batch', batch, 'production', event)
        frappe.set_user('Administrator')
        other_lot = self.receive('1')
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-accountant@example.invalid',
            'allow': 'Knitting Material Lot', 'for_value': other_lot, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-accountant@example.invalid')
        self.assertFalse(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
        self.assertNotIn(batch, frappe.get_list('Knitting Fabric Batch', pluck='name'))

    def test_unexpected_cross_batch_source_cycle_fails_closed_without_stale_cache(self):
        payload = self.prepare()
        payload.update(quantity_kg='44', rolls='3', loss_kg='1', inputs=[{'lot': self.lot, 'quantity_kg': '45', 'units': '1'}])
        first, second = self.post_batch(payload), self.post_batch(payload)
        self.assertNotEqual(first['event'], second['event'])
        self.assertNotEqual(first['data']['batch'], second['data']['batch'])
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', first['data']['batch'], 'production'), first['event'],
            {'meta': frappe.get_meta('Knitting Fabric Batch').has_field('production'),
             'valid_column': 'production' in frappe.get_doc('Knitting Fabric Batch', first['data']['batch']).get_valid_columns()})
        originals = {entry['event']: frappe.db.get_value('Knitting Event', entry['event'], 'payload') for entry in (first, second)}
        for entry, other in ((first, second), (second, first)):
            frappe.db.set_value('Knitting Event', entry['event'], 'payload', frappe.as_json({**payload, 'batch': other['data']['batch']}))
        frappe.set_user('knit-accountant@example.invalid')
        for entry in (first, second):
            doc = frappe.get_doc('Knitting Fabric Batch', entry['data']['batch'])
            self.assertFalse(frappe.has_permission('Knitting Fabric Batch', 'read', doc=doc))
            self.assertFalse(permissions.source_scope(doc))
            self.assertNotIn(entry['data']['batch'], frappe.get_list('Knitting Fabric Batch', pluck='name'))
        for event, payload_json in originals.items():
            frappe.db.set_value('Knitting Event', event, 'payload', payload_json)
        visible = frappe.get_list('Knitting Fabric Batch', pluck='name')
        for entry in (first, second):
            self.assertIn(entry['data']['batch'], visible)

    def test_denied_machine_cannot_review_batch_or_change_its_state(self):
        payload = self.prepare()
        allowed, denied = self.machine(), self.machine()
        result = self.post_batch({**payload, 'machine': denied})
        batch = result['data']['batch']
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-checker@example.invalid',
            'allow': 'Knitting Machine', 'for_value': allowed, 'apply_to_all_doctypes': 1}).insert()
        count = frappe.db.count('Knitting Event', {'job': self.job})
        frappe.set_user('knit-checker@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.call('review_batch', {'job': self.job, 'batch': batch, 'decision': 'Released', 'remarks': 'No access'})
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', batch, 'state'), 'Awaiting review')
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), count)

    def test_machine_restriction_denies_direct_batch_and_delivery_without_changes(self):
        payload = self.prepare()
        allowed, denied = self.machine(), self.machine()
        result = self.post_batch({**payload, 'machine': denied})
        batch = result['data']['batch']
        self.call('review_batch', {'job': self.job, 'batch': batch, 'decision': 'Released', 'remarks': 'Checked'})
        restriction = frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-accountant@example.invalid',
            'allow': 'Knitting Machine', 'for_value': allowed, 'apply_to_all_doctypes': 1}).insert()
        before = frappe.db.get_value('Knitting Fabric Batch', batch, ['quantity_kg', 'rolls', 'state'])
        events = frappe.db.count('Knitting Event', {'job': self.job})
        frappe.set_user('knit-accountant@example.invalid')
        with self.subTest(path='direct'):
            self.assertFalse(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
        with self.subTest(path='native list'):
            self.assertNotIn(batch, frappe.get_list('Knitting Fabric Batch', pluck='name'))
        with self.subTest(path='register'):
            self.assertNotIn(batch, [row.name for row in api.register(fixtures.COMPANY, 'batches', job=self.job)['rows']])
        with self.subTest(path='snapshot'), self.assertRaises(frappe.PermissionError):
            api.snapshot(fixtures.COMPANY, self.job)
        with self.subTest(path='delivery'), self.assertRaises(frappe.PermissionError):
            self.call('deliver_batch', {'job': self.job, 'batch': batch, 'quantity_kg': '10', 'rolls': '1'})
        self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', batch, ['quantity_kg', 'rolls', 'state']), before)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job}), events)
        frappe.set_user('Administrator')
        restriction.for_value = denied
        restriction.save()
        frappe.set_user('knit-accountant@example.invalid')
        self.assertTrue(frappe.has_permission('Knitting Fabric Batch', 'read', doc=frappe.get_doc('Knitting Fabric Batch', batch)))
        self.assertIn(batch, frappe.get_list('Knitting Fabric Batch', pluck='name'))
        self.assertEqual(self.call('deliver_batch', {'job': self.job, 'batch': batch, 'quantity_kg': '10', 'rolls': '1'})['data']['quantity_kg'], '10.000')

    def test_period_production_reversal_uses_producer_and_audit_keeps_corrector(self):
        payload = self.prepare()
        producer = 'knit-operator@example.invalid'
        frappe.set_user(producer)
        result = self.post_batch(payload)
        frappe.set_user('Administrator')
        correction = self.call('cancel_event', {'job': self.job, 'event': result['event'], 'reason': 'Wrong measurement'})
        frappe.db.set_value('Knitting Event', result['event'], 'occurred_at', '2026-11-05 09:00:00')
        frappe.db.set_value('Knitting Event', correction['event'], 'occurred_at', '2026-11-07 09:00:00')
        for first, last, expected in (('05', '05', '88.000'), ('07', '07', '-88.000'), ('05', '07', '0.000')):
            filters = {'job': self.job, 'mode': 'period', 'from_date': '2026-11-' + first, 'to_date': '2026-11-' + last}
            with self.subTest(first=first, last=last):
                self.assertEqual(reports.run(fixtures.COMPANY, 'production', {**filters, 'operator': producer})['summary']['quantity_kg'], expected)
                self.assertEqual(reports.run(fixtures.COMPANY, 'production', {**filters, 'operator': 'Administrator'})['row_count'], 0)
        audit = reports.run(fixtures.COMPANY, 'activity', {**filters, 'operator': 'Administrator', 'kind': 'cancel_event'})
        self.assertEqual([(row['event'], row['operator']) for row in audit['rows']], [(correction['event'], 'Administrator')])
        self.assertEqual(frappe.db.get_value('Knitting Event', correction['event'], 'actor'), 'Administrator')

    def test_real_old_schema_upgrade_preserves_all_versions_and_business_rows(self):
        if frappe.local.site != 'native-test.localhost':
            raise RuntimeError('Schema regression requires the synthetic native test site')
        doc = frappe.get_doc('DocType', 'Knitting Fabric Batch')
        original_fields = [field.as_dict() for field in doc.fields]
        audit = frappe.get_doc({'doctype': 'Version', 'ref_doctype': 'Knitting Fabric Batch',
            'docname': 'SYNTHETIC-OLD-SCHEMA-UPGRADE-AUDIT', 'data': '{}'}).insert()
        version_names = set(frappe.get_all('Version', pluck='name'))
        tables = [*install.SCHEMAS, 'Customer', 'Item', 'Warehouse', 'Stock Entry', 'Stock Entry Detail',
            'Stock Ledger Entry', 'GL Entry', 'Sales Invoice', 'Sales Invoice Item', 'Payment Entry',
            'Payment Entry Reference', 'Journal Entry', 'Journal Entry Account', 'Purchase Invoice',
            'Purchase Invoice Item', 'Delivery Note', 'Delivery Note Item', 'Quotation', 'Quotation Item',
            'Purchase Order', 'Purchase Order Item', 'Purchase Receipt', 'Purchase Receipt Item']
        def snapshot(doctype):
            rows = frappe.db.sql(f'select * from `tab{doctype}` order by name')
            return (len(rows), hashlib.sha256(frappe.as_json(rows).encode()).hexdigest())
        try:
            # Persist genuinely older metadata; do not mock the changed upgrade path.
            doc.set('fields', [field for field in original_fields if field['fieldname'] not in ('production', 'warehouse')])
            next(field for field in doc.fields if field.fieldname == 'state').options = 'Awaiting review\nReleased\nOn Hold'
            doc.save(ignore_version=True)
            frappe.clear_cache(doctype=doc.name)
            old = frappe.get_meta(doc.name)
            self.assertFalse(old.has_field('production'))
            self.assertFalse(old.has_field('warehouse'))
            self.assertNotIn('Cancelled', old.get_field('state').options)
            before_versions = snapshot('Version')
            before_business = {table: snapshot(table) for table in tables}
            # Production default, irrespective of the test runner's global flag.
            with patch.object(frappe, 'in_test', False):
                self.assertTrue(install.upgrade_batch_production_schema()['changed'])
                self.assertFalse(install.upgrade_batch_production_schema()['changed'])
            self.assertEqual(snapshot('Version'), before_versions, 'Schema-only upgrade must not add, change or delete audit rows')
            self.assertEqual({table: snapshot(table) for table in tables}, before_business)
            current = frappe.get_meta(doc.name)
            self.assertEqual(current.get_field('production').options, 'Knitting Event')
            self.assertEqual(current.get_field('warehouse').options, 'Warehouse')
            self.assertIn('Cancelled', current.get_field('state').options.splitlines())
            self.assertTrue(frappe.db.exists('Version', audit.name))
            # The real changed=True path must preserve provenance on the very next insert.
            result = self.post_batch()
            self.assertEqual(frappe.db.get_value('Knitting Fabric Batch', result['data']['batch'], 'production'), result['event'])
            frappe.db.rollback()
        finally:
            # DocType schema synchronization commits; restore only this test's metadata/audit changes.
            frappe.set_user('Administrator')
            restored = frappe.get_doc('DocType', 'Knitting Fabric Batch')
            # Removed DocFields were recreated under new row names by the upgrade.
            names = {field.fieldname: field.name for field in restored.fields}
            restored.set('fields', [{**field, 'name': names.get(field['fieldname'])} for field in original_fields])
            restored.save(ignore_version=True)
            frappe.clear_cache(doctype=restored.name)
            added = set(frappe.get_all('Version', filters={'ref_doctype': 'DocType',
                'docname': 'Knitting Fabric Batch'}, pluck='name')) - version_names
            for name in {*added, audit.name}:
                frappe.db.delete('Version', {'name': name})
            frappe.db.commit()
            self.assertTrue(frappe.get_meta(restored.name).has_field('production'))

    def test_machine_restriction_hides_batch_event_reports_and_guided_cohorts(self):
        payload = self.prepare()
        allowed, denied = self.machine(), self.machine()
        result = self.post_batch({**payload, 'machine': denied})
        restriction = frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-accountant@example.invalid',
            'allow': 'Knitting Machine', 'for_value': allowed, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-accountant@example.invalid')
        self.assertTrue(permissions.link_visible('Knitting Machine', allowed))
        self.assertFalse(permissions.link_visible('Knitting Machine', denied))
        event = frappe.get_doc('Knitting Event', result['event'])
        self.assertFalse(frappe.has_permission('Knitting Event', 'read', doc=event))
        self.assertFalse(permissions.source_scope(frappe._dict(doctype='Knitting Plan', machine=denied)))
        self.assertNotIn(result['event'], [row.name for row in api.register(fixtures.COMPANY, 'events', job=self.job)['rows']])
        for report in ('fabric', 'production'):
            with self.subTest(report=report), self.assertRaises(frappe.PermissionError):
                reports.run(fixtures.COMPANY, report, {'job': self.job})
        with self.assertRaises(frappe.PermissionError):
            api.snapshot(fixtures.COMPANY, self.job)
        frappe.set_user('Administrator')
        restriction.for_value = denied
        restriction.save()
        frappe.set_user('knit-accountant@example.invalid')
        self.assertTrue(frappe.has_permission('Knitting Event', 'read', doc=event))
        self.assertEqual(reports.run(fixtures.COMPANY, 'fabric', {'job': self.job})['summary']['quantity_kg'], '88.000')
        self.assertEqual(api.snapshot(fixtures.COMPANY, self.job)['jobs'][0]['workflow']['batch_inspection'],
            {'count': 1, 'only': result['data']['batch']})


for name in vars(batches.BatchProductionTests):
    if name.startswith('test_'):
        setattr(AggregateReviewTests, name, None)
