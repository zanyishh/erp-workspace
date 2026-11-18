"""Company-enabled industry context; no username-derived or client-trusted access."""
from collections.abc import Mapping

import frappe

from erp_extensions.knitting import permissions


def readiness(values):
    return [{"key": key, "ready": bool(values.get(key))} for key in ("warehouse", "service_item", "fabric_item")]


def obligations(company):
    from decimal import Decimal
    from erp_extensions.knitting import domain as d, procurement
    if d.current_rows("Knitting Job", filters={"company": company, "status": "Running"}, fields=["name"]):
        return True
    totals = {}
    for row in d.current_rows("Knitting Ledger Entry", filters={"company": company}, fields=["lot", "job", "custodian", "quantity_kg", "units"]):
        key = (row.lot, row.job, row.custodian)
        kg, units = totals.get(key, (Decimal(0), Decimal(0)))
        totals[key] = (kg + Decimal(row.quantity_kg), units + Decimal(row.units or "0"))
    if any(kg or units for kg, units in totals.values()):
        return True
    if d.current_rows("Knitting Roll", filters={"company": company, "state": ["not in", ["Delivered", "Split", "Cancelled"]]}, fields=["name"]):
        return True
    if d.current_rows("Knitting Subcontract", filters={"company": company, "status": "Open"}, fields=["name"]):
        return True
    manual_receipts = d.current_rows("Knitting Event", filters={"company": company, "kind": "receive_yarn",
                                     "voucher_type": "Stock Entry", "cancelled": 0}, fields=["name", "result"])
    if manual_receipts:
        billed = procurement.billed_receipt_quantities(company)
        if any(billed.get(r.name, d.ZERO) < Decimal(d.json_value(r.result)["quantity_kg"]) for r in manual_receipts):
            return True
    for event in d.current_rows("Knitting Event", filters={"company": company, "kind": "create_yarn_order", "cancelled": 0}, fields=["result"]):
        name = d.json_value(event.result, {}).get("purchase_order")
        if name:
            order = frappe.get_doc("Purchase Order", name, for_update=True)
            if order.docstatus == 1 and order.status != "Closed" and any(r.received_qty < r.qty or r.billed_amt < r.amount for r in order.items):
                return True
    return False


@frappe.whitelist()
def context(company=None):
    import hashlib
    import json
    from erp_extensions.onboarding import can_manage_team, membership
    available = permissions.companies()
    if frappe.session.user == "Guest":
        frappe.throw("Sign in first.", frappe.PermissionError)
    if company and company not in {c.name for c in available}:
        frappe.throw("This account cannot open that business.", frappe.PermissionError)
    names = {row.name for row in available}
    preferred = frappe.defaults.get_user_default("native_workspace_company")
    default = frappe.defaults.get_user_default("Company")
    selected = company or next((name for name in (preferred, default) if name in names),
                               available[0].name if available else None)
    setup = permissions.profile(selected) if selected else None
    caps = permissions.capabilities() if setup and setup.state in ("Active", "Closing") else set()
    scope = frappe.get_all("User Permission", filters={"user": frappe.session.user},
                           fields=["allow", "for_value", "applicable_for", "apply_to_all_doctypes", "hide_descendants", "modified"], order_by="name")
    core_records = ("Sales Invoice", "Sales Order", "Quotation", "Purchase Order", "Item", "Work Order", "Project", "Asset", "Quality Inspection")
    readable = [name for name in core_records if selected and frappe.has_permission(name, "read")]
    creatable = [name for name in core_records if frappe.has_permission(name, "create")]
    unavailable = []
    if "factory" in caps and not frappe.has_permission("Workstation", "create"):
        unavailable.append("create_machine")
    if "new_job" in caps and not frappe.has_permission("Quotation", "read"):
        unavailable.append("job_from_estimate")
    if "billing" in caps:
        if not frappe.has_permission("Quotation", "create"):
            unavailable.append("create_estimate")
        if not all(frappe.has_permission("Quotation", permission) for permission in ("read", "write", "submit")):
            unavailable.append("accept_estimate")
        for doctype, actions in (
            ("Purchase Order", ("create_subcontract", "create_yarn_order")),
            ("Purchase Invoice", ("bill_yarn", "subcontract_bill")),
            ("Sales Invoice", ("invoice", "credit_invoice")),
        ):
            if not (frappe.has_permission(doctype, "create") and frappe.has_permission(doctype, "submit")):
                unavailable.extend(actions)
    manage_team = can_manage_team(selected)
    member = membership()
    open_desk = not member
    cashier_home = bool(member and member.team_role == "cashier")
    from erp_extensions.reconciliation import permitted
    from erp_extensions.bank_matching import permitted as bank_matching_permitted
    from erp_extensions.pos_checkout import permitted as pos_permitted
    point_of_sale = bool(selected and pos_permitted())
    reconcile = bool(selected and permitted())
    bank_match = bool(selected and bank_matching_permitted())
    from erp_extensions.migration.api import available as imported_history_available, customer_workspace
    imported_history = bool(selected and imported_history_available(selected))
    knitting_only = bool(selected and customer_workspace(selected))
    fingerprint = hashlib.sha256(json.dumps([sorted(frappe.get_roles()), scope, readable, creatable, unavailable, manage_team, open_desk, reconcile, bank_match, point_of_sale, cashier_home, imported_history, knitting_only], sort_keys=True, default=str).encode()).hexdigest()
    from erp_extensions import operations
    return {"version": 1, "operation_recovery_version": 1 if operations.available() and not cashier_home else 0,
            "companies": available, "company": selected, "access_fingerprint": fingerprint,
            "cashier_home":cashier_home, "can_operate_pos": point_of_sale, "can_manage_team": manage_team, "can_open_desk": open_desk, "can_reconcile_payments": reconcile, "can_match_bank_statements": bank_match,
            "can_read_imported_history": imported_history,
            "knitting_only": knitting_only,
            "setup_state": setup.state if setup else "General ERP", "revision": setup.revision if setup else 0,
            "needs_industry_selection": bool(selected and (not setup or setup.state == "Setup") and "configure" in permissions.capabilities()),
            "knitting_enabled": bool(caps), "capabilities": sorted(caps), "creatable_records": creatable, "readable_records": readable,
            "unavailable_knitting_actions": unavailable, "can_configure": "configure" in permissions.capabilities(),
            "readiness": readiness(frappe.parse_json(setup.settings or "{}") if setup else {})}


