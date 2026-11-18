"""Exact sums of preserved production fields; no source requests or native postings."""
from decimal import Decimal, InvalidOperation, localcontext
import re

import frappe
from . import contracts, filtering

GROUPS = ('original_date', 'machine', 'operator', 'shift', 'party', 'description', 'dia')
IDENTITY_FIELDS = ('source_key', 'company', 'source_company_id', 'source_book', 'namespace',
                   'native_id', 'family', 'original_date_raw', 'effective_date', 'date_basis',
                   'shared_cash', 'shared_reference')


def _arguments(group_by, filters, start, page_length):
    if not isinstance(group_by, str) or group_by not in GROUPS:
        raise ValueError('Choose a supported original production grouping.')
    pages = []
    for value in (start, page_length):
        if type(value) is int:pages.append(value)
        elif isinstance(value, str) and re.fullmatch(r'[0-9]{1,7}', value):pages.append(int(value))
        else:raise ValueError('Use a bounded integer production report page.')
    start, page_length = pages
    if not 0 <= start <= 1000000 or not 1 <= page_length <= 100:
        raise ValueError('Use a production report page of 1 to 100 groups.')
    return filtering.parse(filters), start, page_length


def _number(value):
    if value is None or isinstance(value, str) and not value.strip():return None
    if type(value) not in (str, int) or len(str(value)) > 4096:
        raise ValueError('An original production quantity or count is invalid.')
    text = str(value).strip()
    if not re.fullmatch(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?', text):
        raise ValueError('An original production quantity or count is invalid.')
    try:
        number = Decimal(text)
    except InvalidOperation:
        raise ValueError('An original production quantity or count is invalid.') from None
    if not number.is_finite() or abs(number.as_tuple().exponent) > 4096 or abs(number.adjusted()) > 4096:
        raise ValueError('An original production quantity or count is invalid or outside the report bounds.')
    return number


def _add(left, right):
    if left is None:return right
    if right is None:return left
    # Decimal's default precision would silently round large preserved quantities.
    with localcontext() as context:
        context.prec = max(left.adjusted(), right.adjusted()) - min(left.as_tuple().exponent, right.as_tuple().exponent) + 2
        return left + right


def _totals():
    return {'source_record_count': 0, 'quantity_kg': None, 'recorded_count': None,
            'missing_quantity_rows': 0, 'missing_count_rows': 0}


def _accumulate(totals, quantity, count):
    totals['source_record_count'] += 1
    for key, missing, value in (('quantity_kg', 'missing_quantity_rows', quantity),
                                ('recorded_count', 'missing_count_rows', count)):
        if value is None:totals[missing] += 1
        else:totals[key] = _add(totals[key], value)


def _render(totals):
    return {key: format(value, 'f') if isinstance(value, Decimal) else value for key, value in totals.items()}


def _drilldown(group_by, value, filters):
    result = dict(filters)
    if group_by == 'original_date':
        if value is None:
            result.pop('from_date', None);result.pop('to_date', None)
            result['date_basis'] = 'no_original'
        else:result.update(from_date=value, to_date=value, date_basis='original')
    elif isinstance(value, str):result[group_by] = value
    else:return None
    return result


def _summarize(records, group_by, filters=None, start=0, page_length=100):
    filters, start, page_length = _arguments(group_by, filters, start, page_length)
    groups = {};totals = _totals()
    for record in records:
        fields = record['business_data']['fields']
        value = contracts.iso_date(record.get('original_date_raw')) if group_by == 'original_date' else contracts.scalar(fields.get(group_by))
        if value == '':value = None
        key = (type(value).__name__, value)
        if key not in groups:groups[key] = {'value': value, **_totals()}
        quantity = _number(fields.get('net_kg'));count = _number(fields.get('rolls'))
        _accumulate(groups[key], quantity, count);_accumulate(totals, quantity, count)
    values = list(groups.values())
    known = [row for row in values if row['value'] is not None]
    known.sort(key=lambda row: (str(row['value']).encode('utf-8'), type(row['value']).__name__), reverse=group_by == 'original_date')
    ordered = known + [row for row in values if row['value'] is None]
    nontext_labels = {contracts.canonical(row['value']) for row in values
                      if row['value'] is not None and not isinstance(row['value'], str)}
    rows = []
    for group in ordered[start:start + page_length]:
        value = group['value'];drilldown = _drilldown(group_by, value, filters)
        # History's text selectors cannot distinguish JSON strings from matching numeric/bool values.
        if group_by != 'original_date' and isinstance(value, str) and value in nontext_labels:drilldown = None
        rows.append({**_render(group), 'label': 'Unrecorded' if value is None else str(value),
                     'drillable': drilldown is not None, 'filters': drilldown})
    return {'group_by': group_by, 'filters': filters, 'start': start, 'page_length': page_length,
            'row_count': len(ordered), 'has_more': start + len(rows) < len(ordered),
            'rows': rows, 'totals': _render(totals)}


def _verified_records(scope, company, filters):
    from . import service
    from .install import RECORD
    where, params = filtering.predicate(scope['name'], company, 'production', filters)
    after = ''
    while True:
        rows = frappe.db.sql('select name,source_scope,record_data,data_sha256,' + ','.join(IDENTITY_FIELDS) +
            ' from `tab' + RECORD + '` where ' + where + ' and name>%(after)s order by name asc limit %(limit)s',
            {**params, 'after': after, 'limit': 500}, as_dict=True)
        for row in rows:
            record = service.record_from_row(row)
            expected_key = contracts.sha({'instance': scope['source_instance'], 'namespace': record['namespace'],
                'company': record['source_company_id'], 'book': record['source_book'],
                'native_id': record['native_id'], 'parents': record['parent_scope']})
            if (record['company'] != company or record['family'] != 'production'
                    or record['namespace'] != 'knitpack.production' or record['shared_cash'] or record['shared_reference']
                    or record['source_scope'] != scope['name'] or record['source_key'] != expected_key
                    or record['name'] != 'history-' + expected_key
                    or scope['company_bindings'].get(record['source_company_id']) != company):
                raise ValueError('An original production record has inconsistent identity.')
            for key in IDENTITY_FIELDS:
                indexed = str(row[key]) if key == 'effective_date' and row[key] is not None else row[key]
                if indexed != record[key]:raise ValueError('An original production record has inconsistent identity or date fields.')
            yield record
        if len(rows) < 500:return
        after = rows[-1]['name']


@frappe.whitelist()
def summary(company, group_by='original_date', filters=None, start=0, page_length=100):
    from . import api
    scope = api._scope(company);api._family('production')
    try:
        filters, start, page_length = _arguments(group_by, filters, start, page_length)
        result = _summarize(_verified_records(scope, company, filters), group_by, filters, start, page_length)
        available = filtering.available_fields(scope['name'], company, 'production')
        from . import production_jobs
        labels = production_jobs.filter_labels(scope, company, filters)
    except (ValueError, KeyError, TypeError) as error:
        frappe.throw(str(error) if isinstance(error, ValueError) else 'An original production record is invalid.')
    return {'version': 1, 'company': company, 'family': 'production', **result, 'available_filters': available, 'filter_labels': labels}
