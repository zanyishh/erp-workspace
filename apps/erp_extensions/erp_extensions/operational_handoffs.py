"""Company-scoped source handoffs for inspection and scheduled maintenance."""
from decimal import Decimal, InvalidOperation

import frappe
from erpnext.controllers.stock_controller import check_item_quality_inspection, make_quality_inspections

from erp_extensions.api import _check_version, _reference


def related_actions(doc):
    if doc.doctype == 'Purchase Receipt' and doc.docstatus < 2 and doc.has_permission('write') and frappe.has_permission('Quality Inspection','create'):
        return ['Inspect receipt items']
    if doc.doctype == 'Asset Maintenance' and frappe.has_permission('Asset Maintenance Log','read'):
        return ['Maintenance logs']
    if doc.doctype == 'Asset' and doc.docstatus == 1 and doc.maintenance_required and frappe.has_permission('Asset Maintenance','read'):
        return ['Maintenance plan']
    return []


def _receipt(name, lock=False):
    doc = frappe.get_doc('Purchase Receipt',name,for_update=lock)
    doc.check_permission('write')
    if doc.get('knitting_event') or doc.get('knitting_job') or doc.docstatus == 2:
        frappe.throw('Choose an active general purchase receipt.',frappe.PermissionError)
    return doc


def _rows(doc,lock=False):
    after_submission = frappe.db.get_single_value('Stock Settings','allow_to_make_quality_inspection_after_purchase_or_delivery')
    candidates = [row for row in doc.items if row.item_code and row.qty>0]
    eligible = check_item_quality_inspection(doc.doctype, doc.docstatus, [dict(item_code=r.item_code) for r in candidates])
    items = {entry['item_code'] for entry in eligible} if doc.docstatus == 0 or after_submission else set()
    existing = frappe.db.get_values('Quality Inspection',{'reference_type':doc.doctype,'reference_name':doc.name,'docstatus':['<',2]},
                                    ['child_row_reference','name'],as_dict=True,for_update=lock)
    known = {r.child_row_reference:r.name for r in existing}
    result = []
    for row in candidates:
        inspection = known.get(row.name) or row.quality_inspection
        if inspection:
            if not frappe.has_permission('Quality Inspection','read',doc=inspection):
                continue
        elif row.item_code not in items or not frappe.has_permission('Quality Inspection','create'):
            continue
        if frappe.has_permission('Item','read',doc=row.item_code):
            result.append({'row':row.name,'index':row.idx,'item':row.item_code,'quantity':str(row.qty),'inspection':inspection})
    return result


@frappe.whitelist(methods=['POST'])
def receipt_items(receipt: str):
    doc = _receipt(receipt)
    return {'rows':_rows(doc),'modified':str(doc.modified)}


@frappe.whitelist(methods=['POST'])
def inspect_receipt(receipt: str, row: str, sample: str, modified: str):
    doc = _receipt(receipt,lock=True)
    match = next((r for r in _rows(doc,lock=True) if r['row']==row),None)
    if not match:
        frappe.throw('This receipt row is unavailable for inspection.')
    if match['inspection']:
        return {'name':match['inspection']}
    _check_version(doc,modified)
    try:
        quantity = Decimal(sample)
        if not quantity.is_finite() or quantity<=0 or quantity>Decimal(match['quantity']):
            raise ValueError
    except (ValueError,InvalidOperation):
        frappe.throw('Sample size must be positive and within the received quantity.')
    source = next(r for r in doc.items if r.name == row)
    details = {'item_code':source.item_code,'item_name':source.item_name,'description':source.description,'qty':source.qty,
               'sample_size':float(quantity),'serial_no':source.serial_no,'batch_no':source.batch_no,'child_row_reference':source.name}
    names = make_quality_inspections(doc.company,doc.doctype,doc.name,[details],'Incoming')
    return {'name':names[0]}


@frappe.whitelist(methods=['POST'])
def maintenance_logs(plan: str):
    _reference('Asset Maintenance',plan)
    return {'logs':frappe.get_list('Asset Maintenance Log', filters={'asset_maintenance':plan,'docstatus':['<',2]},
            fields=['name','due_date','task_name','maintenance_status','docstatus'],order_by='docstatus asc, due_date desc',limit=100)}


@frappe.whitelist(methods=['POST'])
def asset_plan(asset: str):
    source = _reference('Asset',asset)
    if 'Maintenance plan' not in related_actions(source):
        frappe.throw('A submitted asset requiring maintenance is needed.',frappe.PermissionError)
    plans = frappe.get_list('Asset Maintenance',filters={'company':source.company,'asset_name':asset},pluck='name',limit=1)
    if plans:
        return {'name':plans[0]}
    from erp_extensions.api import _result
    doc = frappe.new_doc('Asset Maintenance')
    doc.company,doc.asset_name = source.company,source.name
    doc.check_permission('create')
    return {'draft':_result(doc)}
