"""Review and save a standard, non-POS Sales Invoice using the ERPNext controllers."""
from datetime import date
from decimal import Decimal, InvalidOperation
from hashlib import sha256
import json
import re

import frappe
from erpnext.controllers.accounts_controller import get_default_taxes_and_charges, get_taxes_and_charges
from frappe.utils import today

from erp_extensions import invoices, team_scope
from erp_extensions.api import _preview_prices, _reference
from erp_extensions.knitting.install import field

RECEIPT = 'Workspace Invoice Draft Receipt'


def install():
    frappe.only_for('System Manager')
    if not frappe.db.exists('DocType',RECEIPT):
        frappe.get_doc({'doctype':'DocType','name':RECEIPT,'module':'Custom','custom':1,'autoname':'field:request_key',
            'fields':[field('request_key',reqd=1,unique=1),field('payload_digest',reqd=1),field('invoice','Link','Sales Invoice',reqd=1)],
            'permissions':[{'role':'System Manager','read':1}]}).insert()


def _access(company):
    invoices._company(company)
    frappe.has_permission('Sales Invoice','create',throw=True)


@frappe.whitelist(methods=['POST'])
def defaults(company: str):
    _access(company)
    return {'posting_date':today(),'currency':frappe.get_cached_value('Company',company,'default_currency'),
            'template_id':invoices.invoice_settings.default_style(company)}


def _decimal(value, positive):
    try:
        result=Decimal(str(value))
        if result.is_finite() and (result>0 if positive else result>=0) and result < Decimal('1e13') and result.as_tuple().exponent>=-9:
            return result
    except (ValueError,InvalidOperation):
        pass
    frappe.throw('Use a positive quantity and a nonnegative rate, up to nine decimal places.')


def _input(company,customer,posting_date,due_date,items,template_id):
    _access(company)
    if not customer or (template_id and template_id not in invoices.TEMPLATES):
        frappe.throw('Choose a customer and a valid invoice template.')
    try:
        posting=date.fromisoformat(posting_date)
        if due_date and date.fromisoformat(due_date)<posting:
            frappe.throw('The due date cannot precede the invoice date.')
    except (TypeError,ValueError):
        frappe.throw('Use valid invoice dates.')
    if isinstance(items,str):
        items=frappe.parse_json(items)
    if not isinstance(items,list) or not 1<=len(items)<=100:
        frappe.throw('Add between one and 100 invoice items.')
    lines=[]
    for row in items:
        if not isinstance(row,dict) or set(row)-{'item_code','qty','rate'} or not isinstance(row.get('item_code'),str) or not row['item_code']:
            frappe.throw('Choose an item for each invoice line.')
        rate=row.get('rate')
        lines.append({'item_code':row['item_code'],'qty':str(_decimal(row.get('qty'),True)),
                      'rate':None if rate in (None,'') else str(_decimal(rate,False))})
    return {'company':company,'customer':customer,'posting_date':posting_date,'due_date':due_date or '',
            'items':lines,'template_id':template_id}


def _build(values):
    customer=_reference('Customer',values['customer'])
    if customer.disabled:
        frappe.throw('Choose an active customer.')
    doc=frappe.new_doc('Sales Invoice')
    doc.update({k:values[k] for k in ('company','customer','posting_date')})
    doc.is_pos,doc.update_stock=0,0
    if values['due_date']:
        doc.due_date=values['due_date']
    for row in values['items']:
        item=_reference('Item',row['item_code'])
        if item.disabled or not item.is_sales_item or item.has_variants:
            frappe.throw('Choose an enabled sales item or an item variant.')
        doc.append('items',{'item_code':item.name,'qty':float(row['qty']),'uom':item.stock_uom})
    doc.check_permission('create')
    with _preview_prices():
        doc.set_missing_values()
        if values['due_date']:
            doc.due_date=values['due_date']
        if doc.taxes_and_charges and not doc.taxes:
            doc.set('taxes',get_taxes_and_charges('Sales Taxes and Charges Template',doc.taxes_and_charges) or [])
        elif not doc.taxes_and_charges and not doc.taxes:
            default=get_default_taxes_and_charges('Sales Taxes and Charges Template',company=doc.company) or {}
            if default.get('taxes_and_charges'):
                doc.update(default)
        for row, entered in zip(doc.items,values['items'],strict=True):
            if entered['rate'] is not None:
                row.rate=float(entered['rate'])
        doc.set_taxes_and_charges()
        doc.calculate_taxes_and_totals()
    team_scope.check_links(doc)
    return doc


