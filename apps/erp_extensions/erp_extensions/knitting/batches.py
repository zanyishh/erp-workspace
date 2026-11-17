"""Fabric batches with measured total weight and count, without per-roll inference."""
import hashlib
from decimal import Decimal
import frappe
from . import domain


def selected(event, data, job):
    batch = domain.reference('Knitting Fabric Batch', data.get('batch'), event.company, lock=True)
    if batch.job != job.name:
        frappe.throw('Choose a fabric batch from this order.')
    if job.material_mode != 'Customer':
        frappe.throw('This batch belongs to a service order; owned stock needs its stock valuation records.')
    if batch.state == 'Cancelled':
        frappe.throw('This batch production was cancelled.')
    return batch


def produce(event, data, job):
    return domain.produce(event, data, job, aggregate=True)


def produce_rows(event, data, job):
    from erp_extensions.api import _check_version
    rows = data.get('entries')
    allowed = {'job', 'modified', 'programme_line', 'quantity_kg', 'rolls', 'inputs',
        'loss_kg', 'warehouse', 'machine', 'shift', 'remarks', 'production_operator', 'production_machine'}
    if (job is not None or set(data) != {'entries'} or not isinstance(rows, list) or not 1 <= len(rows) <= 50
            or any(not isinstance(row, dict) or set(row) - allowed for row in rows)):
        frappe.throw('Enter one to 50 measured production rows, with no individual roll weights.')
    versions = {}
    for row in rows:
        name, modified = row.get('job'), row.get('modified')
        if (not isinstance(name, str) or not name.strip() or len(name) > 140
                or not isinstance(modified, str) or not modified or len(modified) > 40):
            frappe.throw('Each production row needs its selected job and current version.')
        if name in versions and versions[name] != modified:
            frappe.throw('Repeated rows for one job must use the same current version.')
        versions[name] = modified
    jobs = {}
    for name in sorted(versions):
        source = domain.reference('Knitting Job', name, event.company, lock=True)
        _check_version(source, versions[name])
        if source.status != 'Running' or source.material_mode != 'Customer':
            frappe.throw('Record measured production rows only for running customer-owned jobs.')
        jobs[name] = source
    children = []
    for index, row in enumerate(rows):
        payload = {key: value for key, value in row.items() if key != 'modified'}
        child = domain.insert('Knitting Event', company=event.company, job=row['job'], kind='produce_batch',
            request_key=hashlib.sha256(f'{event.request_key}|produce_batch|{index}'.encode()).hexdigest(),
            payload_hash=hashlib.sha256(f'{event.payload_hash}|{index}'.encode()).hexdigest(),
            actor=event.actor, occurred_at=event.occurred_at, payload=frappe.as_json(payload))
        result = produce(child, payload, jobs[row['job']])
        child.result = frappe.as_json(result)
        child.save()
        children.append({'event': child.name, 'job': row['job'], 'batch': result['batch'],
            'programme_line': row.get('programme_line'), 'result': result})
    for source in jobs.values():
        source.save()
    return {'children': children}


def quantities(data, available_kg, available_rolls):
    quantity = domain.decimal(data.get('quantity_kg'), positive=True)
    rolls = domain.decimal(data.get('rolls'), precision=0)
    if quantity > available_kg or rolls > available_rolls or (quantity == available_kg and rolls != available_rolls):
        frappe.throw('Weight and roll count must fit this batch. Moving all its weight must move all remaining rolls.')
    return quantity, rolls


def review(event, data, job):
    batch = selected(event, data, job)
    decision, remarks = data.get('decision'), data.get('remarks')
    if decision not in ('Released', 'On Hold') or not isinstance(remarks, str) or not remarks.strip() or len(remarks)>1000:
        frappe.throw('Record the batch check and choose Released or On Hold.')
    if decision == 'Released' and (Decimal(batch.quantity_kg)<0 or Decimal(batch.rolls)<0):
        frappe.throw('Resolve the original negative stock balance before releasing this batch.')
    previous = batch.state
    batch.state = decision
    batch.save()
    return {'batch':batch.name, 'previous_state':previous,'state':decision,'remarks':remarks.strip()}


def deliver(event, data, job):
    batch = selected(event, data, job)
    if batch.state != 'Released':
        frappe.throw('Check and release this batch before delivery.')
    quantity, rolls = quantities(data, Decimal(batch.quantity_kg), Decimal(batch.rolls))
    transport = {}
    for key in ('destination','transport','transport_reference'):
        value = data.get(key,'')
        if not isinstance(value,str) or len(value)>500:
            frappe.throw('Keep delivery and transport details within 500 characters.')
        transport[key] = value.strip()
    batch.quantity_kg = domain.kg(Decimal(batch.quantity_kg)-quantity)
    batch.rolls = str(int(Decimal(batch.rolls)-rolls))
    batch.save()
    rate = domain.json_value(job.pricing,{}).get(batch.programme_line,domain.money(job.rate or 0))
    source = {'batch':batch.name,'programme_line':batch.programme_line,'quantity_kg':domain.kg(quantity),
              'rolls':str(int(rolls)),'rate':rate}
    return {'batch':batch.name,**transport,'quantity_kg':domain.kg(quantity),'roll_count':str(int(rolls)),
            'lines':[source],'sources':[source],'charges':[],'voucher':None,'voucher_type':None}


def return_batch(event, data, job):
    batch = selected(event, data, job)
    delivery = domain.reference('Knitting Event', data.get('delivery'), event.company)
    reason = data.get('reason')
    if delivery.kind!='deliver_batch' or delivery.job!=job.name or delivery.cancelled or not isinstance(reason,str) or not reason.strip() or len(reason)>1000:
        frappe.throw('Choose this order’s batch delivery and record a return reason.')
    value = domain.json_value(delivery.result,{})
    sources = [r for r in value.get('sources',[]) if r.get('batch')==batch.name]
    if len(sources)!=1:
        frappe.throw('The batch must belong to the selected delivery.')
    source = sources[0]
    prior = [domain.json_value(e.result,{}) for e in domain.job_events(job.name,'return_batch')]
    prior = [r for r in prior if r.get('delivery')==delivery.name and r.get('batch')==batch.name]
    available = Decimal(source['quantity_kg'])-sum((Decimal(r['quantity_kg']) for r in prior),Decimal(0))
    available_rolls = Decimal(source['rolls'])-sum((Decimal(r['roll_count']) for r in prior),Decimal(0))
    quantity, rolls = quantities(data,available,available_rolls)
    billed = domain.delivery_billed(job.name,delivery.name,batch.programme_line,batch=batch.name)
    if quantity > available-billed:
        frappe.throw('Credit the billed weight before returning it to stock.')
    batch.quantity_kg = domain.kg(Decimal(batch.quantity_kg)+quantity)
    batch.rolls = str(int(Decimal(batch.rolls)+rolls))
    batch.state = 'Awaiting review'
    batch.save()
    return {'batch':batch.name,'delivery':delivery.name,'quantity_kg':domain.kg(quantity),
        'roll_count':str(int(rolls)),'reason':reason.strip(),
        'allocations':[{'batch':batch.name,'programme_line':batch.programme_line,'quantity_kg':domain.kg(quantity)}]}


ACTIONS = {'produce_batch':('production',produce), 'review_batch':('quality',review),
    'produce_batches':('production',produce_rows),
    'deliver_batch':('delivery',deliver),'return_batch':('delivery',return_batch)}