@frappe.whitelist(methods=["POST"])
def select_company(company):
    if not company:
        frappe.throw("Choose a company.")
    selected = context(company)
    frappe.defaults.set_user_default("native_workspace_company", selected["company"])
    return selected


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
    with permissions.service_write():
        if settings["state"] in ("Inactive", "Setup") and obligations(company):
            frappe.throw("Settle running jobs, custody, fabric, subcontracts and yarn purchasing before leaving active work.")
    if "revision" in settings and int(settings["revision"]) != int(doc.revision or 0):
        frappe.throw("The setup changed. Reload its latest policy before applying your changes.")
    from erp_extensions.knitting import domain
    if "allow_production_excess_pct" in settings:
        excess = domain.decimal(settings["allow_production_excess_pct"])
        if excess > 100:
            frappe.throw("Review excess production between zero and 100 percent.")
    if "shift_windows" in settings:
        from erp_extensions.knitting.shifts import validate
        validate(settings['shift_windows'])
    if settings.get("warehouse"):
        domain.warehouse(settings["warehouse"], company)
    for field, stock in (("service_item", False), ("fabric_item", True)):
        if settings.get(field):
            item = domain.reference("Item", settings[field])
            if bool(item.is_stock_item) != stock or item.stock_uom != "Kg":
                frappe.throw("Use a non-stock Kg service item and a stock Kg fabric item.")
    for field, doctype in (("income_account", "Account"), ("expense_account", "Account"), ("cost_center", "Cost Center")):
        if settings.get(field):
            domain.reference(doctype, settings[field], company)
    previous = frappe.parse_json(doc.settings or "{}")
    if settings["state"] in ("Active", "Closing") and not all(r["ready"] for r in readiness({**previous, **settings})):
        frappe.throw("Set the default godown, knitting service item and fabric item before activation.")
    allowed = {"shifts", "shift_windows", "warehouse", "service_item", "fabric_item", "cost_center", "expense_account", "income_account",
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


@frappe.whitelist()
def settings(company):
    if "configure" not in permissions.capabilities() or not permissions.company_allowed(company):
        frappe.throw("This account cannot configure this business.", frappe.PermissionError)
    profile = permissions.profile(company)
    return {"settings": frappe.parse_json(profile.settings or "{}") if profile else {},
            "revision": profile.revision if profile else 0, "state": profile.state if profile else "Setup"}
