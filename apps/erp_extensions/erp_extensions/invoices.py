"""Scoped sales invoice register and presentation data sourced from ERPNext."""
from collections import defaultdict
from decimal import Decimal
from html import unescape
import re

import frappe
from bs4 import BeautifulSoup
from frappe.model.meta import get_field_precision
from frappe.utils import cint
from frappe.www.printview import validate_print_for_docstatus

from erp_extensions import invoice_settings
from erp_extensions.api import _fieldnames
from erp_extensions.invoice_settings import payment_uri
from erp_extensions.knitting.permissions import company_allowed

STYLE = 'Workspace Invoice Style'
TEMPLATES = ('canopy','ribbon','offset','cobalt','folio','ledger','terracotta','blueprint',
             'grove','seam','mariner','carbon','saffron','pearl','dispatch')
DEFAULT_STYLE = 'ledger'
DOCTYPE = 'Sales Invoice'


def install():
    frappe.only_for('System Manager')
    from erp_extensions.knitting.install import field
    if not frappe.db.exists('DocType', STYLE):
        frappe.get_doc({'doctype':'DocType','name':STYLE,'module':'Custom','custom':1,'autoname':'field:invoice',
            'fields':[field('invoice','Link',DOCTYPE,reqd=1,unique=1),field('template_id',reqd=1)],
            'permissions':[{'role':'System Manager','read':1}]}).insert()
    invoice_settings.install()
    from erp_extensions import invoice_compose
    invoice_compose.install()


def _company(company):
    if frappe.session.user == 'Guest' or not company_allowed(company) or not frappe.has_permission(DOCTYPE,'read'):
        frappe.throw('You cannot open these sales invoices.',frappe.PermissionError)


@frappe.whitelist(methods=['POST'])
def get_settings(company: str):
    _company(company)
    return invoice_settings.read(company, include_details=invoice_settings.can_manage(company))


@frappe.whitelist(methods=['POST'])
def save_settings(company: str, settings, revision: str):
    _company(company)
    if isinstance(settings, str):
        settings = frappe.parse_json(settings)
    return invoice_settings.save(company, settings, revision)


def recent_customer_choices(company, choices):
    if (not company_allowed(company) or not frappe.has_permission(DOCTYPE, 'read')
            or not frappe.has_permission('Customer', 'read')):
        return choices
    meta = frappe.get_meta(DOCTYPE)
    if ('customer' not in _fieldnames(meta, 'read')
            or any(field.fieldname == 'customer' for field in meta.get_masked_fields())):
        return choices
    # Use the current user's list permissions for both the source bills and today's customers.
    last_bills = frappe.get_list(DOCTYPE, filters={'company': company, 'docstatus': 1},
                                 pluck='customer', order_by='posting_date desc, creation desc', limit=30)
    if not last_bills:
        return choices
    eligible = set(frappe.get_list('Customer', filters={'name': ['in', last_bills], 'disabled': 0},
                                   pluck='name', limit=30))
    recent = [name for name in dict.fromkeys(last_bills) if name in eligible][:5]
    by_name = {row['value']: row for row in choices}
    promoted = []
    for name in recent:
        row = by_name.get(name, {'value': name})
        description = row.get('description')
        promoted.append({**row, 'description': 'Recently invoiced' +
                         (' · ' + description if description else '')})
    return (promoted + [row for row in choices if row['value'] not in recent])[:30]


def _invoice(company, name, lock=False):
    _company(company)
    doc=frappe.get_doc(DOCTYPE,name,for_update=lock)
    if doc.company!=company:
        frappe.throw('You cannot open this invoice in this company.',frappe.PermissionError)
    doc.check_permission('read')
    return doc


def _number(value):
    if value is None or value == '':
        return None
    return format(Decimal(str(value)), 'f')


def _text(value):
    if not value:
        return None
    text=str(value)
    if not re.search(r'</?[a-zA-Z][^>]*>',text):
        return unescape(text).strip() or None
    soup=BeautifulSoup(text,'html.parser')
    for node in soup(['script','style']):
        node.decompose()
    for node in soup.find_all('br'):
        node.replace_with('\n')
    for node in soup.find_all(['p','div','li','tr']):
        node.append('\n')
    return '\n'.join(line.strip() for line in soup.get_text().splitlines() if line.strip()) or None


