"""Lost-response recovery on synthetic records, including real connection races."""
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from threading import Event
import importlib
from unittest.mock import patch

import frappe
from erp_extensions import api
from erp_extensions.tests import test_native_api as native
from erp_extensions.tests import test_knitting as knitting
from erp_extensions.tests import test_invoice_hub as invoice_hub


def _assert_legacy_commit_cannot_be_prepared(test, company, kind, request, perform, action=None):
    """A real legacy writer and preparation must serialize before deciding absence."""
    from erp_extensions import operations
    user = frappe.session.user
    frappe.db.commit()
    saved, release = Event(), Event()

    def legacy_write():
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect(); frappe.set_user(user)
        try:
            result = perform()
            saved.set()
            if not release.wait(20):
                raise RuntimeError('Concurrent preparation did not start')
            frappe.db.commit()
            return result
        finally:
            frappe.db.rollback(); frappe.destroy()

    def prepare():
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect(); frappe.set_user(user)
        try:
            operations.begin_operation(company, kind, request, action=action)
            frappe.db.commit()
            return False
        except frappe.ValidationError:
            frappe.db.rollback()
            return True
        finally:
            frappe.destroy()

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            posting = pool.submit(legacy_write)
            test.assertTrue(saved.wait(20))
            preparing = pool.submit(prepare)
            with test.assertRaises(TimeoutError):
                preparing.result(timeout=0.15)
            release.set()
            result = posting.result(timeout=30)
            test.assertTrue(preparing.result(timeout=30), 'A legacy receipt must prevent a fresh prepared journal')
        frappe.db.rollback()
        with test.assertRaises(frappe.ValidationError):
            operations.begin_operation(company, kind, request, action=action)
        test.assertFalse(frappe.db.exists(operations.DOCTYPE, operations._key(company, request)))
        test.assertEqual(perform(), result, 'The original legacy replay must remain available')
        # Defense for a prepared row created by the old implementation after a legacy save.
        frappe.get_doc({'doctype': operations.DOCTYPE, 'request_key': operations._key(company, request),
                        'request_id': request, 'actor': user, 'company': company, 'kind': kind,
                        'action': action or '', 'state': 'prepared'}).insert(ignore_permissions=True)
        with test.assertRaises(frappe.ValidationError):
            operations.close_operation(company, request)
        test.assertEqual(operations.operation_status(company, request)['state'], 'prepared')
    finally:
        release.set()


