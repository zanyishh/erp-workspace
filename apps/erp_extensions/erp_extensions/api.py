"""Native client contract. GPL-3.0. Business mutations use Frappe controllers."""
from __future__ import annotations

import math
import re
import json
from copy import deepcopy
from functools import lru_cache
from contextlib import contextmanager
from pathlib import Path
from collections.abc import Mapping

import frappe
from erp_extensions import team_scope
from erp_extensions.onboarding import membership
from frappe.permissions import get_doc_permissions
from frappe.utils import cint, flt, get_datetime

VERSION = 1
LAYOUT = {"Section Break", "Column Break", "Tab Break", "Heading", "HTML", "Button", "Image"}
NUMERIC = {"Int", "Float", "Currency", "Percent", "Duration"}


def _signed_in():
    if frappe.session.user == "Guest":
        frappe.throw("Sign in to ERP Workspace first.", frappe.PermissionError)


def _meta(doctype, permission="read"):
    _signed_in()
    if membership() and not team_scope.native_type_allowed(doctype, permission):
        frappe.throw("This record type is unavailable in this workspace.", frappe.PermissionError)
    meta = frappe.get_meta(doctype)
    if meta.istable or not frappe.has_permission(doctype, permission):
        frappe.throw("This account cannot access this record type.", frappe.PermissionError)
    return meta


def _fieldnames(meta, permission, parenttype=None):
    if frappe.session.user == "Administrator":
        return {f.fieldname for f in meta.fields}
    names = set(meta.get_permitted_fieldnames(parenttype=parenttype, permission_type=permission))
    levels = set(meta.get_permlevel_access(permission_type=permission, parenttype=parenttype))
    levels.update(cint(df.permlevel) for df in meta.fields if df.fieldname in names)
    # Frappe's scalar-field helper omits tables; their access follows the parent level.
    names.update(df.fieldname for df in meta.fields
        if df.fieldtype in ("Table", "Table MultiSelect") and cint(df.permlevel) in levels)
    return names


@lru_cache(maxsize=1)
def _conditions():
    return json.loads(Path(__file__).with_name("condition_definitions.json").read_text())


def _resolve_condition(node):
    if isinstance(node, list):
        return [_resolve_condition(value) for value in node]
    if not isinstance(node, dict):
        return node
    if node.get("op") == "environment":
        if node["key"] == "perpetual_inventory":
            cache = frappe.local.cache
            key = ("native_perpetual_inventory", frappe.session.user)
            if key not in cache:
                rows = frappe.get_list("Company", fields=["name", "enable_perpetual_inventory"], limit_page_length=0) if frappe.has_permission("Company", "read") else []
                cache[key] = {row.name: cint(row.get("enable_perpetual_inventory")) for row in rows}
            return {"op":"literal","value":cache[key]}
        environment = {"user":frappe.session.user, "developer_mode":bool(frappe.conf.developer_mode),
            "versions":{"payments":"payments" in frappe.get_installed_apps()}, "today":frappe.utils.today()}
        return {"op":"literal","value":environment.get(node["key"])}
    return {key:_resolve_condition(value) for key,value in node.items()}


def _field_conditions(field):
    result = {}
    for key in ("depends_on", "mandatory_depends_on", "read_only_depends_on"):
        source = field.get(key)
        if not source:
            continue
        if not source.startswith("eval:") and source.isidentifier():
            result[key] = {"op":"field","name":source}
        else:
            result[key] = _resolve_condition(_conditions().get(source, {"op":"unsupported"}))
    return result


def _schema(meta, parenttype=None):
    from erp_extensions.operations import native_recovery_reason
    recovery_reason = native_recovery_reason(meta)
    readable = _fieldnames(meta, "read", parenttype)
    writable = _fieldnames(meta, "write", parenttype) | _fieldnames(meta, "create", parenttype)
    masked = {f.fieldname for f in meta.get_masked_fields(parenttype=parenttype)}
    fields = []
    children = {}
    for df in meta.fields:
        if df.fieldname not in readable and df.fieldtype not in LAYOUT:
            continue
        field = {key: df.get(key) for key in (
            "fieldname", "label", "fieldtype", "options", "reqd", "hidden", "read_only",
            "default", "description", "depends_on", "mandatory_depends_on", "read_only_depends_on",
            "allow_on_submit", "fetch_from", "fetch_if_empty", "precision", "in_list_view")}
        field["read_only"] = bool(df.fieldtype == "Read Only" or df.read_only or df.fieldname not in writable or df.fieldname in masked)
        field["conditions"] = _field_conditions(field)
        fields.append(field)
        if df.fieldtype in ("Table", "Table MultiSelect") and df.options:
            children[df.options] = _schema(frappe.get_meta(df.options), parenttype or meta.name)
    return {"doctype": meta.name, "module": meta.module, "fields": fields, "children": children,
        "operation_recovery_supported": recovery_reason is None,
        "operation_recovery_reason": recovery_reason,
        "single": bool(meta.issingle), "submittable": bool(meta.is_submittable),
        "title_field": meta.title_field, "autoname": meta.autoname, "preparable": bool(meta.has_field("items") and meta.has_field("taxes") and meta.has_field("currency")),
        "party_defaults":meta.name in SELLING | BUYING,
        "item_defaults":meta.name in ITEM_TRANSACTIONS}


@frappe.whitelist()
def catalog(company=None):
    _signed_in()
    if not company:
        from erp_extensions.workspace import context
        company = context()['company']
    managed = membership()
    from erp_extensions.knitting.permissions import visible_type, is_pack
    from erp_extensions.migration.api import customer_workspace, WORKSPACE_RECORDS
    from erp_extensions import master_import
    knitting_only = customer_workspace(company)
    types = []
    for dt in frappe.get_all("DocType", fields=["name", "module", "issingle", "is_submittable", "is_tree"],
        filters={"istable": 0}, order_by="module, name"):
        if knitting_only and dt.name not in WORKSPACE_RECORDS and not is_pack(dt.name):
            continue
        if (not managed or team_scope.native_type_allowed(dt.name)) and frappe.has_permission(dt.name, "read") and visible_type(dt.name, company):
            types.append({**dt, "can_import": master_import.allowed(dt.name), "can_group": dt.name in master_import.GROUPS and frappe.has_permission(dt.name, "write"), "create": bool(not is_pack(dt.name) and (not managed or team_scope.native_type_allowed(dt.name, 'create')) and frappe.has_permission(dt.name, "create"))})
    reports = []
    for row in frappe.get_all("Report", fields=["name", "module", "ref_doctype", "report_type"],
        filters={"disabled": 0}, order_by="module, name"):
        managed_allowed = (not managed or row.name in team_scope.COMPANY_REPORTS or
                           row.report_type == 'Report Builder' and team_scope.native_type_allowed(row.ref_doctype))
        if knitting_only and row.name not in team_scope.COMPANY_REPORTS and not (
                row.report_type == 'Report Builder' and (row.ref_doctype in WORKSPACE_RECORDS or is_pack(row.ref_doctype))):
            continue
        if managed_allowed and frappe.has_permission(row.ref_doctype, "report") and frappe.get_doc("Report", row.name).is_permitted():
            reports.append(row)
    return {"version": VERSION, "site": frappe.local.site, "user": frappe.session.user, "types": types, "reports": reports}


@frappe.whitelist(methods=['POST'])
def reclassify_masters(doctype, company, records, group):
    from erp_extensions import master_import
    return master_import.reclassify(doctype, company, records, group)


@frappe.whitelist(methods=['POST'])
def import_masters(doctype, company, content=None, stage='template'):
    from erp_extensions import master_import
    return master_import.run(doctype, company, content, stage)


@frappe.whitelist()
def schema(doctype):
    meta = _meta(doctype)
    result = _schema(meta)
    result["permissions"] = {p: bool(frappe.has_permission(doctype, p)) for p in
        ("read", "write", "create", "submit", "cancel", "amend", "print", "report")}
    return result


def _native_identities(data, meta):
    if data.get("name") is not None:
        data["name"] = str(data["name"])
    for field in meta.get_table_fields():
        for row in data.get(field.fieldname) or []:
            _native_identities(row, frappe.get_meta(field.options))
    return data


