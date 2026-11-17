"""Console-only initialization from verified stock; original movements stay immutable."""
from decimal import Decimal
import re
import frappe
from frappe.utils import get_datetime
from . import service, contracts


def _validate(record, payload, service_item, warehouse, finance_book, cutoff):
    from erp_extensions.knitting import domain
    from .finance import BOOK_BINDING
    job = payload['job']
    allowed = {'name', 'source_reference', 'company', 'customer', 'billing_customer', 'fabric_owner', 'job_date', 'due_date',
        'kind', 'material_mode', 'status', 'programme', 'pricing', 'target_kg', 'revision', 'charge_policy', 'notes'}
    if set(job)-allowed or job.get('material_mode')!='Customer' or job.get('fabric_owner')!=job.get('customer'):
        frappe.throw('Initialize only the verified customer custody order, without overriding audit fields.')
    if (record['source_book']!=payload.get('source_book') or record['date_basis']!='original'
            or job.get('job_date')!=record['original_date_raw'] or not contracts.iso_date(job.get('job_date'))):
        frappe.throw('Preserve the original order date and source account book.')
    if get_datetime(cutoff).date() < get_datetime(job['job_date']).date():
        frappe.throw('The captured stock date cannot precede the original order date.')
    if not frappe.db.exists(BOOK_BINDING, {'source_scope': record['source_scope'], 'company': job['company'],
            'source_company_id': record['source_company_id'], 'source_book': payload['source_book'], 'finance_book': finance_book}):
        frappe.throw('Use the Finance Book bound to this original company and account book.')
    if not frappe.db.exists('Warehouse', {'name': warehouse, 'company': job['company'], 'is_group': 0}):
        frappe.throw('Choose a warehouse belonging to the original company.')
    if not frappe.db.exists('Item', {'name': service_item, 'is_stock_item': 0, 'stock_uom': 'Kg', 'disabled': 0}):
        frappe.throw('Choose an enabled service item measured in kilograms.')
    lines = job.get('programme')
    if not isinstance(lines, list) or any(not isinstance(r, dict) or not r.get('id') for r in lines):
        frappe.throw('Preserve the original fabric programme identities.')
    line_ids = {r['id'] for r in lines}
    if len(line_ids)!=len(lines) or not isinstance(job.get('pricing'), dict) or set(job['pricing'])-line_ids:
        frappe.throw('The original fabric programme or pricing contains an unknown or repeated line.')
    def exact(value, precision=3):
        if isinstance(value, (float, bool)) or value is None:
            frappe.throw('Preserve exact saved stock quantities without rounding.')
        return domain.decimal(value, signed=True, precision=precision)
    exact(job.get('target_kg'))
    for row in lines: exact(row.get('target_kg'))
    for family in ('batches', 'yarn'):
        rows = payload.get(family)
        if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
            frappe.throw('Use verified native stock rows.')
        names = [r.get('name') for r in rows]
        if not all(isinstance(n, str) and n for n in names) or len(set(names))!=len(names):
            frappe.throw('Each original stock row needs a distinct native identity.')
        for row in rows:
            if row.get('company')!=job['company'] or row.get('job')!=job['name'] or not isinstance(row.get('specification'), dict):
                frappe.throw('Every stock row must belong to the original company and order.')
            exact(row.get('quantity_kg')); exact(row.get('rolls' if family=='batches' else 'units'), 0)
            if family=='batches':
                fields = {'name', 'company', 'job', 'programme_line', 'quantity_kg', 'rolls', 'state',
                    'source_reference', 'specification', 'produced_kg'}
                if set(row)-fields or row.get('programme_line') not in line_ids or row.get('state')!='Awaiting review':
                    frappe.throw('Initialize each verified fabric batch awaiting review, without audit overrides.')
                exact(row.get('produced_kg'))
            elif row.get('party')!=job['customer'] or not row.get('source_lot'):
                frappe.throw('Customer yarn custody must retain the original owner and source lot.')
            elif frappe.db.exists('Item', row.get('item_code')) and not frappe.db.exists('Item', {
                    'name': row.get('item_code'), 'is_stock_item': 1, 'stock_uom': 'Kg', 'disabled': 0}):
                frappe.throw('The native yarn item must retain its enabled kilogram stock identity.')
    if {r['programme_line'] for r in payload['batches']}!=line_ids or len(payload['batches'])!=len(line_ids):
        frappe.throw('Preserve one captured fabric batch per original programme line.')
    if len({r['source_lot'] for r in payload['yarn']})!=len(payload['yarn']):
        frappe.throw('A native yarn custody row cannot initialize twice.')


