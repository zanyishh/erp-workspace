"""Pack permissions apply to native commands and generic Frappe routes alike."""
from contextlib import contextmanager

import frappe

CAPABILITIES = {
    "Knitting Manager": {"overview", "jobs", "new_job", "lifecycle", "materials", "production", "quality", "planning", "delivery", "billing", "financial_read", "factory", "reports", "configure"},
    "Knitting Operator": {"overview", "jobs", "production", "materials"},
    "Knitting Checker": {"overview", "jobs", "quality"},
    "Knitting Planner": {"overview", "jobs", "planning", "factory", "reports"},
    "Knitting Accountant": {"overview", "jobs", "delivery", "billing", "financial_read", "reports"},
}
FINANCIAL_EVENTS = ("invoice", "credit_invoice", "bill_yarn", "create_yarn_order", "set_lot_charge", "deliver", "revise_job", "payment", "subcontract_bill", "estimate", "create_estimate", "cost")


def companies(user=None):
    user = user or frappe.session.user
    if user == "Guest":
        return []
    return frappe.get_list("Company", fields=["name", "abbr", "default_currency"],
                           order_by="name", limit=1000, user=user)


def capabilities(user=None):
    user = user or frappe.session.user
    roles = set(frappe.get_roles(user))
    if user == "Administrator" or "System Manager" in roles:
        return set(CAPABILITIES["Knitting Manager"])
    return set().union(*(values for role, values in CAPABILITIES.items() if role in roles))


def profile(company, *, current=False):
    if not frappe.db.exists("DocType", "Workspace Industry Setup"):
        return None
    return frappe.db.get_value("Workspace Industry Setup", {"company": company}, ["name", "state", "settings", "revision"], as_dict=True, for_update=current)


def company_allowed(company, user=None):
    return company in {c.name for c in companies(user)}


def require(company, capability, history=False, *, current=False):
    if not company_allowed(company) or capability not in capabilities():
        frappe.throw("This account cannot perform that action in this business.", frappe.PermissionError)
    setup = profile(company, current=current)
    if not setup or not history and setup.state not in ("Active", "Closing"):
        frappe.throw("Knitting is not active for this business.", frappe.PermissionError)
    if setup.state == "Closing" and capability == "new_job":
        frappe.throw("This business is closing existing knitting work; new jobs are disabled.", frappe.PermissionError)
    return setup


@contextmanager
def service_write():
    previous = frappe.flags.get("knitting_service_write")
    frappe.flags.knitting_service_write = True
    try:
        yield
    finally:
        frappe.flags.knitting_service_write = previous


def is_pack(doctype):
    return doctype == "Workspace Industry Setup" or doctype.startswith("Knitting ")


def visible_type(doctype, company=None):
    if not is_pack(doctype):
        return True
    caps = capabilities()
    if doctype == "Workspace Industry Setup":
        return "configure" in caps
    if "jobs" not in caps:
        return False
    for item in companies():
        if company and item.name != company:
            continue
        setup = profile(item.name)
        if setup and (setup.state in ("Active", "Closing") or
                      frappe.db.exists("Knitting Job", {"company": item.name})):
            return True
    return False


def guard_write(doc, method=None):
    if not is_pack(doc.doctype):
        if doc.doctype in ("Stock Entry", "Sales Invoice", "Delivery Note", "Purchase Invoice", "Purchase Order", "Purchase Receipt", "Quotation"):
            current = doc.get("knitting_event") or doc.get("knitting_job")
            previous = frappe.db.get_value(doc.doctype, doc.name, "knitting_event") if doc.meta.has_field("knitting_event") and doc.name and not doc.is_new() else None
            if (current or previous) and not frappe.flags.get("knitting_service_write"):
                frappe.throw("Review this source-linked document through its knitting workflow.", frappe.PermissionError)
        return
    if not frappe.flags.get("knitting_service_write"):
        frappe.throw("Use the reviewed knitting workflow to change this record.", frappe.PermissionError)
    if not company_allowed(doc.company):
        frappe.throw("The record belongs to another business.", frappe.PermissionError)


def has_permission(doc, ptype, user=None, **kwargs):
    if not is_pack(doc.doctype):
        return True
    if not company_allowed(doc.company, user):
        return False
    if doc.doctype == "Workspace Industry Setup":
        return "configure" in capabilities(user)
    if not profile(doc.company) or "jobs" not in capabilities(user):
        return False
    if not source_scope(doc, user):
        return False
    if ptype not in ("read", "print", "export", "report", "select"):
        return bool(frappe.flags.get("knitting_service_write"))
    if doc.doctype == "Knitting Event" and doc.kind in FINANCIAL_EVENTS:
        return "financial_read" in capabilities(user)
    return True


def link_visible(doctype, name, user=None):
    if not name or (user or frappe.session.user) == "Administrator":
        return True
    return bool(frappe.get_list(doctype, filters={"name": name}, pluck="name", limit=1, user=user or frappe.session.user))