def _result(doc):
    from frappe.model.workflow import get_transitions, get_workflow_name
    permissions = dict(get_doc_permissions(doc))
    if doc.doctype == 'Sales Invoice' and permissions.get('print'):
        from erp_extensions.invoices import _printable
        permissions['print'] = not doc.is_new() and _printable(
            doc.name, doc.docstatus, frappe.get_cached_doc('Print Settings'))
    from erp_extensions.knitting.permissions import is_pack
    guarded = is_pack(doc.doctype) or bool(doc.get("knitting_event") or doc.get("knitting_job"))
    if guarded:
        permissions.update({p: False for p in ("write", "create", "submit", "cancel", "amend")})
    workflow = get_workflow_name(doc.doctype)
    transitions = get_transitions(doc) if workflow and not doc.is_new() and not guarded else []
    data = _native_identities(doc.copy_with_fieldlevel_read_permissions().as_dict(), doc.meta)
    if doc.flags.native_field_changes:
        _restore_field_uploads(doc, data)
    if doc.is_new() and doc.get("__newname"):
        data["__newname"] = doc.get("__newname")
    if doc.is_new() and doc.flags.native_origin:
        data["__native_origin"] = doc.flags.native_origin
    return {"doc": data, "permissions": permissions, "related_actions":_related_actions(doc),
        "workflow": workflow, "transitions": [{"action": t.action, "next_state": t.next_state} for t in transitions]}


@frappe.whitelist()
def document(doctype, name=None, company=None, tree_parent=None):
    meta = _meta(doctype, "read" if name or frappe.get_meta(doctype).issingle else "create")
    if name or meta.issingle:
        doc = frappe.get_doc(doctype, name or doctype)
        doc.check_permission("read")
        if doctype == "Sales Invoice" and company and doc.company != company:
            frappe.throw("You cannot open this invoice in this company.", frappe.PermissionError)
        doc.run_method("onload")
    else:
        doc = frappe.new_doc(doctype)
        if tree_parent:
            parent_field = _tree_meta(meta)
            parent = _tree_parent(meta, tree_parent, company)
            df = meta.get_field(parent_field)
            if df.read_only or df.hidden or parent_field not in _fieldnames(meta, "create"):
                frappe.throw("This account cannot create a child here.", frappe.PermissionError)
            if meta.has_field("is_group") and not parent.is_group:
                frappe.throw("Choose a group before creating a child.")
            doc.set(parent_field, parent.name)
            if meta.has_field("company"):
                company = company or parent.company
        if company and meta.has_field("company"):
            frappe.get_doc("Company", company).check_permission("read")
            doc.company = company
    return _result(doc)


def _input(value):
    value = frappe.parse_json(value) if isinstance(value, str) else value
    if not isinstance(value, Mapping) or not isinstance(value.get("doctype"), str):
        frappe.throw("A document with a record type is required.")
    return value


def _apply(doc, values, parenttype=None, permission=None):
    permission = permission or ("create" if doc.is_new() else "write")
    writable = _fieldnames(doc.meta, permission, parenttype)
    masked = {f.fieldname for f in doc.meta.get_masked_fields(parenttype=parenttype)}
    for df in doc.meta.fields:
        key = df.fieldname
        if key not in values or df.fieldtype in LAYOUT:
            continue
        value = values[key]
        old = doc.get(key)
        readonly = df.fieldtype == "Read Only" or df.read_only or df.hidden or key not in writable or key in masked
        if cint(doc.docstatus) == 1 and not df.allow_on_submit:
            readonly = True
        if readonly:
            if value != old and not (value in (None, "") and old in (None, "")):
                frappe.throw(f"{df.label or key} is read only for this account.", frappe.PermissionError)
            continue
        if df.fieldtype in NUMERIC and value not in (None, ""):
            try:
                numeric = float(value)
            except (ValueError, TypeError):
                frappe.throw(f"{df.label or key} must be a valid number.")
            if not math.isfinite(numeric) or df.fieldtype == "Int" and not numeric.is_integer():
                frappe.throw(f"{df.label or key} must be a finite {df.fieldtype.lower()} value.")
        if df.fieldtype in ("Table", "Table MultiSelect"):
            if not isinstance(value, list) or any(not isinstance(row, Mapping) for row in value):
                frappe.throw(f"{df.label or key} must contain rows.")
            existing = {str(row.name): row for row in old or [] if row.name}
            updated = []
            seen = set()
            for data in value:
                name = str(data["name"]) if data.get("name") is not None else None
                if name:
                    if name not in existing or name in seen:
                        frappe.throw("A child row does not belong to this document.", frappe.PermissionError)
                    seen.add(name)
                    row = existing[name]
                else:
                    row = frappe.new_doc(df.options)
                _apply(row, data, parenttype or doc.doctype, permission)
                if row.flags.native_field_changes:
                    doc.flags.native_field_changes = True
                row.idx = len(updated) + 1
                updated.append(row)
            removed = [r for key, r in existing.items() if key not in seen]
            for previous in removed:
                attachment_fields = [f.fieldname for f in previous.meta.fields if f.fieldtype in ("Attach", "Attach Image")]
                for field in attachment_fields:
                    if previous.get(field):
                        doc.flags.native_field_changes = True
                        doc.flags.setdefault("native_removed_row_files", []).append((previous, field, previous.get(field)))
            doc.set(key, updated)
        elif df.fieldtype in ("Attach", "Attach Image") and value != old:
            doc.flags.native_field_changes = True
            if isinstance(value, Mapping):
                if set(value) != {"filename", "content"}:
                    frappe.throw("Choose a file from this device.")
                doc.flags.setdefault("native_field_uploads", {})[key] = value
            elif value:
                frappe.throw("Choose a file from this device.", frappe.PermissionError)
            else:
                doc.set(key, "")
            if old:
                doc.flags.setdefault("native_old_files", {})[key] = old
        else:
            doc.set(key, value)


def _editable(value):
    values = _input(value)
    meta = _meta(values["doctype"], "create" if values.get("__islocal") or not values.get("name") else "write")
    if values.get("__native_origin"):
        if values.get("name"):
            frappe.throw("Save a new linked draft before editing an existing record.")
        doc = _origin_document(meta.name, values["__native_origin"])
    elif values.get("__islocal") or not values.get("name") and not meta.issingle:
        doc = frappe.new_doc(meta.name)
    else:
        doc = frappe.get_doc(meta.name, values.get("name") or meta.name)
        doc.check_permission("write")
        _check_version(doc, values.get("modified"))
    if doc.is_new() and (meta.autoname or "").lower() == "prompt" and "__newname" in values:
        name = values["__newname"]
        if not isinstance(name, str) or not name.strip():
            frappe.throw("Enter a document name.")
        doc.set("__newname", name.strip())
    _apply(doc, values)
    team_scope.check_links(doc)
    doc.check_permission("create" if doc.is_new() else "write")
    return doc


def _check_version(doc, modified):
    try:
        matches = bool(modified) and get_datetime(modified) == get_datetime(doc.modified)
    except (TypeError, ValueError):
        matches = False
    if not matches:
        frappe.throw("Someone changed this document. Reload it before continuing.", frappe.TimestampMismatchError)


@frappe.whitelist(methods=["POST"])
def save(document, action="Save", request_id=None, company=None):
    from erp_extensions import operations
    values = _input(document)
    return operations.execute(company, 'native_save', request_id, {'document': values, 'action': action},
        lambda: _save(values, action, company if request_id else None),
        doctype=values.get('doctype'), name=None if values.get('__islocal') else values.get('name'), action=action)


def _save(document, action, operation_company=None):
    doc = _editable(document)
    if operation_company:
        from erp_extensions.operations import _check_document_company
        _check_document_company(doc, operation_company)
    changed_files = _prepare_field_files(doc) if action in ("Save", "Submit") else []
    if action == "Save":
        doc.save()
    elif action == "Submit":
        doc.submit()
    elif action == "Cancel":
        doc.cancel()
    else:
        frappe.throw("Unknown document action.")
    for target, field, url in changed_files:
        if target.get(field) != url or target.get("parentfield") and not frappe.db.exists(target.doctype, target.name):
            for name in frappe.get_all("File", filters={"attached_to_doctype":target.doctype,
                        "attached_to_name":target.name, "attached_to_field":field, "file_url":url}, pluck="name"):
                frappe.delete_doc("File", name, ignore_permissions=True)
    return _result(doc)


@frappe.whitelist(methods=["POST"])
def prepare(document):
    doc = _editable(document)
    from erpnext.controllers.accounts_controller import AccountsController
    if not isinstance(doc, AccountsController) or not (doc.meta.has_field("items") and doc.meta.has_field("taxes") and doc.meta.has_field("currency")) or cint(doc.docstatus) != 0:
        frappe.throw("Calculation refresh is not available for this document.")
    doc.calculate_taxes_and_totals()
    return _result(doc)