def apply_job(record_name, payload, *, service_item, warehouse, finance_book, cutoff):
    if getattr(frappe.local,'request',None) or not frappe.conf.get('erp_customer_migration_enabled'):
        frappe.throw('Run verified operational initialization from the dedicated workspace console.')
    from erp_extensions.knitting import domain, permissions
    company=payload['job']['company']
    record=service.get_record_for_effect(record_name,company,'closing_custody')
    if record['family']!='job' or record['native_id']!=payload['source_job_id'] or record['source_company_id']!=payload['source_company_id']:
        frappe.throw('The original order does not match this operational initialization.')
    _validate(record, payload, service_item, warehouse, finance_book, cutoff)
    digest=contracts.sha({'payload':payload,'service_item':service_item,'warehouse':warehouse,'finance_book':finance_book,'cutoff':cutoff})
    with service.locked_scope(record['source_scope']):
        name=payload['job']['name']
        if frappe.db.exists('Knitting Job',name):
            existing = frappe.db.get_value('Knitting Job', name, ['migration_digest', 'source_record', 'company'], as_dict=True)
            event = frappe.db.get_value('Knitting Event', {'request_key': 'migration-stock-'+record['source_key']},
                ['name', 'job', 'company', 'kind', 'payload_hash', 'result'], as_dict=True)
            if (existing.migration_digest!=digest or existing.source_record!=record_name or existing.company!=company
                    or not event or event.job!=name or event.company!=company
                    or event.kind!='migration_stock_initialization' or event.payload_hash!=digest
                    or not domain.json_value(event.result, {}).get('basis')):
                frappe.throw('The original order already has a different operational initialization.')
            return {'job':name,'created':False}
        frappe.db.savepoint('migration_job')
        try:
            with permissions.service_write():
                values={**payload['job'],'source_record':record_name,'migration_digest':digest,
                    'migration_cutoff':get_datetime(cutoff),'service_item':service_item,'finance_book':finance_book}
                for field in ('programme','pricing'):values[field]=frappe.as_json(values[field])
                job=frappe.get_doc({'doctype':'Knitting Job',**values}).insert(set_name=name)
                event=frappe.get_doc({'doctype':'Knitting Event','company':company,'job':name,
                    'kind':'migration_stock_initialization','request_key':'migration-stock-'+record['source_key'],
                    'payload_hash':digest,'actor':frappe.session.user,'occurred_at':get_datetime(cutoff),
                    'payload':frappe.as_json({'basis':'Captured stock initialization','source_record':record_name})}).insert()
                batch_snapshot=[]
                for row in payload['batches']:
                    values={k:v for k,v in row.items() if k!='produced_kg'}
                    values.update(source_record=record_name,captured_at=get_datetime(cutoff),specification=frappe.as_json(row['specification']))
                    batch=frappe.get_doc({'doctype':'Knitting Fabric Batch',**values}).insert(set_name=row['name'])
                    service.bind_authority(record_name,'closing_custody',record['source_key']+'.fabric.'+row['programme_line'],
                        'Knitting Fabric Batch',batch.name,contracts.sha(row))
                    batch_snapshot.append({**{k:row[k] for k in ('name','job','programme_line','quantity_kg','rolls','state','produced_kg','specification')},
                        'source_reference':row.get('source_reference'), 'captured_at':str(get_datetime(cutoff))})
                for row in payload['yarn']:
                    item=row['item_code']
                    if not frappe.db.exists('Item',item):
                        frappe.get_doc({'doctype':'Item','item_code':item,'item_name':row['item_name'],
                            'item_group':frappe.db.get_value('Item Group',{'is_group':0},'name'),
                            'stock_uom':'Kg','is_stock_item':1,'item_defaults':[{'company':company,'default_warehouse':warehouse}]}).insert()
                    lot=frappe.get_doc({'doctype':'Knitting Material Lot','name':row['name'],'company':company,
                        'item':item,'party':row['party'],'material_owner':'Customer','warehouse':warehouse,
                        'source_lot':row['source_lot'],'specification':frappe.as_json(row['specification'])}).insert(set_name=row['name'])
                    entry=domain.ledger(event,lot,Decimal(row['quantity_kg']),job=name,units=row['units'])
                    service.bind_authority(record_name,'closing_custody',record['source_key']+'.yarn.'+row['source_lot'],
                        'Knitting Ledger Entry',entry.name,contracts.sha(row))
                event.result=frappe.as_json({'basis':payload['physical_basis'],'source_record':record_name,
                    'batches':batch_snapshot,'yarn_kg':domain.kg(sum((Decimal(r['quantity_kg']) for r in payload['yarn']),Decimal(0))),
                    'programme_output':[{'programme_line':r['programme_line'],'quantity_kg':r['produced_kg']} for r in payload['batches']]})
                event.save()
                return {'job':name,'created':True,'batches':len(payload['batches']),'yarn_lots':len(payload['yarn'])}
        except Exception:
            frappe.db.rollback(save_point='migration_job')
            raise