def _digest(obj):
    return sha256(json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False,default=str).encode()).hexdigest()


def _quote(doc):
    result={'company':doc.company,'customer':doc.customer,'posting_date':str(doc.posting_date),'due_date':str(doc.due_date) if doc.due_date else None,
            'currency':doc.currency,'precision':invoices._precision('grand_total',doc.currency),'pricing':doc.selling_price_list,
            'items':[{'item_code':r.item_code,'item_name':r.item_name,'uom':r.uom, **{k:invoices._number(r.get(k)) for k in ('qty','rate','amount','net_amount')}} for r in doc.items],
            'taxes':[{'label':invoices._text(t.description) or t.account_head,'account':t.account_head,'amount':invoices._number(t.tax_amount_after_discount_amount)} for t in doc.taxes],
            **{k:invoices._number(doc.get(k)) for k in ('net_total','total_taxes_and_charges','grand_total','rounded_total','rounding_adjustment')},
            'disable_rounded_total':bool(doc.disable_rounded_total)}
    # Storage can normalize 10.0 to 10.000000. Compare accounting values, not their representation.
    def canonical(value):
        if isinstance(value,list):
            return [canonical(r) for r in value]
        if isinstance(value,dict):
            return {k:format(Decimal(v).normalize(),'f') if v is not None and k in {
                'qty','rate','amount','net_amount','net_total','total_taxes_and_charges','grand_total','rounded_total','rounding_adjustment'} else canonical(v) for k,v in value.items()}
        return value
    return {**result,'review':_digest(canonical(result))}


@frappe.whitelist(methods=['POST'])
def preview(company: str, customer: str, posting_date: str, due_date: str, items, template_id: str = ''):
    return _quote(_build(_input(company,customer,posting_date,due_date,items,template_id)))


@frappe.whitelist(methods=['POST'])
def save_draft(company: str, customer: str, posting_date: str, due_date: str, items, template_id: str, request_id: str, review: str):
    from erp_extensions import operations
    values = dict(company=company, customer=customer, posting_date=posting_date, due_date=due_date,
                  items=frappe.parse_json(items) if isinstance(items, str) else items,
                  template_id=template_id, request_id=request_id, review=review)
    return operations.execute(company, 'invoice', request_id, values,
                              lambda: _save_draft(**values), optional=True)


def _save_draft(company, customer, posting_date, due_date, items, template_id, request_id, review):
    values=_input(company,customer,posting_date,due_date,items,template_id)
    if not re.fullmatch(r'[a-zA-Z0-9_-]{24,80}',request_id) or not re.fullmatch(r'[0-9a-f]{64}',review):
        frappe.throw('Review the current invoice before saving.')
    key=_digest([frappe.session.user,company,request_id])
    payload=_digest([values,review])
    frappe.db.get_value('Company',company,'name',for_update=True)
    previous=frappe.db.get_value(RECEIPT,key,['invoice','payload_digest'],as_dict=True,for_update=True)
    if previous:
        if previous.payload_digest!=payload:
            frappe.throw('This save reference was used for different invoice details.')
        invoices._invoice(company,previous.invoice)
        return {'name':previous.invoice}
    doc=_build(values)
    if _quote(doc)['review']!=review:
        frappe.throw('Invoice prices, terms or taxes changed. Review the invoice again before saving.')
    with _preview_prices():
        doc.insert()
    if _quote(doc)['review']!=review:
        frappe.throw('The invoice changed during validation. Review the current pricing and taxes.')
    if template_id:
        frappe.get_doc({'doctype':invoices.STYLE,'invoice':doc.name,'template_id':template_id}).insert(ignore_permissions=True)
    frappe.get_doc({'doctype':RECEIPT,'request_key':key,'payload_digest':payload,'invoice':doc.name}).insert(ignore_permissions=True)
    return {'name':doc.name}
