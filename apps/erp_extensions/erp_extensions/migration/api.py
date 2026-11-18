"""Company-scoped history projections. No raw archive or credential endpoints."""
from decimal import Decimal, InvalidOperation

import frappe
from erp_extensions.knitting.permissions import company_allowed
from . import contracts, service
from .install import SCOPE, RECORD, AUTHORITY


# Supporting native records stay reachable from the customer's knitting workspace.
WORKSPACE_RECORDS = frozenset({
    'Company', 'Customer', 'Customer Group', 'Supplier', 'Supplier Group', 'Address', 'Contact',
    'Item', 'Item Group', 'Item Price', 'Item Tax Template', 'UOM', 'Warehouse', 'Warehouse Type',
    'Workstation', 'Workstation Type', 'Holiday List', 'Account', 'Cost Center', 'Finance Book',
    'Fiscal Year', 'Currency', 'Country', 'Territory', 'Bank', 'Bank Account', 'Mode of Payment',
    'Payment Term', 'Payment Terms Template', 'Tax Category', 'Tax Rule',
    'Sales Taxes and Charges Template', 'Purchase Taxes and Charges Template',
    'Quotation', 'Sales Order', 'Sales Invoice', 'Delivery Note', 'Supplier Quotation',
    'Purchase Order', 'Purchase Receipt', 'Purchase Invoice', 'Payment Entry', 'Journal Entry',
    'Material Request', 'Stock Entry', 'Stock Reconciliation', 'Batch', 'Serial No',
    'Quality Inspection', 'Quality Inspection Template',
})


def financial_access():
    return frappe.session.user=='Administrator' or bool(set(frappe.get_roles()) & {
        'System Manager','Accounts Manager','Accounts User','Knitting Manager','Knitting Accountant'})


def _deny():
    frappe.throw('This account cannot read that imported business record.',frappe.PermissionError)


def _member(scope):
    return frappe.session.user!='Guest' and frappe.session.user in scope['allowed_users']


def _scope(company,*,required=True):
    if not company or not company_allowed(company) or not frappe.db.exists('DocType',SCOPE):
        return _deny() if required else None
    names=frappe.get_all(SCOPE,or_filters={f'company_{i}':company for i in range(1,5)},pluck='name',limit_page_length=20)
    scopes=[service.get_scope(name) for name in names]
    scopes=[scope for scope in scopes if _member(scope)]
    if len(scopes)!=1:return _deny() if required else None
    return scopes[0]


def customer_workspace(company):
    """Navigation policy follows verified company/scope membership, not client flags."""
    return _scope(company,required=False) is not None


def available(company):
    """Workspace capability probe; absence is expected on non-imported sites."""
    from erp_extensions.team_scope import membership
    member=membership()
    if member and member.team_role=='cashier':return False
    scope=_scope(company,required=False)
    if not scope:return False
    filters,ors=_filters(scope,company)
    if frappe.get_all(RECORD,filters=filters,or_filters=ors,pluck='name',limit_page_length=1):return True
    return bool(financial_access() and frappe.db.exists(RECORD,{'source_scope':scope['name'],'shared_cash':1}))


def _family(family):
    if family not in contracts.FAMILIES or family in ('cash_movement','cash_opening'):_deny()
    if family in contracts.FINANCIAL_FAMILIES and not financial_access():_deny()


def _paging(start,page_length):
    try:
        start=int(start);page_length=int(page_length)
    except (TypeError,ValueError):frappe.throw('Use a valid history page.')
    if start<0 or start>1000000 or page_length<1 or page_length>100:frappe.throw('Use a page of 1 to 100 records.')
    return start,page_length


def _filters(scope,company,family=None,shared=False):
    filters={'source_scope':scope['name'],'shared_cash':int(shared)}
    if family:filters['family']=family
    elif not financial_access():filters['family']=['not in',list(contracts.FINANCIAL_FAMILIES)]
    # This predicate is applied by the database before pagination or text search.
    return filters,{} if shared else {'company':company,'shared_reference':1}


def _header(row):
    return {'name':row['name'],'family':row['family'],'reference':row.get('original_reference'),
        'original_date':contracts.iso_date(row.get('original_date_raw')),
        'effective_date':str(row['effective_date']) if row.get('effective_date') else None,
        'date_basis':row.get('date_basis'),'review_status':'Original source record',
        'title':row.get('title') or contracts.FAMILIES[row['family']],'summary':row.get('summary') or ''}


