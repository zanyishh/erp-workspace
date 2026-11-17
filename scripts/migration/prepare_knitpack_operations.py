"""Compile verified current native job contexts; no source requests or writes."""
from datetime import date
from decimal import Decimal
import hashlib
import json


def exact(value, *, integer=False):
    if isinstance(value,(bool,float)) or value is None:
        raise ValueError('Use exact saved source quantities.')
    amount=Decimal(str(value))
    if not amount.is_finite() or amount != amount.quantize(Decimal(1) if integer else Decimal('.001')):
        raise ValueError('The source quantity cannot be represented without alteration.')
    return str(int(amount)) if integer else format(amount,'.3f')


def compile_job(company, context, yarn_context, parties):
    job=context['job']; cid=str(job['companymas_id']); jid=str(job['id'])
    if cid not in ('1','2','3','4') or str(yarn_context['id'])!=jid:
        raise ValueError('Native job contexts must have the same company and identity.')
    if job['invoice_type']!='service' or job['completed'] not in ('0','1'):
        raise ValueError('An unmapped source order type or status needs review.')
    if date.fromisoformat(job['jobdate']).isoformat()!=job['jobdate']:
        raise ValueError('The original order date must be preserved.')
    customer=parties[str(job['partymas_id'])];billing=parties[str(job['billed_to'])]
    name=f'KP-JOB-{cid}-{jid}'
    programme,batches,pricing=[],[],{}
    for fabric in context['fabs']:
        if str(fabric['jobmas_id'])!=jid:raise ValueError('Fabric belongs to another order.')
        for dia in fabric['dias']:
            if str(dia['jobfabric_id'])!=str(fabric['id']):raise ValueError('Size belongs to another fabric.')
            key=f"KP-{fabric['id']}-{dia['id']}"
            quantity=exact(dia['stock_kgs']);rolls=exact(dia['stock_rolls'],integer=True)
            row={'id':key,'fabric':fabric['fabName'],'colour':fabric.get('colordesc',''),
                'gsm':[fabric.get('gsm','0')],'ll':[fabric.get('ll','0')],'gauge':fabric.get('gg',''),
                'dia':dia['diaorsize'],'knit_type':fabric.get('knit_type',''),
                'target_kg':exact(dia['programqty']),'source_fabric_id':str(fabric['id']),
                'source_size_id':str(dia['id'])}
            programme.append(row);pricing[key]=str(fabric['billrate'])
            batches.append({'name':f"KP-FAB-{cid}-{jid}-{fabric['id']}-{dia['id']}",
                'company':company,'job':name,'programme_line':key,'quantity_kg':quantity,'rolls':rolls,
                'state':'Awaiting review','source_reference':f"{job['jobno']} · {fabric['id']}/{dia['id']}",
                'specification':row,'produced_kg':exact(dia['prod_qty'])})
    if len({r['id'] for r in programme})!=len(programme):raise ValueError('Repeated native fabric size identity.')
    yarn=[]
    for row in yarn_context['yarn_mas']:
        if str(row['jobmas_id'])!=jid:raise ValueError('Yarn stock belongs to another order.')
        yarn.append({'name':f"KP-YARN-{cid}-{jid}-{row['id']}",'company':company,'job':name,
            'item_code':f"KP-YARN-{cid}-{jid}-{row['yarnmas_id']}",'item_name':row['yarn_name'],
            'source_lot':str(row['id']),'quantity_kg':exact(row['stock_kgs']),
            'units':exact(row['stock_bags'],integer=True),'party':customer,
            'specification':{k:row[k] for k in ('id','jobmas_id','yarnmas_id','countid','colorid','varietyid','millid')},
            'source_received_kg':exact(row['grn_kgs']),'source_returned_kg':exact(row['return_kgs'])})
    if len({r['name'] for r in yarn})!=len(yarn):raise ValueError('Repeated native yarn stock identity.')
    due=job.get('duedate')
    try:due=date.fromisoformat(due).isoformat()
    except (ValueError,TypeError):due=None
    return {'source_company_id':cid,'source_job_id':jid,'source_book':str(job['sec_acc']),
        'job':{'name':name,'company':company,'customer':customer,'billing_customer':billing,
            'job_date':job['jobdate'],'source_reference':str(job['jobno']),'due_date':due,'kind':'Order','material_mode':'Customer','fabric_owner':customer,
            'status':'Completed' if job['completed']=='1' else 'Running','programme':programme,'pricing':pricing,
            'target_kg':exact(job['total_prgrm_qty']),'revision':1,'charge_policy':'Included',
            'notes':f"Original order {job['jobno']}. Original transactions are in Imported history."},
        'batches':batches,'yarn':yarn,
        'physical_basis':'Verified captured stock; service custody, not a reconstructed historical stock ledger.'}


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