@frappe.whitelist()
def new_row(document, field):
    doc = _editable(document)
    df = doc.meta.get_field(field)
    if not df or df.fieldtype not in ("Table", "Table MultiSelect") or df.read_only or df.hidden:
        frappe.throw("This field cannot accept new rows.", frappe.PermissionError)
    if field not in _fieldnames(doc.meta, "create" if doc.is_new() else "write"):
        frappe.throw("This account cannot add rows here.", frappe.PermissionError)
    child = frappe.new_doc(df.options, parent_doc=doc, parentfield=field)
    doc.append(field, child)
    visible = doc.copy_with_fieldlevel_read_permissions().get(field)
    if not visible:
        frappe.throw("This account cannot read these rows.", frappe.PermissionError)
    return {"doc": visible[-1].as_dict()}


@frappe.whitelist()
def task_view(company, month=None, status=None, start=0):
    from erp_extensions.task_views import task_view as get_tasks
    return get_tasks(company, month=month, status=status, start=start)


@frappe.whitelist()
def records(doctype, query="", start=0, company=None, limit=50):
    meta = _meta(doctype)
    if meta.issingle:
        return []
    readable = _fieldnames(meta, "read")
    fields = ["name", "modified"]
    if meta.title_field and meta.title_field in readable:
        fields.append(meta.title_field)
    filters = {"company": company} if company and meta.has_field("company") else {}
    or_filters = [["name", "like", f"%{query}%"]] if query else None
    if query and meta.title_field and meta.title_field in readable:
        or_filters.append([meta.title_field, "like", f"%{query}%"])
    rows = frappe.get_list(doctype, fields=fields, filters=filters, or_filters=or_filters,
        start=max(0, cint(start)), page_length=min(100, max(1, cint(limit))), order_by="modified desc")
    return [{**row, "name":str(row["name"])} for row in rows]


def _tree_meta(meta):
    parent_field = meta.nsm_parent_field or "parent_" + frappe.scrub(meta.name)
    if not meta.is_tree or not meta.has_field(parent_field):
        frappe.throw("This record type does not provide a hierarchy.")
    readable = _fieldnames(meta, "read")
    masked = {f.fieldname for f in meta.get_masked_fields()}
    required = {parent_field} | ({"is_group"} if meta.has_field("is_group") else set())
    if not required.issubset(readable - masked):
        frappe.throw("This account cannot read this hierarchy.", frappe.PermissionError)
    return parent_field


def _tree_parent(meta, name, company):
    parent = frappe.get_doc(meta.name, name)
    parent.check_permission("read")
    if company and meta.has_field("company") and parent.company not in (None, "", company):
        frappe.throw("The selected group belongs to another company.", frappe.PermissionError)
    return parent


@frappe.whitelist()
def tree_children(doctype, parent=None, company=None, start=0, limit=50):
    meta = _meta(doctype)
    parent_field = _tree_meta(meta)
    if parent:
        _tree_parent(meta, parent, company)
    filters = [["docstatus", "<", 2],
        [parent_field, "=", parent] if parent else [parent_field, "is", "not set"]]
    shared_company = [["company", "=", company], ["company", "is", "not set"]] if company and meta.has_field("company") else None
    fields = ["name", "modified"] + (["is_group"] if meta.has_field("is_group") else [])
    readable = _fieldnames(meta, "read") - {f.fieldname for f in meta.get_masked_fields()}
    if meta.title_field and meta.title_field in readable and meta.title_field != "name":
        fields.append(meta.title_field)
    limit = min(100, max(1, cint(limit)))
    rows = frappe.get_list(doctype, fields=fields, filters=filters, or_filters=shared_company,
        offset=max(0, cint(start)), limit=limit + 1, order_by="name asc")
    df = meta.get_field(parent_field)
    return {"nodes": [{"name":str(row.name), "modified":row.modified, "title":row.get(meta.title_field) or str(row.name),
        "expandable":bool(row.is_group) if meta.has_field("is_group") else True} for row in rows[:limit]], "has_more":len(rows) > limit,
        "can_rename":bool(meta.allow_rename and frappe.has_permission(doctype, "write") and (not membership() or team_scope.native_type_allowed(doctype, "write"))),
        "can_delete":bool(frappe.has_permission(doctype, "delete") and (not membership() or team_scope.native_type_allowed(doctype, "delete"))),
        "can_create":bool(frappe.has_permission(doctype, "create") and not df.read_only and not df.hidden
            and parent_field in _fieldnames(meta, "create"))}


@frappe.whitelist(methods=["POST"])
def change_tree_record(doctype, name, modified, action, company=None, new_name=None):
    if action not in ("rename", "delete"):
        frappe.throw("Choose a hierarchy action.")
    permission = "write" if action == "rename" else "delete"
    meta = _meta(doctype, permission)
    parent_field = _tree_meta(meta)
    doc = frappe.get_doc(doctype, name, for_update=True)
    doc.check_permission("read")
    doc.check_permission(permission)
    if company and meta.has_field("company") and doc.company != company:
        frappe.throw("Choose a record belonging to the current company.", frappe.PermissionError)
    _check_version(doc, modified)
    if action == "rename":
        if not meta.allow_rename or not isinstance(new_name, str) or not new_name.strip():
            frappe.throw("Choose a new name for a record that supports renaming.")
        return {"name":str(frappe.rename_doc(doctype, name, new_name.strip()))}
    if frappe.db.exists(doctype, {parent_field:name}):
        frappe.throw("Move or remove the children before deleting this group.")
    frappe.delete_doc(doctype, name)
    return {"deleted":True}


def _document_link_filters(doctype, parent, field, context):
    values = frappe.parse_json(context) if isinstance(context, str) else context or {}
    if not isinstance(values, dict):
        frappe.throw("Choose a record from the form.")
    company = values.get("company")
    transactional = parent in ITEM_TRANSACTIONS | {"Work Order","Stock Entry","Payment Entry","Journal Entry"}
    if transactional and company and doctype in {"Account","Warehouse","Cost Center","BOM"}:
        from erp_extensions.knitting.permissions import company_allowed
        if not isinstance(company,str) or not company_allowed(company):
            frappe.throw("Choose an accessible company first.", frappe.PermissionError)
    filters = {}
    if doctype == "Finance Book" and company:
        from erp_extensions.knitting.permissions import company_allowed
        from erp_extensions.migration.finance import BOOK_BINDING, _bindings
        if not isinstance(company, str) or not company_allowed(company):
            frappe.throw("Choose an accessible company first.", frappe.PermissionError)
        books = _bindings(company)
        if books:
            filters["name"] = ["in", [row.finance_book for row in books]]
        elif frappe.db.exists("DocType", BOOK_BINDING):
            mapped = frappe.get_all(BOOK_BINDING, pluck="finance_book")
            if mapped:
                filters["name"] = ["not in", mapped]
    if field == 'group' and (parent,doctype) in {('Customer','Customer Group'),('Supplier','Supplier Group'),('Item','Item Group')}:
        filters['is_group'] = 0
    if transactional and company and doctype in {"Account","Warehouse","Cost Center"}:
        filters.update(company=company, is_group=0, disabled=0)
    if parent == "Sales Invoice" and field == "customer" and doctype == "Customer":
        filters["disabled"] = 0
    if doctype == "Item" and field == "item_code" and parent in SELLING | BUYING:
        filters.update(disabled=0, has_variants=0)
        filters["is_sales_item" if parent in SELLING else "is_purchase_item"] = 1
    if parent == "Work Order" and doctype == "Item" and field == "production_item":
        filters.update(disabled=0, has_variants=0, is_stock_item=1)
    if parent == "Work Order" and doctype == "BOM" and field == "bom_no":
        item = values.get("production_item")
        if not item:
            return None
        if not isinstance(item, str):
            frappe.throw("Select a production item first.")
        _reference("Item", item)
        filters.update(item=item, docstatus=1, is_active=1)
        if company:
            filters["company"] = company
    return filters


@frappe.whitelist()
def search_link(doctype, query="", parent=None, field=None, context=None):
    _signed_in()
    values = frappe.parse_json(context) if isinstance(context, str) else context
    filters = _document_link_filters(doctype, parent, field, values) if values is not None else {}
    if filters is None:
        return []
    if membership():
        rows = team_scope.search_link(doctype, query, filters)
    else:
        from frappe.desk.search import search_link as search
        rows = search(doctype=doctype, txt=query, page_length=30, reference_doctype=parent, filters=filters)
    if (not query and parent == "Sales Invoice" and field == "customer" and doctype == "Customer"
            and values and isinstance(values.get("company"), str)):
        from erp_extensions.invoices import recent_customer_choices
        return recent_customer_choices(values["company"], rows)
    return rows