PAGE_FIELDS=['name','family','original_reference','original_date_raw','effective_date','date_basis','title','summary']


def _production_job_references(scope,company,originals):
    from .production_jobs import references
    return references(scope, company, originals)


@frappe.whitelist()
def summary(company):
    scope=_scope(company);filters,ors=_filters(scope,company)
    groups=frappe.get_all(RECORD,filters=filters,or_filters=ors,fields=['family',{'COUNT':'name','as':'count'}],group_by='family',limit_page_length=30)
    return {'version':1,'company':company,'scope_available':True,'companies':[c for c in scope['company_bindings'].values() if company_allowed(c)],
        'families':[{'key':row.family,'label':contracts.FAMILIES[row.family],'count':row.count} for row in groups],
        'shared_cash_available':bool(financial_access() and frappe.db.exists(RECORD,{'source_scope':scope['name'],'shared_cash':1}))}


@frappe.whitelist()
def records(company,family,query='',start=0,page_length=40,filters=None):
    scope=_scope(company);_family(family);start,page_length=_paging(start,page_length)
    from . import filtering
    fields=PAGE_FIELDS+['native_id','source_scope','record_data','data_sha256'] if family=='production' else PAGE_FIELDS
    try:
        result=filtering.page(scope['name'],company,family,fields,value=filters,query=query,start=start,page_length=page_length)
        rows=[];originals=[]
        for row in result['rows']:
            if family=='production':
                record=service.record_from_row(row)
                if record['company']!=company or record['family']!=family or record['native_id']!=row.native_id:_deny()
                originals.append(record)
                rows.append({**_header(record),'native_id':record['native_id'],
                    'production_fields':contracts.production_fields(record['business_data'])})
            else:rows.append(_header(row))
        references=_production_job_references(scope,company,originals) if originals else {}
        for row in rows:
            if row['name'] in references:row['job_reference_display']=references[row['name']]
        if family == 'production':
            from . import production_jobs
            result['filter_labels'] = production_jobs.filter_labels(scope, company, filtering.parse(filters))
    except ValueError as error:frappe.throw(str(error))
    return {'version':1,'company':company,'family':family,'start':start,'page_length':page_length,
        **result,'rows':rows}


@frappe.whitelist()
def filter_options(company,family,field,query='',start=0,filters=None):
    scope=_scope(company)
    if family=='shared_cash':
        if not financial_access():_deny()
    else:_family(family)
    start,_=_paging(start,50)
    from . import filtering
    try:
        result=filtering.options(scope['name'],company,family,field,value=filters,query=query,start=start)
        if family == 'production':
            from . import production_jobs
            result['filter_labels'] = production_jobs.filter_labels(scope, company, filtering.parse(filters))
    except ValueError as error:frappe.throw(str(error))
    return {'version':1,'company':company,'family':family,'field':field,**result}


def _visible_record(company,name):
    scope=_scope(company)
    row=frappe.db.get_value(RECORD,{'name':name,'source_scope':scope['name']},['name','company','family','shared_cash','shared_reference'],as_dict=True)
    if not row or (row.company!=company and not row.shared_cash and not row.shared_reference):_deny()
    if row.family in contracts.FINANCIAL_FAMILIES and not financial_access():_deny()
    return scope,service.get_record(name)


def _original_master(record,namespace,native_id):
    names=frappe.get_all(RECORD,filters={'source_scope':record['source_scope'],'namespace':namespace,
        'native_id':str(native_id),'family':'master'},pluck='name',limit_page_length=2)
    if len(names)!=1:return None
    return service.get_record(names[0])['business_data'].get('original_business',{}).get('header')


def _projection(record):
    projection=record['business_data'].get('invoice_print')
    if projection is not None:return projection
    if record['namespace']!='knitpack.general_invoice':return None
    header=record['business_data'].get('original_business',{}).get('header',{})
    company=_original_master(record,'masters.company',record['source_company_id'])
    party=_original_master(record,'masters.party',header.get('party_id'))
    if not company or not party:return None
    from .normalize import general_invoice_projection
    try:return general_invoice_projection(header,company,party,currency=record['business_data']['fields'].get('currency'))
    except (ValueError,TypeError):return None


def _printable(record,projection=None):
    projection=projection if projection is not None else _projection(record)
    return bool(record['family']=='invoice' and contracts.print_projection_ready(projection)
        and projection['posting_date']==contracts.iso_date(record['original_date_raw']))