def _regional(doc, *keys):
    for key in keys:
        if doc.meta.has_field(key) and doc.get(key):
            return _text(doc.get(key))
    return None


def _india_tax_id(value, country):
    from erp_extensions.migration.master_details import india_gstin
    return india_gstin(value, country)


def _gst_identifiers(doc, company_doc):
    seller = _regional(doc, 'company_gstin')
    buyer = _regional(doc, 'billing_address_gstin', 'customer_gstin')
    if not doc.meta.has_field('company_gstin'):
        seller = _india_tax_id(_regional(doc, 'company_tax_id') or _regional(company_doc, 'tax_id'), company_doc.country)
    if not any(doc.meta.has_field(k) for k in ('billing_address_gstin', 'customer_gstin')):
        # Generic Tax ID is used only in an Indian invoice context and only when
        # it has GSTIN's exact shape. An explicit foreign billing country wins.
        country = company_doc.country
        if doc.get('customer_address'):
            country = frappe.db.get_value('Address', doc.customer_address, 'country') if frappe.has_permission(
                'Address', 'read', doc=doc.customer_address) else None
        buyer = _india_tax_id(_regional(doc, 'tax_id'), country) if company_doc.country == 'India' else None
    return seller, buyer


def _print_particulars(doc):
    # The projected document has already passed field-level permissions. Regional
    # installations can add transport fields to Sales Invoice itself.
    fields = ('company_tax_id', 'tax_id', 'dispatch_address', 'shipping_rule', 'incoterm',
        'named_place', 'mode_of_transport', 'transporter_name', 'transporter', 'vehicle_no',
        'lr_no', 'lr_date')
    readable = _fieldnames(doc.meta, 'read') - {field.fieldname for field in doc.meta.get_masked_fields()}
    return {key: value for key in fields if key in readable and (value := _regional(doc, key))}


def _delivery_notes(doc):
    # Standard ERPNext stores dispatch details on the Delivery Note, while each
    # invoice item carries the note it was billed from. Keep shipments distinct.
    references = list(dict.fromkeys(row.delivery_note for row in doc.get('items') or [] if row.delivery_note))
    if not references or not doc.get('customer'):
        return []
    child = frappe.get_meta('Sales Invoice Item')
    if ('delivery_note' not in _fieldnames(child, 'read', parenttype=DOCTYPE)
            or any(field.fieldname == 'delivery_note' for field in child.get_masked_fields(parenttype=DOCTYPE))):
        return []
    doctype = 'Delivery Note'
    if not frappe.has_permission(doctype, 'read') or not frappe.has_permission(doctype, 'print'):
        return []
    meta = frappe.get_meta(doctype)
    readable = _fieldnames(meta, 'read') - {field.fieldname for field in meta.get_masked_fields()}
    fields = [field for field in ('posting_date', 'transporter', 'transporter_name', 'vehicle_no', 'lr_no', 'lr_date')
              if field in readable]
    filters = {'company': doc.company, 'customer': doc.customer, 'docstatus': 1, 'name': ['in', references]}
    try:
        rows = frappe.get_list(doctype, filters=filters, fields=['name', *fields], limit=len(references))
    except frappe.PermissionError:
        # A role can print an invoice without being allowed to filter dispatch records.
        return []
    by_name = {row.name: row for row in rows}
    result = []
    for name in references:
        row = by_name.get(name)
        if row and frappe.has_permission(doctype, 'read', doc=name) and frappe.has_permission(doctype, 'print', doc=name):
            result.append({'name': name, **{key: str(row[key]) for key in fields if row.get(key)}})
    return result


def _precision(field, currency):
    return get_field_precision(frappe.get_meta(DOCTYPE).get_field(field),currency=currency)


def _printable(name, state, settings):
    return bool((state!=0 or cint(settings.allow_print_for_draft)) and (state!=2 or cint(settings.allow_print_for_cancelled))
                and frappe.has_permission(DOCTYPE,'print',doc=name))


