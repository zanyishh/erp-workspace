"""Offline source conversion helpers. They never call Frappe or a source server."""
from decimal import Decimal, InvalidOperation
import hashlib
import json
import re
from . import contracts

PRIVATE_KEYS=frozenset({'request','response','variables','pass','uri','headers','created_by','updated_by','prepared_by',
    'user_id','userid','user','owner','modified_by','user_editable','usereditable','islogin','currentuserinfo',
    'rcloud_dev_id','rc_session','session_id','cmp_logo','avatar','prod_query'})


def private_field(key):
    return key.lower() in PRIVATE_KEYS or bool(contracts.SENSITIVE.search(key))


def clean_business(value,allowed_fields):
    """A reviewed, closed native schema is supplied by the offline assembler."""
    if isinstance(value,dict):
        clean={}
        for key,child in value.items():
            if private_field(key):continue
            if key not in allowed_fields:raise ValueError('Unreviewed original business field: '+key)
            clean[key]=clean_business(child,allowed_fields)
        return clean
    if isinstance(value,list):return [clean_business(child,allowed_fields) for child in value]
    return contracts.scalar(value)


def success(value):
    return (isinstance(value,dict) and 'rc_error' not in value and value.get('isLogin') is not False
        and str(value.get('mode','')).lower() not in ('error','failed','failure'))


def read_artifact(directory,entry):
    name=entry['file']
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,220}',name):raise ValueError('Use a manifested artifact basename.')
    raw=(directory/name).read_bytes()
    if len(raw)!=entry['bytes'] or hashlib.sha256(raw).hexdigest()!=entry['sha256']:
        raise ValueError('The captured artifact differs from its immutable manifest.')
    return json.loads(raw,parse_float=Decimal),{'file':name,'sha256':entry['sha256'],'pointer':'/'}


def print_line(row,*,quantity,rate,amount,description):
    try:
        values=[row[k] for k in (quantity,rate,amount)]
        if any(v is None or not Decimal(str(v)).is_finite() for v in values):return None
    except (KeyError,InvalidOperation,TypeError,ValueError):return None
    name=row.get(description)
    if not isinstance(name,str):return None
    return {'item_name':name,'description':name,'qty':contracts.scalar(values[0]),
        'rate':contracts.scalar(values[1]),'amount':contracts.scalar(values[2])}


def general_invoice_projection(header,company,party,*,currency):
    """Project saved fields; an explicitly blank line description stays blank."""
    if (str(header.get('companymas_id'))!=str(company.get('id')) or
        str(header.get('party_id'))!=str(party.get('id'))):
        raise ValueError('Original invoice and master identities must match exactly.')
    items=[]
    for line in header.get('item_details',[]):
        description=line.get('item_disc')
        if isinstance(description,dict):description=description.get('fab_name')
        item=print_line({**line,'description':description},quantity='qty',rate='price',amount='total',description='description')
        if item is None:return None
        if 'hsn' in line:item['hsn_sac']=line['hsn']
        items.append(item)
    if not items or not company.get('name') or not party.get('party_name') or not currency:return None
    taxes=[]
    for key,label in (('cgst_value','CGST'),('sgst_value','SGST'),('igst_value','IGST'),('tcs_value','TCS')):
        if key in header:taxes.append({'description':label,'tax_amount':contracts.scalar(header[key])})
    # All three saved tax fields are needed; a missing field is not zero.
    if any(k not in header for k in ('cgst_value','sgst_value','igst_value')):return None
    address=lambda data,fields:', '.join(str(data[k]) for k in fields if data.get(k))
    result={'seller_name':company['name'],'customer':str(party['id']),'customer_name':party['party_name'],
        'posting_date':header.get('inv_date'),'currency':currency,'precision':2,'company_currency':currency,'company_currency_precision':2,
        'items':items,'taxes':taxes,'grand_total':contracts.scalar(header.get('invoice_value')),'disable_rounded_total':1,
        'company_address':address(company,('address1','address2','address3','city','state','bill_zip_code')),
        'billing_address':address(party,('bill_address1','bill_address2','bill_address3','bill_city','bill_state','bill_zip_code')),
        'company_gstin':company.get('gstin'),'customer_gstin':party.get('gstin'),
        'terms':'Original accounting amount: '+str(header.get('r_invoice_value'))+' '+currency+'. Original blank descriptions remain blank.'}
    for source,target in (('total_item_val','total'),('nettotal_value','net_total'),('tax_total_value','total_taxes_and_charges')):
        if source in header:result[target]=contracts.scalar(header[source])
    return result if contracts.print_projection_ready(result) else None