@frappe.whitelist(methods=["POST"])
def transition(doctype, name, action, modified=None, request_id=None, company=None):
    from erp_extensions import operations
    return operations.execute(company, 'native_transition', request_id,
        {'doctype': doctype, 'name': name, 'action': action, 'modified': modified},
        lambda: _transition(doctype, name, action, modified, company if request_id else None),
        doctype=doctype, name=name, action=action)


def _transition(doctype, name, action, modified, operation_company=None):
    _meta(doctype)
    from frappe.model.workflow import apply_workflow
    doc = frappe.get_doc(doctype, name, for_update=True)
    doc.check_permission("read")
    if operation_company:
        from erp_extensions.operations import _check_document_company
        _check_document_company(doc, operation_company)
    _check_version(doc, modified)
    result = apply_workflow(doc.as_dict(), action)
    return _result(frappe.get_doc(result))


def _report(name):
    _signed_in()
    if membership() and name not in team_scope.COMPANY_REPORTS:
        definition = frappe.db.get_value('Report', name, ['report_type', 'ref_doctype'], as_dict=True)
        if not definition or definition.report_type != 'Report Builder' or not team_scope.native_type_allowed(definition.ref_doctype):
            frappe.throw("This report is unavailable in this workspace.", frappe.PermissionError)
    from frappe.desk.query_report import get_report_doc
    return get_report_doc(name)


def _report_default(value, company=None):
    if not isinstance(value, dict) or "native_default" not in value:
        return value
    from frappe.utils import add_days, add_months, get_first_day, get_last_day, get_datetime_in_timezone, get_system_timezone
    from erpnext.accounts.utils import get_fiscal_year
    kind = value["native_default"]
    if kind == "user":
        return frappe.defaults.get_user_default(value["key"])
    if kind == 'global_date' and value['key'] in ('year_start_date','year_end_date'):
        return frappe.defaults.get_global_default(value['key'])
    if kind == 'fallback':
        return _report_default(value['first'], company) or _report_default(value['second'], company)
    if kind == 'bank_account':
        if not company:
            company = frappe.defaults.get_user_default('Company')
        if company and frappe.has_permission('Company', 'read', doc=company):
            account = frappe.get_cached_value('Company', company, 'default_bank_account')
            if account and frappe.has_permission('Account', 'select', doc=account):
                return account
        return None
    timezone = frappe.get_cached_value('User', frappe.session.user, 'time_zone') or get_system_timezone()
    now = get_datetime_in_timezone(timezone)
    date = now.date()
    if kind in ('fiscal_year', 'fiscal_start', 'fiscal_end'):
        from erpnext.accounts.utils import FiscalYearError
        try:
            fiscal = get_fiscal_year(date, company=company, verbose=0)
        except FiscalYearError:
            return None
        return str(fiscal[{'fiscal_year':0, 'fiscal_start':1, 'fiscal_end':2}[kind]])
    if kind == "today":
        return str(date)
    if kind == 'user_datetime':
        return now.strftime('%Y-%m-%d %H:%M:%S')
    if kind == 'system_month_offset':
        from zoneinfo import ZoneInfo
        return add_months(now, value['value']).astimezone(ZoneInfo(get_system_timezone())).strftime('%Y-%m-%d %H:%M:%S')
    if kind == "date_offset":
        fn = add_months if value["unit"] == "months" else add_days
        base = get_first_day(date) if value.get('base') == 'month_start' else date
        return str(fn(base, value["value"]))
    if kind == "month_start":
        return str(get_first_day(date))
    if kind == "month_end":
        return str(get_last_day(date))
    if kind in ("year_start", "year_end"):
        return f"{date.year}-{'01-01' if kind == 'year_start' else '12-31'}"
    return None


@frappe.whitelist()
def report_definition(name, company=None):
    report = _report(name)
    definitions = json.loads(Path(__file__).with_name("report_definitions.json").read_text())["reports"]
    definition = deepcopy(definitions.get(name, {"fields": [], "requires_adapter": True}))
    if report.filters:
        definition["fields"] = [field.as_dict() for field in report.filters]
    if report.report_type == "Report Builder":
        definition["fields"] = [{"fieldname":"search","fieldtype":"Data","label":"Search document name"}]
        if frappe.get_meta(report.ref_doctype).has_field("company"):
            definition["fields"].append({"fieldname":"company","fieldtype":"Link","options":"Company","label":"Company"})
    if name in ('General Ledger', 'Accounts Receivable', 'Accounts Receivable Summary', 'Accounts Payable', 'Accounts Payable Summary'):
        account_type = {'Accounts Receivable':'Receivable', 'Accounts Payable':'Payable'}.get(name.removesuffix(' Summary'))
        types = frappe.get_all('Party Type', filters={'account_type':account_type} if account_type else {},
                               pluck='name', order_by='name')
        for field in definition['fields']:
            if field['fieldname'] == 'party_type':
                choices = [dt for dt in types if frappe.has_permission(dt, 'read')
                           and (not membership() or dt in ('Customer', 'Supplier', 'Employee'))]
                field.update(fieldtype='Select', options='\n'.join(choices))
    if member := membership():
        if company and company != member.company:
            frappe.throw('Choose your current company.', frappe.PermissionError)
        company = member.company
        definition['fields'] = [f for f in definition['fields'] if team_scope.report_field_allowed(f)]
    defaults = {}
    for field in definition["fields"]:
        field["conditions"] = _field_conditions(field)
        key = field["fieldname"]
        default = _report_default(field.get("default"), company)
        if default is None and field.get("options") == "Fiscal Year":
            default = _report_default({"native_default":"fiscal_year"}, company)
        if key == "company" and company:
            frappe.get_doc("Company", company).check_permission("read")
            default = company
        if default is not None:
            defaults[key] = default
        if field.get("fieldtype") == "MultiSelectList":
            defaults.setdefault(key, [])
        option_source = field.get('native_options')
        if option_source == 'enabled_currencies':
            field['options'] = '\n' + '\n'.join(frappe.get_all('Currency', filters={'enabled':1}, pluck='name', order_by='name'))
        elif option_source in ('enabled_accounting_dimensions', 'accounting_dimensions'):
            types = ['Cost Center', 'Project']
            if frappe.has_permission('Accounting Dimension', 'read'):
                types.extend(frappe.get_list('Accounting Dimension',
                    filters={'disabled':0} if option_source == 'enabled_accounting_dimensions' else {},
                    pluck='document_type', order_by='creation', limit=0))
            field['options'] = '\n'.join(dict.fromkeys(['', *types]))

    return {**definition, "name":name, "doctype":name,"children":{},"defaults":defaults,
        "reference":report.ref_doctype,"type":report.report_type,
        "can_export":bool(frappe.permissions.can_export(report.ref_doctype))}


def _builder_group(report, group, filters):
    from frappe.model.meta import get_default_df
    meta = frappe.get_meta(report.ref_doctype)
    readable = _fieldnames(meta, 'read') - {df.fieldname for df in meta.get_masked_fields()}

    def field(value):
        # Frappe saves both plain and table-qualified fieldnames. Use only real
        # readable fields on the report's own record type in aggregates.
        match = re.fullmatch(r'(?:`tab([^`]+)`\.)?`?([A-Za-z_][A-Za-z0-9_]*)`?', str(value))
        if not match or match[1] not in (None, meta.name):
            frappe.throw('This grouping requires a field on the report record.')
        name = match[2]
        df = meta.get_field(name)
        if df is None and name in ('name', 'owner', 'modified_by', 'creation', 'modified', 'docstatus', 'idx'):
            df = get_default_df(name)
        elif name not in readable:
            frappe.throw('This group contains a field you cannot read.', frappe.PermissionError)
        if not df or df.fieldtype in LAYOUT | {'Table', 'Table MultiSelect', 'Password', 'Code'}:
            frappe.throw('This field cannot be grouped.')
        return df

    if not isinstance(group, Mapping):
        frappe.throw('This saved report requires a supported grouping.')
    group_field = field(group.get('group_by'))
    operation = str(group.get('aggregate_function') or 'count').lower()
    if operation not in ('count', 'sum', 'avg'):
        frappe.throw('Choose Count, Sum or Average in the saved report.')
    target = field(group.get('aggregate_on')) if operation != 'count' else None
    if target and target.fieldtype not in NUMERIC:
        frappe.throw('A total or average requires a numeric field.')
    aggregate = {'fieldname':'_aggregate_column', 'fieldtype':'Int', 'label':'Count'}
    if target:
        aggregate.update(fieldtype='Float' if operation == 'avg' and target.fieldtype == 'Int' else target.fieldtype,
                         label=f"{'Sum' if operation == 'sum' else 'Average'} of {target.label}")
        # A group can contain different document currencies.
        if target.fieldtype == 'Currency' and target.options and target.options != group_field.fieldname:
            aggregate['fieldtype'] = 'Float'
    group_name = group_field.fieldname
    query_fields = [group_name, {operation.upper():target.fieldname if target else 'name', 'as':'_aggregate_column'}]
    rows = frappe.get_list(meta.name, fields=query_fields, filters=filters, group_by=group_name,
                           order_by='_aggregate_column desc', limit=10001)
    return {'columns':[{'fieldname':group_name, 'label':group_field.label, 'fieldtype':group_field.fieldtype,
                        'options':group_field.options}, aggregate],
            'result':rows[:10000], 'truncated':len(rows) > 10000}


