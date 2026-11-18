"""Strict, framework-free normalized history contract. Raw exports are not payloads."""
from datetime import date
from decimal import Decimal, InvalidOperation
import hashlib
import json
import re

FAMILIES = {
    'master':'Masters','job':'Orders','yarn_receipt':'Yarn receipts','yarn_return':'Yarn returns',
    'production':'Production','delivery':'Deliveries','invoice':'Invoices','voucher':'Accounts',
    'opening':'Opening balances','cash_movement':'Shared cash movements','cash_opening':'Shared cash openings',
    'adjustment':'Adjustments','subcontract':'Subcontracts','stock_state':'Stock positions'}
FINANCIAL_FAMILIES = frozenset({'invoice','voucher','opening','cash_movement','cash_opening'})
REGISTER_COLUMNS = ('source_key','company','source_company_id','source_book','namespace','native_id','family',
                    'original_reference','original_date_raw','effective_date','date_basis','shared_cash',
                    'shared_reference','title','summary','data_sha256')
FIELD_LABELS = {
    'source_id':'Original record','reference':'Reference','party':'Party','accounting_party':'Accounting party',
    'delivery_party':'Delivery party','customer':'Customer','supplier':'Supplier','job':'Order','job_reference':'Order reference',
    'item':'Item','description':'Description','status':'Status','quantity':'Quantity','net_kg':'Net weight (kg)',
    'gross_kg':'Gross weight (kg)','rolls':'Rolls','bags':'Bags','cones':'Cones','pieces':'Pieces','uom':'Unit',
    'dia':'Diameter / size','knit_type':'Knit type','gsm':'GSM','loop_length':'Loop length','gauge':'Gauge',
    'count':'Yarn count','color':'Colour','variety':'Variety','mill':'Mill','machine':'Machine','operator':'Operator',
    'shift':'Shift','warehouse':'Warehouse','owner':'Material owner','amount':'Amount','rate':'Rate',
    'taxable_value':'Taxable value','cgst':'CGST','sgst':'SGST','igst':'IGST','tax':'Tax','total':'Total',
    'rounding_adjustment':'Rounding','invoice_value':'Original invoice value','posted_amount':'Accounting amount',
    'adjusted_amount':'Source adjusted amount','pending_amount':'Source pending amount','currency':'Currency',
    'entry_type':'Entry type','book':'Book','financial_year':'Financial year','date':'Date','due_date':'Due date',
    'address':'Address','phone':'Phone','email':'Email','gstin':'GSTIN','pan':'PAN','company_name':'Company',
    'role':'Role','original_party_id':'Original party','accounting_party_id':'Accounting party identity',
    'quantity_basis':'Quantity basis','balance':'Balance','available':'Available','received':'Received',
    'delivered':'Delivered','returned':'Returned','produced':'Produced','notes':'Notes',
    'debit':'Source debit','credit':'Source credit','native_amount':'Original voucher amount','cash_book':'Shared cash category'}
MONEY_FIELDS = frozenset({'amount','rate','taxable_value','cgst','sgst','igst','tax','total','rounding_adjustment',
                         'invoice_value','posted_amount','adjusted_amount','pending_amount','balance','debit','credit','native_amount'})
TABLES = {'items':'Items','taxes':'Taxes','quantities':'Quantities','references':'References',
          'allocations':'Source adjustments','changes':'Changes','stock':'Stock','parties':'Parties'}
FINANCIAL_KEYS = frozenset({'amount','currency','entry_type','voucher_type','accounting_party_id','invoice_party_id',
    'general_ledger_id','cash_ledger_id','payment_mode','invoice_namespace','invoice_native_id','source_reference',
    'original_invoice_value','original_r_invoice_value','source_adjusted_amount','source_pending_amount',
    'taxable_amount','cgst_amount','sgst_amount','igst_amount','cancelled'})
ANOMALIES = {
    'invalid_original_date':'The original transaction date is unavailable or invalid; no date was invented.',
    'party_identity_difference':'Original invoice and accounting parties differ; both identities are retained.',
    'amount_projection':'Original invoice and accounting amounts use the source’s recorded rounding presentation.',
    'header_detail_basis':'Original summary and detailed quantities use different retained source aggregation bases.',
    'adjusted_state_difference':'The source adjusted state remains distinct from reconstructed bill references.',
    'view_total_difference':'The source current adjustment view differs from its saved control.',
    'missing_current_state':'Current source state is unavailable; historical records are retained.',
    'unmapped_reference':'A source reference has not been bound to a verified target.',
    'cancelled_source':'The source record is cancelled; no cancellation history was invented.',
    'source_review':'This original source state requires review.',
    'shared_cash':'This cash record belongs to the shared book, not four separate company balances.'}
