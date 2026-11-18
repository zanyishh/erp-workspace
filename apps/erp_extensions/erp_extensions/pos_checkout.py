"""Online, exact-cash POS checkout against ERPNext's configured invoice controller."""
from decimal import Decimal, InvalidOperation
from hashlib import sha256
import json
import re

import frappe
from frappe.utils import flt, nowdate
from erpnext.accounts.doctype.pos_closing_entry.pos_closing_entry import make_closing_entry_from_opening
from erpnext.accounts.doctype.pos_profile.pos_profile import get_child_nodes, get_item_groups
from erpnext.selling.page.point_of_sale.point_of_sale import check_pos_profile_access, create_opening_voucher

from erp_extensions.knitting.permissions import company_allowed
from erp_extensions import team_scope

RECEIPT = 'Workspace POS Receipt'
CASHIER = 'Workspace POS Cashier'
SHIFT_RIGHTS = {
    'POS Profile': ('read',),
    'POS Opening Entry': ('read', 'create', 'write', 'submit'),
    'POS Closing Entry': ('read', 'create', 'write', 'submit'),
    'POS Invoice': ('read', 'create', 'write', 'submit'),
    'Sales Invoice': ('read', 'create', 'write', 'submit'),
    'Sales Order': ('read',),
    'Customer': ('read',), 'Item': ('read',), 'Item Price': ('read',),
    'Price List': ('read',), 'Company': ('read',), 'Account': ('read',),
    'Warehouse': ('read',), 'Mode of Payment': ('read',),
}


def install():
    from erp_extensions.knitting.install import field
    frappe.only_for('System Manager')
    from frappe.permissions import add_permission, update_permission_property
    if not frappe.db.exists('Role', CASHIER):
        frappe.get_doc({'doctype':'Role', 'role_name':CASHIER, 'desk_access':1}).insert()
    for doctype, rights in SHIFT_RIGHTS.items():
        perm = frappe.db.get_value('Custom DocPerm', {'parent':doctype,'role':CASHIER,'permlevel':0}, ['name', *rights], as_dict=True)
        if not perm:
            add_permission(doctype,CASHIER)
        for right in rights:
            if not perm or not perm[right]:
                update_permission_property(doctype,CASHIER,0,right,1)
    if not frappe.db.exists('DocType', RECEIPT):
        frappe.get_doc({'doctype':'DocType','name':RECEIPT,'module':'Custom','custom':1,'autoname':'field:request_key',
            'fields':[field('request_key',reqd=1,unique=1),field('payload_digest',reqd=1),
                      field('voucher_type',reqd=1),field('voucher',reqd=1)],
            'permissions':[{'role':'System Manager','read':1}]}).insert()


def invoice_type():
    return frappe.db.get_single_value('POS Settings','invoice_type') or 'Sales Invoice'


def permitted():
    return frappe.session.user != 'Guest' and all(frappe.has_permission(dt, p)
        for dt in ('POS Opening Entry','POS Closing Entry',invoice_type()) for p in ('create','submit'))


def _company(company):
    if not permitted() or not company_allowed(company):
        frappe.throw('This account cannot operate a register for this company.', frappe.PermissionError)


def _profile(company, name, lock=False):
    if lock:
        frappe.db.get_value('POS Profile',name,'name',for_update=True)
    profile = frappe.get_doc('POS Profile',name)
    check_pos_profile_access(name)
    allowed = [r.user for r in profile.applicable_for_users if r.user]
    if profile.company != company or profile.disabled or allowed and frappe.session.user not in allowed:
        frappe.throw('This register is unavailable for this cashier.',frappe.PermissionError)
    return profile


def _default_name(company):
    return 'Register - ' + frappe.db.get_value('Company',company,'abbr')


def assign_default(company, user):
    # Called by authorized owner setup or staff invitation acceptance.
    name=_default_name(company)
    if not frappe.db.exists('POS Profile', {'name':name,'company':company}):
        return
    profile=frappe.get_doc('POS Profile',name,for_update=True)
    if not any(r.user==user for r in profile.applicable_for_users):
        profile.append('applicable_for_users',{'user':user})
        profile.save(ignore_permissions=True)


