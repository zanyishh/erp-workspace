"""Read-only saved production job identities and verified original labels."""
from . import contracts
from .references import verified_job_reference


def _identity(value):
    try:return contracts.identity(value)
    except (TypeError, ValueError):return None


def source_job(record):
    if record.get('namespace') != 'knitpack.production' or record.get('family') != 'production':return None
    original = record.get('business_data', {}).get('original_business')
    header = original.get('header') if isinstance(original, dict) else None
    if (not isinstance(header, dict) or _identity(header.get('id')) != record.get('native_id')
            or _identity(header.get('companymas_id')) != record.get('source_company_id')):return None
    return _identity(header.get('jobmas_id'))


def _links(records):
    return {(record['source_scope'], record['company'], record['source_company_id'], record['source_book'], job)
            for record in records if (job := source_job(record)) is not None}


def _candidate(record):
    original = record.get('business_data', {}).get('original_business')
    label = verified_job_reference(record) if isinstance(original, dict) else None
    original = original if isinstance(original, dict) else {}
    ledger = original.get('job_ledger')
    headers = [ledger.get('job') if isinstance(ledger, dict) else None, original.get('original_saved_job')]
    if any(isinstance(header, dict) and header.get('sec_acc') is not None
           and _identity(header['sec_acc']) != record['source_book'] for header in headers):label = None
    return {key: record[key] for key in ('name', 'source_scope', 'company', 'source_company_id', 'source_book', 'native_id')} | {'label': label}


def _labels(links, candidates):
    result = {}
    for job in {link[4] for link in links}:
        contexts = [link[:4] for link in links if link[4] == job]
        matches = {row['name']: row for row in candidates if row['native_id'] == job and any(
            (row['source_scope'], row['company'], row['source_company_id']) == context[:3]
            and (context[3] is None or row['source_book'] == context[3]) for context in contexts)}
        result[job] = next(iter(matches.values()))['label'] if len(matches) == 1 else None
    return result


def resolved_labels(records, jobs):
    return _labels(_links(records), [_candidate(job) for job in jobs])


def _jobs(scope, company, links):
    import frappe
    from . import service
    ids = sorted({link[4] for link in links});result = []
    fields = ('source_key', 'company', 'source_company_id', 'source_book', 'namespace', 'native_id',
              'family', 'shared_cash', 'shared_reference')
    for offset in range(0, len(ids), 100):
        after = ''
        while True:
            rows = frappe.get_all(service.RECORD, filters={'source_scope': scope['name'], 'company': company,
                'namespace': 'knitpack.job', 'family': 'job', 'native_id': ['in', ids[offset:offset + 100]],
                'name': ['>', after]}, fields=['name', 'source_scope', 'record_data', 'data_sha256', *fields],
                order_by='name asc', limit=500)
            for row in rows:
                record = service.record_from_row(row)
                key = contracts.sha({'instance': scope['source_instance'], 'namespace': record['namespace'],
                    'company': record['source_company_id'], 'book': record['source_book'],
                    'native_id': record['native_id'], 'parents': record['parent_scope']})
                if (record['source_scope'] != scope['name'] or record['company'] != company
                        or record['namespace'] != 'knitpack.job' or record['family'] != 'job'
                        or record['shared_cash'] or record['shared_reference']
                        or scope['company_bindings'].get(record['source_company_id']) != company
                        or record['source_key'] != key or record['name'] != 'history-' + key
                        or any(row[field] != record[field] for field in fields)):
                    raise ValueError('An original job failed its saved identity check.')
                result.append(_candidate(record))
            if len(rows) < 500:break
            after = rows[-1].name
    return result


def references(scope, company, records):
    candidates = _jobs(scope, company, _links(records))
    result = {}
    for record in records:
        job = source_job(record)
        label = _labels(_links([record]), candidates).get(job)
        if label is not None:result[record['name']] = label
    return result


def _matching_links(scope, company, filters):
    from .production_reports import _verified_records
    # Keep identity contexts only; raw production payloads remain bounded to one read batch.
    return _links(_verified_records(scope, company, filters))


def filter_labels(scope, company, filters):
    if 'source_job' not in filters:return {}
    links = _matching_links(scope, company, filters)
    if not links:
        # Empty date/dimension results do not erase a known selection's verified identity label.
        context = {key: filters[key] for key in ('source_job', 'source_book') if key in filters}
        links = _matching_links(scope, company, context)
    label = _labels(links, _jobs(scope, company, links)).get(filters['source_job'])
    return {'source_job': label or 'Original job ' + filters['source_job']}


def options(scope_name, company, *, value=None, query='', start=0):
    from . import filtering, service
    filters = filtering.parse(value);filters.pop('source_job', None)
    filtering.search_text(query)
    scope = service.get_scope(scope_name)
    links = _matching_links(scope, company, filters)
    labels = _labels(links, _jobs(scope, company, links))
    rows = [{'value': job, 'label': label or 'Original job ' + job} for job, label in labels.items()]
    if query:rows = [row for row in rows if any(query.casefold() in row[key].casefold() for key in ('value', 'label'))]
    rows.sort(key=lambda row: row['value'].encode('utf-8'))
    return {'rows': rows[start:start + 50], 'has_more': start + 50 < len(rows), 'start': start}