ZERO_DATES = (None,'','0','0000-00-00','0000-00-00 00:00:00')
SENSITIVE = re.compile(r'password|secret|token|session|cookie|authorization|credential|userinfo|rcloud|api.?key|^auth$',re.I)


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)


def sha(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def text(value, limit=140, *, optional=False):
    if optional and value is None:return None
    if not isinstance(value,str) or not value or len(value)>limit or '\x00' in value:
        raise ValueError('A bounded original business value is required.')
    return value


def identity(value, *, optional=False):
    if optional and value is None:return None
    value=str(value) if isinstance(value,int) and not isinstance(value,bool) else value
    value=text(value)
    if value!=value.strip() or not re.fullmatch(r'[A-Za-z0-9_.:/-]+',value):
        raise ValueError('Use a canonical source identity.')
    return value


def iso_date(value):
    if not isinstance(value,str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}',value):return None
    try:return date.fromisoformat(value).isoformat()
    except ValueError:return None


def reject_raw_metadata(value):
    if isinstance(value,dict):
        for key,child in value.items():
            if not isinstance(key,str) or SENSITIVE.search(key):raise ValueError('Raw authentication or archive metadata is not business data.')
            reject_raw_metadata(child)
    elif isinstance(value,list):
        for child in value:reject_raw_metadata(child)


def scalar(value):
    if isinstance(value,Decimal):value=format(value,'f')
    if value is None or isinstance(value,(bool,int)):return value
    if isinstance(value,str) and len(value)<=4096 and '\x00' not in value:return value
    raise ValueError('Business fields must be bounded scalar values; use exact decimal strings for money.')


def production_fields(data):
    """Fixed original-production list columns; never project raw or money fields."""
    fields = data.get('fields', {})
    return {key: scalar(fields.get(key)) for key in
        ('job', 'party', 'description', 'dia', 'net_kg', 'rolls', 'machine', 'operator', 'shift')}


def normalize_scope(value):
    allowed={'source_instance','company_bindings','allowed_users','opening_effective_date','physical_posting_mode','shared_cash_policy','manifest_sha256','policy_evidence_sha256'}
    if not isinstance(value,dict) or set(value)-allowed:raise ValueError('Use the fixed migration scope contract.')
    bindings=value.get('company_bindings');users=value.get('allowed_users')
    if not isinstance(bindings,dict) or set(bindings)!={'1','2','3','4'}:raise ValueError('Bind exactly four source companies.')
    companies=[text(bindings[str(i)]) for i in range(1,5)]
    if len(set(companies))!=4:raise ValueError('Each source company needs a distinct destination Company.')
    if not isinstance(users,list) or not users or len(users)>1000:raise ValueError('Explicit destination scope members are required.')
    users=sorted({text(u) for u in users})
    opening=iso_date(value.get('opening_effective_date'))
    if not opening:raise ValueError('The approved opening effective date is required.')
    mode=value.get('physical_posting_mode','unconfigured')
    if mode not in ('unconfigured','historical_movements','closing_initialization'):raise ValueError('Choose an explicit physical posting mode.')
    if value.get('shared_cash_policy','shared_pool')!='shared_pool':raise ValueError('Cash books must retain their approved shared scope.')
    for field in ('manifest_sha256','policy_evidence_sha256'):
        if not isinstance(value.get(field),str) or not re.fullmatch(r'[0-9a-f]{64}',value[field]):raise ValueError('Scope evidence hashes are required.')
    return {**value,'source_instance':identity(value.get('source_instance')),'company_bindings':dict(zip(('1','2','3','4'),companies)),
        'allowed_users':users,'opening_effective_date':opening,'physical_posting_mode':mode,'shared_cash_policy':'shared_pool'}


def business_data(value):
    if not isinstance(value,dict) or set(value)-{'fields','tables','financial','invoice_print','original_business','cash_control'}:raise ValueError('Use reviewed business fields and tables.')
    reject_raw_metadata(value)
    fields=value.get('fields',{})
    if not isinstance(fields,dict) or set(fields)-FIELD_LABELS.keys():raise ValueError('An unreviewed business field was supplied.')
    tables=value.get('tables',[])
    if not isinstance(tables,list) or len(tables)>12:raise ValueError('Use bounded business tables.')
    output={'fields':{k:scalar(v) for k,v in fields.items()},'tables':[]}
    for table in tables:
        if not isinstance(table,dict) or set(table)!={'kind','rows'} or table['kind'] not in TABLES or not isinstance(table['rows'],list) or len(table['rows'])>1000:
            raise ValueError('Use a supported bounded business table.')
        rows=[]
        for row in table['rows']:
            if not isinstance(row,dict) or set(row)-FIELD_LABELS.keys():raise ValueError('An unreviewed table field was supplied.')
            rows.append({k:scalar(v) for k,v in row.items()})
        output['tables'].append({'kind':table['kind'],'rows':rows})
    financial=value.get('financial')
    if financial is not None:
        if not isinstance(financial,dict) or set(financial)-FINANCIAL_KEYS:raise ValueError('Use the fixed financial record contract.')
        output['financial']={k:scalar(v) for k,v in financial.items()}
    if 'invoice_print' in value:output['invoice_print']=normalize_print_projection(value['invoice_print'])
    if 'original_business' in value:output['original_business']=original_business(value['original_business'])
    if 'cash_control' in value:
        control=value['cash_control']
        required={'cash_book_id','label','opening_debit','opening_credit','movement_debit','movement_credit','closing_net','opening_count','movement_count'}
        if not isinstance(control,dict) or not required<=set(control) or set(control)-required-{'as_of_date'}:raise ValueError('Use the fixed shared cash control contract.')
        from .cash import amount
        for key in ('opening_debit','opening_credit','movement_debit','movement_credit','closing_net'):amount(control[key])
        for key in ('opening_count','movement_count'):
            if type(control[key]) is not int or control[key]<0:raise ValueError('Use exact source cash row counts.')
        output['cash_control']={k:scalar(v) for k,v in control.items()}
    if len(canonical(output))>524288:raise ValueError('The business record is too large.')
    return output


def original_business(value, depth=0):
    """A caller supplies known native business schemas, never response envelopes."""
    if depth>8:raise ValueError('Original business data is too deeply nested.')
    forbidden={'request','response','variables','pass','uri','headers','created_by','updated_by','user_id','userid','user','owner','modified_by','user_editable','usereditable','islogin'}
    if isinstance(value,dict):
        if len(value)>300:raise ValueError('Original business fields exceed the supported schema size.')
        result={}
        for key,child in value.items():
            if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,80}',key) or key.lower() in forbidden or SENSITIVE.search(key):
                raise ValueError('Only sanitized original business fields may be retained.')
            result[key]=original_business(child,depth+1)
        return result
    if isinstance(value,list):
        if len(value)>2000:raise ValueError('Original business rows exceed the supported size.')
        return [original_business(child,depth+1) for child in value]
    return scalar(value)


