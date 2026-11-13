"""Idempotent schema installation for the independently implemented industry pack."""
import frappe

ROLES = ("Knitting Manager", "Knitting Operator", "Knitting Checker", "Knitting Planner", "Knitting Accountant")


def field(name, kind="Data", options=None, **kw):
    return {"fieldname": name, "label": name.replace("_", " ").title(), "fieldtype": kind,
            **({"options": options} if options else {}), **kw}


BASE = [field("company", "Link", "Company", reqd=1, in_list_view=1)]
SCHEMAS = {
    "Workspace Industry Setup": [field("company", "Link", "Company", reqd=1, unique=1),
        field("state", "Select", "Setup\nActive\nClosing\nInactive", reqd=1), field("settings", "JSON"), field("revision", "Int")],
    "Knitting Job": [*BASE, field("customer", "Link", "Customer", reqd=1, in_list_view=1),
        field("kind", "Select", "Order\nSample"), field("material_mode", "Select", "Customer\nOwned"),
        field("fabric_owner", "Link", "Customer"), field("due_date", "Date"),
        field("status", "Select", "Running\nCompleted\nCancelled", in_list_view=1),
        field("programme", "JSON"), field("target_kg"), field("revision", "Int"),
        field("service_item", "Link", "Item", permlevel=1), field("rate", "Currency", permlevel=1),
        field("quotation", "Link", "Quotation"), field("notes", "Small Text")],
    "Knitting Machine": [*BASE, field("title", reqd=1, in_list_view=1), field("workstation", "Link", "Workstation"),
        field("dia"), field("gauge"), field("knit_type"), field("capacity_kg"), field("enabled", "Check", default=1)],
    "Knitting Material Lot": [*BASE, field("item", "Link", "Item", reqd=1), field("party", "Link", "Customer"),
        field("material_owner", "Select", "Customer\nOwned"), field("warehouse", "Link", "Warehouse"),
        field("source_lot"), field("specification", "JSON")],
    "Knitting Event": [*BASE, field("job", "Link", "Knitting Job"), field("kind", in_list_view=1),
        field("request_key", unique=1), field("payload_hash"), field("actor", "Link", "User"),
        field("occurred_at", "Datetime"), field("payload", "JSON"), field("result", "JSON"),
        field("reverses", "Link", "Knitting Event"), field("cancelled", "Check"), field("voucher_type"), field("voucher_name")],
    "Knitting Ledger Entry": [*BASE, field("job", "Link", "Knitting Job"), field("lot", "Link", "Knitting Material Lot"),
        field("event", "Link", "Knitting Event", reqd=1), field("material_owner", "Select", "Customer\nOwned"),
        field("party", "Link", "Customer"), field("custodian"), field("warehouse", "Link", "Warehouse"),
        field("quantity_kg", reqd=1), field("units"), field("voucher_type"), field("voucher_name")],
    "Knitting Roll": [*BASE, field("job", "Link", "Knitting Job", reqd=1), field("programme_line"),
        field("job_revision", "Int"), field("weight_kg", reqd=1), field("fabric_item", "Link", "Item"),
        field("warehouse", "Link", "Warehouse"), field("machine", "Link", "Knitting Machine"),
        field("operator", "Link", "User"), field("shift"), field("produced_at", "Datetime"),
        field("state", "Select", "Awaiting QC\nReleased\nOn Hold\nRework\nRejected\nDelivered\nSplit\nCancelled", in_list_view=1),
        field("production", "Link", "Knitting Event"), field("delivery", "Link", "Knitting Event"),
        field("parent_roll", "Link", "Knitting Roll"), field("specification", "JSON")],
    "Knitting QC": [*BASE, field("roll", "Link", "Knitting Roll", reqd=1), field("job", "Link", "Knitting Job"),
        field("checker", "Link", "User"), field("decision", "Select", "Released\nOn Hold\nRework\nRejected"),
        field("defects", "JSON"), field("remarks", "Small Text"), field("event", "Link", "Knitting Event")],
    "Knitting Plan": [*BASE, field("job", "Link", "Knitting Job", reqd=1), field("machine", "Link", "Knitting Machine", reqd=1),
        field("starts_at", "Datetime", reqd=1), field("ends_at", "Datetime", reqd=1), field("quantity_kg", reqd=1),
        field("state", "Select", "Planned\nStarted\nCompleted\nCancelled"), field("event", "Link", "Knitting Event")],
    "Knitting Subcontract": [*BASE, field("job", "Link", "Knitting Job", reqd=1), field("supplier", "Link", "Supplier", reqd=1),
        field("target_kg"), field("status", "Select", "Open\nCompleted\nCancelled"), field("rate", "Currency", permlevel=1)],
    "Knitting Component": [*BASE, field("machine", "Link", "Knitting Machine"), field("component_type", "Select", "Needle\nSinker\nCylinder\nDial"),
        field("item", "Link", "Item"), field("boundary_kg"), field("run_kg"), field("installed_at", "Datetime")],
    "Knitting Holiday": [*BASE, field("machine", "Link", "Knitting Machine"), field("date", "Date", reqd=1), field("description")],
}


def install():
    if frappe.session.user != "Administrator" and "System Manager" not in frappe.get_roles():
        frappe.throw("Only a system manager can install the industry schema.", frappe.PermissionError)
    from frappe.permissions import add_permission, update_permission_property
    for role in ROLES:
        if not frappe.db.exists("Role", role):
            frappe.get_doc({"doctype": "Role", "role_name": role}).insert()
        for target in ("Company", "Warehouse", "Item", "Customer", "Supplier", "Workstation"):
            if not frappe.db.exists("Custom DocPerm", {"parent": target, "role": role}):
                add_permission(target, role)
                update_permission_property(target, role, 0, "read", 1)
    for name, fields in SCHEMAS.items():
        if frappe.db.exists("DocType", name):
            continue
        permissions = [{"role": role, "read": 1, "write": 1, "create": 1, "report": 1, "print": 1, "export": 1}
                       for role in ("System Manager", *ROLES)]
        if any(f.get("permlevel") == 1 for f in fields):
            permissions += [{"role": role, "permlevel": 1, "read": 1, "write": 1, "create": 1}
                            for role in ("System Manager", "Knitting Manager", "Knitting Accountant")]
        frappe.get_doc({"doctype": "DocType", "name": name, "module": "Custom", "custom": 1,
                        "autoname": "hash", "track_changes": 1, "fields": fields, "permissions": permissions}).insert()
    frappe.clear_cache()
    # Frappe's global cache reset leaves the request's expanded document hooks intact.
    frappe.local.doc_events_hooks = None
