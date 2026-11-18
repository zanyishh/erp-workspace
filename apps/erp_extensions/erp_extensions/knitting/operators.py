"""Original shop-floor attribution, separate from the authenticated signing user."""
from collections.abc import Mapping

import frappe

from erp_extensions.migration import api as history, contracts, service
from erp_extensions.migration.install import RECORD, SCOPE


def _deny():
    frappe.throw('The original production operator is unavailable in your current business access.', frappe.PermissionError)


def _scope(company, user=None):
    from . import permissions
    user = user or frappe.session.user
    if user == frappe.session.user:
        scope = history._scope(company, required=False)
        if scope and company in scope['company_bindings'].values():
            return scope
        _deny()
    if user == 'Guest' or not permissions.company_allowed(company, user) or not frappe.db.exists('DocType', SCOPE):
        _deny()
    scopes = [service.get_scope(name) for name in frappe.get_all(SCOPE,
        or_filters={f'company_{i}': company for i in range(1, 5)}, pluck='name', limit_page_length=20)]
    scopes = [scope for scope in scopes if user in scope['allowed_users'] and company in scope['company_bindings'].values()]
    if len(scopes) != 1:
        _deny()
    return scopes[0]


FIELDS = ['name', 'source_scope', 'record_data', 'data_sha256', 'namespace', 'family',
    'native_id', 'source_company_id', 'source_book', 'source_key', 'shared_reference', 'shared_cash']
OUTPUT_KEYS = {'production_operator_record', 'production_operator_label', 'production_operator_number'}


def _person(scope, row):
    if not row or row.source_scope != scope['name']:
        _deny()
    record = service.record_from_row(row)
    if (record.get('namespace') != 'masters.employee' or record.get('family') != 'master'
            or not record.get('shared_reference') or record.get('shared_cash') or record.get('company') is not None):
        _deny()
    indexed = ('namespace', 'family', 'native_id', 'source_company_id', 'source_book', 'source_key', 'shared_reference', 'shared_cash')
    if any((row.get(key) or None) != (record.get(key) or None) for key in indexed):
        _deny()
    identity = {'instance': scope['source_instance'], 'namespace': record['namespace'],
        'company': record['source_company_id'], 'book': record['source_book'],
        'native_id': record['native_id'], 'parents': record['parent_scope']}
    key = contracts.sha(identity)
    if record['source_key'] != key or row.name != 'history-' + key:
        _deny()
    business = record.get('business_data')
    original = business.get('original_business') if isinstance(business, Mapping) else None
    header = original.get('header') if isinstance(original, Mapping) else None
    if not isinstance(header, Mapping):
        _deny()
    label = header.get('name')
    if (str(header.get('id')) != record['native_id'] or not isinstance(label, str)
            or not label.strip() or len(label) > 200):
        _deny()
    # A shared employee reference establishes attribution, not employment or payroll ownership.
    result = {'production_operator_record': row.name, 'production_operator_label': label}
    number = header.get('emp_no')
    if number not in (None, ''):
        if not isinstance(number, str) or len(number) > 140:
            _deny()
        if number.strip():
            result['production_operator_number'] = number
    return result


def resolve(company, name, user=None):
    if not isinstance(name, str) or not name or len(name) > 140:
        _deny()
    scope = _scope(company, user)
    row = frappe.db.get_value(RECORD, {'name': name, 'source_scope': scope['name']}, FIELDS, as_dict=True)
    return _person(scope, row)


def reject_output_fields(data):
    if OUTPUT_KEYS & set(data) or 'batch_snapshot' in data:
        frappe.throw('Choose the original production operator; authoritative attribution is supplied by the server.')


def attribution(company, data, kind):
    reject_output_fields(data)
    token = data.get('production_operator')
    if token in (None, ''):
        return {}
    if kind not in ('produce', 'produce_bulk', 'produce_batch'):
        frappe.throw('Original employee attribution is supported only for factory production entries.')
    return resolve(company, token)


def choices(company, query='', start=0, job=None):
    from . import domain, permissions
    permissions.require(company, 'jobs', history=True)
    if not isinstance(query, str) or len(query) > 120 or not str(start).isdigit() or int(start) > 1000000:
        frappe.throw('Choose a supported record selector and page.')
    if job:
        domain.reference('Knitting Job', job, company)
    scope = _scope(company)
    originals = frappe.get_all(RECORD, filters={'source_scope': scope['name'], 'namespace': 'masters.employee',
        'family': 'master', 'shared_reference': 1, 'shared_cash': 0}, fields=FIELDS, limit_page_length=10001)
    if len(originals) > 10000:
        frappe.throw('The original employee register needs review before it can be selected.')
    rows = []
    for row in originals:
        person = _person(scope, row)
        number = person.get('production_operator_number', '')
        if query.casefold() in person['production_operator_label'].casefold() or query.casefold() in number.casefold():
            rows.append({'name': person['production_operator_record'], 'title': person['production_operator_label'],
                **({'employee_number': number} if number else {})})
    rows.sort(key=lambda row: (row['title'].casefold(), row['name']))
    offset = int(start)
    return {'rows': rows[offset:offset + 50], 'start': offset, 'has_more': len(rows) > offset + 50}


def _references(value):
    if isinstance(value, Mapping):
        for key in ('production_operator', 'production_operator_record'):
            if value.get(key) not in (None, ''):
                yield (value[key], value.get('production_operator_label') if key == 'production_operator_record' else None,
                    value.get('production_operator_number') if key == 'production_operator_record' else None)
        for child in value.values():
            if isinstance(child, (Mapping, list)):
                yield from _references(child)
    elif isinstance(value, list):
        for child in value:
            yield from _references(child)


def visible(doc, user=None):
    """Revalidate attribution for reads, including Administrator and replayed receipts."""
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
            for name, label, number in _references(frappe.parse_json(raw or '{}')):
                if not isinstance(name, str):
                    return False
                cache = permissions._snapshot_links.get()
                key = ('production_operator', doc.company, user or frappe.session.user, name)
                person = cache.get(key) if cache is not None else None
                if person is None:
                    person = resolve(doc.company, name, user)
                    if cache is not None:
                        cache[key] = person
                if label is not None and label != person['production_operator_label']:
                    return False
                if number is not None and number != person.get('production_operator_number'):
                    return False
    except (frappe.PermissionError, frappe.ValidationError, ValueError, TypeError):
        return False
    return True