def _invoice_vouchers(record):
    namespace={'knitpack.invoice':'kpinvoice','knitpack.general_invoice':'kpgeninvoice'}.get(record['namespace'])
    if not namespace:return []
    rows=frappe.db.sql('select name from `tabHistorical Business Record` '
        'where source_scope=%(scope)s and company=%(company)s and source_book=%(book)s '
        'and namespace=\'accv2.voucher\' and family=\'voucher\' '
        'and JSON_UNQUOTE(JSON_EXTRACT(record_data,\'$.business_data.financial.invoice_namespace\'))=%(namespace)s '
        'and JSON_UNQUOTE(JSON_EXTRACT(record_data,\'$.business_data.financial.invoice_native_id\'))=%(native)s limit 2',
        {'scope':record['source_scope'],'company':record['company'],'book':record['source_book'],
            'namespace':namespace,'native':record['native_id']},as_dict=True)
    return [rows[0].name] if len(rows)==1 else []


@frappe.whitelist()
def detail(company,name):
    scope,record=_visible_record(company,name);data=record['business_data'];can_money=financial_access()
    allowed=lambda key:can_money or key not in contracts.MONEY_FIELDS
    fields=[{'label':contracts.FIELD_LABELS[k],'value':v} for k,v in data['fields'].items() if allowed(k)]
    if record['namespace']=='knitpack.general_invoice':
        header=data.get('original_business',{}).get('header',{})
        fields.extend({'label':label,'value':header[key]} for key,label in
            (('prefix','Original prefix'),('inv_no','Original invoice number'),('suffix','Original suffix')) if key in header)
    tables=[]
    for table in data['tables']:
        if table['kind'] in ('taxes','allocations') and not can_money:continue
        keys=[k for k in contracts.FIELD_LABELS if allowed(k) and any(k in row for row in table['rows'])]
        tables.append({'title':contracts.TABLES[table['kind']],
            'columns':[{'key':k,'label':contracts.FIELD_LABELS[k]} for k in keys],
            'rows':[{k:row.get(k) for k in keys} for row in table['rows']]})
    from .dimensions import history_tables
    history_tables(company, record, tables)
    links=[]
    authority_records=[name,*(_invoice_vouchers(record) if can_money else [])]
    for link in frappe.get_all(AUTHORITY,filters={'record':['in',authority_records]},fields=['target_doctype','target_name','effect_kind']):
        if link.effect_kind=='financial' and not can_money:continue
        if frappe.has_permission(link.target_doctype,'read',link.target_name):
            links.append({'doctype':link.target_doctype,'name':link.target_name})
    from .printing import can_print
    record_printable=can_print(company,record)
    printable=_printable(record) and can_money and frappe.has_permission('Sales Invoice','print')
    notes=[contracts.ANOMALIES[a['code']] for a in record['anomalies']]
    if record['date_basis']=='approved_opening':notes.append('The original undated opening is retained; its approved effective date is '+record['effective_date']+'.')
    if record['shared_cash']:notes.append('This is one shared cash book across the four businesses; it is not duplicated in company totals.')
    return {'version':1,'company':company,**_header(record),'review_status':'Review source state' if notes else 'Original source record',
        'fields':fields,'tables':tables,'review_notes':notes,'target_links':links,'printable':bool(printable),'record_printable':record_printable,
        'print_reason':None if printable else 'Original invoice printing requires a valid original date, complete original quantities, rates, taxes and totals, and financial print access.'}


@frappe.whitelist()
def shared_cash(company,start=0,page_length=40,query='',filters=None):
    scope=_scope(company)
    if not financial_access():_deny()
    start,page_length=_paging(start,page_length)
    from . import filtering
    try:result=filtering.page(scope['name'],company,'shared_cash',PAGE_FIELDS,value=filters,query=query,start=start,page_length=page_length)
    except ValueError as error:frappe.throw(str(error))
    global_filters,_=_filters(scope,company,shared=True)
    from .cash import summarize
    control_names=frappe.get_all(RECORD,filters={'source_scope':scope['name'],'namespace':'accv2.cash_ledger','family':'master'},pluck='name')
    controls=[service.get_record(name)['business_data'].get('cash_control') for name in control_names]
    controls=[control for control in controls if control is not None]
    all_names=frappe.get_all(RECORD,filters=global_filters,pluck='name',limit_page_length=0)
    try:balances=summarize([service.get_record(name) for name in all_names],controls)
    except ValueError:frappe.throw('The shared cash import does not yet match its source controls.')
    return {'version':1,'company':company,'family':'shared_cash','start':start,'page_length':page_length,
        **result,'rows':[_header(row) for row in result['rows']],
        'balances':balances,'balances_verified':bool(balances) and all(row['verified'] for row in balances),
        'shared_scope':{'name':scope['name'],'companies':list(scope['company_bindings'].values()),'cash_is_shared':True}}


