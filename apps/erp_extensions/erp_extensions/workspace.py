"""Company-enabled industry context; no username-derived or client-trusted access."""
from collections.abc import Mapping

import frappe

from erp_extensions.knitting import permissions


@frappe.whitelist()
def context(company=None):
    available = permissions.companies()
    if frappe.session.user == "Guest":
        frappe.throw("Sign in first.", frappe.PermissionError)
    if company and company not in {c.name for c in available}:
        frappe.throw("This account cannot open that business.", frappe.PermissionError)
    selected = company or (available[0].name if available else None)
    setup = permissions.profile(selected) if selected else None
    caps = permissions.capabilities() if setup and setup.state in ("Active", "Closing") else set()
    return {"version": 1, "companies": available, "company": selected,
            "setup_state": setup.state if setup else "General ERP", "revision": setup.revision if setup else 0,
            "knitting_enabled": bool(caps), "capabilities": sorted(caps),
            "can_configure": "configure" in permissions.capabilities()}


@frappe.whitelist(methods=["POST"])
def configure(company, settings):
    if "configure" not in permissions.capabilities() or not permissions.company_allowed(company):
        frappe.throw("This account cannot configure this business.", frappe.PermissionError)
    settings = frappe.parse_json(settings) if isinstance(settings, str) else settings
    if not isinstance(settings, Mapping) or settings.get("state") not in ("Setup", "Active", "Closing", "Inactive"):
        frappe.throw("Choose a valid industry setup state.")
    from erp_extensions.knitting.install import install
    if not frappe.db.exists("DocType", "Workspace Industry Setup"):
        install()
    found = permissions.profile(company)
    doc = frappe.get_doc("Workspace Industry Setup", found.name) if found else frappe.new_doc("Workspace Industry Setup")
    if found:
        # Serialise setup changes with in-flight domain operations using the same lock.
        doc = frappe.get_doc("Workspace Industry Setup", found.name, for_update=True)
    if settings["state"] == "Inactive" and frappe.db.exists("Knitting Job", {"company": company, "status": "Running"}):
        frappe.throw("Settle the open knitting jobs before deactivating the pack.")
    previous = frappe.parse_json(doc.settings or "{}")
    allowed = {"shifts", "warehouse", "service_item", "fabric_item", "cost_center", "expense_account", "income_account",
               "allow_production_excess_pct", "lycra_charge", "service_rate", "number_prefix", "component_defaults", "rate_lookup"}
    unknown = set(settings) - allowed - {"state", "revision"}
    if unknown:
        frappe.throw("Unknown industry setting: " + ", ".join(sorted(unknown)))
    if settings.get("rate_lookup", "Fabric") not in ("Fabric", "FabricCountGauge") or settings.get("lycra_charge", "Included") not in ("Included", "Separate"):
        frappe.throw("Choose valid pricing and lycra charge policies.")
    if "number_prefix" in settings:
        import re
        if not re.fullmatch(r"[A-Z0-9-]{1,16}", settings["number_prefix"]):
            frappe.throw("Use one to 16 uppercase letters, numbers or hyphens for the document prefix.")
    doc.company, doc.state = company, settings["state"]
    doc.settings = frappe.as_json({**previous, **{k: v for k, v in settings.items() if k in allowed}})
    doc.revision = (doc.revision or 0) + 1
    with permissions.service_write():
        doc.save()
    return context(company)