def _managed_builder_input(meta, config, filters, company):
    if set(filters) - {'search', 'company'} or filters.get('company', company) != company:
        frappe.throw('Choose your current company for this report.', frappe.PermissionError)
    if not isinstance(filters.get('search', ''), str):
        frappe.throw('Enter a document name to search.')
    allowed = _fieldnames(meta, 'read') - {df.fieldname for df in meta.get_masked_fields()}
    allowed = {name for name in allowed if (df := meta.get_field(name)) and df.fieldtype not in LAYOUT | {
        'Table', 'Table MultiSelect', 'Password', 'Code'}} | {'name', 'creation','modified','docstatus'}
    for column in config.get('columns') or config.get('fields') or []:
        if isinstance(column, list) and len(column) == 2 and column[1] == meta.name:
            column = column[0]
        if not isinstance(column, str) or (column not in allowed and not (column == '_aggregate_column' and config.get('group_by'))):
            frappe.throw('This saved report contains a column outside your workspace access.', frappe.PermissionError)
    for condition in config.get('filters') or []:
        if not isinstance(condition, list):
            frappe.throw('This saved filter is unavailable in the workspace.', frappe.PermissionError)
        if len(condition) == 4 and condition[0] == meta.name:
            condition = condition[1:]
        if len(condition) != 3 or condition[0] not in allowed:
            frappe.throw('This saved filter is unavailable in the workspace.', frappe.PermissionError)
    sort = config.get('order_by')
    if sort:
        for term in sort.split(','):
            match = re.fullmatch(r'(?:`tab' + re.escape(meta.name) + r'`\.)?`?([a-zA-Z_]\w*)`?(?: (?:asc|desc))?', term.strip(), re.I)
            if not match or not (match[1] in allowed or match[1] == '_aggregate_column' and config.get('group_by')):
                frappe.throw('This saved sort is unavailable in the workspace.', frappe.PermissionError)
    return {**filters, 'company':company}


def _builder_report(report, filters):
    config = frappe.parse_json(report.json) if report.json else {}
    meta = frappe.get_meta(report.ref_doctype)
    if member := membership():
        filters = _managed_builder_input(meta, config, filters, member.company)
    if config.get("add_totals_row") or config.get("aggregates"):
        frappe.throw("This report’s grouping is not available in the app yet.")
    conditions = list(config.get("filters") or [])
    if filters.get("company") and meta.has_field("company"):
        conditions.append(["company","=",filters["company"]])
    if filters.get("search"):
        conditions.append(["name","like",f"%{filters['search']}%"])
    if config.get("group_by"):
        return _builder_group(report, config["group_by"], conditions)
    raw_columns = config.get("columns") or config.get("fields")
    if not raw_columns:
        permitted = _fieldnames(meta, "read") - {f.fieldname for f in meta.get_masked_fields()}
        raw_columns = [["name",meta.name]] + [[df.fieldname,meta.name] for df in meta.fields if df.in_list_view and df.fieldname in permitted and df.fieldtype not in ("Table","Table MultiSelect")]
    fields = []
    columns = []
    for col in raw_columns:
        fieldname, doctype = col if isinstance(col,list) else (col,meta.name)
        df = frappe.get_meta(doctype).get_field(fieldname)
        fields.append(fieldname if doctype == meta.name else f"{doctype}.{fieldname}")
        columns.append({"fieldname":fieldname,"label":df.label if df else fieldname.replace("_"," ").title(),
            "fieldtype":df.fieldtype if df else "Data","options":df.options if df else None})
    rows = frappe.get_list(meta.name, fields=fields, filters=conditions, limit=10001,
        order_by=config.get("order_by") or "modified desc")
    return {"columns":columns,"result":rows[:10000],"truncated":len(rows)>10000}


def _can_show_report_chart(report, filters):
    # Frappe filters result rows after running the report. A chart is computed
    # by the report controller before row filtering, so it must share that scope.
    if frappe.session.user == 'Administrator':
        return True
    from frappe.permissions import get_role_permissions, get_user_permissions
    roles = get_role_permissions(frappe.get_meta(report.ref_doctype))
    if roles.get('if_owner', {}).get('report'):
        return False
    scopes = get_user_permissions(frappe.session.user)
    if not scopes:
        return True
    return (set(scopes) == {'Company'} and report.name in team_scope.COMPANY_REPORTS
            and filters.get('company') in {p['doc'] for p in scopes['Company']})


@frappe.whitelist()
def run_report(name, filters=None):
    report = _report(name)
    filters = frappe.parse_json(filters) if isinstance(filters,str) else filters or {}
    if not isinstance(filters, Mapping):
        frappe.throw("Report filters must be an object.")
    if "prepared_report_name" in filters:
        frappe.throw("Open prepared reports using their original filters.", frappe.PermissionError)
    if report.report_type == "Report Builder":
        return _builder_report(report, filters)
    from frappe.desk.query_report import run
    definition = report_definition(name)
    if member := membership():
        filters = team_scope.report_filters(name, filters, definition['fields'], member.company)
        result = run(name, filters=filters, js_filters=definition['fields'], ignore_prepared_report=True, are_default_filters=False)
    else:
        result = run(name, filters=filters, js_filters=definition["fields"])
    if result.get('chart') and not _can_show_report_chart(report, filters):
        result['chart'] = None
    return result


@frappe.whitelist(methods=["POST"])
def queue_report(name, filters=None):
    _report(name)
    if membership():
        frappe.throw('Run this company report directly in your workspace.', frappe.PermissionError)
    filters = frappe.parse_json(filters) if isinstance(filters,str) else filters or {}
    if not isinstance(filters, Mapping):
        frappe.throw("Report filters must be an object.")
    from frappe.desk.query_report import validate_filters_permissions
    from frappe.core.doctype.prepared_report.prepared_report import make_prepared_report
    validate_filters_permissions(name, filters, js_filters=report_definition(name)["fields"])
    return make_prepared_report(name, filters)


def _reference(doctype, name, permission="read"):
    _meta(doctype, permission)
    doc = frappe.get_doc(doctype, name)
    doc.check_permission(permission)
    return doc


def _attachment(doc, file):
    attachment = frappe.get_doc("File", file)
    attachment.check_permission("read")
    if (attachment.attached_to_doctype, str(attachment.attached_to_name)) != (doc.doctype, str(doc.name)):
        frappe.throw("This attachment belongs to another document.", frappe.PermissionError)
    field = attachment.attached_to_field
    if field and (field not in _fieldnames(doc.meta, "read") or
        field in {f.fieldname for f in doc.meta.get_masked_fields()}):
        frappe.throw("This attachment is restricted.", frappe.PermissionError)
    return attachment


