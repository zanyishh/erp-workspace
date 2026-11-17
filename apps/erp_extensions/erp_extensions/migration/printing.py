"""Authorized, read-only operational source copies; never a posting contract."""
import frappe

from . import api, contracts

PRINT_TYPES = {'job': 'Knitting Job', **dict.fromkeys(
    ('yarn_receipt', 'yarn_return', 'production', 'delivery', 'subcontract'), 'Knitting Event')}
PRINT_KEYS = ('version', 'company', 'title', 'reference', 'original_date', 'effective_date',
              'date_basis', 'review_status', 'fields', 'tables', 'review_notes')


def can_print(company, record):
    doctype = PRINT_TYPES.get(record['family'])
    if not doctype or record['company'] != company:
        return False
    scope = api._scope(company, required=False)
    return bool(scope and scope['name'] == record['source_scope'] and frappe.has_permission(doctype, 'print'))


@frappe.whitelist()
def record_data(company, name):
    _, record = api._visible_record(company, name)
    if not can_print(company, record):
        api._deny()
    # The same projection used on screen owns financial masking and source review notes.
    detail = api.detail(company, name)
    return {**{key: detail[key] for key in PRINT_KEYS}, 'source_record': name, 'source_copy': True,
            'document_label': contracts.FAMILIES[record['family']]}
