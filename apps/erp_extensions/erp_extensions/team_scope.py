"""Native account scope on the local shared evaluation site.

ERPNext user permissions cover company links. Site-wide masters have no such link,
so a managed workspace shares masters created by its own team. Existing ERP users
retain ERPNext's original permission model.
"""
import re

import frappe

from erp_extensions.onboarding import MEMBER, membership
from erp_extensions.knitting.install import SCHEMAS as PACK_TYPES

# Shared configuration needed to create documents. Members can select these values.
REFERENCE_TYPES = frozenset({'Currency', 'Country', 'UOM', 'Item Group', 'Territory', 'Customer Group',
    'Supplier Group', 'Price List', 'Fiscal Year', 'Mode of Payment', 'Payment Term', 'Payment Terms Template',
    'Sales Partner Type', 'Salutation', 'Gender', 'Language', 'Brand', 'Incoterm', 'Warehouse Type',
    'Stock Entry Type', 'Workstation Type', 'Project Type', 'Naming Series', 'Print Heading'})
TEAM_MASTERS = frozenset({'Location', 'Asset Category', 'Customer', 'Supplier', 'Item', 'Workstation', 'Address', 'Contact', 'Lead', 'Prospect',
                          'Item Price', 'Sales Person', 'Sales Partner', 'Task', 'Project Template', 'Batch', 'Serial No'})
# Standard ERPNext records can follow their real Company link. Custom code, virtual
# records and site settings require an explicit review before they are exposed.
COMPANY_REPORTS = frozenset({'General Ledger', 'Trial Balance', 'Profit and Loss Statement', 'Balance Sheet',
    'Accounts Receivable', 'Accounts Payable', 'Sales Order Analysis', 'Purchase Order Analysis', 'Stock Ledger', 'Stock Balance'})
REPORT_LINK_FILTERS = frozenset({'Company', 'Account', 'Cost Center', 'Project', 'Fiscal Year', 'Warehouse', 'Customer Group',
    'Supplier Group', 'Territory', 'Item Group', 'Item', 'UOM', 'Payment Terms Template', 'Stock Entry Type', 'Warehouse Type',
    'Sales Order', 'Purchase Order', 'Sales Person', 'Sales Partner', 'Brand', 'Batch'})
OVERVIEW_TYPES = frozenset({'Company','Customer','Supplier','Warehouse','Item','Sales Invoice','Sales Order',
                            'Purchase Order','Work Order','Project','Asset','Quality Inspection'})
READ_ACTIONS = frozenset({'read','select','report','print','export'})


def _scope(doctype):
    if doctype in ('Company', 'User') or doctype in REFERENCE_TYPES:
        return doctype
    if doctype == 'Role':
        return 'own_roles'
    if doctype == 'Asset Maintenance Log':
        return 'maintenance_plan'
    if doctype in TEAM_MASTERS:
        return 'team'
    if not doctype:
        return None
    meta = frappe.get_meta(doctype)
    company = meta.get_field('company')
    if company and company.fieldtype == 'Link' and company.options == 'Company' and not (meta.issingle or meta.is_virtual or meta.istable):
        if (not meta.custom and frappe.local.module_app.get(frappe.scrub(meta.module)) == 'erpnext') or doctype in PACK_TYPES:
            return 'company'
    return None


def native_type_allowed(doctype, permission='read'):
    scope = _scope(doctype)
    return bool(scope and doctype != 'User' and (permission in READ_ACTIONS or scope not in REFERENCE_TYPES | {'Company','own_roles'}))


def _team_user(name, company):
    return bool(name and frappe.db.get_value(MEMBER, {'member_user':name, 'company':company}, 'name', cache=True))


def has_permission(doc, ptype, user=None, **kwargs):
    member = membership(user)
    if not member:
        return True
    scope = _scope(doc.doctype)
    if scope == 'own_roles':
        return ptype in READ_ACTIONS and doc.name in frappe.get_roles(user)
    if scope == 'maintenance_plan':
        return bool(doc.asset_maintenance and frappe.has_permission('Asset Maintenance','read',doc=doc.asset_maintenance,user=user))
    if scope == 'Company':
        return ptype in READ_ACTIONS and doc.name == member.company
    if scope == 'User':
        return ptype in READ_ACTIONS and _team_user(doc.name, member.company)
    if scope == 'company':
        return doc.company == member.company
    if scope == 'team':
        return doc.is_new() and (not doc.owner or doc.owner == (user or frappe.session.user)) or _team_user(doc.owner, member.company)
    if scope in REFERENCE_TYPES:
        return ptype in READ_ACTIONS
    # Attached files are reached only through an already authorized parent in the native API.
    if doc.doctype == 'File' and doc.attached_to_doctype and doc.attached_to_name and _scope(doc.attached_to_doctype) in {'company','team'}:
        return frappe.has_permission(doc.attached_to_doctype, 'read', doc.attached_to_name, user=user)
    return False


