"""Native client contract. GPL-3.0. Business mutations use Frappe controllers."""
from __future__ import annotations

import math
import json
from copy import deepcopy
from functools import lru_cache
from contextlib import contextmanager
from pathlib import Path
from collections.abc import Mapping

import frappe
from frappe.permissions import get_doc_permissions
from frappe.utils import cint, get_datetime

VERSION = 1
LAYOUT = {"Section Break", "Column Break", "Tab Break", "Heading", "HTML", "Button", "Image"}
NUMERIC = {"Int", "Float", "Currency", "Percent", "Duration"}


def _signed_in():
    if frappe.session.user == "Guest":
        frappe.throw("Sign in to ERP Workspace first.", frappe.PermissionError)


def _meta(doctype, permission="read"):
    _signed_in()
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
        "single": bool(meta.issingle), "submittable": bool(meta.is_submittable),
        "title_field": meta.title_field, "autoname": meta.autoname, "preparable": bool(meta.has_field("items") and meta.has_field("taxes") and meta.has_field("currency")),
        "party_defaults":meta.name in SELLING | BUYING,
        "item_defaults":meta.name in ITEM_TRANSACTIONS}


@frappe.whitelist()
def catalog(company=None):
    _signed_in()
    from erp_extensions.knitting.permissions import visible_type, is_pack
    types = []
    for dt in frappe.get_all("DocType", fields=["name", "module", "issingle", "is_submittable", "is_tree"],
        filters={"istable": 0}, order_by="module, name"):
        if frappe.has_permission(dt.name, "read") and visible_type(dt.name, company):
            types.append({**dt, "create": bool(not is_pack(dt.name) and frappe.has_permission(dt.name, "create"))})
    reports = []
    for row in frappe.get_all("Report", fields=["name", "module", "ref_doctype", "report_type"],
        filters={"disabled": 0}, order_by="module, name"):
        if frappe.has_permission(row.ref_doctype, "report") and frappe.get_doc("Report", row.name).is_permitted():
            reports.append(row)
    return {"version": VERSION, "site": frappe.local.site, "user": frappe.session.user, "types": types, "reports": reports}


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
    from erp_extensions.knitting.permissions import is_pack
    guarded = is_pack(doc.doctype) or bool(doc.get("knitting_event") or doc.get("knitting_job"))
    if guarded:
        permissions.update({p: False for p in ("write", "create", "submit", "cancel", "amend")})
    workflow = get_workflow_name(doc.doctype)
    transitions = get_transitions(doc) if workflow and not doc.is_new() and not guarded else []
    data = _native_identities(doc.copy_with_fieldlevel_read_permissions().as_dict(), doc.meta)
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
                updated.append({**row.as_dict(), "idx": len(updated) + 1})
            doc.set(key, updated)
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
    _apply(doc, values)
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
def save(document, action="Save"):
    doc = _editable(document)
    if action == "Save":
        doc.save()
    elif action == "Submit":
        doc.submit()
    elif action == "Cancel":
        doc.cancel()
    else:
        frappe.throw("Unknown document action.")
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
    fields = ["name"] + (["is_group"] if meta.has_field("is_group") else [])
    readable = _fieldnames(meta, "read") - {f.fieldname for f in meta.get_masked_fields()}
    if meta.title_field and meta.title_field in readable and meta.title_field != "name":
        fields.append(meta.title_field)
    limit = min(100, max(1, cint(limit)))
    rows = frappe.get_list(doctype, fields=fields, filters=filters, or_filters=shared_company,
        offset=max(0, cint(start)), limit=limit + 1, order_by="name asc")
    df = meta.get_field(parent_field)
    return {"nodes": [{"name":str(row.name), "title":row.get(meta.title_field) or str(row.name),
        "expandable":bool(row.is_group) if meta.has_field("is_group") else True} for row in rows[:limit]], "has_more":len(rows) > limit,
        "can_create":bool(frappe.has_permission(doctype, "create") and not df.read_only and not df.hidden
            and parent_field in _fieldnames(meta, "create"))}


@frappe.whitelist()
def search_link(doctype, query="", parent=None, field=None):
    _signed_in()
    from frappe.desk.search import search_link as search
    return search(doctype=doctype, txt=query, page_length=30, reference_doctype=parent)


@frappe.whitelist(methods=["POST"])
def transition(doctype, name, action, modified=None):
    _meta(doctype)
    from frappe.model.workflow import apply_workflow
    doc = frappe.get_doc(doctype, name, for_update=True)
    doc.check_permission("read")
    _check_version(doc, modified)
    result = apply_workflow(doc.as_dict(), action)
    return _result(frappe.get_doc(result))


def _report(name):
    _signed_in()
    from frappe.desk.query_report import get_report_doc
    return get_report_doc(name)


def _report_default(value, company=None):
    if not isinstance(value, dict) or "native_default" not in value:
        return value
    from frappe.utils import add_days, add_months, get_first_day, get_last_day, today
    kind = value["native_default"]
    if kind == "user":
        return frappe.defaults.get_user_default(value["key"])
    if kind == "fiscal_year":
        from erpnext.accounts.utils import get_fiscal_year
        return get_fiscal_year(today(), company=company)[0]
    if kind == "today":
        return today()
    if kind == "date_offset":
        fn = add_months if value["unit"] == "months" else add_days
        return str(fn(today(), value["value"]))
    if kind == "month_start":
        return str(get_first_day(today()))
    if kind == "month_end":
        return str(get_last_day(today()))
    if kind in ("year_start", "year_end"):
        date = get_datetime(today())
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
        if field.get("fieldtype") == "Select" and not field.get("options") and "currency" in key:
            field["options"] = "\n" + "\n".join(frappe.get_all("Currency", filters={"enabled":1}, pluck="name", order_by="name"))
    return {**definition, "name":name, "doctype":name,"children":{},"defaults":defaults,
        "reference":report.ref_doctype,"type":report.report_type,
        "can_export":bool(frappe.permissions.can_export(report.ref_doctype))}


