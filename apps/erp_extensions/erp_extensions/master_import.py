"""Small, reviewed CSV imports for the first records in a company."""
import csv
from hashlib import sha256
from io import StringIO

import frappe

from erp_extensions.knitting.permissions import company_allowed

RECEIPT = 'Workspace Import Receipt'
COLUMNS = {
    'Customer': ('customer_name', 'customer_type', 'customer_group', 'territory'),
    'Supplier': ('supplier_name', 'supplier_type', 'supplier_group'),
    'Item': ('item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item'),
}
GROUPS = {'Customer':('customer_group','Customer Group'), 'Supplier':('supplier_group','Supplier Group'),
          'Item':('item_group','Item Group')}
MAX_ROWS = 200
MAX_BYTES = 262144


def install():
    from erp_extensions.knitting.install import field
    frappe.only_for('System Manager')
    if not frappe.db.exists('DocType', RECEIPT):
        frappe.get_doc({'doctype':'DocType', 'name':RECEIPT, 'module':'Custom', 'custom':1,
            'autoname':'field:request_digest', 'fields':[field('request_digest', reqd=1, unique=1),
            field('record_count','Int',reqd=1)], 'permissions':[{'role':'System Manager','read':1}]}).insert()


def allowed(doctype):
    return doctype in COLUMNS and frappe.has_permission(doctype, 'import') and frappe.has_permission(doctype, 'create')


def _rows(doctype, content):
    if not isinstance(content, str) or len(content.encode('utf-8')) > MAX_BYTES:
        frappe.throw('Choose a UTF-8 CSV file of up to 256 KB.')
    reader = csv.reader(StringIO(content.removeprefix('\ufeff'), newline=''), strict=True)
    rows, keys = [], set()
    try:
        columns = tuple(next(reader, []))
        if columns != COLUMNS[doctype]:
            frappe.throw('Use the column headers and order from the template.')
        for values in reader:
            if not any(v.strip() for v in values):
                continue
            if len(values) != len(columns) or len(rows) >= MAX_ROWS:
                frappe.throw(f'Check line {reader.line_num}. Use one value per column and up to {MAX_ROWS} records.')
            values = [v.strip() for v in values]
            if not values[0] or values[0].casefold() in keys:
                frappe.throw(f'Line {reader.line_num} needs a unique {columns[0].replace("_", " ")}.')
            keys.add(values[0].casefold())
            row = dict(zip(columns, values, strict=True))
            if doctype == 'Item' and row['is_stock_item'] not in ('0','1'):
                frappe.throw(f'Line {reader.line_num}: use 1 for a stock item or 0 for a service.')
            rows.append((reader.line_num, row))
    except csv.Error:
        frappe.throw(f'Check the CSV quoting near line {reader.line_num}.')
    if not rows:
        frappe.throw('Add at least one record below the column headers.')
    return rows


def run(doctype, company, content=None, stage='template'):
    from erp_extensions.api import _meta
    _meta(doctype,'create')
    if not allowed(doctype) or not company or not company_allowed(company):
        frappe.throw('You need import access to this company and record type.', frappe.PermissionError)
    if stage == 'template':
        return {'columns': COLUMNS[doctype], 'max_rows': MAX_ROWS}
    if stage not in ('preview','confirm'):
        frappe.throw('Choose a valid import step.')
    rows = _rows(doctype, content)
    digest = sha256(frappe.as_json([company,doctype,frappe.session.user,[row for _,row in rows]]).encode()).hexdigest()
    confirming = stage == 'confirm'
    if confirming:
        frappe.db.get_value('Company', company, 'name', for_update=True)
    count = frappe.db.get_value(RECEIPT, digest, 'record_count', for_update=confirming)
    if count is not None:
        return {'count':count, 'already_imported':True}
    if confirming:
        frappe.db.savepoint('native_master_import')
    try:
        _apply_rows(doctype, rows, digest, confirming)
    except frappe.QueryDeadlockError:
        # InnoDB already reverted this transaction and discarded its savepoints.
        frappe.throw('Another import was updating these records. Review the file and try again.')
    except Exception:
        if confirming:
            frappe.db.rollback(save_point='native_master_import')
        raise
    return {'count':len(rows),'columns':COLUMNS[doctype], 'sample':[list(row.values()) for _,row in rows[:5]]}


def _apply_rows(doctype, rows, digest, confirming):
    from erp_extensions.api import _editable
    for line, row in rows:
        try:
            if frappe.db.exists(doctype,{COLUMNS[doctype][0]:row[COLUMNS[doctype][0]]}):
                frappe.throw('Choose an unused name or item code.')
            doc = _editable({'doctype':doctype,'__islocal':1, **row})
            if confirming:
                doc.insert()
            else:
                doc._set_defaults()
                doc._action = 'save'
                doc._validate_mandatory()
                doc._validate_links()
        except frappe.PermissionError:
            raise
        except frappe.ValidationError as error:
            frappe.throw(f'Line {line}: {error}')
    if confirming:
        # Frappe commits the receipt and all inserted masters in the same POST transaction.
        frappe.get_doc({'doctype':RECEIPT,'request_digest':digest,'record_count':len(rows)}).insert(ignore_permissions=True)


def reclassify(doctype, company, records, group):
    from erp_extensions.api import _meta, _check_version, _editable
    meta = _meta(doctype,'write')
    if doctype not in GROUPS or not company_allowed(company):
        frappe.throw('Choose a permitted company and record type.',frappe.PermissionError)
    field, group_type = GROUPS[meta.name]
    records = frappe.parse_json(records) if isinstance(records,str) else records
    if not isinstance(records,list) or not 1 <= len(records) <= 50 or not isinstance(group,str):
        frappe.throw('Select up to 50 records and one group.')
    ids = {}
    for row in records:
        if not isinstance(row,dict) or not isinstance(row.get('name'),str) or not isinstance(row.get('modified'),str):
            frappe.throw('Refresh the list before changing these records.')
        ids[row['name']] = row['modified']
    if len(ids) != len(records):
        frappe.throw('Select each record only once.')
    target = frappe.get_doc(group_type,group)
    target.check_permission('read')
    if target.is_group:
        frappe.throw('Choose a leaf group for the selected records.')
    changed = []
    for name in sorted(ids):
        doc = frappe.get_doc(doctype,name,for_update=True)
        doc.check_permission('read')
        doc.check_permission('write')
        _check_version(doc,ids[name])
        if doc.get(field) != group:
            changed.append(_editable({'doctype':doctype,'name':name,'modified':ids[name],field:group}))
    for doc in changed:
        doc.save()
    return {'count':len(changed)}
