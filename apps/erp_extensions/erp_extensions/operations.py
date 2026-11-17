"""Durable, scoped operation references. Draft payloads are never stored here."""
from hashlib import sha256
import json
import re

import frappe
from frappe.utils import cint

from erp_extensions.knitting.permissions import company_allowed

DOCTYPE = 'Workspace Operation'
KINDS = {'native_save', 'native_transition', 'invoice', 'knitting', 'reconciliation'}
LEGACY_RECEIPT_KINDS = {'invoice', 'knitting'}
# These upstream save controllers can commit sessions or schema changes themselves.
# Preserve their original save behavior; a journal cannot make those writes atomic.
NON_ATOMIC_NATIVE_TYPES = {
    'User', 'Role', 'Employee', 'DocType', 'Custom Field', 'Workflow',
    'Permission Type', 'Domain Settings', 'CRM Settings', 'Inventory Dimension',
    'Service Level Agreement',
}


def native_recovery_reason(meta):
    if meta.is_virtual or meta.name in NON_ATOMIC_NATIVE_TYPES:
        return 'This record saves in separate steps. Check its current state after an interrupted save.'
    return None


def install():
    frappe.only_for('System Manager')
    if frappe.db.exists('DocType', DOCTYPE):
        return
    from erp_extensions.knitting.install import field
    frappe.get_doc({'doctype': 'DocType', 'name': DOCTYPE, 'module': 'Custom', 'custom': 1,
        'autoname': 'field:request_key', 'fields': [
            field('request_key', reqd=1, unique=1), field('request_id', reqd=1),
            field('actor', 'Link', 'User', reqd=1), field('company', 'Link', 'Company', reqd=1),
            field('kind', reqd=1), field('action'), field('document_type'), field('document_name'),
            field('state', 'Select', 'prepared\ncompleted\nclosed', reqd=1), field('payload_digest'),
            field('receipt', 'JSON'), field('acknowledged', 'Check')],
        'permissions': [{'role': 'System Manager', 'read': 1}]}).insert()


def available():
    return bool(frappe.db.exists('DocType', DOCTYPE))


def _company(company):
    if frappe.session.user == 'Guest' or not company_allowed(company):
        frappe.throw('This account cannot recover operations in that business.', frappe.PermissionError)


def _key(company, request_id):
    if not isinstance(request_id, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{8,128}', request_id):
        frappe.throw('A valid operation reference is required.')
    return _digest([frappe.local.site, frappe.session.user, company, request_id])


def _digest(value):
    try:
        return sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                 allow_nan=False, default=str).encode()).hexdigest()
    except (TypeError, ValueError):
        frappe.throw('Use finite, supported values in the reviewed entry.')


def _load(company, request_id, *, optional=False):
    _company(company)
    key = _key(company, request_id)
    if optional and not available():
        return None
    row = frappe.db.get_value(DOCTYPE, key, '*', as_dict=True, for_update=True)
    if not row and not optional:
        frappe.throw('This operation reference is unavailable for this account and business.', frappe.PermissionError)
    return row


def _lock_legacy_scope(company, kind):
    """Use the original controller's lock before the journal, even for old callers."""
    if kind not in LEGACY_RECEIPT_KINDS:
        return
    _company(company)
    if kind == 'invoice':
        frappe.db.get_value('Company', company, 'name', for_update=True)
    else:
        frappe.db.get_value('Workspace Industry Setup', {'company': company}, 'name', for_update=True)


def _reject_legacy_receipt(company, kind, request_id):
    if kind == 'invoice':
        from erp_extensions import invoice_compose
        key = invoice_compose._digest([frappe.session.user, company, request_id])
        found = frappe.db.get_value(invoice_compose.RECEIPT, key, 'name', for_update=True)
    elif kind == 'knitting':
        from erp_extensions.knitting.api import request_key
        found = frappe.db.get_value('Knitting Event', {'request_key': request_key(company, request_id)},
                                    'name', for_update=True)
    else:
        return
    if found:
        frappe.throw('This reference already has a saved result from the earlier workflow. '
                     'Check that original result before starting another entry.')


