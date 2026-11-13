"""Idempotent schema installation for the independently implemented industry pack."""
import frappe

ROLES = ("Knitting Manager", "Knitting Operator", "Knitting Checker", "Knitting Planner", "Knitting Accountant")


def field(name, kind="Data", options=None, **kw):
    return {"fieldname": name, "label": name.replace("_", " ").title(), "fieldtype": kind,
            **({"options": options} if options else {}), **kw}


BASE = [field("company", "Link", "Company", reqd=1, in_list_view=1)]
SCHEMAS = {
    "Knitting Master": [*BASE, field("category", reqd=1), field("title", reqd=1, in_list_view=1), field("enabled", "Check", default=1), field("specification", "JSON")],
    "Workspace Industry Setup": [field("company", "Link", "Company", reqd=1, unique=1),
        field("state", "Select", "Setup\nActive\nClosing\nInactive", reqd=1), field("settings", "JSON"), field("revision", "Int")],
    "Knitting Job": [*BASE, field("customer", "Link", "Customer", reqd=1, in_list_view=1),
        field("kind", "Select", "Order\nSample"), field("material_mode", "Select", "Customer\nOwned"),
        field("fabric_owner", "Link", "Customer"), field("due_date", "Date"),
        field("status", "Select", "Running\nCompleted\nCancelled", in_list_view=1),
        field("programme", "JSON"), field("target_kg"), field("revision", "Int"),
        field("charge_policy", "Select", "Included\nSeparate", permlevel=1), field("service_item", "Link", "Item", permlevel=1), field("rate", "Currency", permlevel=1), field("pricing", "JSON", permlevel=1),
        field("quotation", "Link", "Quotation", unique=1), field("notes", "Small Text")],
    "Knitting Machine": [*BASE, field("title", reqd=1, in_list_view=1), field("workstation", "Link", "Workstation"),
        field("dia"), field("gauge"), field("knit_type"), field("capacity_kg"), field("shifts", "JSON"), field("enabled", "Check", default=1)],
    "Knitting Material Lot": [*BASE, field("item", "Link", "Item", reqd=1), field("party", "Link", "Customer"),
        field("material_owner", "Select", "Customer\nOwned"), field("warehouse", "Link", "Warehouse"),
        field("source_lot"), field("specification", "JSON"), field("charge_item", "Link", "Item", permlevel=1),
        field("charge_rate", "Currency", permlevel=1)],
    "Knitting Event": [*BASE, field("job", "Link", "Knitting Job"), field("target_job", "Link", "Knitting Job"), field("kind", in_list_view=1),
        field("request_key", unique=1), field("payload_hash"), field("actor", "Link", "User"),
        field("occurred_at", "Datetime"), field("payload", "JSON", permlevel=1), field("result", "JSON", permlevel=1),
        field("reverses", "Link", "Knitting Event"), field("cancelled", "Check"), field("voucher_type"), field("voucher_name")],
    "Knitting Ledger Entry": [*BASE, field("job", "Link", "Knitting Job"), field("lot", "Link", "Knitting Material Lot"),
        field("event", "Link", "Knitting Event", reqd=1), field("material_owner", "Select", "Customer\nOwned"),
        field("party", "Link", "Customer"), field("custodian"), field("warehouse", "Link", "Warehouse"),
        field("quantity_kg", reqd=1), field("units"), field("voucher_type"), field("voucher_name")],
    "Knitting Roll": [*BASE, field("charges", "JSON", permlevel=1), field("job", "Link", "Knitting Job", reqd=1), field("programme_line"),
        field("job_revision", "Int"), field("weight_kg", reqd=1), field("fabric_item", "Link", "Item"),
        field("warehouse", "Link", "Warehouse"), field("machine", "Link", "Knitting Machine"),
        field("operator", "Link", "User"), field("shift"), field("produced_at", "Datetime"),
        field("state", "Select", "Awaiting QC\nReleased\nOn Hold\nRework\nRejected\nDelivered\nSplit\nCancelled", in_list_view=1),
        field("production", "Link", "Knitting Event"), field("delivery", "Link", "Knitting Event"),
        field("parent_roll", "Link", "Knitting Roll"), field("specification", "JSON")],
    "Knitting QC": [*BASE, field("roll", "Link", "Knitting Roll", reqd=1), field("job", "Link", "Knitting Job"),
        field("checker", "Link", "User"), field("decision", "Select", "Released\nOn Hold\nRework\nRejected"),
        field("defects", "JSON"), field("remarks", "Small Text"), field("event", "Link", "Knitting Event")],
    "Knitting Plan": [*BASE, field("job", "Link", "Knitting Job", reqd=1), field("machine", "Link", "Knitting Machine", reqd=1), field("programme_line"), field("required_yarn_kg"), field("produced_kg", default="0.000"),
        field("starts_at", "Datetime", reqd=1), field("ends_at", "Datetime", reqd=1), field("quantity_kg", reqd=1),
        field("state", "Select", "Planned\nStarted\nCompleted\nCancelled"), field("shift"), field("event", "Link", "Knitting Event")],
    "Knitting Subcontract": [*BASE, field("job", "Link", "Knitting Job", reqd=1), field("supplier", "Link", "Supplier", reqd=1),
        field("target_kg"), field("status", "Select", "Open\nCompleted\nCancelled"), field("rate", "Currency", permlevel=1),
        field("warehouse", "Link", "Warehouse"), field("purchase_order", "Link", "Purchase Order"), field("service_item", "Link", "Item")],
    "Knitting Component": [*BASE, field("machine", "Link", "Knitting Machine"), field("component_type", "Select", "Needle\nSinker\nCylinder\nDial"),
        field("item", "Link", "Item"), field("boundary_kg"), field("run_kg"), field("installed_at", "Datetime")],
    "Knitting Holiday": [*BASE, field("machine", "Link", "Knitting Machine"), field("date", "Date", reqd=1), field("description")],
    "Knitting Rate": [*BASE, field("customer", "Link", "Customer", reqd=1), field("fabric", reqd=1),
        field("yarn_count"), field("gauge"), field("rate", "Currency", permlevel=1), field("effective_from", "Date", reqd=1)],
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
        permissions = [{"role": role, "read": 1, "write": 1, "create": 1, "report": 1, "print": 1, "export": 1}
                       for role in ("System Manager", *ROLES)]
        if any(f.get("permlevel") == 1 for f in fields):
            permissions += [{"role": role, "permlevel": 1, "read": 1, "write": 1, "create": 1}
                            for role in ("System Manager", "Knitting Manager", "Knitting Accountant")]
        if frappe.db.exists("DocType", name):
            doc = frappe.get_doc("DocType", name)
            changed = bool(doc.track_changes)
            doc.track_changes = 0
            for definition in fields:
                existing = next((f for f in doc.fields if f.fieldname == definition["fieldname"]), None)
                if existing is None:
                    doc.append("fields", definition)
                    changed = True
                elif existing.permlevel != definition.get("permlevel", 0):
                    existing.permlevel = definition.get("permlevel", 0)
                    changed = True
                if existing and definition.get("unique") and not existing.unique:
                    existing.unique = 1
                    changed = True
            for permission in permissions:
                if not any(p.role == permission["role"] and p.permlevel == permission.get("permlevel", 0) for p in doc.permissions):
                    doc.append("permissions", permission)
                    changed = True
            if changed:
                doc.save()
        else:
            frappe.get_doc({"doctype": "DocType", "name": name, "module": "Custom", "custom": 1,
                            "autoname": "hash", "track_changes": 0, "fields": fields, "permissions": permissions}).insert()
        # The immutable, permission-scoped event journal is the pack audit.
        # Desk's generic Version feed does not enforce field-level privacy.
        frappe.db.delete("Version", {"ref_doctype": name})
    from frappe.custom.doctype.custom_field.custom_field import create_custom_fields
    create_custom_fields({name: [
        field("knitting_event", "Link", "Knitting Event", read_only=1, no_copy=1),
        field("knitting_job", "Link", "Knitting Job", read_only=1, no_copy=1),
    ] for name in ("Stock Entry", "Delivery Note", "Sales Invoice", "Purchase Invoice", "Purchase Order", "Purchase Receipt", "Quotation")})
    create_custom_fields({"Purchase Invoice Item": [field("knitting_receipt", "Link", "Knitting Event", read_only=1, no_copy=1)]})
    create_custom_fields({"Sales Invoice Item": [field("knitting_delivery", "Link", "Knitting Event", read_only=1, no_copy=1)]})
    create_custom_fields({"Quotation": [field("knitting_programme", "JSON", read_only=1),
        field("knitting_material_mode", "Select", "Customer\nOwned", read_only=1)]})
    frappe.clear_cache()
    # Frappe's global cache reset leaves the request's expanded document hooks intact.
    frappe.local.doc_events_hooks = None
