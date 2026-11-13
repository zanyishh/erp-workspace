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
FINANCIAL_EVENTS = ("invoice", "deliver", "revise_job", "payment", "subcontract_bill", "estimate", "cost")


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


def profile(company):
    if not frappe.db.exists("DocType", "Workspace Industry Setup"):
        return None
    return frappe.db.get_value("Workspace Industry Setup", {"company": company}, ["name", "state", "settings", "revision"], as_dict=True)


def company_allowed(company, user=None):
    return company in {c.name for c in companies(user)}


def require(company, capability, history=False):
    if not company_allowed(company) or capability not in capabilities():
        frappe.throw("This account cannot perform that action in this business.", frappe.PermissionError)
    setup = profile(company)
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
        if doc.doctype in ("Stock Entry", "Sales Invoice", "Delivery Note"):
            current = doc.get("knitting_event") or doc.get("knitting_job")
            previous = frappe.db.get_value(doc.doctype, doc.name, "knitting_event") if doc.name and not doc.is_new() else None
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
    if ptype not in ("read", "print", "export", "report", "select"):
        return bool(frappe.flags.get("knitting_service_write"))
    if doc.doctype == "Knitting Event" and doc.kind in FINANCIAL_EVENTS:
        return "financial_read" in capabilities(user)
    return True


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
    return condition
