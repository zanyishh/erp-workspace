"""Reviewed CSV to submitted Bank Transactions, with duplicate detection per bank account."""
import csv
from datetime import datetime
from decimal import Decimal, InvalidOperation
from hashlib import sha256
from io import StringIO
import re

import frappe

from erp_extensions.bank_matching import _bank

FIELDS = {'date', 'deposit', 'withdrawal', 'reference', 'description', 'id'}
SUGGESTIONS = {
    'date':('date','booking date','transaction date','value date'), 'deposit':('deposit','deposits','credit','credit amount','money in'),
    'withdrawal':('withdrawal','withdrawals','debit','debit amount','money out'), 'reference':('reference','reference number','reference no','cheque number'),
    'description':('description','narration','details','memo'), 'id':('transaction id','bank transaction id','bank id')}
FORMATS = {'YMD':'%Y-%m-%d', 'DMY':'%d/%m/%Y', 'MDY':'%m/%d/%Y'}


def _csv(content):
    if len(content.encode('utf-8')) > 262144:
        frappe.throw('Choose a UTF-8 CSV file up to 256 KB.')
    reader = csv.reader(StringIO(content.removeprefix('\ufeff'), newline=''), strict=True)
    try:
        headers = [s.strip() for s in next(reader, [])]
        if not headers or len(headers)>50 or not all(headers) or len(set(h.casefold() for h in headers))!=len(headers):
            frappe.throw('Use up to 50 named columns with distinct headers.')
        rows = []
        for values in reader:
            if not any(v.strip() for v in values):
                continue
            if len(values)!=len(headers) or len(rows)>=200:
                frappe.throw(f'Check CSV line {reader.line_num}. Use one value per column and up to 200 data rows.')
            rows.append((reader.line_num, dict(zip(headers,[v.strip() for v in values],strict=True))))
    except csv.Error:
        frappe.throw(f'Check the CSV quoting near line {reader.line_num}.')
    if not rows:
        frappe.throw('Add statement transactions below the header.')
    return headers,rows


def _money(text, precision, line):
    if not text:
        return Decimal(0)
    if not re.fullmatch(r'(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?',text):
        frappe.throw(f'Line {line} needs a non-negative amount using a decimal point.')
    try:
        value = Decimal(text.replace(',',''))
        if value >= Decimal('1e14') or value != round(value,precision):
            raise ValueError
    except (InvalidOperation, ValueError):
        frappe.throw(f'Line {line} exceeds the amount range or currency precision.')
    return value


def _date(text, format_key, line):
    try:
        return datetime.strptime(text, FORMATS[format_key]).date().isoformat()
    except (ValueError,KeyError):
        frappe.throw(f'Line {line} does not match the selected date format.')


def _read_rows(content, mapping, date_format, currency, precision):
    headers, records = _csv(content)
    if (not isinstance(mapping,dict) or set(mapping)-FIELDS or not all(isinstance(v,str) and v in headers for v in mapping.values())
            or len(set(mapping.values()))!=len(mapping) or not mapping.get('date') or not ('deposit' in mapping or 'withdrawal' in mapping)):
        frappe.throw('Map the date and at least one amount column. Use each file column once.')
    result, bank_ids, seen = [], set(), set()
    anonymous = set()
    for line, source in records:
        value = {k:source[v] for k,v in mapping.items()}
        day = _date(value['date'],date_format,line)
        credit = _money(value.get('deposit'),precision,line)
        debit = _money(value.get('withdrawal'),precision,line)
        if bool(credit) == bool(debit):
            frappe.throw(f'Line {line} must have exactly one positive deposit or withdrawal.')
        bank_id, reference, narration = [value.get(k,'') for k in ('id','reference','description')]
        if len(bank_id)>140 or len(reference)>1000 or len(narration)>4000:
            frappe.throw(f'Line {line} has an identifier or description that is too long.')
        if bank_id and bank_id.casefold() in bank_ids:
            frappe.throw(f'Line {line} repeats a transaction ID within this statement.')
        if bank_id:
            bank_ids.add(bank_id.casefold())
        record = {'date':day,'deposit':credit,'withdrawal':debit,'reference_number':reference,'description':narration}
        key = (day,credit,debit,reference,narration)
        if key in anonymous or (not bank_id and key in seen):
            frappe.throw(f'Line {line} is indistinguishable from another line. Map distinct bank transaction IDs to import both.')
        seen.add(key)
        if not bank_id:
            anonymous.add(key)
        digest = sha256(frappe.as_json([day,format(credit.normalize(),'f'),format(debit.normalize(),'f'),currency,reference,narration]).encode()).hexdigest()
        result.append({'line':line,'identity':bank_id or 'native-csv-'+digest,'record':record,'has_id':bool(bank_id)})
    return result


