"""Native Task board and calendar, keeping the original Task controller for edits."""
from datetime import date
import re

import frappe
from frappe.query_builder import functions
from frappe.utils import add_months, cint

from erp_extensions.api import _fieldnames, _meta


def task_view(company, month=None, status=None, start=0):
    meta = _meta('Task')
    if not company or not frappe.has_permission('Company', 'read', doc=company):
        frappe.throw('Choose a company you can read.', frappe.PermissionError)
    allowed = _fieldnames(meta, 'read') - {f.fieldname for f in meta.get_masked_fields()}
    needed = {'subject', 'status', 'company'}
    if month:
        needed.update(('exp_start_date', 'exp_end_date'))
    if not needed.issubset(allowed):
        frappe.throw('You do not have permission to view these task fields.', frappe.PermissionError)
    statuses = (meta.get_field('status').options or '').splitlines()
    filters = [['company', '=', company]]
    if status:
        if status not in statuses:
            frappe.throw('Choose an available task status.')
        filters.append(['status', '=', status])
    if month:
        if not isinstance(month, str) or not re.fullmatch(r'\d{4}-(?:0[1-9]|1[0-2])', month):
            frappe.throw('Choose a valid calendar month.')
        first = date.fromisoformat(month + '-01')
        task = frappe.qb.DocType('Task')
        filters.extend([[functions.IfNull(task.exp_start_date, task.exp_end_date), '<', add_months(first, 1)],
                        [functions.IfNull(task.exp_end_date, task.exp_start_date), '>=', first]])
    fields = ['name', 'subject', 'status', 'modified']
    fields.extend(f for f in ('exp_start_date','exp_end_date','project') if f in allowed)
    rows = frappe.get_list('Task', fields=fields, filters=filters, offset=max(0, cint(start)), limit=51,
                           order_by='exp_start_date asc, name asc' if month else 'name asc')
    return {'rows':rows[:50], 'has_more':len(rows) > 50, 'statuses':statuses}