def _check_document_company(doc, company):
    if (doc.get('company') and doc.company != company) or (doc.doctype == 'Company' and doc.name != company):
        frappe.throw('This record belongs to another business.', frappe.PermissionError)


def _access(row):
    """Recheck current authority, including linked-source restrictions on receipts."""
    _company(row.company)
    receipt = frappe.parse_json(row.receipt or '{}')
    if row.kind in ('native_save', 'native_transition'):
        from erp_extensions import api
        saved = receipt if row.state == 'completed' else {}
        name = saved.get('name') or row.document_name
        permission = 'read' if row.state == 'completed' or row.kind == 'native_transition' else 'write' if name else 'create'
        reason = native_recovery_reason(api._meta(row.document_type, permission))
        if reason:
            frappe.throw(reason)
        if name:
            # A status request can have opened its snapshot before the write committed.
            doc = frappe.get_doc(row.document_type, name, for_update=True)
            _check_document_company(doc, row.company)
            doc.check_permission(permission)
            if row.state == 'completed':
                return api._result(doc)
    elif row.kind == 'invoice':
        from erp_extensions import invoice_compose, invoices
        if row.state == 'completed':
            invoices._invoice(row.company, receipt['name'], lock=True)
            return receipt
        invoice_compose._access(row.company)
    elif row.kind == 'knitting':
        from erp_extensions.knitting import api, domain, factory, procurement, batches, permissions
        if row.state == 'completed':
            permissions.require(row.company, 'jobs', history=True)
            return api.response(domain.reference('Knitting Event', receipt['event'], row.company, lock=True))
        actions = {**domain.ACTIONS, **factory.ACTIONS, **procurement.ACTIONS, **batches.ACTIONS}
        if row.action not in actions:
            frappe.throw('That knitting action is not supported.')
        permissions.require(row.company, actions[row.action][0])
    elif row.kind == 'reconciliation':
        from erp_extensions import reconciliation
        if not reconciliation.permitted():
            frappe.throw('This account cannot reconcile payments.', frappe.PermissionError)
        if row.state == 'completed':
            reconciliation._context(row.company, receipt['party_type'], receipt['party'])
            result = receipt['result']
            for doctype, name, permission in (
                ('Payment Entry', result['payment'], 'write'),
                (reconciliation.INVOICES[receipt['party_type']], result['invoice'], 'read'),
            ):
                doc = frappe.get_doc(doctype, name, for_update=True)
                _check_document_company(doc, row.company)
                doc.check_permission(permission)
            return result
    else:
        frappe.throw('This operation type is not supported.')


def _response(row, *, include_result=True):
    result = _access(row)
    receipt = frappe.parse_json(row.receipt or '{}')
    value = {'request_id': row.request_id, 'company': row.company, 'kind': row.kind,
             'action': row.action or '', 'doctype': row.document_type or None,
             'name': receipt.get('name') or row.document_name or None,
             'state': row.state, 'creation': str(row.creation)}
    if include_result and row.state == 'completed':
        value['result'] = result
    return value


@frappe.whitelist(methods=['POST'])
def begin_operation(company, kind, request_id, doctype=None, name=None, action=None):
    _company(company)
    if kind not in KINDS or any(value is not None and (not isinstance(value, str) or len(value) > 140)
                                for value in (doctype, name, action)):
        frappe.throw('Choose a supported operation and bounded record references.')
    action = action or ('Save' if kind == 'native_save' else '')
    if kind.startswith('native_') and (not doctype or kind == 'native_transition' and (not name or not action)):
        frappe.throw('Choose the document and action to recover.')
    if kind == 'native_save' and action not in ('Save', 'Submit', 'Cancel'):
        frappe.throw('Choose a supported document action.')
    values = dict(company=company, actor=frappe.session.user, kind=kind, action=action,
                  document_type=doctype or '', document_name=name or '', request_id=request_id)
    candidate = frappe._dict(**values, receipt=None, state='prepared')
    _access(candidate)
    key = _key(company, request_id)
    row = None
    if kind in LEGACY_RECEIPT_KINDS:
        _lock_legacy_scope(company, kind)
        row = _load(company, request_id, optional=True)
        if row is None or row.state != 'completed':
            _reject_legacy_receipt(company, kind, request_id)
    # The unique key also serializes simultaneous preparation of the same reference.
    if row is None:
        if not frappe.db.exists(DOCTYPE, key):
            try:
                frappe.get_doc({'doctype': DOCTYPE, 'request_key': key, 'state': 'prepared', **values}).insert(ignore_permissions=True)
            except frappe.DuplicateEntryError:
                pass
        row = _load(company, request_id)
    if any((row.get(field) or '') != (values[field] or '') for field in ('kind', 'action', 'document_type', 'document_name')):
        frappe.throw('This operation reference was already used for another action.')
    return _response(row)


