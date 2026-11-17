"""Read-only filters over explicit visible original fields, never opaque source data."""
from datetime import date
import json

from . import contracts

PRODUCTION_FIELDS = ('machine', 'operator', 'description', 'dia', 'source_job')
FIELDS = ('source_book', 'party', 'job', 'status', 'shift', *PRODUCTION_FIELDS)
KEYS = frozenset((*FIELDS, 'from_date', 'to_date', 'date_basis'))


def parse(value):
    if isinstance(value, str):
        try:value = json.loads(value)
        except (ValueError, TypeError):raise ValueError('Use valid history filters.') from None
    if value is None:return {}
    if not isinstance(value, dict) or set(value)-KEYS:
        raise ValueError('Use supported history filters.')
    result = dict(value)
    for key, item in result.items():
        if key == 'source_job':
            result[key] = contracts.identity(item)
            continue
        if key == 'source_book' and item is None:continue
        if not isinstance(item, str) or not item or len(item) > (140 if key == 'source_book' else 4096) or '\x00' in item:
            raise ValueError('Use a bounded original filter value.')
    for key in ('from_date', 'to_date'):
        if key in result:
            try:
                if date.fromisoformat(result[key]).isoformat() != result[key]:raise ValueError()
            except ValueError:raise ValueError('Use a valid YYYY-MM-DD history date.') from None
    basis = result.get('date_basis')
    if basis is not None and basis not in ('original', 'effective', 'no_original'):
        raise ValueError('Choose Original date, Effective date or No original date.')
    if 'from_date' in result or 'to_date' in result:
        if basis == 'no_original':raise ValueError('No original date cannot be combined with a date range.')
        result.setdefault('date_basis', 'original')
    if result.get('from_date', '') > result.get('to_date', '9999-12-31'):
        raise ValueError('The history start cannot follow its finish.')
    return result


def expression(field):
    if field not in FIELDS:raise ValueError('Choose a supported history filter.')
    if field == 'source_book':return 'source_book'
    if field == 'source_job':
        path = '$.business_data.original_business.header.'
        job = "JSON_EXTRACT(record_data, '" + path + "jobmas_id')"
        original = "JSON_EXTRACT(record_data, '" + path + "id')"
        company = "JSON_EXTRACT(record_data, '" + path + "companymas_id')"
        value = 'JSON_UNQUOTE(' + job + ')'
        checks = ["JSON_TYPE(" + job + ") in ('STRING','INTEGER')",
                  'char_length(' + value + ') between 1 and 140',
                  "BINARY " + value + " not regexp '[^A-Za-z0-9_.:/-]'",
                  "JSON_TYPE(" + original + ") in ('STRING','INTEGER')",
                  "JSON_TYPE(" + company + ") in ('STRING','INTEGER')",
                  'BINARY JSON_UNQUOTE(' + original + ')=BINARY native_id',
                  'BINARY JSON_UNQUOTE(' + company + ')=BINARY source_company_id']
        return '(CASE WHEN ' + ' and '.join(checks) + ' THEN ' + value + ' ELSE NULL END)'
    # Other selectors use visible normalized fields, never arbitrary original JSON.
    value="JSON_EXTRACT(record_data, '$.business_data.fields."+field+"')"
    return "(CASE WHEN JSON_TYPE("+value+")='NULL' THEN NULL ELSE JSON_UNQUOTE("+value+") END)"


def search_text(value):
    if not isinstance(value, str) or len(value)>100 or '\x00' in value:
        raise ValueError('Use a short history search.')
    return '%'+value.replace('=', '==').replace('%', '=%').replace('_', '=_')+'%'