PRINT_KEYS = frozenset({'seller_name','customer','customer_name','posting_date','due_date','po_no','po_date','status','is_return',
    'return_against','currency','precision','company_currency','company_currency_precision','company_address','billing_address',
    'shipping_address','company_gstin','customer_gstin','place_of_supply','in_words','terms','apply_discount_on','disable_rounded_total',
    'items','taxes','total','net_total','total_taxes_and_charges','grand_total','rounded_total','rounding_adjustment','discount_amount',
    'additional_discount_percentage','outstanding_amount','paid_amount'})
PRINT_ITEM_KEYS=frozenset({'item_code','item_name','description','hsn_sac','uom','qty','rate','amount','net_rate','net_amount',
                         'discount_amount','discount_percentage','taxes'})
PRINT_TAX_KEYS=frozenset({'account_head','description','rate','tax_amount','tax_amount_after_discount_amount','total','charge_type','included_in_print_rate','amount'})


def normalize_print_projection(value):
    if not isinstance(value,dict) or set(value)-PRINT_KEYS:raise ValueError('Use reviewed original invoice print fields.')
    result={k:scalar(v) for k,v in value.items() if k not in ('items','taxes')}
    for key,allowed in (('items',PRINT_ITEM_KEYS),('taxes',PRINT_TAX_KEYS)):
        if key not in value:continue
        if not isinstance(value[key],list) or len(value[key])>1000:raise ValueError('Use bounded original invoice lines.')
        result[key]=[]
        for row in value[key]:
            if not isinstance(row,dict) or set(row)-allowed:raise ValueError('Use reviewed original invoice line fields.')
            clean={k:scalar(v) for k,v in row.items() if k!='taxes'}
            if 'taxes' in row:
                if not isinstance(row['taxes'],list):raise ValueError('Use original line taxes.')
                clean['taxes']=[{k:scalar(v) for k,v in tax.items()} for tax in row['taxes'] if isinstance(tax,dict) and not set(tax)-PRINT_TAX_KEYS]
                if len(clean['taxes'])!=len(row['taxes']):raise ValueError('An unreviewed tax field was supplied.')
            result[key].append(clean)
    return result


def print_projection_ready(value):
    if not isinstance(value,dict) or not iso_date(value.get('posting_date')):return False
    if not all(value.get(k) for k in ('seller_name','customer_name','currency')):return False
    if not isinstance(value.get('items'),list) or not value['items'] or not isinstance(value.get('taxes'),list):return False
    try:
        amounts=[value['grand_total'],*(r[k] for r in value['items'] for k in ('qty','rate','amount'))]
        return all(v is not None and Decimal(str(v)).is_finite() for v in amounts)
    except (KeyError,InvalidOperation,TypeError,ValueError):return False