def _builder_report(report, filters):
    config = frappe.parse_json(report.json) if report.json else {}
    meta = frappe.get_meta(report.ref_doctype)
    if config.get("group_by") or config.get("add_totals_row") or config.get("aggregates"):
        frappe.throw("This report’s grouping is not available in the app yet.")
    raw_columns = config.get("columns") or config.get("fields")
    if not raw_columns:
        permitted = _fieldnames(meta, "read")
        raw_columns = [["name",meta.name]] + [[df.fieldname,meta.name] for df in meta.fields if df.in_list_view and df.fieldname in permitted and df.fieldtype not in ("Table","Table MultiSelect")]
    fields = []
    columns = []
    for col in raw_columns:
        fieldname, doctype = col if isinstance(col,list) else (col,meta.name)
        df = frappe.get_meta(doctype).get_field(fieldname)
        fields.append(fieldname if doctype == meta.name else f"{doctype}.{fieldname}")
        columns.append({"fieldname":fieldname,"label":df.label if df else fieldname.replace("_"," ").title(),
            "fieldtype":df.fieldtype if df else "Data","options":df.options if df else None})
    conditions = list(config.get("filters") or [])
    if filters.get("company") and meta.has_field("company"):
        conditions.append(["company","=",filters["company"]])
    if filters.get("search"):
        conditions.append(["name","like",f"%{filters['search']}%"])
    rows = frappe.get_list(meta.name, fields=fields, filters=conditions, limit=10000,
        order_by=config.get("order_by") or "modified desc")
    return {"columns":columns,"result":rows,"truncated":len(rows)==10000}


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
    return run(name, filters=filters, js_filters=definition["fields"])


@frappe.whitelist(methods=["POST"])
def queue_report(name, filters=None):
    _report(name)
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
    comments = get_comments(doctype, name, ["Comment", "Workflow", "Info", "Edit", "Attachment", "Attachment Removed", "Assigned", "Assignment Completed"])
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
    from frappe.share import validate_user_access
    from frappe.desk.form.assign_to import add
    validate_user_access(user, "Assigned To")
    add({"doctype":doctype,"name":name,"assign_to":[user],"description":description})
    return {"assigned":user}


@frappe.whitelist(methods=["POST"])
def unassign(doctype, name, user):
    _reference(doctype, name)
    from frappe.desk.form.assign_to import remove
    remove(doctype, name, user)
    return {"removed":user}


@frappe.whitelist(methods=["POST"])
def upload_attachment(doctype, name, filename, content):
    _reference(doctype, name, "write")
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
    file = frappe.get_doc({"doctype":"File","file_name":filename,"content":raw,"is_private":1,
        "attached_to_doctype":doctype,"attached_to_name":name}).insert()
    return {"name":file.name,"file_name":file.file_name,"file_size":file.file_size,"is_private":file.is_private}


@frappe.whitelist()
def attachment(doctype, name, file):
    doc = _reference(doctype, name)
    file = _attachment(doc, file)
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
        "Purchase Receipt":("Purchase Receipt","erpnext.buying.doctype.purchase_order.purchase_order.make_purchase_receipt"),
        "Purchase Invoice":("Purchase Invoice","erpnext.buying.doctype.purchase_order.purchase_order.make_purchase_invoice")},
    "Purchase Receipt": {
        "Purchase Invoice":("Purchase Invoice","erpnext.stock.doctype.purchase_receipt.purchase_receipt.make_purchase_invoice"),
        "Purchase Return":("Purchase Receipt","erpnext.stock.doctype.purchase_receipt.purchase_receipt.make_purchase_return")},
    "Sales Invoice": {"Credit Note":("Sales Invoice","erpnext.accounts.doctype.sales_invoice.sales_invoice.make_sales_return")},
}


def _related_actions(doc):
    if doc.is_new() or doc.meta.issingle:
        return []
    from erp_extensions.knitting.permissions import is_pack
    if is_pack(doc.doctype) or doc.get("knitting_event") or doc.get("knitting_job"):
        return ["Payment Entry"] if doc.doctype in ("Sales Invoice", "Purchase Invoice") and cint(doc.docstatus) == 1 and frappe.has_permission("Payment Entry", "create") else []
    actions = []
    if frappe.has_permission(doc.doctype, "create"):
        actions.append("Duplicate")
    if cint(doc.docstatus) == 2 and doc.meta.has_field("amended_from") and doc.has_permission("amend"):
        actions.append("Amend")
    if cint(doc.docstatus) == 1:
        actions.extend(action for action, (target, _) in MAPPINGS.get(doc.doctype, {}).items()
            if frappe.has_permission(target, "create"))
        if doc.doctype in ("Sales Invoice", "Purchase Invoice", "Sales Order", "Purchase Order") and frappe.has_permission("Payment Entry", "create"):
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
            doc = frappe.get_attr(path)(source.name)
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
    return doc


@frappe.whitelist(methods=["POST"])
def new_from(doctype, name, action, modified):
    source = _reference(doctype, name)
    target = doctype if action in ("Duplicate","Amend") else "Payment Entry" if action == "Payment Entry" else MAPPINGS.get(doctype, {}).get(action, (None,None))[0]
    if not target:
        frappe.throw("This action is not available for this document.")
    _meta(target, "create")
    return _result(_origin_document(target, {"doctype":source.doctype,"name":str(source.name),
        "action":action,"modified":modified}))


@frappe.whitelist(allow_guest=True)
def session_status():
    return {"signed_in":frappe.session.user != "Guest"}