@frappe.whitelist(methods=['POST'])
def register(company: str, query: str = '', status: str = 'All', start: int = 0, limit: int = 25):
    _company(company)
    meta=frappe.get_meta(DOCTYPE)
    statuses=['All', *filter(None,meta.get_field('status').options.splitlines())]
    if status not in statuses or start<0 or not 1<=limit<=100 or len(query)>140:
        frappe.throw('Choose a valid invoice filter and page size.')
    readable=_fieldnames(meta,'read') - {f.fieldname for f in meta.get_masked_fields()}
    columns=('customer','customer_name','posting_date','due_date','currency','grand_total','rounded_total','disable_rounded_total','party_account_currency','outstanding_amount','status','is_return')
    fields=['name','docstatus',*[key for key in columns if key in readable]]
    filters={'company':company}
    if status!='All':
        if 'status' not in readable:
            frappe.throw('Invoice status is unavailable for this account.',frappe.PermissionError)
        filters['status']=status
    query=query.strip()
    search=[[key,'like',f'%{query}%'] for key in ('name','customer','customer_name','po_no') if key=='name' or key in readable] if query else None
    rows=frappe.get_list(DOCTYPE,filters=filters,or_filters=search,fields=fields,offset=start,limit=limit+1,order_by='posting_date desc, creation desc, name desc')
    settings=frappe.get_cached_doc('Print Settings')
    display=[]
    for row in rows[:limit]:
        outstanding_currency=row.get('party_account_currency')
        grand_total = row.get('grand_total')
        payable = grand_total
        if (grand_total is not None and 'disable_rounded_total' in row
                and not cint(row.get('disable_rounded_total')) and row.get('rounded_total')):
            payable = row.rounded_total
        display.append({**row,'grand_total':_number(grand_total),'payable_total':_number(payable),'outstanding_amount':_number(row.get('outstanding_amount')),
            'posting_date':str(row.posting_date) if row.get('posting_date') else None,'due_date':str(row.due_date) if row.get('due_date') else None,
            'precision':_precision('grand_total',row.get('currency')),'outstanding_currency':outstanding_currency,
            'outstanding_precision':_precision('outstanding_amount',outstanding_currency),'is_return':bool(row.get('is_return')),
            'can_print':_printable(row.name,row.docstatus,settings)})
    return {'rows':display,'has_more':len(rows)>limit,'statuses':statuses,'can_create':bool(frappe.has_permission(DOCTYPE,'create')),
            'default_template_id':invoice_settings.default_style(company),'can_manage_settings':invoice_settings.can_manage(company)}


def _style(name):
    if not frappe.db.exists('DocType',STYLE,cache=True):
        return ''
    code=frappe.db.get_value(STYLE,name,'template_id')
    return code if code in TEMPLATES else ''


def _taxes(doc, base_currency):
    taxes=doc.get('taxes') or []
    labels={tax.name:_text(tax.description) or tax.account_head for tax in taxes}
    by_item=defaultdict(list)
    for detail in doc.get('item_wise_tax_details') or []:
        if detail.tax_row in labels:
            by_item[detail.item_row].append({'label':labels[detail.tax_row],'rate':_number(detail.rate),'amount':_number(detail.amount),
                'taxable_amount':_number(detail.taxable_amount),'currency':base_currency})
    rows=[]
    for tax in taxes:
        rows.append({'label':labels[tax.name],'account':tax.account_head,'charge_type':tax.charge_type,
            'rate':_number(tax.rate) if tax.charge_type!='Actual' else None,'amount':_number(tax.tax_amount_after_discount_amount),
            'before_discount_amount':_number(tax.tax_amount),'included_in_price':bool(tax.included_in_print_rate)})
    return rows,by_item