def apply_legacy_billing_refs(job_name, summary, deliveries, *, proof_sha256):
    """Register proved unbilled originals; no stock movement or invoice is posted."""
    if getattr(frappe.local, 'request', None) or not frappe.conf.get('erp_customer_migration_enabled'):
        frappe.throw('Run verified billing continuation from the dedicated workspace console.')
    from erp_extensions.knitting import domain, permissions
    from .finance import BOOK_BINDING
    job = frappe.get_doc('Knitting Job', job_name)
    original = service.get_record_for_effect(job.source_record, job.company, 'closing_custody')
    if (not job.migration_digest or original['family']!='job' or summary.get('source_record')!=job.source_record
            or summary.get('source_company_id')!=original['source_company_id']
            or summary.get('native_job_id')!=original['native_id'] or summary.get('source_book')!=original['source_book']
            or summary.get('current_available') is not True or not isinstance(deliveries, list)
            or not isinstance(proof_sha256, str) or not re.fullmatch(r'[0-9a-f]{64}', proof_sha256)):
        frappe.throw('Use the verified original company, order, book and complete delivery proof.')
    if not frappe.db.exists(BOOK_BINDING, {'source_scope': original['source_scope'], 'company': job.company,
            'source_book': original['source_book'], 'finance_book': job.finance_book}):
        frappe.throw('The original order account book must match its native Finance Book.')
    captured = {key: domain.decimal(summary.get(source)) for key, source in (
        ('captured_delivered_kg', 'child_delivered_kgs'),
        ('captured_billed_kg', 'source_billed_delivery_group_kgs'),
        ('captured_unbilled_kg', 'eligible_unbilled_kgs'))}
    if captured['captured_delivered_kg']-captured['captured_billed_kg']!=captured['captured_unbilled_kg']:
        frappe.throw('Original delivered, billed and unbilled line quantities must reconcile exactly.')
    digest = contracts.sha({'job_initialization': job.migration_digest, 'summary': summary,
        'deliveries': deliveries, 'proof_sha256': proof_sha256})
    request_key = 'migration-billing-'+original['source_key']
    with service.locked_scope(original['source_scope']):
        existing = frappe.db.get_value('Knitting Event', {'request_key': request_key},
            ['name', 'company', 'job', 'kind', 'payload_hash'], as_dict=True)
        if existing:
            if (existing.company!=job.company or existing.job!=job.name
                    or existing.kind!='migration_billing_initialization' or existing.payload_hash!=digest):
                frappe.throw('The original delivery billing baseline already contains different facts.')
            return {'job': job.name, 'created': False, 'event': existing.name}
        programme = domain.json_value(job.programme, [])
        source_fabrics = original['business_data'].get('original_business', {}).get('fabric_context', {}).get('fabs', [])
        prepared, seen, total = [], set(), Decimal(0)
        for delivery in deliveries:
            record = service.get_record_for_effect(delivery.get('source_record'), job.company, 'closing_custody')
            header = record['business_data'].get('original_business', {}).get('header', {})
            if (record['source_scope']!=original['source_scope'] or record['family']!='delivery'
                    or record['native_id']!=delivery.get('native_dc_id')
                    or record['source_company_id']!=original['source_company_id']
                    or str(header.get('id'))!=record['native_id'] or str(header.get('job_no'))!=original['native_id']
                    or str(header.get('companymas_id'))!=original['source_company_id']
                    or str(header.get('cancelled'))!='0' or header.get('invoice_id') not in (None, '', 0, '0')
                    or record['original_date_raw']!=delivery.get('original_date')
                    or header.get('dc_date')!=record['original_date_raw']
                    or delivery.get('job_source_record')!=job.source_record
                    or record['source_key'] in seen):
                frappe.throw('Use each original unlinked delivery once, from this company and order.')
            seen.add(record['source_key'])
            children = header.get('fabric_dia_details', [])
            rows, child_ids = [], set()
            for candidate in delivery.get('lines', []):
                if candidate.get('eligible_for_continuation') is not True:
                    continue
                child_id = candidate.get('native_line_id')
                matches = [row for row in children if str(row.get('id'))==child_id]
                if len(matches)!=1 or child_id in child_ids:
                    frappe.throw('Each billing reference needs its exact original delivery child identity.')
                child_ids.add(child_id); child = matches[0]
                if (str(child.get('fabric_id'))!=candidate.get('fabric_id')
                        or str(child.get('jobdia_id'))!=candidate.get('jobdia_id')
                        or child.get('dc_id') not in (None, '') and str(child['dc_id'])!=record['native_id']
                        or any(not link.get('invoice_cancelled') for link in candidate.get('invoice_references', []))):
                    frappe.throw('The original child identity or existing invoice reference conflicts.')
                quantity = domain.decimal(child.get('dlvry_kgs'), positive=True)
                if quantity!=domain.decimal(candidate.get('eligible_unbilled_kgs'), positive=True):
                    frappe.throw('Preserve the complete proved unbilled quantity of the original line.')
                lines = [line for line in programme if str(line.get('source_fabric_id'))==str(child['fabric_id'])
                    and str(line.get('source_size_id'))==str(child['jobdia_id'])]
                fabrics = [fabric for fabric in source_fabrics if str(fabric.get('id'))==str(child['fabric_id'])
                    and str(fabric.get('jobmas_id'))==original['native_id'] and any(
                        str(size.get('id'))==str(child['jobdia_id']) and str(size.get('jobfabric_id'))==str(child['fabric_id'])
                        for size in fabric.get('dias', []))]
                if len(lines)!=1 or len(fabrics)!=1 or fabrics[0].get('uoms')!='KGS':
                    frappe.throw('Bind the original fabric and size to one verified kilogram programme line.')
                line = lines[0]
                rate = domain.decimal(domain.json_value(job.pricing, {}).get(line['id']), precision=2)
                rows.append({'legacy_line': child_id, 'programme_line': line['id'], 'quantity_kg': domain.kg(quantity),
                    'rolls': str(domain.decimal(child.get('dlvry_rolls'), precision=0)),
                    'rate': domain.money(rate), 'rate_basis': 'Current agreed rate at invoice review',
                    'original_dc_rate': child.get('rate'), 'original_rate_for': child.get('rate_for'),
                    'source_fabric_id': str(child['fabric_id']), 'source_size_id': str(child['jobdia_id'])})
                total += quantity
            if not rows:
                frappe.throw('Only deliveries with proved unbilled native lines become billing references.')
            prepared.append((record, rows))
        if total!=captured['captured_unbilled_kg']:
            frappe.throw('The supplied original delivery references do not cover the proved unbilled quantity.')
        frappe.db.savepoint('migration_billing')
        try:
            with permissions.service_write():
                names = []
                for record, rows in prepared:
                    event = domain.insert('Knitting Event', company=job.company, job=job.name,
                        kind='migration_delivery_reference', request_key='migration-dc-'+record['source_key'],
                        payload_hash=contracts.sha({'proof': digest, 'source_record': record['name'], 'sources': rows}),
                        actor=frappe.session.user, occurred_at=get_datetime(record['original_date_raw']),
                        payload=frappe.as_json({'source_record': record['name'], 'basis': 'Original delivery reference; no stock movement'}),
                        result=frappe.as_json({'billing_reference': True, 'source_record': record['name'],
                            'source_reference': record['original_reference'], 'original_date': record['original_date_raw'],
                            'source_book': original['source_book'], 'quantity_kg': domain.kg(sum((Decimal(r['quantity_kg']) for r in rows), Decimal(0))),
                            'sources': rows, 'lines': rows, 'charges': [], 'rate_basis': 'Current agreed rate at invoice review'}))
                    names.append(event.name)
                baseline = domain.insert('Knitting Event', company=job.company, job=job.name,
                    kind='migration_billing_initialization', request_key=request_key, payload_hash=digest,
                    actor=frappe.session.user, occurred_at=job.migration_cutoff,
                    payload=frappe.as_json({'source_record': original['name'], 'proof_sha256': proof_sha256}),
                    result=frappe.as_json({**{k: domain.kg(v) for k, v in captured.items()},
                        'reference_events': names, 'original_delivery_count': summary.get('dc_count'),
                        'basis': 'Original delivery-line totals and exact original invoice group references; no financial or stock posting'}))
                job.save()
                return {'job': job.name, 'created': True, 'event': baseline.name, 'references': len(names)}
        except Exception:
            frappe.db.rollback(save_point='migration_billing')
            raise