def source_scope(doc, user=None):
    """Apply linked record restrictions even when private JSON is projected by a service."""
    if (user or frappe.session.user) == "Administrator":
        return True
    for field, doctype in (("warehouse", "Warehouse"), ("customer", "Customer"), ("party", "Customer"),
                           ("job", "Knitting Job"), ("target_job", "Knitting Job"), ("lot", "Knitting Material Lot"),
                           ("roll", "Knitting Roll")):
        if doc.get(field) and not link_visible(doctype, doc.get(field), user):
            return False
    if doc.doctype == 'Knitting Event':
        for raw in (doc.payload, doc.result):
            value = frappe.parse_json(raw or '{}')
            def allowed(value):
                if isinstance(value, list):
                    return all(allowed(v) for v in value)
                if not isinstance(value, dict):
                    return True
                for key, target in {'customer':'Customer', 'party':'Customer', 'supplier':'Supplier',
                    'warehouse':'Warehouse', 'target_warehouse':'Warehouse', 'lot':'Knitting Material Lot',
                    'source_lot':'Knitting Material Lot', 'roll':'Knitting Roll', 'parent_roll':'Knitting Roll',
                    'job':'Knitting Job', 'target_job':'Knitting Job', 'invoice':'Sales Invoice',
                    'quotation':'Quotation', 'purchase_order':'Purchase Order'}.items():
                    name = value.get(key)
                    if name and frappe.db.exists(target, name) and not link_visible(target, name, user):
                        return False
                for name in value.get('rolls', []):
                    if not link_visible('Knitting Roll', name, user):
                        return False
                return all(allowed(v) for v in value.values() if isinstance(v, (dict, list)))
            if not allowed(value):
                return False
        if doc.voucher_type and doc.voucher_name and not link_visible(doc.voucher_type, doc.voucher_name, user):
            return False
    return True


def require_aggregate_scope(company, job=None):
    """A reconciliation is either complete and authorised, or unavailable.

    Silently excluding a restricted godown would turn a correct ledger into
    an incorrect available balance. Internal authoritative reads remain full.
    """
    if frappe.session.user == "Administrator":
        return
    for doctype in ("Knitting Job", "Knitting Ledger Entry", "Knitting Roll", "Knitting Subcontract"):
        filters = {"company": company, **({"name" if doctype == "Knitting Job" else "job": job} if job else {})}
        for row in frappe.get_all(doctype, filters=filters, fields=["name"]):
            doc = frappe.get_doc(doctype, row.name)
            if not source_scope(doc) or not link_visible(doctype, row.name):
                frappe.throw("This reconciliation includes source records outside your access. Ask a manager with full source access.", frappe.PermissionError)


def require_event_scope(event):
    event.check_permission("read")
    if not source_scope(event):
        frappe.throw('This action includes source records outside your access.', frappe.PermissionError)
    if event.job:
        require_aggregate_scope(event.company, event.job)
    if event.target_job:
        require_aggregate_scope(event.company, event.target_job)
    for row in frappe.get_all("Knitting Ledger Entry", filters={"event": event.name}, fields=["name"]):
        frappe.get_doc("Knitting Ledger Entry", row.name).check_permission("read")


def query_conditions(user=None, doctype=None):
    if not doctype or not is_pack(doctype):
        return ""
    caps = capabilities(user)
    if not caps or doctype == "Workspace Industry Setup" and "configure" not in caps:
        return "1=0"
    allowed = [c.name for c in companies(user) if profile(c.name)]
    if not allowed:
        return "1=0"
    condition = f"`tab{doctype}`.`company` in ({','.join(frappe.db.escape(c) for c in allowed)})"
    if doctype == "Knitting Event" and "financial_read" not in caps:
        condition += " and `kind` not in (" + ",".join(frappe.db.escape(k) for k in FINANCIAL_EVENTS) + ")"
    for field, target in (("warehouse", "Warehouse"), ("customer", "Customer"), ("party", "Customer"),
                           ("job", "Knitting Job"), ("target_job", "Knitting Job"), ("lot", "Knitting Material Lot"), ("roll", "Knitting Roll")):
        if frappe.get_meta(doctype).has_field(field):
            names = frappe.get_list(target, pluck="name", limit_page_length=0, user=user or frappe.session.user)
            values = ",".join(frappe.db.escape(n) for n in names) or "NULL"
            condition += f" and (coalesce(`tab{doctype}`.`{field}`, '')='' or `tab{doctype}`.`{field}` in ({values}))"
    if doctype == 'Knitting Event' and (user or frappe.session.user) != 'Administrator':
        # JSON sources are not covered by Frappe's Link-field User Permission
        # joins. Generic Desk/API lists must enforce the same source checks.
        filters = {"company": ["in", allowed]}
        if "financial_read" not in caps:
            filters["kind"] = ["not in", FINANCIAL_EVENTS]
        names = [r.name for r in frappe.get_all('Knitting Event', filters=filters, fields=['name'])
                 if source_scope(frappe.get_doc('Knitting Event', r.name), user)]
        condition += f' and `tab{doctype}`.`name` in (' + (','.join(frappe.db.escape(n) for n in names) or 'NULL') + ')'
    return condition