def _existing(bank, entry, lock):
    values = entry['record']
    where = {'bank_account':bank,'transaction_id':entry['identity']}
    fields = ['name','date','deposit','withdrawal','reference_number','description','docstatus','transaction_id']
    found = frappe.db.get_value('Bank Transaction',where,fields,as_dict=True,for_update=lock)
    if found:
        same = (str(found.date)==values['date'] and Decimal(str(found.deposit or 0))==values['deposit'] and
                Decimal(str(found.withdrawal or 0))==values['withdrawal'] and
                (found.reference_number or '')==values['reference_number'] and (found.description or '')==values['description'])
        if not same or found.docstatus!=1:
            frappe.throw(f"Line {entry['line']} conflicts with an existing or cancelled bank transaction. Review it before importing.")
        return found.name
    # A previously imported (or manually entered) statement can predate this importer.
    # Distinct authoritative bank IDs still distinguish genuine identical movements.
    where = {'bank_account':bank, 'date':values['date'],'deposit':values['deposit'],'withdrawal':values['withdrawal']}
    candidates = frappe.db.get_values('Bank Transaction',where,fields,as_dict=True,for_update=lock)
    matching = [c for c in candidates if (c.reference_number or '')==values['reference_number'] and (c.description or '')==values['description']
                and (not entry['has_id'] or not c.transaction_id or c.transaction_id.startswith('native-csv-'))]
    if matching:
        if len(matching)>1 or matching[0].docstatus!=1:
            frappe.throw(f"Line {entry['line']} matches multiple, draft or cancelled entries. Review the statement identifiers.")
        return matching[0].name
    return None


@frappe.whitelist(methods=['POST'])
def statement_csv(company: str, bank_account: str, stage: str, content: str, mapping=None, date_format: str='YMD'):
    bank = _bank(company,bank_account)
    if not frappe.has_permission('Bank Transaction','create') or not frappe.has_permission('Bank Transaction','submit'):
        frappe.throw('Creating and submitting bank transactions requires accounting permission.',frappe.PermissionError)
    if stage == 'columns':
        headers,_ = _csv(content)
        lookup={h.casefold():h for h in headers}
        return {'headers':headers,'mapping':{k:next(lookup[a] for a in names if a in lookup) for k,names in SUGGESTIONS.items() if any(a in lookup for a in names)}}
    if stage not in ('preview','import'):
        frappe.throw('Choose a valid import stage.')
    if isinstance(mapping,str):
        mapping=frappe.parse_json(mapping)
    currency=frappe.get_cached_value('Account',bank.account,'account_currency')
    prototype=frappe.new_doc('Bank Transaction')
    prototype.currency=currency
    rows=_read_rows(content,mapping,date_format,currency,prototype.precision('deposit'))
    posting=stage=='import'
    if posting:
        # Serializes overlapping files, including repeated requests after a lost response.
        frappe.db.get_value('Bank Account',bank.name,'name',for_update=True)
    review=[]
    for row in rows:
        existing=_existing(bank.name,row,posting)
        review.append({'line':row['line'],**{k:str(v) for k,v in row['record'].items()},'existing':existing})
    count=sum(1 for r in review if not r['existing'])
    if not posting:
        return {'currency':currency,'rows':review,'new_count':count,'duplicates':len(rows)-count}
    for row, checked in zip(rows,review,strict=True):
        if not checked['existing']:
            frappe.get_doc({'doctype':'Bank Transaction','company':company,'bank_account':bank.name,'currency':currency,
                            'transaction_id':row['identity'],**row['record']}).insert().submit()
    return {'created':count,'duplicates':len(rows)-count}