@frappe.whitelist(methods=['POST'])
def configure(company):
    from erp_extensions.onboarding import MEMBER, _check_owner
    _check_owner(company)
    c=frappe.get_doc('Company',company,for_update=True)
    name=_default_name(company)
    if frappe.db.exists('POS Profile',name):
        frappe.throw('This company already has a default register.')
    warehouse=c.default_warehouse or frappe.db.get_value('Warehouse',{'company':company,'disabled':0,'is_group':0})
    price=frappe.db.get_value('Price List',{'enabled':1,'selling':1,'currency':c.default_currency},'name',order_by='creation')
    if not warehouse or not price or not c.default_cash_account:
        frappe.throw('Configure a company warehouse, selling price list in company currency and cash account before opening a register.')
    # Mode of Payment is a site-level master: only add this company's default
    # account, under a lock, without changing any other company's choice.
    mode=frappe.get_doc('Mode of Payment','Cash',for_update=True)
    if not mode.enabled or mode.type!='Cash':
        frappe.throw('Enable the Cash payment method for this register.')
    if not any(r.company==company for r in mode.accounts):
        mode.append('accounts',{'company':company,'default_account':c.default_cash_account})
        mode.save(ignore_permissions=True)
    users=frappe.get_all(MEMBER,filters={'company':company,'team_role':['in',['owner','cashier']]},pluck='member_user')
    doc=frappe.get_doc({'doctype':'POS Profile','__newname':name,'company':company,'warehouse':warehouse,
        'currency':c.default_currency,'selling_price_list':price,'income_account':c.default_income_account,
        'expense_account':c.default_expense_account,'cost_center':c.cost_center,'write_off_account':c.write_off_account,
        'write_off_cost_center':c.cost_center,'update_stock':1,
        'payments':[{'mode_of_payment':mode.name,'default':1}],
        'applicable_for_users':[{'user':u} for u in sorted(users)]}).insert(ignore_permissions=True)
    return {'profile':doc.name}


def _cash(profile):
    for row in sorted(profile.payments, key=lambda d: not d.default):
        if frappe.db.get_value('Mode of Payment',row.mode_of_payment,'type') == 'Cash':
            return row.mode_of_payment
    frappe.throw('This register needs a configured cash payment method.')


def _number(value, label, positive=False):
    try:
        parsed=Decimal(str(value))
    except (InvalidOperation, ValueError):
        frappe.throw(f'Enter a valid {label}.')
    if not parsed.is_finite() or parsed < 0 or positive and not parsed or parsed > Decimal('1000000000'):
        frappe.throw(f'Enter a valid {label}.')
    return parsed


@frappe.whitelist(methods=['POST'])
def register(company):
    _company(company)
    profiles=frappe.get_list('POS Profile',filters={'company':company,'disabled':0},pluck='name',limit=0)
    allowed=[]
    for name in profiles:
        users=frappe.get_all('POS Profile User',filters={'parent':name,'parenttype':'POS Profile'},pluck='user')
        if not any(users) or frappe.session.user in users:
            allowed.append(name)
    session=frappe.db.get_value('POS Opening Entry',{'user':frappe.session.user,'company':company,'docstatus':1,'status':'Open'},
        ['name','pos_profile'],as_dict=True)
    from erp_extensions.onboarding import can_manage_team
    return {'can_configure':can_manage_team(company) and not frappe.db.exists('POS Profile',{'name':_default_name(company),'company':company}), 'profiles':sorted(allowed),'opening':session.name if session and session.pos_profile in allowed else None,
            'profile':session.pos_profile if session and session.pos_profile in allowed else None}


@frappe.whitelist(methods=['POST'])
def open_shift(company,profile,amount):
    _company(company)
    # Serialize opens by cashier and by till, including a cashier choosing two tills.
    frappe.db.get_value('User',frappe.session.user,'name',for_update=True)
    profile=_profile(company,profile,lock=True)
    cash=_cash(profile)
    result=create_opening_voucher(profile.name,company,[{'mode_of_payment':cash,'opening_amount':float(_number(amount,'opening float'))}])
    return {'opening':result['name']}


def _session(company,opening,lock=False):
    _company(company)
    doc=frappe.get_doc('POS Opening Entry',opening,for_update=lock)
    if doc.company!=company or doc.user!=frappe.session.user:
        frappe.throw('This shift belongs to another cashier.',frappe.PermissionError)
    doc.check_permission('read')
    profile=_profile(company,doc.pos_profile)
    if doc.docstatus!=1 or doc.status!='Open':
        frappe.throw('The register shift is closed.')
    return doc,profile


def _cart(items):
    items=frappe.parse_json(items)
    if not isinstance(items,list) or not 1 <= len(items) <= 100:
        frappe.throw('Add between one and 100 items.')
    rows=[]
    for row in items:
        if not isinstance(row,dict) or not isinstance(row.get('item'),str) or not row['item']:
            frappe.throw('Choose an item for each row.')
        rows.append({'item':row['item'],'qty':str(_number(row.get('qty'),'quantity',positive=True).normalize())})
    return rows