@frappe.whitelist(methods=['POST'])
def print_data(company: str, name: str):
    original=_invoice(company,name)
    original.check_permission('print')
    validate_print_for_docstatus(original)
    doc=original.copy_with_fieldlevel_read_permissions()
    company_doc=frappe.get_doc('Company',company)
    company_doc.check_permission('read')
    company_doc=company_doc.copy_with_fieldlevel_read_permissions()
    base_currency=company_doc.default_currency
    currency=doc.get('currency')
    settings = invoice_settings.read(company, include_details=True)['settings']
    override = _style(name)
    taxes,by_item=_taxes(doc,base_currency)
    company_gstin, customer_gstin = _gst_identifiers(doc, company_doc)
    items=[]
    for row in doc.get('items') or []:
        items.append({'item_code':row.item_code,'item_name':_text(row.item_name),'description':_text(row.description),
            'hsn_sac':_regional(row,'gst_hsn_code','hsn_sac','hsn_code','sac_code'),'uom':row.uom,'taxes':by_item[row.name],
            **{k:_number(row.get(k)) for k in ('qty','rate','amount','net_rate','net_amount','discount_amount','discount_percentage')}})
    result={
        'name':doc.name,'modified':str(original.modified),'company':company,'seller_name':company_doc.company_name or company,'customer':doc.customer,'customer_name':doc.customer_name,
        'posting_date':str(doc.posting_date) if doc.posting_date else None,'due_date':str(doc.due_date) if doc.due_date else None,
        'po_no':doc.po_no,'po_date':str(doc.po_date) if doc.po_date else None,'docstatus':int(doc.docstatus),'status':doc.status,'is_return':bool(doc.is_return),
        'return_against':doc.return_against,'amended_from':doc.amended_from,'currency':currency,'precision':_precision('grand_total',currency),
        'outstanding_currency':doc.party_account_currency,'outstanding_precision':_precision('outstanding_amount',doc.party_account_currency),
        'company_currency':base_currency,'company_currency_precision':_precision('base_grand_total',base_currency),
        'company_address':_text(doc.company_address_display),'billing_address':_text(doc.address_display),'shipping_address':_text(doc.shipping_address),
        'company_gstin':company_gstin,'customer_gstin':customer_gstin, **_print_particulars(doc),
        'place_of_supply':_regional(doc,'place_of_supply'),'in_words':_text(doc.in_words),'terms':_text(doc.terms),'apply_discount_on':doc.apply_discount_on,
        'disable_rounded_total':bool(doc.disable_rounded_total),'template_id':override or settings['template_id'],
        'template_override':override,'company_template_id':settings['template_id'],'settings':settings,
        'can_set_template':bool(original.has_permission('write') and frappe.db.exists('DocType',STYLE,cache=True)),
        'items':items,'taxes':taxes,'delivery_notes':_delivery_notes(doc),
        'payments':[{'mode_of_payment':p.mode_of_payment,'amount':_number(p.amount)} for p in doc.get('payments') or []],
        'payment_schedule':[{'payment_term':p.payment_term,'due_date':str(p.due_date) if p.due_date else None,'payment_amount':_number(p.payment_amount)}
                            for p in doc.get('payment_schedule') or []],
        **{k:_number(doc.get(k)) for k in ('total','net_total','total_taxes_and_charges','grand_total','rounded_total','rounding_adjustment','discount_amount',
            'additional_discount_percentage','outstanding_amount','paid_amount','write_off_amount','change_amount')},
    }
    # These are stored fields owned by the regional integration, never a locally
    # generated registration number or a QR link assembled from invoice data.
    status = _regional(doc,'einvoice_status','e_invoice_status')
    irn = _regional(doc,'irn')
    active = bool('india_compliance' in frappe.get_installed_apps() and doc.docstatus == 1 and irn
        and re.fullmatch(r'[0-9a-fA-F]{64}',irn) and (status or '').lower() in ('generated','active'))
    qr = _regional(doc,'signed_qr_code') if active else None
    if qr and not re.fullmatch(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', qr):
        qr = None
    result.update(irn=irn if active else None,einvoice_status=status,
        acknowledgement_number=_regional(doc,'acknowledgement_number','ack_no','acknowledgement_no') if active else None,
        acknowledgement_date=_regional(doc,'acknowledgement_date','ack_date') if active else None,signed_qr_code=qr)
    result['upi_uri'] = payment_uri(result, settings)
    return result


@frappe.whitelist(methods=['POST'])
def set_template(company: str, name: str, template_id: str):
    if template_id and template_id not in TEMPLATES:
        frappe.throw('Choose an available invoice template.')
    doc=_invoice(company,name,lock=True)
    doc.check_permission('print')
    doc.check_permission('write')
    # Styling a draft does not print it or alter any posted accounting field.
    if not frappe.db.exists('DocType',STYLE):
        frappe.throw('Invoice styles have not been installed on this site.')
    if not template_id:
        frappe.db.delete(STYLE, {'invoice': name})
    elif frappe.db.get_value(STYLE,name,'name',for_update=True):
        frappe.db.set_value(STYLE,name,'template_id',template_id)
    else:
        frappe.get_doc({'doctype':STYLE,'invoice':name,'template_id':template_id}).insert(ignore_permissions=True)
    return {'template_id':template_id}
