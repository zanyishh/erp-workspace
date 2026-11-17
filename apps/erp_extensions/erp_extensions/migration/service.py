"""Trusted import/bridge boundary. No endpoint accepts raw export bodies."""
from contextlib import contextmanager
from contextvars import ContextVar
import json
import re

import frappe
from . import contracts
from .install import SCOPE, RECORD, AUTHORITY

_writing=ContextVar('historical_import_write',default=False)
KINDS={'financial':'financial','stock':'stock','closing_stock':'stock','custody':'custody','closing_custody':'custody'}
TARGETS={'financial':{'Journal Entry','Sales Invoice','Purchase Invoice','Payment Entry'},
         'stock':{'Stock Entry'},'custody':{'Knitting Ledger Entry','Knitting Fabric Batch'}}


def _manager():
    frappe.only_for('System Manager')


def _invalid(message):
    frappe.throw(message,frappe.ValidationError)


def _normalize(fn,*args):
    try:return fn(*args)
    except (ValueError,TypeError) as exc:_invalid(str(exc))


def _json(value):
    return json.loads(value) if isinstance(value,str) else value


@contextmanager
def _write():
    token=_writing.set(True)
    try:yield
    finally:_writing.reset(token)


def guard_write(doc,method=None):
    if doc.doctype not in (SCOPE,RECORD,AUTHORITY):return
    if method in ('on_trash','before_cancel','before_update_after_submit') or not doc.is_new() or not _writing.get():
        frappe.throw('Imported originals and their posting bindings are immutable.',frappe.PermissionError)


def has_permission(doc,ptype,user=None,**kwargs):
    if doc.doctype not in (SCOPE,RECORD,AUTHORITY):return True
    user=user or frappe.session.user
    if ptype not in ('read','select') or not (user=='Administrator' or 'System Manager' in frappe.get_roles(user)):return False
    scope=get_scope(doc.name if doc.doctype==SCOPE else doc.source_scope)
    if user not in scope['allowed_users']:return False
    from erp_extensions.knitting.permissions import company_allowed
    return company_allowed(doc.company,user) if doc.get('company') else any(company_allowed(c,user) for c in scope['company_bindings'].values())


def query_conditions(user=None,doctype=None):
    if doctype not in (SCOPE,RECORD,AUTHORITY):return ''
    user=user or frappe.session.user
    if user!='Administrator' and 'System Manager' not in frappe.get_roles(user):return '1=0'
    from erp_extensions.knitting.permissions import companies
    permitted={c.name for c in companies(user)}
    scopes=[row.name for row in frappe.get_all(SCOPE,fields=['name','scope_data'])
        if user in _json(row.scope_data)['allowed_users'] and permitted.intersection(_json(row.scope_data)['company_bindings'].values())]
    if not scopes:return '1=0'
    field='name' if doctype==SCOPE else 'source_scope'
    condition=f'`tab{doctype}`.`{field}` in ('+','.join(frappe.db.escape(n) for n in scopes)+')'
    if doctype!=SCOPE:
        condition+=' and (coalesce(`company`,\'\')=\'\' or `company` in ('+','.join(frappe.db.escape(c) for c in permitted)+'))'
    return condition


def create_scope(values):
    _manager();scope=_normalize(contracts.normalize_scope,values)
    for company in scope['company_bindings'].values():
        if not frappe.db.exists('Company',company):_invalid('Bind an existing destination Company.')
    for user in scope['allowed_users']:
        if user=='Guest' or not frappe.db.exists('User',{'name':user,'enabled':1}):_invalid('Bind an enabled destination user.')
    digest=contracts.sha(scope);name='scope-'+contracts.sha(scope['source_instance'])[:40]
    if frappe.db.exists(SCOPE,name):
        if frappe.db.get_value(SCOPE,name,'data_sha256')!=digest:_invalid('An immutable migration scope already has different policy or company bindings.')
        return name
    with _write():
        frappe.get_doc({'doctype':SCOPE,'name':name,'source_instance':scope['source_instance'],
            **{f'company_{i}':scope['company_bindings'][str(i)] for i in range(1,5)},
            'scope_data':contracts.canonical(scope),'data_sha256':digest}).insert(ignore_permissions=True,set_name=name)
    return name


def get_scope(name):
    row=frappe.db.get_value(SCOPE,name,['name','scope_data','data_sha256'],as_dict=True)
    if not row:_invalid('The imported business scope does not exist.')
    scope=_json(row.scope_data)
    if contracts.sha(scope)!=row.data_sha256:_invalid('The imported business scope failed its integrity check.')
    return {**scope,'name':row.name}


def require_scope_write(scope,company=None):
    """Administrative role alone cannot write another import scope or business."""
    _manager()
    from erp_extensions.knitting.permissions import company_allowed
    user=frappe.session.user
    bound=set(scope['company_bindings'].values())
    selected={company} if company else bound
    if (user not in scope['allowed_users'] or not selected.issubset(bound)
            or not all(company_allowed(c,user) for c in selected)):
        frappe.throw('This account cannot change imported records for this business scope.',frappe.PermissionError)


@contextmanager
def locked_scope(name):
    if not frappe.db.get_value(SCOPE,name,'name',for_update=True):_invalid('The imported business scope does not exist.')
    yield get_scope(name)