def predicate(scope, company, family, value=None, query=''):
    f=parse(value)
    if family != 'production' and set(f).intersection(PRODUCTION_FIELDS):
        raise ValueError('Use production dimensions with original production records.')
    params={'scope':scope, 'company':company}
    where=['source_scope=%(scope)s']
    if family == 'shared_cash':
        where.append('shared_cash=1')
    else:
        params['family']=family
        where += ['shared_cash=0', 'family=%(family)s']
        if family == 'production':
            params['namespace'] = 'knitpack.production'
            where += ['company=%(company)s', 'shared_reference=0', 'BINARY namespace=BINARY %(namespace)s']
        else:where.append('(company=%(company)s or shared_reference=1)')
    if query:
        params['query']=search_text(query)
        where.append("(title like %(query)s escape '=' or original_reference like %(query)s escape '=')")
    else:search_text(query)
    for key in FIELDS:
        if key not in f:continue
        column=expression(key)
        if f[key] is None:where.append(column+' is null')
        else:
            params[key]=f[key]
            where.append('BINARY '+column+'=BINARY %('+key+')s')
    if f.get('date_basis')=='original':where.append("date_basis='original'")
    elif f.get('date_basis')=='no_original':where.append("(date_basis is null or date_basis!='original')")
    for key, comparison in (('from_date','>='),('to_date','<=')):
        if key in f:
            params[key]=f[key]
            where.append('effective_date'+comparison+'%('+key+')s')
    return ' and '.join(where),params


def available_fields(scope, company, family):
    import frappe
    where,params=predicate(scope,company,family)
    fields=[key for key in FIELDS[1:] if family=='production' or key not in PRODUCTION_FIELDS]
    columns=["MAX("+expression(key)+" is not null and "+expression(key)+"!='') as "+key for key in fields]
    row=frappe.db.sql('select '+','.join(columns)+' from `tabHistorical Business Record` where '+where,params,as_dict=True)[0]
    return ['source_book', *(key for key in fields if row[key])]


def page(scope,company,family,fields,*,value=None,query='',start=0,page_length=40):
    import frappe
    where,params=predicate(scope,company,family,value,query)
    total=frappe.db.sql('select count(*) from `tabHistorical Business Record` where '+where,params)[0][0]
    order='effective_date desc,name asc'
    if family=='production':
        numeric="native_id regexp '^[0-9]+$'"
        digits="trim(leading '0' from native_id)"
        # Length and binary digits preserve numeric order without integer overflow.
        order=('effective_date desc,case when '+numeric+' then char_length('+digits+') end desc,'
            'case when '+numeric+' then BINARY '+digits+' end desc,name asc')
    rows=frappe.db.sql('select '+','.join(fields)+' from `tabHistorical Business Record` where '+where+
        ' order by '+order+' limit %(limit)s offset %(start)s',
        {**params,'limit':page_length,'start':start},as_dict=True)
    return {'rows':rows,'row_count':total,'has_more':start+len(rows)<total,
        'available_filters':available_fields(scope,company,family)}


def options(scope,company,family,field,*,value=None,query='',start=0):
    import frappe
    if field in PRODUCTION_FIELDS and family!='production':
        raise ValueError('Use production dimensions with original production records.')
    column=expression(field)
    if field == 'source_job':
        from . import production_jobs
        return production_jobs.options(scope, company, value=value, query=query, start=start)
    # A facet can change its own selection while retaining all other predicates.
    f=parse(value);f.pop(field,None)
    where,params=predicate(scope,company,family,f)
    if field!='source_book':where+=' and '+column+" is not null and "+column+"!=''"
    if query:
        params['option_query']=search_text(query)
        where+=' and '+column+" like %(option_query)s escape '='"
    else:search_text(query)
    # Binary grouping preserves case-distinct normalized values and stable paging.
    rows=frappe.db.sql('select '+column+' as value from `tabHistorical Business Record` where '+where+
        ' group by BINARY '+column+' order by BINARY '+column+' limit 51 offset %(start)s',
        {**params,'start':start},as_dict=True)
    return {'rows':[{'value':r.value,'label':'No source book' if r.value is None else r.value} for r in rows[:50]],
        'has_more':len(rows)>50,'start':start}