def _invoice(profile,customer,lines):
    party=frappe.get_doc('Customer',customer)
    party.check_permission('read')
    customer_groups={r.name for group in profile.customer_groups for r in get_child_nodes('Customer Group',group.customer_group)}
    if party.disabled or customer_groups and party.customer_group not in customer_groups:
        frappe.throw('Choose an enabled customer from this POS profile.')
    groups=set(get_item_groups(profile.name))
    doc=frappe.new_doc(invoice_type())
    doc.update({'company':profile.company,'pos_profile':profile.name,'is_pos':1,'is_created_using_pos':1,
        'posting_date':nowdate(),'customer':party.name,'set_warehouse':profile.warehouse,'update_stock':1})
    for row in lines:
        item=frappe.get_doc('Item',row['item'])
        item.check_permission('read')
        if item.disabled or not item.is_sales_item or item.has_variants or groups and item.item_group not in groups:
            frappe.throw('Choose a sellable item from this POS profile.')
        if item.has_batch_no or item.has_serial_no:
            frappe.throw('This item needs serial or batch selection before sale.')
        doc.append('items',{'item_code':item.name,'qty':float(row['qty']),'uom':item.stock_uom,'warehouse':profile.warehouse})
    doc.set_missing_values()
    doc.calculate_taxes_and_totals()
    if any(row.rate <= 0 for row in doc.items):
        frappe.throw('Set a selling price for each item before checkout.')
    amount=doc.rounded_total or doc.grand_total
    if amount <= 0:
        frappe.throw('A cash sale must have a positive total.')
    cash=_cash(profile)
    doc.set('payments',[{'mode_of_payment':cash,'amount':amount}])
    doc.set_paid_amount()
    team_scope.check_links(doc)
    return doc


def _summary(doc):
    return {'doctype':doc.doctype,'invoice':doc.name, 'amount':str(doc.rounded_total or doc.grand_total),
        'currency':doc.currency, 'cash':doc.payments[0].mode_of_payment,'items':[{'item':r.item_code,'qty':r.qty,'rate':r.rate,'amount':r.amount} for r in doc.items]}


@frappe.whitelist(methods=['POST'])
def quote(company,opening,customer,items):
    _, profile=_session(company,opening)
    return _summary(_invoice(profile,customer,_cart(items)))


@frappe.whitelist(methods=['POST'])
def checkout(company,opening,customer,items,expected,token):
    _, profile=_session(company,opening,lock=True)
    if not isinstance(token,str) or not re.fullmatch('[A-Za-z0-9_-]{24,80}',token):
        frappe.throw('Reopen checkout to obtain a sale reference.')
    lines=_cart(items)
    expected=_number(expected,'reviewed total',positive=True)
    key=sha256(json.dumps([company,opening,frappe.session.user,token]).encode()).hexdigest()
    digest=sha256(json.dumps([customer,lines,str(expected.normalize())],sort_keys=True).encode()).hexdigest()
    prior=frappe.db.get_value(RECEIPT,key,['payload_digest','voucher_type','voucher'],as_dict=True,for_update=True)
    if prior:
        if prior.payload_digest!=digest:
            frappe.throw('This sale reference has already been used for a different cart.')
        doc=frappe.get_doc(prior.voucher_type,prior.voucher)
        doc.check_permission('read')
        return _summary(doc)
    doc=_invoice(profile,customer,lines)
    if Decimal(str(doc.rounded_total or doc.grand_total))!=expected:
        frappe.throw('Prices changed. Review the current total before checkout.')
    doc.insert()
    doc.submit()
    frappe.get_doc({'doctype':RECEIPT,'request_key':key,'payload_digest':digest,'voucher_type':doc.doctype,
        'voucher':doc.name}).insert(ignore_permissions=True)
    return _summary(doc)


def _closing(opening):
    doc=make_closing_entry_from_opening(opening)
    rows={r.mode_of_payment:r for r in doc.payment_reconciliation}
    for opening_row in opening.balance_details:
        row=rows.get(opening_row.mode_of_payment)
        if row is None:
            row=doc.append('payment_reconciliation',{'mode_of_payment':opening_row.mode_of_payment})
            rows[opening_row.mode_of_payment]=row
        row.opening_amount=opening_row.opening_amount
        row.expected_amount=flt(row.expected_amount)+flt(row.opening_amount)
    values=[{'mode':r.mode_of_payment,'expected':str(flt(r.expected_amount))} for r in doc.payment_reconciliation]
    ids=sorted([r.pos_invoice for r in doc.pos_invoices]+[r.sales_invoice for r in doc.sales_invoices])
    return doc, {'payments':values,'sales':len(ids),'revision':sha256(json.dumps([ids, values],sort_keys=True).encode()).hexdigest()}


@frappe.whitelist(methods=['POST'])
def closing(company,opening):
    doc,_=_session(company,opening)
    return _closing(doc)[1]


