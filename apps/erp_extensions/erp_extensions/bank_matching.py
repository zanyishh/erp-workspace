"""Match an imported or manually entered bank statement line to a posted payment."""
from datetime import timedelta
from decimal import Decimal
import json

import frappe
from erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool import get_linked_payments, reconcile_vouchers
from frappe.utils import getdate

from erp_extensions.knitting.permissions import company_allowed
from erp_extensions.reconciliation import _decimal


def permitted():
    return bool(frappe.session.user != 'Guest' and frappe.has_permission('Bank Transaction', 'write') and
                frappe.has_permission('Bank Account', 'read') and frappe.has_permission('Payment Entry', 'write'))


def _bank(company, bank_account):
    if not permitted() or not company_allowed(company):
        frappe.throw('This account cannot reconcile this bank account.', frappe.PermissionError)
    bank = frappe.get_doc('Bank Account', bank_account)
    bank.check_permission('read')
    if bank.company != company or not bank.is_company_account or not bank.account:
        frappe.throw('Select a company bank account in this workspace.', frappe.PermissionError)
    return bank


@frappe.whitelist(methods=['POST'])
def entries(company: str, bank_account: str, query: str = ''):
    _bank(company, bank_account)
    rows = frappe.get_list('Bank Transaction', filters={'company':company, 'bank_account':bank_account,
                           'docstatus':1, 'unallocated_amount':['>',0]},
                           or_filters=[[field,'like',f'%{query}%'] for field in ('name','description','reference_number')] if query else None,
                           fields=['name','date','deposit','withdrawal','currency','reference_number','description','unallocated_amount'],
                           order_by='date desc, name desc', limit=100)
    for row in rows:
        row.name = str(row.name)
    return {'statements':rows, 'can_import':bool(frappe.has_permission('Bank Transaction','create') and frappe.has_permission('Bank Transaction','submit'))}


def _statement(company, bank_account, name, *, lock=False):
    bank = _bank(company, bank_account)
    row = frappe.get_doc('Bank Transaction', name, for_update=lock)
    row.check_permission('write')
    if row.company != company or row.bank_account != bank.name:
        frappe.throw('Choose a statement line from this bank account.', frappe.PermissionError)
    if row.docstatus != 1 or row.unallocated_amount <= 0:
        frappe.throw('This statement line no longer has an unmatched balance.')
    return row


def _payments(row, from_date, to_date):
    start = getdate(from_date) if from_date else getdate(row.date) - timedelta(days=31)
    end = getdate(to_date) if to_date else getdate(row.date) + timedelta(days=31)
    if start > end or (end-start).days > 366:
        frappe.throw('Choose a payment date range of up to one year.')
    matched = get_linked_payments(str(row.name), ['payment_entry'], start, end)
    return [{'name':str(m.name), 'date':m.posting_date, 'reference':m.reference_no, 'amount':str(m.paid_amount),
             'currency':m.currency} for m in matched if m.doctype=='Payment Entry' and m.paid_amount > 0 and frappe.db.get_value('Payment Entry',m.name,'payment_type') in ('Receive','Pay') and
             frappe.has_permission('Payment Entry','write',doc=m.name)]


@frappe.whitelist(methods=['POST'])
def matches(company: str, bank_account: str, statement: str, from_date: str = '', to_date: str = ''):
    row = _statement(company, bank_account, statement)
    return {'payments':_payments(row, from_date, to_date)}


@frappe.whitelist(methods=['POST'])
def match(company: str, bank_account: str, statement: str, payment: str, expected_statement: str, expected_payment: str,
          from_date: str = '', to_date: str = ''):
    row = _statement(company, bank_account, statement, lock=True)
    pay = frappe.get_doc('Payment Entry',payment,for_update=True)
    pay.check_permission('write')
    if pay.company != company:
        frappe.throw('Select a payment from this company.', frappe.PermissionError)
    if pay.docstatus != 1 or pay.clearance_date:
        frappe.throw('This payment is no longer available for matching.')
    pending = _decimal(expected_statement)
    # A payment can be partly matched to another statement. Lock its existing match
    # rows before comparing the amount; the upstream report otherwise reads a snapshot.
    existing = frappe.db.get_values('Bank Transaction Payments', {'payment_document':'Payment Entry','payment_entry':payment},
                                    ['parent','allocated_amount'], as_dict=True,for_update=True)
    amount_field = 'received_amount_after_tax' if row.deposit else 'paid_amount_after_tax'
    cleared = sum(Decimal(str(r.allocated_amount)) for r in existing if frappe.db.get_value('Bank Transaction',r.parent,'docstatus',for_update=True)==1)
    available = Decimal(str(pay.get(amount_field))) - cleared
    if Decimal(str(row.unallocated_amount)) != pending or available != _decimal(expected_payment):
        frappe.throw('A bank or payment balance changed. Refresh before matching.')
    selected = next((m for m in _payments(row,from_date,to_date) if m['name']==payment),None)
    if not selected or Decimal(selected['amount']) != available:
        frappe.throw('The payment no longer matches this bank account and statement line.')
    applied = min(pending,available)
    voucher = {'payment_doctype':'Payment Entry','payment_name':payment, 'amount':float(applied)}
    result = reconcile_vouchers(str(row.name), json.dumps([voucher]))
    updated = Decimal(str(result.unallocated_amount))
    if pending - updated != applied:
        frappe.throw('The accounting allocation changed. Refresh and review the match.')
    return {'statement':str(row.name),'payment':payment,'matched':str(applied),'remaining':str(updated),
            'clearance_date':frappe.db.get_value('Payment Entry',payment,'clearance_date',for_update=True)}