def query_conditions(user=None, doctype=None):
    member = membership(user)
    if not member:
        return ''
    scope = _scope(doctype)
    if scope in REFERENCE_TYPES:
        return ''
    company = frappe.db.escape(member.company)
    if scope == 'own_roles':
        return '`tabRole`.`name` in (' + ','.join(frappe.db.escape(r) for r in frappe.get_roles(user)) + ')'
    if scope == 'maintenance_plan':
        plans = frappe.get_list('Asset Maintenance',filters={'company':member.company},pluck='name',limit=0,user=user)
        return '`tabAsset Maintenance Log`.`asset_maintenance` in (' + (','.join(frappe.db.escape(p) for p in plans) or 'NULL') + ')'
    if scope == 'Company':
        return f'`tabCompany`.`name` = {company}'
    if scope == 'company':
        return f'`tab{doctype}`.`company` = {company}'
    if scope in ('User', 'team'):
        field = 'name' if scope == 'User' else 'owner'
        return f'`tab{doctype}`.`{field}` in (select member_user from `tabWorkspace Team Member` where company={company})'
    return '1=0'


def check_links(doc):
    """Check sensitive identities before ERPNext controllers fetch their linked data."""
    member = membership()
    if not member:
        return
    for row in [doc, *doc.get_all_children()]:
        for df in row.meta.get_link_fields() + row.meta.get_dynamic_link_fields():
            name = row.get(df.fieldname)
            if not name:
                continue
            target = df.options if df.fieldtype == 'Link' else row.get(df.options)
            if not target:
                continue
            scope = _scope(target)
            if scope == 'Company' and name != member.company or scope == 'User' and not _team_user(name, member.company):
                frappe.throw('Choose a record from this workspace.', frappe.PermissionError)
            if scope == 'team' and not _team_user(frappe.db.get_value(target, name, 'owner'), member.company):
                frappe.throw('Choose a record from this workspace.', frappe.PermissionError)
            if scope == 'company' and frappe.db.get_value(target, name, 'company') != member.company:
                frappe.throw('Choose a record from this workspace.', frappe.PermissionError)


def search_link(doctype, query, filters=None):
    if not _scope(doctype) or len(query) > 140:
        return []
    meta = frappe.get_meta(doctype)
    title = meta.title_field
    fields = ['name']
    if title and title != 'name' and title in meta.get_permitted_fieldnames():
        fields.append(title)
    rows = frappe.get_list(doctype, fields=fields, filters=filters, or_filters=[[f, 'like', '%' + query + '%'] for f in fields], limit=30)
    return [{'value':r.name, 'description':r.get(title) or ''} for r in rows]