def store_record(scope_name,values):
    _manager()
    with locked_scope(scope_name) as scope:
        record=_normalize(contracts.normalize_record,scope,values)
        require_scope_write(scope,record['company'])
        name='history-'+record['source_key']
        existing=frappe.db.get_value(RECORD,{'source_key':record['source_key']},
            ['name','data_sha256','source_scope','company','shared_cash','shared_reference'],as_dict=True)
        if existing:
            if existing.name!=name or existing.data_sha256!=record['data_sha256'] or existing.source_scope!=scope_name:
                _invalid('This source identity already contains different immutable business facts.')
            if record['company'] is None and existing.company:
                # Older Frappe inserts filled this nullable link with the operator's default.
                if (existing.company not in scope['company_bindings'].values()
                        or existing.shared_cash != record['shared_cash']
                        or existing.shared_reference != record['shared_reference']
                        or get_record(name)['data_sha256'] != record['data_sha256']):
                    _invalid('The shared record has inconsistent company or visibility metadata.')
                frappe.db.set_value(RECORD,name,'company',None)
            return {'name':existing.name,'created':False,'source_key':record['source_key']}
        columns={k:record[k] for k in contracts.REGISTER_COLUMNS}
        with _write():
            doc=frappe.get_doc({'doctype':RECORD,'name':name,'source_scope':scope_name,**columns,
                'record_data':contracts.canonical(record)})
            # An absent original date, reference or owning company must remain absent.
            doc.dont_update_if_missing.extend(columns)
            doc.insert(ignore_permissions=True,set_name=name)
        return {'name':name,'created':True,'source_key':record['source_key']}


def get_record(name):
    row=frappe.db.get_value(RECORD,name,['name','source_scope','record_data','data_sha256'],as_dict=True)
    if not row:_invalid('The original business record does not exist.')
    return record_from_row(row)


def record_from_row(row):
    """Verify already batched source rows with the same immutable-record contract."""
    record=_json(row.record_data);digest=record.pop('data_sha256',None)
    if digest!=row.data_sha256 or contracts.sha(record)!=digest:_invalid('The original business record failed its integrity check.')
    return {**record,'data_sha256':digest,'name':row.name,'source_scope':row.source_scope}


def get_record_for_effect(name,company,effect_kind):
    _manager();record=get_record(name)
    scope=get_scope(record['source_scope'])
    require_scope_write(scope,record['company'])
    if effect_kind not in KINDS:_invalid('Choose a supported historical posting authority.')
    if record['company']!=company or record['shared_cash'] or record['shared_reference']:
        _invalid('A company posting requires its own source company; shared balances cannot be duplicated.')
    if record['date_basis'] not in ('original','approved_opening') or not record['effective_date']:
        _invalid('A posting requires an original date or the approved opening date.')
    if effect_kind!='financial':
        expected='closing_initialization' if effect_kind.startswith('closing_') else 'historical_movements'
        if scope['physical_posting_mode']!=expected:_invalid('This scope uses a different physical posting authority.')
    return record


def _authority_key(scope_name,economic_key,effect_kind):
    if effect_kind not in KINDS:_invalid('Choose a supported historical posting authority.')
    economic_key=_normalize(contracts.identity,economic_key)
    return contracts.sha([scope_name,KINDS[effect_kind],economic_key])


def authority(scope_name,economic_key,effect_kind):
    key=_authority_key(scope_name,economic_key,effect_kind)
    return frappe.db.get_value(AUTHORITY,{'authority_key':key},
        ['name','record','effect_kind','target_doctype','target_name','proof_sha256'],as_dict=True)


def bind_authority(record_name,effect_kind,economic_key,target_doctype,target_name,proof_hash):
    _manager();record=get_record(record_name)
    with locked_scope(record['source_scope']):
        get_record_for_effect(record_name,record['company'],effect_kind)
        if target_doctype not in TARGETS[KINDS[effect_kind]]:_invalid('Unsupported target for this historical effect.')
        if target_doctype=='Knitting Fabric Batch' and effect_kind!='closing_custody':_invalid('Aggregate fabric batches require the closing initialization authority.')
        if not isinstance(proof_hash,str) or not re.fullmatch(r'[0-9a-f]{64}',proof_hash):_invalid('Posting verification evidence is required.')
        target=frappe.get_doc(target_doctype,target_name)
        if target.get('company')!=record['company']:_invalid('The target document belongs to another company.')
        if target.meta.is_submittable and target.docstatus!=1:_invalid('Bind only a successfully submitted target document.')
        previous=authority(record['source_scope'],economic_key,effect_kind)
        if previous:
            if previous.target_doctype!=target_doctype or previous.target_name!=target_name or previous.proof_sha256!=proof_hash:
                _invalid('This economic source already has a different posting authority.')
            return previous.name
        key=_authority_key(record['source_scope'],economic_key,effect_kind)
        with _write():
            doc=frappe.get_doc({'doctype':AUTHORITY,'name':'effect-'+key,'source_scope':record['source_scope'],
                'record':record_name,'authority_key':key,'economic_key':economic_key,'effect_kind':effect_kind,
                'company':record['company'],'target_doctype':target_doctype,'target_name':target_name,'proof_sha256':proof_hash})
            doc.insert(ignore_permissions=True,set_name='effect-'+key)
        return doc.name