def _print_tax(row):
    """Translate saved source fields to the shared PDF contract without recomputing tax."""
    result=dict(row)
    for target,sources in (('label',('description',)),('account',('account_head',)),
            ('amount',('tax_amount_after_discount_amount','tax_amount')),
            ('included_in_price',('included_in_print_rate',))):
        if target in result:continue
        for source in sources:
            if source in row:
                result[target]=row[source]
                break
    return result


def _regular_print_pricing(record,data):
    rows=record['business_data'].get('original_business',{}).get('fabric_context',{}).get('samplerates')
    if not isinstance(rows,list) or len(rows)!=len(data['items']):
        frappe.throw('This original invoice is missing its captured delivery pricing context.')
    notes=['Delivery rates come from the captured source context; historical item tariffs are unverified. Original group amounts are retained without recalculation.']
    for index,(source,item) in enumerate(zip(rows,data['items']),1):
        try:
            quantity,rate,amount,sample_quantity,sample_price=[Decimal(str(source[key]))
                for key in ('dlvry_kgs','billrate','fabric_value','kgs','rate')]
            if not all(value.is_finite() for value in (quantity,rate,amount,sample_quantity,sample_price)):
                raise ValueError
            if quantity!=Decimal(str(item['qty'])) or amount!=Decimal(str(item['amount'])):
                raise ValueError
        except (KeyError,InvalidOperation,TypeError,ValueError):
            frappe.throw('This original invoice has incomplete or mismatched delivery pricing fields.')
        item['rate']=source['billrate']
        if sample_quantity or sample_price:
            notes.append(f"Line {index}: source sample quantity {source['kgs']} kg; flat sample price {source['rate']} {data.get('currency','')}. The sample price is not a delivery unit rate.")
        if amount!=quantity*rate:
            notes.append(f'Line {index}: the original group amount differs from delivered kg multiplied by the displayed delivery rate; it is retained without recalculation.')
    data['source_rate_label']='Delivery rate'
    data['source_quantity_label']='Delivered kg'
    data['terms']=(data.get('terms') or '')+'\n'+'\n'.join(notes)


@frappe.whitelist()
def invoice_print_data(company,name):
    _,record=_visible_record(company,name)
    if not financial_access() or not frappe.has_permission('Sales Invoice','print'):_deny()
    projection=_projection(record)
    if not _printable(record,projection):frappe.throw('This original invoice does not contain complete, verified print fields.')
    from erp_extensions.invoices import DEFAULT_STYLE
    data=dict(projection)
    data['taxes']=[_print_tax(row) for row in projection.get('taxes',[])]
    data['items']=[{**row,**({'taxes':[_print_tax(tax) for tax in row['taxes']]} if 'taxes' in row else {})}
        for row in projection.get('items',[])]
    if record['namespace']=='knitpack.invoice':
        _regular_print_pricing(record,data)
        data['source_net_total_label']='Recorded source total'
        data['source_tax_breakdown']=True
        data['taxes']=[{**row,'label':str(row['label'])+' (recorded)'} if row.get('label') else row for row in data['taxes']]
        data['terms']+='\nRecorded source total and recorded tax components are retained independently; this copy does not recalculate a subtotal-plus-tax amount.'
    if record['namespace']=='knitpack.general_invoice':
        header=record['business_data'].get('original_business',{}).get('header',{})
        data['source_prefix']=header.get('prefix');data['source_suffix']=header.get('suffix')
        parts=[label+': '+str(header[key]) for key,label in (('prefix','Original prefix'),('inv_no','Original invoice number'),('suffix','Original suffix')) if key in header]
        data['terms']=(data.get('terms') or '')+'\n'+'; '.join(parts)
    original='Original source copy — '+(record['original_reference'] or record['native_id'])+'. This copy preserves source facts and is not a newly posted ERP invoice.'
    data.update(name=record['original_reference'] or record['native_id'],company=company,source_copy=True,
        source_reference=record['original_reference'],source_record=name,can_set_template=False,
        terms=(data.get('terms') or '')+'\n'+original,docstatus=0,template_id=DEFAULT_STYLE,template_override=None,
        company_template_id=DEFAULT_STYLE,settings={},payments=[],payment_schedule=[],upi_uri=None)
    return data