def guard_request():
    if not membership():
        return
    # Numerous Desk/website methods legitimately use site-wide SQL. A new native-only
    # account gets the reviewed app RPCs and its bounded dashboard reads.
    path = frappe.request.path
    cmd = path.removeprefix('/api/method/')
    if not path.startswith('/api/method/') or frappe.form_dict.get('cmd') not in (None, '', cmd):
        frappe.throw('Use the native workspace for this account.', frappe.PermissionError)
    if cmd in {'erp_extensions.pos_checkout.' + name for name in ('register','configure','open_shift','quote','checkout','closing','close_shift','refund_review','refund')}:
        return
    if membership().team_role == 'cashier' and path.startswith('/api/method/erp_extensions.') and cmd not in {
            'erp_extensions.workspace.context', 'erp_extensions.workspace.select_company', 'erp_extensions.api.search_link',
            'erp_extensions.api.session_status'}:
        frappe.throw('Use the register to record a cashier sale.',frappe.PermissionError)
    if cmd in {'erp_extensions.migration.printing.record_data',
               'erp_extensions.migration.production_reports.summary'}:
        return
    if cmd in {'erp_extensions.migration.api.'+name for name in
            ('summary','records','detail','shared_cash','invoice_print_data','filter_options')}:
        return
    if cmd in {'erp_extensions.operations.' + name for name in
               ('begin_operation', 'pending_operations', 'operation_status', 'close_operation', 'acknowledge_operation')}:
        return
    if cmd in ('login','logout','erp_extensions.invoices.register','erp_extensions.invoices.get_settings','erp_extensions.invoices.save_settings','erp_extensions.invoices.print_data','erp_extensions.invoices.set_template','erp_extensions.invoice_compose.defaults','erp_extensions.invoice_compose.preview','erp_extensions.invoice_compose.save_draft', 'erp_extensions.reconciliation.candidates', 'erp_extensions.reconciliation.allocate', 'erp_extensions.bank_matching.entries', 'erp_extensions.bank_matching.matches', 'erp_extensions.bank_matching.match', 'erp_extensions.bank_csv.statement_csv', 'erp_extensions.operational_handoffs.receipt_items', 'erp_extensions.operational_handoffs.inspect_receipt', 'erp_extensions.operational_handoffs.maintenance_logs', 'erp_extensions.operational_handoffs.asset_plan') or re.fullmatch(r'erp_extensions\.(api|workspace|onboarding|knitting\.api)\.[a-z_]+', cmd):
        return
    if cmd not in ('frappe.client.get_list','frappe.client.get_count') or frappe.form_dict.get('doctype') not in OVERVIEW_TYPES:
        frappe.throw('Use the native workspace for this account.', frappe.PermissionError)
    # The dashboard reads only scalar fields of its main table and two sales aggregates.
    args = frappe.form_dict
    if set(args) - {'doctype','fields','filters','or_filters','limit_page_length','limit_start','group_by','order_by','cmd'}:
        frappe.throw_permission_error()
    for key in ('fields','group_by','order_by','filters','or_filters'):
        value = args.get(key)
        if not value:
            continue
        if key in ('order_by','group_by'):
            if not re.fullmatch(r'[a-z_]+(?: (?:asc|desc))?', value):
                frappe.throw_permission_error()
            continue
        values = frappe.parse_json(value) if isinstance(value, str) else value
        if not isinstance(values, list):
            frappe.throw_permission_error()
        for entry in values:
            if key == 'fields':
                if isinstance(entry, str) and re.fullmatch('[a-z_]+', entry):
                    continue
                if args.doctype == 'Sales Invoice' and entry in ({'SUM':'base_grand_total','as':'billed'}, {'SUM':'base_grand_total','as':'amount'}):
                    continue
            elif isinstance(entry, list) and len(entry) == 3 and isinstance(entry[0], str) and re.fullmatch('[a-z_]+', entry[0]):
                continue
            frappe.throw_permission_error()


def report_field_allowed(field):
    key = field['fieldname']
    if key in {'report_template', 'show_variant_attributes', 'show_stock_ageing_data', 'group_by_dimension', 'party_name', 'tax_id'}:
        return False
    if field.get('fieldtype') in ('Link', 'MultiSelectList'):
        # The pinned order-analysis adapters name these multiselect filters after the order.
        return field.get('options') in REPORT_LINK_FILTERS or key in ('status', 'party')
    return field.get('fieldtype') in {'Date', 'Check', 'Select'} or key in {'range', 'voucher_no', 'against_voucher_no'}


def report_filters(name, values, fields, company):
    if values.get('company', company) != company:
        frappe.throw('Choose your current company for this report.', frappe.PermissionError)
    definitions = {f['fieldname']:f for f in fields}
    if set(values) - definitions.keys():
        frappe.throw('This filter is unavailable in your company report.', frappe.PermissionError)
    for key, value in values.items():
        if value in ('', None, []):
            continue
        field = definitions[key]
        if key == 'party_type' and value not in field.get('options', '').split('\n'):
            frappe.throw('Choose a permitted party type.', frappe.PermissionError)
        if field.get('fieldtype') not in ('Link','MultiSelectList'):
            if isinstance(value, (dict, list)):
                frappe.throw('Choose a single value for this filter.')
            continue
        target = field.get('options')
        if key == 'party':
            target = values.get('party_type') or {'Accounts Payable':'Supplier', 'Accounts Receivable':'Customer'}.get(name)
            options = (definitions.get('party_type', {}).get('options') or '').split('\n')
            if target not in options:
                frappe.throw('Choose a permitted party type.', frappe.PermissionError)
        if key == 'status':
            if not isinstance(value, list) or any(item not in field.get('options','').splitlines() for item in value):
                frappe.throw('Choose an available order status.')
            continue
        if not target or not _scope(target):
            frappe.throw('This filter is unavailable.', frappe.PermissionError)
        for selected in value if isinstance(value, list) else [value]:
            if not isinstance(selected, str) or not frappe.get_list(target, filters={'name':selected}, pluck='name', limit=1):
                frappe.throw('Choose report values from this workspace.', frappe.PermissionError)
    return {**values, 'company':company}