@frappe.whitelist()
def activity(doctype, name):
    doc = _reference(doctype, name)
    from frappe.desk.form.load import get_attachments, get_assignments, get_comments, get_versions
    attachments = []
    for row in get_attachments(doctype, name):
        try:
            _attachment(doc, row.name)
            attachments.append(row)
        except frappe.PermissionError:
            frappe.clear_last_message()
    readable = _fieldnames(doc.meta, "read") - {f.fieldname for f in doc.meta.get_masked_fields()}
    versions = []
    for row in get_versions(doc):
        data = frappe.parse_json(row.data) or {}
        changes = [change for change in data.get("changed", []) if change[0] in readable]
        versions.append({"name":row.name,"owner":row.owner,"creation":row.creation,"changed":changes})
    # Field attachments have per-field access. Old attachment comments may still
    # name a restricted file after a replacement, so use the filtered Files list.
    types = ["Comment", "Workflow", "Info", "Edit", "Assigned", "Assignment Completed"]
    if all(f.fieldname in readable for f in doc.meta.fields if f.fieldtype in ("Attach", "Attach Image")):
        types.extend(["Attachment", "Attachment Removed"])
    comments = get_comments(doctype, name, types)
    return {"comments":comments,"versions":versions,"attachments":attachments,
        "assignments":get_assignments(doctype,name),"permissions":get_doc_permissions(doc)}


@frappe.whitelist(methods=["POST"])
def add_comment(doctype, name, content):
    _reference(doctype, name)
    if not isinstance(content, str) or not content.strip() or len(content) > 10000:
        frappe.throw("Enter a comment between 1 and 10,000 characters.")
    from html import escape
    from frappe.desk.form.utils import add_comment as standard_add_comment
    comment = standard_add_comment(doctype, name, escape(content).replace("\n", "<br>"),
        frappe.session.user, frappe.utils.get_fullname())
    return {"name":comment.name}


@frappe.whitelist(methods=["POST"])
def assign(doctype, name, user, description=""):
    _reference(doctype, name)
    if membership() and (not membership(user) or membership(user).company != membership().company):
        frappe.throw('Select a member of this team.', frappe.PermissionError)
    from frappe.share import validate_user_access
    from frappe.desk.form.assign_to import add
    validate_user_access(user, "Assigned To")
    add({"doctype":doctype,"name":name,"assign_to":[user],"description":description})
    return {"assigned":user}


@frappe.whitelist(methods=["POST"])
def unassign(doctype, name, user):
    _reference(doctype, name)
    if membership() and (not membership(user) or membership(user).company != membership().company):
        frappe.throw('Select a member of this team.', frappe.PermissionError)
    from frappe.desk.form.assign_to import remove
    remove(doctype, name, user)
    return {"removed":user}


def _file_content(filename, content):
    import base64
    import binascii
    if not isinstance(filename, str) or not filename.strip() or "/" in filename or "\\" in filename:
        frappe.throw("Choose a valid file name.")
    # Keep JSON transfers bounded on phones and the local 8 GB development Mac.
    if not isinstance(content, str) or len(content) > 7_000_000:
        frappe.throw("Choose a file smaller than 5 MB.")
    try:
        raw = base64.b64decode(content, validate=True)
    except (ValueError, binascii.Error):
        frappe.throw("The attachment could not be read.")
    if len(raw) > 5_000_000:
        frappe.throw("Choose a file smaller than 5 MB.")
    return raw


def _restore_field_uploads(doc, data):
    for field, value in (doc.flags.native_field_uploads or {}).items():
        visible = _fieldnames(doc.meta, "read", doc.parenttype if doc.meta.istable else None)
        if field in visible:
            data[field] = value
    for table in doc.meta.get_table_fields():
        for row, visible in zip(doc.get(table.fieldname) or [], data.get(table.fieldname) or []):
            if row.flags.native_field_changes:
                _restore_field_uploads(row, visible)


def _prepare_field_files(doc):
    """Bind uploaded bytes and the business document in the same transaction."""
    from frappe.model.naming import set_new_name
    if not doc.flags.native_field_changes:
        return []
    changed = [(target, field, url) for target, field, url in (doc.flags.native_removed_row_files or [])]
    pending = [(target, field, value) for target in [doc, *doc.get_all_children()]
               for field, value in (target.flags.native_field_uploads or {}).items()]
    if len(pending) > 20:
        frappe.throw("Save up to 20 field attachments at a time.")
    # A repeated failed save must not accumulate files before all selections are validated.
    prepared = []
    total = 0
    for target, field, value in pending:
        raw = _file_content(value["filename"], value["content"])
        total += len(raw)
        if not raw or total > 10_000_000:
            frappe.throw("Choose nonempty field files totaling up to 10 MB per save.")
        if target.meta.get_field(field).fieldtype == "Attach Image":
            _validate_field_image(raw)
        prepared.append((target, field, value["filename"], raw))
    if pending and doc.is_new() and not doc.name:
        doc.set_new_name()
    for target in [doc, *doc.get_all_children()]:
        changed.extend((target, f, url) for f, url in (target.flags.native_old_files or {}).items())
    for target, field, filename, raw in prepared:
        if not target.name:
            set_new_name(target)
        # _editable checked document, child-table, and field create/write privileges.
        file = frappe.get_doc({"doctype":"File","file_name":filename,"content":raw,"is_private":1,
            "attached_to_doctype":target.doctype, "attached_to_name":target.name, "attached_to_field":field})
        file.insert(ignore_permissions=True)
        target.set(field, file.file_url)
        target.flags.native_field_uploads.pop(field)
    doc.flags.native_field_changes = False
    return changed


def _validate_field_image(raw):
    from PIL import Image, UnidentifiedImageError
    from io import BytesIO
    try:
        with Image.open(BytesIO(raw)) as image:
            if image.format not in ("PNG","JPEG","WEBP","GIF") or image.width * image.height > 40_000_000:
                frappe.throw("Choose a PNG, JPEG, WebP or GIF image under 40 megapixels.")
            image.verify()
    except (UnidentifiedImageError, ValueError, SyntaxError, OSError, Image.DecompressionBombError):
        frappe.throw("Choose a valid PNG, JPEG, WebP or GIF image.")


@frappe.whitelist(methods=["POST"])
def upload_attachment(doctype, name, filename, content):
    _reference(doctype, name, "write")
    raw = _file_content(filename, content)
    file = frappe.get_doc({"doctype":"File","file_name":filename,"content":raw,"is_private":1,
        "attached_to_doctype":doctype,"attached_to_name":name}).insert()
    return {"name":file.name,"file_name":file.file_name,"file_size":file.file_size,"is_private":file.is_private}


@frappe.whitelist()
def field_attachment(doctype, name, field, table=None, row=None):
    parent = _reference(doctype, name)
    target = parent
    def readable(doc, key):
        return key in _fieldnames(doc.meta, "read", parent.doctype if doc != parent else None) and key not in {
            df.fieldname for df in doc.meta.get_masked_fields(parenttype=parent.doctype if doc != parent else None)}
    if table or row:
        df = parent.meta.get_field(table or "")
        if not df or df.fieldtype != "Table" or not readable(parent, table):
            frappe.throw("This row is unavailable.", frappe.PermissionError)
        target = next((r for r in parent.get(table) if str(r.name) == str(row)), None)
    df = target.meta.get_field(field) if target else None
    if not df or df.fieldtype not in ("Attach", "Attach Image") or not readable(target, field):
        frappe.throw("This field is unavailable.", frappe.PermissionError)
    url = target.get(field)
    file = frappe.db.get_value("File", {"attached_to_doctype":target.doctype, "attached_to_name":target.name,
        "file_url":url, "attached_to_field":field}, "name") if url else None
    if not file:
        frappe.throw("This field has no locally attached file.")
    return _file_bytes(frappe.get_doc("File", file))


@frappe.whitelist()
def attachment(doctype, name, file):
    doc = _reference(doctype, name)
    return _file_bytes(_attachment(doc, file))


def _file_bytes(file):
    import base64
    if file.file_size > 10_000_000:
        frappe.throw("This attachment exceeds the current native download limit of 10 MB.")
    # get_content reads the stored File; arbitrary URLs supplied by a client are never fetched.
    if file.is_remote_file:
        frappe.throw("Remote attachments need their storage integration configured in the native app.")
    content = file.get_content(encodings=())
    content = content.encode() if isinstance(content, str) else content
    return {"name":file.file_name,"content":base64.b64encode(content).decode()}


@frappe.whitelist(methods=["POST"])
def remove_attachment(doctype, name, file):
    doc = _reference(doctype, name, "write")
    file = _attachment(doc, file)
    if file.attached_to_field and doc.get(file.attached_to_field) == file.file_url:
        frappe.throw("Remove this file from its document field, then save the document.")
    file.delete()
    return {"removed":file.name}


@frappe.whitelist()
def print_options(doctype, name):
    doc = _reference(doctype, name, "print")
    formats = frappe.get_all("Print Format", filters={"doc_type":doctype,"disabled":0}, pluck="name")
    return {"formats":["Standard", *[f for f in formats if f != "Standard"]]}