@frappe.whitelist(methods=['POST'])
def operation_status(company, request_id):
    return _response(_load(company, request_id))


@frappe.whitelist(methods=['POST'])
def close_operation(company, request_id):
    _company(company)
    # Kind is immutable. Do not acquire the scope lock after locking the journal.
    kind = frappe.db.get_value(DOCTYPE, _key(company, request_id), 'kind')
    _lock_legacy_scope(company, kind)
    row = _load(company, request_id)
    if row.kind in LEGACY_RECEIPT_KINDS and row.kind != kind:
        frappe.throw('This operation changed while it was being checked. Check its outcome again.')
    _access(row)
    if row.state != 'completed':
        _reject_legacy_receipt(company, row.kind, request_id)
    if row.state == 'prepared':
        frappe.db.set_value(DOCTYPE, row.name, 'state', 'closed')
        row.state = 'closed'
    return _response(row)


@frappe.whitelist(methods=['POST'])
def acknowledge_operation(company, request_id):
    row = _load(company, request_id)
    _access(row)
    if row.state == 'prepared':
        frappe.throw('Check or close this operation before dismissing it.')
    frappe.db.set_value(DOCTYPE, row.name, 'acknowledged', 1)
    return {'request_id': request_id, 'state': row.state}


@frappe.whitelist(methods=['POST'])
def pending_operations(company, start=0):
    _company(company)
    start = max(0, cint(start))
    rows = frappe.get_all(DOCTYPE, filters={'company': company, 'actor': frappe.session.user, 'acknowledged': 0},
                          fields=['*'], order_by='creation desc, name desc', start=start, limit=51)
    visible = []
    for row in rows[:50]:
        try:
            if row.kind.startswith('native_') and native_recovery_reason(frappe.get_meta(row.document_type)):
                continue
            visible.append(_response(row, include_result=False))
        except (frappe.PermissionError, frappe.DoesNotExistError):
            continue
    return {'rows': visible, 'has_more': len(rows) > 50}


def execute(company, kind, request_id, payload, perform, *, doctype=None, name=None, action=None, optional=False):
    """Hold the reference lock until Frappe commits the business write and receipt."""
    if not request_id:
        return perform()
    _lock_legacy_scope(company, kind)
    row = _load(company, request_id, optional=optional)
    if row is None:
        return perform()
    action = action or ('Save' if kind == 'native_save' else '')
    if (row.kind != kind or (row.action or '') != action or
            kind.startswith('native_') and ((row.document_type or '') != (doctype or '') or
                                            (row.document_name or '') != (name or ''))):
        frappe.throw('This operation reference belongs to another action.')
    _access(row)
    digest = _digest(payload)
    if row.payload_digest and row.payload_digest != digest:
        frappe.throw('This operation reference was already used with different values.')
    if row.state == 'closed':
        frappe.throw('This operation was closed without posting. Review a new entry before continuing.')
    if row.state == 'completed':
        return _access(row)
    result = perform()
    if kind.startswith('native_'):
        receipt = {'name': result['doc']['name']}
        _check_document_company(frappe.get_doc(doctype, receipt['name']), company)
    elif kind == 'knitting':
        receipt = {'event': result['event']}
    elif kind == 'reconciliation':
        receipt = {'result': result, 'party_type': payload['party_type'], 'party': payload['party']}
    else:
        receipt = result
    frappe.db.set_value(DOCTYPE, row.name, {'state': 'completed', 'payload_digest': digest,
                                          'receipt': frappe.as_json(receipt)})
    return result
