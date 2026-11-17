"""Permission-scoped matching of a posted, unallocated payment to an outstanding invoice."""
from decimal import Decimal, InvalidOperation

import frappe
from erpnext.accounts.party import get_party_account
from frappe.permissions import get_role_permissions

from erp_extensions.knitting.permissions import company_allowed

INVOICES = {'Customer': 'Sales Invoice', 'Supplier': 'Purchase Invoice'}


def permitted():
    return bool(frappe.session.user != 'Guest' and
        (frappe.session.user == 'Administrator' or get_role_permissions(frappe.get_meta('Payment Reconciliation')).get('write')) and
        frappe.has_permission('Payment Entry', 'write'))


def _context(company, party_type, party):
    if not permitted() or not company_allowed(company):
        frappe.throw('This account cannot reconcile payments in that company.', frappe.PermissionError)
    if party_type not in INVOICES:
        frappe.throw('Choose a customer or supplier.')
    frappe.get_doc(party_type, party).check_permission('read')
    frappe.has_permission(INVOICES[party_type], 'read', throw=True)
    return get_party_account(party_type, party, company, include_advance=True)


def _tool(company, party_type, party, accounts, payment=None, invoice=None):
    doc = frappe.new_doc('Payment Reconciliation')
    doc.update({'company':company, 'party_type':party_type, 'party':party, 'receivable_payable_account':accounts[0],
                'default_advance_account':accounts[1] if len(accounts)>1 else None, 'payment_name':payment,
                'invoice_name':invoice, 'invoice_limit':100, 'payment_limit':100})
    doc.get_unreconciled_entries()
    return doc


def _rows(doc):
    invoice_type = INVOICES[doc.party_type]
    payments = {r.reference_name:r for r in doc.payments if r.reference_type == 'Payment Entry' and not r.reference_row and r.amount > 0}
    invoices = {r.invoice_number:r for r in doc.invoices if r.invoice_type == invoice_type and r.outstanding_amount > 0}
    return payments, invoices


def _visible(doctype, entries, **filters):
    if not entries:
        return []
    return frappe.get_list(doctype, filters={**filters,'docstatus':1,'name':['in',list(entries)]}, pluck='name', order_by='posting_date, name', limit=100)


@frappe.whitelist(methods=['POST'])
def candidates(company: str, party_type: str, party: str, payment_query: str = '', invoice_query: str = ''):
    accounts = _context(company, party_type, party)
    doc = _tool(company, party_type, party, accounts, payment_query, invoice_query)
    payments, invoices = _rows(doc)
    pay_names = _visible('Payment Entry',payments,company=company,party_type=party_type,party=party)
    inv_names = _visible(INVOICES[party_type], invoices,company=company,**{party_type.lower():party})
    return {'account':accounts[0], 'currency':frappe.get_cached_value('Account', accounts[0], 'account_currency'),
        'payments':[{'name':n,'date':payments[n].posting_date,'balance':str(payments[n].amount)} for n in pay_names],
        'invoices':[{'name':n,'date':invoices[n].invoice_date,'balance':str(invoices[n].outstanding_amount)} for n in inv_names]}


def _decimal(value):
    try:
        number = Decimal(str(value))
        if number.is_finite() and number > 0:
            return number
    except (InvalidOperation, ValueError):
        pass
    frappe.throw('Enter a positive amount.')


@frappe.whitelist(methods=['POST'])
def allocate(company: str, party_type: str, party: str, payment: str, invoice: str, amount: str, expected_payment: str, expected_invoice: str, request_id: str | None = None):
    from erp_extensions import operations
    values = {'company': company, 'party_type': party_type, 'party': party, 'payment': payment,
              'invoice': invoice, 'amount': amount, 'expected_payment': expected_payment, 'expected_invoice': expected_invoice}
    return operations.execute(company, 'reconciliation', request_id, values, lambda: _allocate(**values))


def _allocate(company, party_type, party, payment, invoice, amount, expected_payment, expected_invoice):
    accounts = _context(company, party_type, party)
    # Lock both source balances in a consistent order, including repeat requests
    # whose transaction opened before a competing allocation was committed.
    pay = frappe.get_doc('Payment Entry', payment, for_update=True)
    inv = frappe.get_doc(INVOICES[party_type], invoice, for_update=True)
    pay.check_permission('write')
    inv.check_permission('read')
    if (pay.company != company or inv.company != company or pay.party_type != party_type or pay.party != party or
            inv.get(party_type.lower()) != party or pay.docstatus != 1 or inv.docstatus != 1):
        frappe.throw('Choose posted entries for the same company and party.', frappe.PermissionError)
    pay_balance, inv_balance = Decimal(str(pay.unallocated_amount)), Decimal(str(inv.outstanding_amount))
    if pay_balance != _decimal(expected_payment) or inv_balance != _decimal(expected_invoice):
        frappe.throw('A balance changed. Refresh the entries before confirming another allocation.')
    selected = _decimal(amount)
    if selected > min(pay_balance, inv_balance) or max(0,-selected.normalize().as_tuple().exponent) > pay.precision('unallocated_amount'):
        frappe.throw('Choose an amount within both balances and the payment currency precision.')
    doc = _tool(company, party_type, party, accounts, payment, invoice)
    pays, invs = _rows(doc)
    if payment not in pays or invoice not in invs or Decimal(str(pays[payment].amount)) != pay_balance or Decimal(str(invs[invoice].outstanding_amount)) != inv_balance:
        frappe.throw('The selected payment or invoice is no longer available. Refresh the entries.')
    # ERPNext calculates exchange differences, reference rows and ledger changes.
    payment_row, invoice_row = pays[payment].as_dict(), invs[invoice].as_dict()
    doc.allocate_entries({'payments':[payment_row.copy()], 'invoices':[invoice_row.copy()]})
    allocation = doc.allocation[0]
    allocation.allocated_amount = float(selected)
    allocation.difference_amount = doc.calculate_difference_on_allocation_change([payment_row], [invoice_row], float(selected))
    doc.reconcile()
    return {'payment':payment, 'invoice':invoice, 'allocated':str(selected),
            'payment_balance':str(frappe.db.get_value('Payment Entry',payment,'unallocated_amount',for_update=True)),
            'invoice_balance':str(frappe.db.get_value(inv.doctype,invoice,'outstanding_amount',for_update=True))}