def normalize_record(scope, values):
    allowed={'namespace','source_company_id','source_book','native_id','parent_scope','family','original_reference',
             'original_date_raw','effective_date','title','summary','business_data','provenance','anomalies','shared_cash','shared_reference'}
    if not isinstance(values,dict) or set(values)-allowed:raise ValueError('Use the fixed historical business record contract.')
    reject_raw_metadata(values)
    family=values.get('family')
    if family not in FAMILIES:raise ValueError('Choose a supported historical business family.')
    source_company=identity(values.get('source_company_id'),optional=True)
    shared=values.get('shared_cash',False);reference=values.get('shared_reference',False)
    if type(shared) is not bool or type(reference) is not bool:raise ValueError('Visibility choices must be explicit.')
    if shared and (family not in ('cash_movement','cash_opening') or reference):raise ValueError('Only shared cash families use the shared cash view.')
    if reference and (family!='master' or shared):raise ValueError('Only master references may use shared reference visibility.')
    if family in ('cash_movement','cash_opening') and not shared:raise ValueError('Cash books must remain shared.')
    if source_company not in scope['company_bindings'] and not (source_company is None and (shared or reference)):
        raise ValueError('The source company is outside this migration scope.')
    book=identity(values.get('source_book'),optional=True)
    if family in ('invoice','voucher','opening') and book is None:raise ValueError('Financial source book identity is required.')
    parents=values.get('parent_scope',[])
    if not isinstance(parents,list) or len(parents)>8:raise ValueError('Use explicit source parent identities.')
    parents=[identity(v) for v in parents]
    key={'instance':scope['source_instance'],'namespace':identity(values.get('namespace')),'company':source_company,
         'book':book,'native_id':identity(values.get('native_id')),'parents':parents}
    original=values.get('original_date_raw')
    if original is not None and (not isinstance(original,str) or len(original)>64):raise ValueError('Retain the original date string without coercion.')
    effective=iso_date(original)
    basis='original' if effective else 'not_applicable' if family=='master' else 'undated_review'
    if family in ('opening','cash_opening') and original in ZERO_DATES:
        effective,basis=scope['opening_effective_date'],'approved_opening'
    if 'effective_date' in values and values['effective_date']!=effective:raise ValueError('The effective date conflicts with the source/date policy.')
    anomalies=values.get('anomalies',[])
    if not isinstance(anomalies,list) or len(anomalies)>30:raise ValueError('Use bounded source review codes.')
    result_anomalies=[]
    for anomaly in anomalies:
        if not isinstance(anomaly,dict) or set(anomaly)-{'code'} or anomaly.get('code') not in ANOMALIES:raise ValueError('Use a reviewed source anomaly code, not a raw server message.')
        result_anomalies.append({'code':anomaly['code']})
    if basis=='undated_review':result_anomalies.append({'code':'invalid_original_date'})
    provenance=values.get('provenance')
    if not isinstance(provenance,list) or not provenance or len(provenance)>100:raise ValueError('Hash-bound source provenance is required.')
    refs=[]
    for ref in provenance:
        if not isinstance(ref,dict) or set(ref)!={'file','sha256','pointer'}:raise ValueError('Use only file/hash/pointer provenance.')
        if not isinstance(ref['file'],str) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,220}',ref['file']):raise ValueError('Use an archive artifact label, not a path or URL.')
        if not isinstance(ref['sha256'],str) or not re.fullmatch(r'[0-9a-f]{64}',ref['sha256']):raise ValueError('Use an exact source content hash.')
        if not isinstance(ref['pointer'],str) or not ref['pointer'].startswith('/') or len(ref['pointer'])>500 or SENSITIVE.search(ref['pointer']):raise ValueError('Use a business-record JSON pointer.')
        refs.append(ref)
    result={'source_key':sha(key),'namespace':key['namespace'],'source_company_id':source_company,'source_book':book,
        'native_id':key['native_id'],'parent_scope':parents,'company':None if shared or reference else scope['company_bindings'][source_company],
        'family':family,'original_reference':text(values.get('original_reference'),optional=True),
        'original_date_raw':original,'effective_date':effective,'date_basis':basis,'shared_cash':shared,'shared_reference':reference,
        'title':text(values.get('title',FAMILIES[family]),200),'summary':text(values.get('summary'),500,optional=True),
        'business_data':business_data(values.get('business_data',{})),
        'anomalies':[json.loads(v) for v in sorted({canonical(a) for a in result_anomalies})],
        'provenance':[json.loads(v) for v in sorted({canonical(r) for r in refs})]}
    result['data_sha256']=sha(result)
    return result