@frappe.whitelist()
def print_pdf(doctype, name, format="Standard"):
    _reference(doctype, name, "print")
    if format not in print_options(doctype, name)["formats"]:
        frappe.throw("Choose an enabled print format for this document.")
    from frappe.utils.print_format import download_pdf
    import base64
    download_pdf(doctype, name, format=format)
    content = frappe.local.response.pop("filecontent")
    filename = frappe.local.response.pop("filename")
    frappe.local.response.pop("type", None)
    return {"name":filename,"content":base64.b64encode(content).decode()}


SELLING = {"Quotation", "Sales Order", "Delivery Note", "Sales Invoice"}
BUYING = {"Supplier Quotation", "Purchase Order", "Purchase Receipt", "Purchase Invoice"}
ITEM_TRANSACTIONS = SELLING | BUYING | {"Material Request"}


@frappe.whitelist(methods=["POST"])
def party_defaults(document):
    doc = _editable(document)
    if doc.doctype not in SELLING | BUYING or cint(doc.docstatus) != 0:
        frappe.throw("Party defaults are not available for this document.")
    from erpnext.accounts.party import get_party_details
    kind = "Customer" if doc.doctype in SELLING else "Supplier"
    field = "party_name" if doc.doctype == "Quotation" else kind.lower()
    party = doc.get(field)
    if not party or doc.doctype == "Quotation" and doc.quotation_to != "Customer":
        frappe.throw("Choose a customer or supplier first.")
    _reference(kind, party)
    _reference("Company", doc.company)
    details = get_party_details(party=party, party_type=kind, company=doc.company,
        posting_date=doc.get("posting_date") or doc.get("transaction_date"), bill_date=doc.get("bill_date"),
        price_list=doc.get("selling_price_list") or doc.get("buying_price_list"),
        currency=doc.get("currency"), doctype=doc.doctype)
    for key, value in details.items():
        if doc.meta.has_field(key):
            doc.set(key, value)
    doc.check_permission("create" if doc.is_new() else "write")
    return _result(doc)


@frappe.whitelist(methods=["POST"])
def item_defaults(document, field, row):
    doc = _editable(document)
    if doc.doctype not in ITEM_TRANSACTIONS or cint(doc.docstatus) != 0:
        frappe.throw("Item defaults are not available for this document.")
    df = doc.meta.get_field(field)
    if not df or df.fieldtype != "Table" or not frappe.get_meta(df.options).has_field("item_code"):
        frappe.throw("Choose an item row.")
    if df.hidden or df.read_only or field not in _fieldnames(doc.meta, "create" if doc.is_new() else "write"):
        frappe.throw("This account cannot change these items.", frappe.PermissionError)
    values = _input(row)
    if values["doctype"] != df.options:
        frappe.throw("The row does not match this item table.", frappe.PermissionError)
    existing = {r.name:r for r in doc.get(field) if r.name}
    child = existing.get(values.get("name")) if values.get("name") else frappe.new_doc(df.options)
    if child is None:
        frappe.throw("This row belongs to another document.", frappe.PermissionError)
    _apply(child, values, doc.doctype, "create" if doc.is_new() else "write")
    _reference("Item", child.item_code)
    _reference("Company", doc.company)
    for warehouse in (child.get("warehouse"),doc.get("set_warehouse"),child.get("from_warehouse")):
        if warehouse:
            _reference("Warehouse", warehouse)
    price_list = doc.get("selling_price_list") or doc.get("buying_price_list")
    if price_list:
        _reference("Price List", price_list)
    from erpnext.stock.get_item_details import get_item_details
    ctx = frappe._dict(doc.as_dict())
    ctx.update(child.as_dict())
    ctx.update(doctype=doc.doctype, parenttype=doc.doctype, name=doc.name,
        price_list=price_list, rate=0, price_list_rate=0)
    # The upstream helper may auto-create Item Prices when given a rate; defaults never supply one.
    details = get_item_details(ctx, doc=doc.as_dict())
    if details.get("warehouse"):
        _reference("Warehouse", details["warehouse"])
    for key, value in details.items():
        if child.meta.has_field(key):
            child.set(key, value)
    if not values.get("name"):
        doc.append(field, child)
    if doc.meta.has_field("items") and doc.meta.has_field("taxes") and doc.meta.has_field("currency"):
        doc.calculate_taxes_and_totals()
    visible = doc.copy_with_fieldlevel_read_permissions().get(field)
    result = next((r for r in visible if r.name == child.name), visible[-1]) if child.name else visible[-1]
    return {"doc":result.as_dict()}


# Native actions use a fixed registry of upstream mapping entry points.
MAPPINGS = {
    "Material Request": {
        "Purchase Order":("Purchase Order","erpnext.stock.doctype.material_request.material_request.make_purchase_order"),
        "Stock Entry":("Stock Entry","erpnext.stock.doctype.material_request.material_request.make_stock_entry")},
    "Work Order": {
        "Transfer materials":("Stock Entry","erpnext.manufacturing.doctype.work_order.work_order.make_stock_entry"),
        "Record finished goods":("Stock Entry","erpnext.manufacturing.doctype.work_order.work_order.make_stock_entry")},
    "Supplier Quotation": {"Purchase Order":("Purchase Order","erpnext.buying.doctype.supplier_quotation.supplier_quotation.make_purchase_order")},
    "Subcontracting Order": {
        "Send materials to supplier":("Stock Entry","erpnext.controllers.subcontracting_controller.make_rm_stock_entry"),
        "Subcontracting Receipt":("Subcontracting Receipt","erpnext.subcontracting.doctype.subcontracting_order.subcontracting_order.make_subcontracting_receipt")},
    "Subcontracting Receipt": {"Purchase Receipt":("Purchase Receipt","erpnext.subcontracting.doctype.subcontracting_receipt.subcontracting_receipt.make_purchase_receipt")},
    "Purchase Invoice": {"Debit Note":("Purchase Invoice","erpnext.accounts.doctype.purchase_invoice.purchase_invoice.make_debit_note")},
    "Quotation": {
        "Sales Order":("Sales Order","erpnext.selling.doctype.quotation.quotation.make_sales_order"),
        "Sales Invoice":("Sales Invoice","erpnext.selling.doctype.quotation.quotation.make_sales_invoice")},
    "Sales Order": {
        "Delivery Note":("Delivery Note","erpnext.selling.doctype.sales_order.sales_order.make_delivery_note"),
        "Sales Invoice":("Sales Invoice","erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice")},
    "Delivery Note": {
        "Sales Invoice":("Sales Invoice","erpnext.stock.doctype.delivery_note.delivery_note.make_sales_invoice"),
        "Sales Return":("Delivery Note","erpnext.stock.doctype.delivery_note.delivery_note.make_sales_return")},
    "Purchase Order": {
        "Subcontracting Order":("Subcontracting Order","erpnext.buying.doctype.purchase_order.purchase_order.make_subcontracting_order"),
        "Purchase Receipt":("Purchase Receipt","erpnext.buying.doctype.purchase_order.purchase_order.make_purchase_receipt"),
        "Purchase Invoice":("Purchase Invoice","erpnext.buying.doctype.purchase_order.purchase_order.make_purchase_invoice")},
    "Purchase Receipt": {
        "Purchase Invoice":("Purchase Invoice","erpnext.stock.doctype.purchase_receipt.purchase_receipt.make_purchase_invoice"),
        "Purchase Return":("Purchase Receipt","erpnext.stock.doctype.purchase_receipt.purchase_receipt.make_purchase_return")},
    "Sales Invoice": {"Credit Note":("Sales Invoice","erpnext.accounts.doctype.sales_invoice.sales_invoice.make_sales_return")},
}


def _work_order_qty(doc, action):
    if doc.track_semi_finished_goods or doc.status in ("Stopped", "Closed", "Completed"):
        return 0
    if action == "Transfer materials":
        if doc.skip_transfer or doc.transfer_material_against == "Job Card":
            return 0
        return flt(doc.qty) - flt(doc.material_transferred_for_manufacturing)
    available = doc.qty if doc.skip_transfer else doc.material_transferred_for_manufacturing
    return flt(available) - flt(doc.produced_qty)