class OperationTests(native.NativeApiTests):
    company = 'ERP Native Verification'

    def operations(self):
        try:
            module = importlib.import_module('erp_extensions.operations')
        except ModuleNotFoundError:
            module = None
        self.assertTrue(module and callable(getattr(module, 'begin_operation', None)),
                        'Durable operation recovery is not implemented')
        module.install()
        return module

    def begin(self, request=None, **kwargs):
        request = request or 'operation-' + frappe.generate_hash(length=24)
        self.operations().begin_operation(self.company, 'native_save', request,
                                         doctype=native.TYPE, action='Save', **kwargs)
        return request

    def draft(self, title='Recovery record'):
        return {'doctype': native.TYPE, '__islocal': 1, 'title': title, 'amount': 12.5}

    def test_prepared_reference_is_discoverable_and_close_seals_delayed_write(self):
        request = self.begin()
        ops = self.operations()
        self.assertEqual(ops.operation_status(self.company, request)['state'], 'prepared')
        pending = ops.pending_operations(self.company)
        self.assertIn(request, [row['request_id'] for row in pending['rows']])
        self.assertEqual(ops.close_operation(self.company, request)['state'], 'closed')
        self.assertEqual(ops.close_operation(self.company, request)['state'], 'closed')
        with self.assertRaises(frappe.ValidationError):
            api.save(self.draft(), request_id=request, company=self.company)
        self.assertFalse(frappe.db.exists(native.TYPE, {'title': 'Recovery record'}))
        ops.acknowledge_operation(self.company, request)
        self.assertNotIn(request, [row['request_id'] for row in ops.pending_operations(self.company)['rows']])

    def test_lost_create_response_replays_once_and_changed_payload_is_rejected(self):
        request = self.begin()
        values = self.draft('One recovered create')
        first = api.save(values, request_id=request, company=self.company)
        replay = api.save(values, request_id=request, company=self.company)
        self.assertEqual(first['doc']['name'], replay['doc']['name'])
        self.assertEqual(frappe.db.count(native.TYPE, {'title': values['title']}), 1)
        status = self.operations().operation_status(self.company, request)
        self.assertEqual(status['state'], 'completed')
        self.assertEqual(status['result']['doc']['name'], first['doc']['name'])
        stored = frappe.db.get_value('Workspace Operation', {'request_id': request}, 'receipt')
        self.assertEqual(frappe.parse_json(stored), {'name': first['doc']['name']})
        with self.assertRaises(frappe.ValidationError):
            api.save({**values, 'amount': 13}, request_id=request, company=self.company)
        self.assertEqual(self.operations().close_operation(self.company, request)['state'], 'completed')

    def test_edit_replay_precedes_stale_version_check_and_status_reads_current_permissions(self):
        doc = api.save(self.draft('Original'))['doc']
        request = self.begin(name=doc['name'])
        values = {**doc, 'title': 'Changed'}
        result = api.save(values, request_id=request, company=self.company)
        self.assertEqual(api.save(values, request_id=request, company=self.company)['doc']['name'], doc['name'])
        self.assertEqual(result['doc']['title'], 'Changed')
        self.assertNotEqual(str(result['doc']['modified']), str(doc['modified']))

    def test_rollback_does_not_leave_a_false_completed_receipt(self):
        request = self.begin()
        frappe.db.savepoint('before_recovery_mutation')
        api.save(self.draft('Rolled back'), request_id=request, company=self.company)
        frappe.db.rollback(save_point='before_recovery_mutation')
        self.assertEqual(self.operations().operation_status(self.company, request)['state'], 'prepared')
        self.assertFalse(frappe.db.exists(native.TYPE, {'title': 'Rolled back'}))

    def test_workflow_transition_recovers_without_reapplying_old_version(self):
        doc = api.save({'doctype': native.APPROVAL, '__islocal': 1, 'title': 'Recovery approval'})['doc']
        request = 'workflow-' + frappe.generate_hash(length=24)
        ops = self.operations()
        ops.begin_operation(self.company, 'native_transition', request, doctype=native.APPROVAL,
                            name=doc['name'], action='Native Approve')
        result = api.transition(native.APPROVAL, doc['name'], 'Native Approve', doc['modified'],
                                request_id=request, company=self.company)
        replay = api.transition(native.APPROVAL, doc['name'], 'Native Approve', doc['modified'],
                                request_id=request, company=self.company)
        self.assertEqual(result['doc']['workflow_state'], 'Native Approved')
        self.assertEqual(replay['doc']['workflow_state'], 'Native Approved')
        self.assertEqual(ops.operation_status(self.company, request)['state'], 'completed')

    def test_revoked_link_scope_hides_completed_result_and_blocks_replay(self):
        ops = self.operations()
        email = 'operation-scope-' + frappe.generate_hash(length=12) + '@example.invalid'
        frappe.get_doc({'doctype': 'User', 'email': email, 'first_name': 'Recovery scope', 'send_welcome_email': 0,
                        'roles': [{'role': 'System Manager'}]}).insert()
        request = 'scope-' + frappe.generate_hash(length=24)
        values = {**self.draft('Protected record'), 'warehouse': self.denied_warehouse}
        frappe.set_user(email)
        ops.begin_operation(self.company, 'native_save', request, doctype=native.TYPE, action='Save')
        result = api.save(values, request_id=request, company=self.company)
        self.assertEqual(ops.operation_status(self.company, request)['result']['doc']['name'], result['doc']['name'])
        frappe.set_user('Administrator')
        frappe.get_doc({'doctype': 'User Permission', 'user': email, 'allow': 'Warehouse',
                        'for_value': self.allowed_warehouse, 'apply_to_all_doctypes': 0,
                        'applicable_for': native.TYPE}).insert()
        frappe.set_user(email)
        self.assertEqual(ops.pending_operations(self.company)['rows'], [])
        with self.assertRaises(frappe.PermissionError):
            ops.operation_status(self.company, request)
        with self.assertRaises(frappe.PermissionError):
            api.save(values, request_id=request, company=self.company)
        frappe.cache.hdel('user_permissions', email)

    def test_different_user_company_and_changed_kind_cannot_recover_reference(self):
        request = self.begin()
        ops = self.operations()
        with self.assertRaises(frappe.ValidationError):
            ops.begin_operation(self.company, 'native_transition', request, doctype=native.TYPE, name='other', action='Approve')
        with self.assertRaises(frappe.PermissionError):
            ops.operation_status('Missing company', request)
        frappe.set_user('native-reader@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            ops.operation_status(self.company, request)

    def test_same_request_id_has_distinct_site_user_and_company_keys(self):
        ops = self.operations()
        request = 'scoped-reference-123456'
        keys = {ops._key(self.company, request)}
        with patch.object(frappe.local, 'site', 'second-synthetic.invalid'):
            keys.add(ops._key(self.company, request))
        with patch.dict(frappe.session, {'user': 'second-user@example.invalid'}):
            keys.add(ops._key(self.company, request))
        keys.add(ops._key('Other synthetic business', request))
        self.assertEqual(len(keys), 4)

    def test_non_atomic_native_controllers_opt_out_without_changing_legacy_saves(self):
        ops = self.operations()
        for doctype in ('User', 'Employee', 'Payment Reconciliation'):
            schema = api.schema(doctype)
            self.assertFalse(schema.get('operation_recovery_supported', True), doctype)
            self.assertTrue(schema.get('operation_recovery_reason'))
        for doctype in ('Customer', 'Sales Invoice'):
            self.assertTrue(api.schema(doctype)['operation_recovery_supported'], doctype)
        request = 'unsafe-controller-' + frappe.generate_hash(length=16)
        with self.assertRaises(frappe.ValidationError):
            ops.begin_operation(self.company, 'native_save', request, doctype='User')
        # An old prepared reference must not bypass the newer capability boundary.
        frappe.get_doc({'doctype': ops.DOCTYPE, 'request_key': ops._key(self.company, request),
                        'request_id': request, 'actor': frappe.session.user, 'company': self.company,
                        'kind': 'native_save', 'action': 'Save', 'document_type': 'User',
                        'state': 'prepared'}).insert(ignore_permissions=True)
        self.assertNotIn(request, [row['request_id'] for row in ops.pending_operations(self.company)['rows']])
        with self.assertRaises(frappe.ValidationError):
            ops.operation_status(self.company, request)
        email = 'ux-legacy-' + frappe.generate_hash(length=12) + '@example.invalid'
        values = {'doctype': 'User', '__islocal': 1, 'email': email, 'first_name': 'Legacy synthetic user',
                  'send_welcome_email': 0, 'user_type': 'Website User'}
        with self.assertRaises(frappe.ValidationError):
            api.save(values, request_id=request, company=self.company)
        self.assertFalse(frappe.db.exists('User', email))
        self.assertEqual(api.save(values)['doc']['name'], email)

    def test_status_and_close_wait_for_commit_in_another_connection(self):
        request = self.begin()
        ops = self.operations()
        frappe.db.commit()
        posted, release = Event(), Event()
        name = None

        def post():
            frappe.init(site='native-test.localhost', sites_path='.')
            frappe.connect(); frappe.set_user('Administrator')
            try:
                result = api.save(self.draft('Concurrent receipt'), request_id=request, company=self.company)
                posted.set()
                if not release.wait(20):
                    raise RuntimeError('Concurrent close did not start')
                frappe.db.commit()
                return result['doc']['name']
            finally:
                frappe.db.rollback(); frappe.destroy()

        def close():
            frappe.init(site='native-test.localhost', sites_path='.')
            frappe.connect(); frappe.set_user('Administrator')
            try:
                result = ops.close_operation(self.company, request)
                frappe.db.commit()
                return result
            finally:
                frappe.db.rollback(); frappe.destroy()

        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                write = pool.submit(post)
                self.assertTrue(posted.wait(20))
                closing = pool.submit(close)
                with self.assertRaises(TimeoutError):
                    closing.result(timeout=0.15)
                release.set()
                name = write.result(timeout=30)
                result = closing.result(timeout=30)
            self.assertEqual(result['state'], 'completed')
            self.assertEqual(result['result']['doc']['name'], name)
        finally:
            release.set()
            frappe.db.rollback()
            if name:
                frappe.delete_doc(native.TYPE, name, force=True)
            frappe.db.delete('Workspace Operation', {'request_id': request})
            frappe.db.commit()

    def test_committed_close_blocks_a_mutation_already_waiting_for_its_lock(self):
        request = self.begin()
        ops = self.operations()
        frappe.db.commit()
        ops.close_operation(self.company, request)

        def delayed_post():
            frappe.init(site='native-test.localhost', sites_path='.')
            frappe.connect(); frappe.set_user('Administrator')
            try:
                api.save(self.draft('Must not post'), request_id=request, company=self.company)
                frappe.db.commit()
                return 'posted'
            except frappe.ValidationError:
                frappe.db.rollback()
                return 'closed'
            finally:
                frappe.db.rollback(); frappe.destroy()

        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                write = pool.submit(delayed_post)
                with self.assertRaises(TimeoutError):
                    write.result(timeout=0.15)
                frappe.db.commit()
                self.assertEqual(write.result(timeout=30), 'closed')
            self.assertFalse(frappe.db.exists(native.TYPE, {'title': 'Must not post'}))
        finally:
            frappe.db.rollback()
            frappe.db.delete('Workspace Operation', {'request_id': request})
            frappe.db.commit()


for name in list(vars(native.NativeApiTests)):
    if name.startswith('test_'):
        setattr(OperationTests, name, None)


class KnittingOperationTests(knitting.KnittingTests):
    def test_legacy_knitting_commit_rejects_preparation_and_false_close(self):
        from erp_extensions import operations
        from erp_extensions.knitting import api as commands
        operations.install()
        self.fixtures()
        request = 'legacy-knitting-' + frappe.generate_hash(length=24)
        payload = {'job': self.job, 'item': self.items['yarn'], 'quantity_kg': '3.000',
                   'material_owner': 'Customer', 'party': self.customer, 'warehouse': self.warehouse}
        modified = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        _assert_legacy_commit_cannot_be_prepared(self, knitting.COMPANY, 'knitting', request,
            lambda: commands.command(knitting.COMPANY, 'receive_yarn', payload, request, modified), 'receive_yarn')

    def test_knitting_receipt_is_discoverable_and_replayed_without_posting_again(self):
        from erp_extensions import operations
        from erp_extensions.knitting import api as commands
        operations.install()
        self.fixtures()
        request = 'knitting-operation-' + frappe.generate_hash(length=24)
        payload = {'job': self.job, 'item': self.items['yarn'], 'quantity_kg': '3.000',
                   'material_owner': 'Customer', 'party': self.customer, 'warehouse': self.warehouse}
        modified = str(frappe.db.get_value('Knitting Job', self.job, 'modified'))
        operations.begin_operation(knitting.COMPANY, 'knitting', request, action='receive_yarn')
        result = commands.command(knitting.COMPANY, 'receive_yarn', payload, request, modified)
        self.assertEqual(commands.command(knitting.COMPANY, 'receive_yarn', payload, request, modified), result)
        self.assertEqual(operations.operation_status(knitting.COMPANY, request)['result'], result)
        self.assertEqual(frappe.db.count('Knitting Event', {'job': self.job, 'kind': 'receive_yarn'}), 1)
        with self.assertRaises(frappe.ValidationError):
            commands.command(knitting.COMPANY, 'receive_yarn', {**payload, 'quantity_kg': '4.000'}, request, modified)


for name in list(vars(knitting.KnittingTests)):
    if name.startswith('test_'):
        setattr(KnittingOperationTests, name, None)


class InvoiceOperationTests(invoice_hub.InvoiceHubTests):
    def test_legacy_invoice_commit_rejects_preparation_and_false_close(self):
        from frappe.utils import today
        from erp_extensions import invoice_compose, operations
        frappe.set_user('Administrator')
        operations.install()
        frappe.set_user(self.owner)
        values = {'company': self.company, 'customer': self.customer.name, 'posting_date': today(),
                  'due_date': today(), 'items': [{'item_code': self.item.name, 'qty': '1', 'rate': '100'}],
                  'template_id': 'ledger'}
        preview = invoice_compose.preview(**values)
        request = frappe.generate_hash(length=32)
        _assert_legacy_commit_cannot_be_prepared(self, self.company, 'invoice', request,
            lambda: invoice_compose.save_draft(**values, request_id=request, review=preview['review']))


for name in list(vars(invoice_hub.InvoiceHubTests)):
    if name.startswith('test_'):
        setattr(InvoiceOperationTests, name, None)