@frappe.whitelist(methods=['POST'])
def close_shift(company,opening,amounts,revision):
    session,_=_session(company,opening,lock=True)
    doc,summary=_closing(session)
    amounts=frappe.parse_json(amounts)
    if revision!=summary['revision'] or not isinstance(amounts,dict) or set(amounts)!={r.mode_of_payment for r in doc.payment_reconciliation}:
        frappe.throw('The shift changed. Review the closing balances again.')
    for row in doc.payment_reconciliation:
        row.closing_amount=float(_number(amounts[row.mode_of_payment],'counted amount'))
        row.difference=row.closing_amount-row.expected_amount
    doc.submit()
    return {'closing':doc.name,'status':doc.status}


def _original(profile, invoice, lock=False):
    dt = invoice_type()
    name = frappe.db.get_value(dt, {'name':invoice,'company':profile.company,'pos_profile':profile.name,
        'docstatus':1,'is_return':0,'is_pos':1}, 'name', for_update=lock)
    if not name:
        frappe.throw('Choose a posted sale from this register.', frappe.PermissionError)
    doc = frappe.get_doc(dt, name)
    doc.check_permission('read')
    if not frappe.db.exists(RECEIPT,{'voucher_type':dt,'voucher':name}):
        frappe.throw('This receipt was not generated by the native register.')
    cash = _cash(profile)
    amount = doc.rounded_total or doc.grand_total
    if amount <= 0 or len(doc.payments) != 1 or doc.payments[0].mode_of_payment != cash or flt(doc.payments[0].amount - amount, doc.precision('paid_amount')):
        frappe.throw('Only an original exact-cash sale can be refunded here.')
    return doc


def _refund_quote(profile, source):
    # The native register refunds whole, untouched receipts. Partial returns from
    # any other ERP workflow must be handled using their original return flow.
    prior=frappe.db.get_value(source.doctype,{'return_against':source.name,'is_return':1,'docstatus':1},'name',for_update=True)
    if prior:
        frappe.throw('A return already exists for this receipt.')
    if source.doctype=='POS Invoice' and not source.consolidated_invoice and source.owner != frappe.session.user:
        frappe.throw('Close the original cashier’s shift before returning this POS invoice.')
    summary=_summary(source)
    return {**summary,'customer':source.customer}


@frappe.whitelist(methods=['POST'])
def refund_review(company, opening, invoice):
    _,profile=_session(company,opening)
    source=_original(profile,invoice)
    return _refund_quote(profile,source)


@frappe.whitelist(methods=['POST'])
def refund(company, opening, invoice, expected, token):
    from erpnext.controllers.sales_and_purchase_return import make_return_doc
    _,profile=_session(company,opening,lock=True)
    source=_original(profile,invoice,lock=True)
    if not isinstance(token,str) or not re.fullmatch('[A-Za-z0-9_-]{24,80}',token):
        frappe.throw('Reopen the refund to obtain a return reference.')
    total=_number(expected,'reviewed refund',positive=True)
    key=sha256(json.dumps(['refund',company,opening,frappe.session.user,token]).encode()).hexdigest()
    digest=sha256(json.dumps([source.doctype, source.name, str(total.normalize())]).encode()).hexdigest()
    prior=frappe.db.get_value(RECEIPT,key,['payload_digest','voucher_type','voucher'],as_dict=True,for_update=True)
    if prior:
        if prior.payload_digest!=digest:
            frappe.throw('This refund reference belongs to a different receipt or amount.')
        result=frappe.get_doc(prior.voucher_type,prior.voucher)
        result.check_permission('read')
        return _summary(result)
    quote=_refund_quote(profile,source)
    if Decimal(quote['amount'])!=total:
        frappe.throw('The refund amount changed. Review the original sale again.')
    doc=make_return_doc(source.doctype,source.name)
    doc.pos_profile=profile.name
    doc.is_created_using_pos=1
    doc.pos_closing_entry=None
    doc.consolidated_invoice=None
    doc.set_posting_time=0
    doc.posting_date=nowdate()
    doc.posting_time=frappe.utils.nowtime()
    doc.calculate_taxes_and_totals()
    actual=Decimal(str(doc.rounded_total or doc.grand_total))
    if -actual!=total:
        frappe.throw('The full receipt amount is no longer returnable.')
    doc.set('payments',[{'mode_of_payment':quote['cash'], 'amount':float(actual), 'account':source.payments[0].account}])
    doc.set_paid_amount()
    team_scope.check_links(doc)
    doc.insert()
    doc.submit()
    frappe.get_doc({'doctype':RECEIPT,'request_key':key,'payload_digest':digest,'voucher_type':doc.doctype,'voucher':doc.name}).insert(ignore_permissions=True)
    return _summary(doc)