def _can_map(source, action):
    if source.doctype in ("Sales Order","Purchase Order") and source.status in ("Closed","On Hold"):
        return False
    if source.doctype == "Sales Order" and action == "Delivery Note":
        return (flt(source.per_delivered) < 100 and source.order_type != "Maintenance" and not source.skip_delivery_note
                and (source.has_unit_price_items or any(not r.delivered_by_supplier and flt(r.qty)>flt(r.delivered_qty) for r in source.items)))
    if source.doctype == "Sales Order" and action == "Sales Invoice":
        from erpnext.selling.doctype.sales_order.sales_order import has_potentially_billable_items
        return bool(source.is_subcontracted or has_potentially_billable_items(source.name))
    if source.doctype == "Purchase Order" and action == "Purchase Receipt":
        return any(not r.delivered_by_supplier and flt(r.received_qty) < flt(r.qty) for r in source.items)
    if source.doctype in ("Purchase Order","Purchase Receipt") and action == "Purchase Invoice":
        return source.status != "Closed" and flt(source.per_billed) < 100
    if source.doctype == "Delivery Note" and action == "Sales Invoice":
        return not source.is_return and flt(source.per_returned) != 100 and source.status != "Closed" and flt(source.per_billed) < 100 and not any(r.against_sales_invoice for r in source.items)
    if source.doctype in ("Purchase Receipt","Delivery Note","Sales Invoice","Purchase Invoice") and action in ("Debit Note","Credit Note","Sales Return","Purchase Return"):
        return not source.is_return
    if source.doctype == "Purchase Order" and action == "Subcontracting Order":
        return (source.is_subcontracted and not source.is_old_subcontracting_flow and source.status not in ("Closed","On Hold")
                and any(flt(row.qty) > flt(row.subcontracted_qty) for row in source.items))
    if source.doctype == "Subcontracting Order":
        if source.status in ("Closed","Completed"):
            return False
        if action == "Send materials to supplier":
            return any(flt(row.required_qty) > flt(row.total_supplied_qty) for row in source.supplied_items)
        return any(flt(row.qty) > flt(row.received_qty) for row in source.items)
    if source.doctype == "Subcontracting Receipt":
        return not source.is_return and not frappe.db.exists("Purchase Receipt", {"subcontracting_receipt":source.name,"is_return":0,"docstatus":["<",2]})

    if source.doctype == "Material Request":
        if source.status in ("Stopped", "Cancelled") or flt(source.per_ordered) >= 100:
            return False
        if action == "Purchase Order":
            return source.material_request_type in ("Purchase", "Subcontracting")
        return source.material_request_type in ("Material Transfer", "Material Issue", "Customer Provided")
    if source.doctype == "Work Order":
        return _work_order_qty(source, action) > 0
    return True


def _related_actions(doc):
    if doc.is_new() or doc.meta.issingle:
        return []
    from erp_extensions.knitting.permissions import is_pack
    invoice = doc.doctype in ("Sales Invoice", "Purchase Invoice")
    can_pay = (cint(doc.docstatus) == 1
               and ((invoice and flt(doc.get("outstanding_amount")) != 0)
                    or (doc.doctype in ("Sales Order", "Purchase Order") and doc.status not in ("Closed","On Hold")
                        and flt(doc.per_billed) < 100 + flt(frappe.get_cached_value("Accounts Settings", None, "over_billing_allowance"))))
               and frappe.has_permission("Payment Entry", "create"))
    if is_pack(doc.doctype) or doc.get("knitting_event") or doc.get("knitting_job"):
        return ["Payment Entry"] if invoice and can_pay else []
    from erp_extensions.operational_handoffs import related_actions
    actions = related_actions(doc)
    if frappe.has_permission(doc.doctype, "create"):
        actions.append("Duplicate")
    if cint(doc.docstatus) == 2 and doc.meta.has_field("amended_from") and doc.has_permission("amend"):
        actions.append("Amend")
    if cint(doc.docstatus) == 1:
        actions.extend(action for action, (target, _) in MAPPINGS.get(doc.doctype, {}).items()
            if frappe.has_permission(target, "create") and _can_map(doc, action))
        if can_pay:
            actions.append("Payment Entry")
    return actions


@contextmanager
def _preview_prices():
    # Override only this request's cached settings; shared cache and database stay intact.
    from frappe.model.document import get_document_cache_key
    key = frappe.cache.make_key(get_document_cache_key("Stock Settings", "Stock Settings"))
    present = key in frappe.local.cache
    previous = frappe.local.cache.get(key)
    settings = deepcopy(frappe.get_cached_doc("Stock Settings"))
    settings.auto_insert_price_list_rate_if_missing = 0
    settings.update_existing_price_list_rate = 0
    frappe.local.cache[key] = settings
    try:
        yield
    finally:
        if present:
            frappe.local.cache[key] = previous
        else:
            frappe.local.cache.pop(key, None)


def _origin_document(target, origin):
    if not isinstance(origin, Mapping) or any(not isinstance(origin.get(k),str) for k in ("doctype","name","action","modified")):
        frappe.throw("A valid source document is required.")
    source = _reference(origin["doctype"], origin["name"])
    _check_version(source, origin["modified"])
    action = origin["action"]
    if action not in _related_actions(source):
        frappe.throw("This action is not available for this document.", frappe.PermissionError)
    if origin.get("quantity") is not None and (source.doctype != "Work Order" or action not in ("Transfer materials", "Record finished goods")):
        frappe.throw("This action does not use a production quantity.")
    expected = source.doctype if action in ("Duplicate", "Amend") else "Payment Entry" if action == "Payment Entry" else MAPPINGS[source.doctype][action][0]
    if target != expected:
        frappe.throw("The new record does not match its source action.", frappe.PermissionError)
    _meta(expected, "create")
    if action in ("Duplicate", "Amend"):
        expected = source.doctype
        doc = frappe.copy_doc(source, ignore_no_copy=action == "Amend")
        if action == "Amend":
            doc.amended_from = source.name
    elif action == "Payment Entry":
        expected = "Payment Entry"
        from erpnext.accounts.doctype.payment_entry.payment_entry import get_payment_entry
        with _preview_prices():
            doc = get_payment_entry(source.doctype, source.name)
    else:
        expected, path = MAPPINGS[source.doctype][action]
        if source.doctype == "Quotation" and source.quotation_to != "Customer":
            from erpnext.selling.doctype.quotation.quotation import get_existing_customer_name
            customer = get_existing_customer_name(source.quotation_to, source.party_name)
            if not customer:
                frappe.throw("Create and save a customer for this lead or prospect before creating the next document.")
            _reference("Customer", customer)
        with _preview_prices():
            if source.doctype == "Work Order":
                purpose = "Material Transfer for Manufacture" if action == "Transfer materials" else "Manufacture"
                available = _work_order_qty(source, action)
                quantity = available if origin.get("quantity") is None else flt(origin["quantity"])
                if not math.isfinite(quantity) or not 0 < quantity <= available:
                    frappe.throw(f"Enter a production quantity greater than zero and up to {available:g}.")
                doc = frappe.get_doc(frappe.get_attr(path)(source.name, purpose, quantity))
            else:
                doc = frappe.get_attr(path)(source.name)
                if isinstance(doc, Mapping):
                    doc = frappe.get_doc(doc)
    if target != expected or doc.doctype != expected:
        frappe.throw("The new record does not match its source action.", frappe.PermissionError)
    # Mapping helpers use privileged flags internally; none may cross into a user save.
    doc.flags = frappe._dict()
    for child in doc.get_all_children():
        child.flags = frappe._dict()
    doc.name = None
    doc.docstatus = 0
    doc.set("__islocal", 1)
    doc.flags.name_set = False
    doc.check_permission("create")
    # Stable temporary row identities preserve hidden source references during native edits.
    for index, child in enumerate(doc.get_all_children()):
        child.name = f"native-origin-row-{index}"
        child.set("__islocal", 1)
    doc.flags.native_origin = {key:origin[key] for key in ("doctype","name","action","modified")}
    if origin.get("quantity") is not None:
        doc.flags.native_origin["quantity"] = quantity
    return doc


@frappe.whitelist(methods=["POST"])
def new_from(doctype, name, action, modified, quantity=None):
    source = _reference(doctype, name)
    target = doctype if action in ("Duplicate","Amend") else "Payment Entry" if action == "Payment Entry" else MAPPINGS.get(doctype, {}).get(action, (None,None))[0]
    if not target:
        frappe.throw("This action is not available for this document.")
    _meta(target, "create")
    return _result(_origin_document(target, {"doctype":source.doctype,"name":str(source.name),
        "action":action,"modified":modified,"quantity":quantity}))


@frappe.whitelist(allow_guest=True)
def session_status():
    return {"signed_in":frappe.session.user != "Guest"}
