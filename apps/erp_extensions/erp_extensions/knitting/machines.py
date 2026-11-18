"""Recorded original machine use, separate from configured native planning machines."""
from collections.abc import Mapping

import frappe

from erp_extensions.migration import contracts, service
from erp_extensions.migration.install import RECORD
from . import operators


OUTPUT_KEYS = {'production_machine_record', 'production_machine_label', 'production_machine_code'}


def _deny():
    frappe.throw('The original production machine is unavailable in your current business access.', frappe.PermissionError)


def _scope(company, user=None):
    try:
        return operators._scope(company, user)
    except frappe.PermissionError:
        _deny()


def _machine(scope, row):
    if not row or row.source_scope != scope['name']:
        _deny()
    record = service.record_from_row(row)
    if (record.get('namespace') != 'knitpack.machine' or record.get('family') != 'master'
            or record.get('shared_reference') is not True or record.get('shared_cash') is not False
            or any(record.get(key) is not None for key in ('company', 'source_company_id', 'source_book'))):
        _deny()
    indexed = ('namespace', 'family', 'native_id', 'source_company_id', 'source_book',
        'source_key', 'shared_reference', 'shared_cash')
    if any((row.get(key) if row.get(key) != '' else None) !=
            (record.get(key) if record.get(key) != '' else None) for key in indexed):
        _deny()
    key = contracts.sha({'instance': scope['source_instance'], 'namespace': record['namespace'],
        'company': record['source_company_id'], 'book': record['source_book'],
        'native_id': record['native_id'], 'parents': record['parent_scope']})
    if record['source_key'] != key or row.name != 'history-' + key:
        _deny()
    business = record.get('business_data')
    original = business.get('original_business') if isinstance(business, Mapping) else None
    header = original.get('header') if isinstance(original, Mapping) else None
    if not isinstance(header, Mapping):
        _deny()
    native_id, label, code = header.get('id'), header.get('mc_name'), header.get('mc_code')
    if (isinstance(native_id, bool) or not isinstance(native_id, (str, int)) or str(native_id) != record['native_id']
            or not isinstance(label, str) or not label.strip() or len(label) > 200
            or code not in (None, '') and (not isinstance(code, str) or len(code) > 140)):
        _deny()
    # Shared originals establish recorded use, never company ownership, capacity or availability.
    return {'production_machine_record': row.name, 'production_machine_label': label,
        **({'production_machine_code': code} if code is not None else {})}


def resolve(company, name, user=None):
    if not isinstance(name, str) or not name or len(name) > 140:
        _deny()
    scope = _scope(company, user)
    row = frappe.db.get_value(RECORD, {'name': name, 'source_scope': scope['name']}, operators.FIELDS, as_dict=True)
    return _machine(scope, row)


def reject_output_fields(data):
    if OUTPUT_KEYS & set(data) or 'batch_snapshot' in data:
        frappe.throw('Choose the original production machine; recorded machine details are supplied by the server.')


def attribution(company, data, kind):
    reject_output_fields(data)
    token = data.get('production_machine')
    if token in (None, ''):
        return {}
    if kind not in ('produce', 'produce_bulk', 'produce_batch'):
        frappe.throw('Original machine attribution is supported only for factory production entries.')
    if data.get('machine') not in (None, ''):
        frappe.throw('Choose either a configured native machine or an original recorded machine, not both.')
    return resolve(company, token)


def choices(company, query='', start=0, job=None):
    from . import domain, permissions
    permissions.require(company, 'jobs', history=True)
    if not isinstance(query, str) or len(query) > 120 or not str(start).isdigit() or int(start) > 1000000:
        frappe.throw('Choose a supported record selector and page.')
    if job:
        domain.reference('Knitting Job', job, company)
    scope = _scope(company)
    originals = frappe.get_all(RECORD, filters={'source_scope': scope['name'], 'namespace': 'knitpack.machine',
        'family': 'master', 'shared_reference': 1, 'shared_cash': 0}, fields=operators.FIELDS, limit_page_length=10001)
    if len(originals) > 10000:
        frappe.throw('The original machine register needs review before it can be selected.')
    rows = []
    for original in originals:
        machine = _machine(scope, original)
        label, code = machine['production_machine_label'], machine.get('production_machine_code', '')
        if query.casefold() in label.casefold() or query.casefold() in code.casefold():
            rows.append({'name': machine['production_machine_record'], 'title': label,
                **({'machine_code': code} if code else {})})
    rows.sort(key=lambda row: (row['title'].casefold(), row['name']))
    offset = int(start)
    return {'rows': rows[offset:offset + 50], 'start': offset, 'has_more': len(rows) > offset + 50}


def _references(value):
    if isinstance(value, Mapping):
        for key in ('production_machine', 'production_machine_record'):
            if value.get(key) not in (None, ''):
                yield (value[key], value.get('production_machine_label') if key.endswith('_record') else None,
                    value.get('production_machine_code') if key.endswith('_record') else None)
        for child in value.values():
            if isinstance(child, (Mapping, list)):
                yield from _references(child)
    elif isinstance(value, list):
        for child in value:
            yield from _references(child)


def visible(doc, user=None):
    from . import permissions
    if doc.doctype in ('Knitting Fabric Batch', 'Knitting Roll'):
        if not doc.get('production'):
            return True
        with permissions.snapshot_link_checks():
            source = permissions._batch_production_sources([doc]).get(doc.production)
        if not source or source.company != doc.company:
            return False
        doc = source
    elif doc.doctype != 'Knitting Event':
        return True
    try:
        for raw in (doc.get('payload'), doc.get('result')):
            for name, label, code in _references(frappe.parse_json(raw or '{}')):
                if not isinstance(name, str):
                    return False
                cache = permissions._snapshot_links.get()
                key = ('production_machine', doc.company, user or frappe.session.user, name)
                machine = cache.get(key) if cache is not None else None
                if machine is None:
                    machine = resolve(doc.company, name, user)
                    if cache is not None:
                        cache[key] = machine
                if ((label is not None and label != machine['production_machine_label'])
                        or code is not None and code != machine.get('production_machine_code')):
                    return False
    except (frappe.PermissionError, frappe.ValidationError, ValueError, TypeError):
        return False
    return True
