"""Read-only measurements from verified source identities; never rewrite stored programmes."""
import frappe

from . import api, contracts, service
from .install import RECORD
from .references import verified_job_reference


def _json(value):
    return frappe.parse_json(value) if isinstance(value, str) else value


def _selectors(record):
    context = record['business_data'].get('original_business', {}).get('fabric_context', {})
    job = context.get('job') or {}
    if (not isinstance(job, dict) or str(job.get('id')) != record['native_id']
            or str(job.get('companymas_id')) != record['source_company_id']):
        return {}
    result = {}
    for fabric in context.get('fabs', []):
        if str(fabric.get('jobmas_id')) != record['native_id']:
            continue
        for size in fabric.get('dias', []):
            if str(size.get('jobfabric_id')) != str(fabric.get('id')) or size.get('diatype') != 'circular':
                continue
            key = (str(fabric.get('id')), str(size.get('id')))
            if key in result:
                frappe.throw('The original programme has repeated dimension identities.')
            result[key] = size.get('diaorsize')
    return result


class Projection:
    def __init__(self, company, jobs=(), originals=()):
        self.jobs, self.originals, self.labels, self.references = {}, {}, {}, {}
        if not jobs and not originals:
            return
        scope = api._scope(company, required=False)
        if not scope:
            return
        names = set(jobs)
        native = frappe.get_list('Knitting Job', filters={'company': company, 'name': ['in', list(names)]},
            fields=['name', 'source_record'], limit=0) if names else []
        references = {row.source_record for row in native if row.source_record}
        def verified(record):
            identity = {'instance': scope['source_instance'], 'namespace': record['namespace'],
                'company': record['source_company_id'], 'book': record['source_book'],
                'native_id': record['native_id'], 'parents': record['parent_scope']}
            key = contracts.sha(identity)
            company = None if record['shared_reference'] or record['shared_cash'] else scope['company_bindings'].get(record['source_company_id'])
            if (record['source_scope'] != scope['name'] or record['source_key'] != key
                    or record['name'] != 'history-' + key or record['company'] != company):
                frappe.throw('The original dimension record has inconsistent source identity or company binding.')
            return record

        def records(filters):
            fields = ('company', 'source_key', 'source_company_id', 'source_book', 'namespace',
                'native_id', 'family', 'shared_reference', 'shared_cash')
            result = []
            for row in frappe.get_all(RECORD, filters={'source_scope': scope['name'], **filters},
                    fields=['name', 'source_scope', 'record_data', 'data_sha256', *fields]):
                record = verified(service.record_from_row(row))
                if any(record.get(key) != filters[key] for key in ('namespace', 'family', 'shared_reference')
                        if key in filters):
                    frappe.throw('The original dimension record does not match the exact requested source namespace or family.')
                # Frappe may default the company index on an explicitly shared master.
                indexed = [key for key in fields if key != 'company' or not record['shared_reference']]
                if any((row.get(key) if row.get(key) != '' else None) !=
                        (record.get(key) if record.get(key) != '' else None) for key in indexed):
                    frappe.throw('The original dimension record has inconsistent indexed source identity.')
                result.append(record)
            return result
        loaded = records({'name': ['in', list(references)], 'company': company,
            'namespace': 'knitpack.job', 'family': 'job'}) if references else []
        loaded.extend(verified(record) for record in originals if record['source_scope'] == scope['name']
            and record['company'] == company and record['namespace'] == 'knitpack.job' and record['family'] == 'job')
        self.originals = {record['name']: _selectors(record) for record in loaded}
        self.jobs = {row.name: self.originals.get(row.source_record, {}) for row in native}
        references = {record['name']: verified_job_reference(record) for record in loaded}
        self.references = {row.name: references.get(row.source_record) for row in native}
        if self.originals:
            for record in records({'namespace': 'knitpack.dia', 'family': 'master', 'shared_reference': 1}):
                header = record['business_data'].get('original_business', {}).get('header', {})
                if str(header.get('id')) != record['native_id'] or not isinstance(header.get('dia'), str):
                    continue
                if record['native_id'] in self.labels:
                    frappe.throw('The original diameter identity is ambiguous.')
                self.labels[record['native_id']] = header['dia']

    def line(self, line, *, job=None, original=None):
        result = dict(line)
        raw = line.get('dia')
        if 'source_fabric_id' not in line and 'source_size_id' not in line:
            return {**result, 'dia_display': raw, 'dia_basis': 'physical'}
        selectors = self.originals.get(original, {}) if original else self.jobs.get(job, {})
        key = (str(line.get('source_fabric_id')), str(line.get('source_size_id')))
        if key not in selectors or raw != selectors[key]:
            return {**result, 'dia_display': None, 'dia_basis': 'unresolved'}
        if raw in (None, ''):
            return {**result, 'dia_display': raw, 'dia_basis': 'unrecorded'}
        label = self.labels.get(str(raw))
        return {**result, 'dia_display': label, 'dia_basis': 'source_master_id' if label is not None else 'unresolved'}


def programmes(company, rows):
    projection = Projection(company, jobs=[row['name'] for row in rows])
    for row in rows:
        if projection.references.get(row['name']):
            row['source_reference_display'] = projection.references[row['name']]
        row['programme'] = [projection.line(line, job=row['name']) for line in _json(row.get('programme') or [])]


def specifications(company, rows):
    projection = Projection(company, jobs={row['job'] for row in rows if row.get('job') and any(
        key in _json(row.get('specification') or {}) for key in ('source_fabric_id', 'source_size_id'))})
    for row in rows:
        spec = _json(row.get('specification') or {})
        row['specification'] = projection.line(spec, job=row.get('job'))


def report_rows(company, rows):
    candidates = [row for row in rows if row.get('_dimension_spec') or row.get('specification')]
    projection = Projection(company, jobs={row.get('_dimension_job') or row['job'] for row in candidates if row.get('job') and any(
        key in _json(row.get('_dimension_spec') or row.get('specification') or {})
        for key in ('source_fabric_id', 'source_size_id'))})
    for row in candidates:
        origin = row.pop('_dimension_job', None) or row.get('job')
        spec = projection.line(_json(row.pop('_dimension_spec', None) or row.get('specification') or {}), job=origin)
        row['dia'] = spec['dia_display']
        row['dia_basis'] = spec['dia_basis']
        if spec['dia_basis'] != 'physical':
            row['source_dia_id'] = spec.get('dia')


def history_tables(company, record, tables):
    if record['namespace'] != 'knitpack.job' or record['family'] != 'job':
        return
    projection = Projection(company, originals=[record])
    selectors = projection.originals.get(record['name'], {})
    for table in tables:
        changed = False
        for row in table['rows']:
            matches = [key for key in selectors if key[1] == str(row.get('source_id'))]
            if len(matches) != 1 or 'dia' not in row:
                continue
            fabric, size = matches[0]
            line = projection.line({'dia': row['dia'], 'source_fabric_id': fabric, 'source_size_id': size}, original=record['name'])
            row['source_dia_id'], row['dia'] = row['dia'], line['dia_display']
            changed = True
        if changed:
            table['columns'].append({'key': 'source_dia_id', 'label': 'Original diameter identity'})
