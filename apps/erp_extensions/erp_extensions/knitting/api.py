"""Versioned, fixed knitting commands; no arbitrary RPC and no automatic write replay."""
import hashlib
import json
import re
from collections.abc import Mapping
from decimal import Decimal

import frappe
from frappe.utils import now_datetime

from . import domain, permissions


def request_key(company, request_id):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", request_id):
        frappe.throw("A valid action request reference is required.")
    return hashlib.sha256(f"{frappe.local.site}|{frappe.session.user}|{company}|{request_id}".encode()).hexdigest()


def project(value):
    if "financial_read" in permissions.capabilities():
        return value
    private = {"rate", "amount", "valuation_rate", "charge_rate", "income_account", "expense_account", "grand_total", "pricing"}
    if isinstance(value, Mapping):
        return {key: project(item) for key, item in value.items() if key not in private}
    return [project(item) for item in value] if isinstance(value, list) else value


def response(event):
    return {"event": event.name, "action": event.kind, "data": project(domain.json_value(event.result, {}))}


@frappe.whitelist(methods=["POST"])
def command(company, action, payload, request_id, modified=None):
    data = frappe.parse_json(payload) if isinstance(payload, str) else payload
    if not isinstance(data, Mapping) or len(frappe.as_json(data)) > 262144:
        frappe.throw("A bounded, structured action payload is required.")
    from . import factory
    actions = {**domain.ACTIONS, **factory.ACTIONS}
    if action not in actions:
        frappe.throw("That knitting action is not supported.")
    capability, handler = actions[action]
    if "financial_read" not in permissions.capabilities():
        def financial_keys(value):
            if isinstance(value, Mapping):
                return any(k in {"rate", "valuation_rate", "charge_rate", "charge_item", "income_account", "expense_account"} or
                           financial_keys(v) for k, v in value.items())
            return isinstance(value, list) and any(financial_keys(v) for v in value)
        if financial_keys(data):
            frappe.throw("This account cannot set financial values.", frappe.PermissionError)
    # Configuration is the common lock for scope changes and quantity-consuming commands.
    setup = permissions.require(company, capability)
    frappe.db.sql("select name from `tabWorkspace Industry Setup` where name=%s for update", setup.name)
    permissions.require(company, capability)
    key = request_key(company, request_id)
    digest = hashlib.sha256(json.dumps({"action": action, "payload": data, "modified": modified},
        sort_keys=True, separators=(",", ":"), allow_nan=False, default=str).encode()).hexdigest()
    existing = frappe.db.get_value("Knitting Event", {"request_key": key}, "name")
    if existing:
        event = frappe.get_doc("Knitting Event", existing)
        if event.payload_hash != digest:
            frappe.throw("That request reference was already used with different values.")
        return response(event)
    job = domain.reference("Knitting Job", data["job"], company) if data.get("job") else None
    if job:
        from erp_extensions.api import _check_version
        _check_version(job, modified)
        if job.status != "Running" and action not in ("reopen_job",):
            frappe.throw("Reopen this job before posting more work.")
    elif action not in {"create_job", "receive_yarn", *factory.JOB_OPTIONAL}:
        frappe.throw("Select the source knitting job.")
    savepoint = "knitting_command"
    frappe.db.savepoint(savepoint)
    try:
        with permissions.service_write():
            event = domain.insert("Knitting Event", company=company, job=job.name if job else None, kind=action,
                request_key=key, payload_hash=digest, actor=frappe.session.user, occurred_at=now_datetime(), payload=frappe.as_json(data))
            result = handler(event, data, job)
            if action == "create_job":
                event.job = result["job"]
            if job:
                # Advance the aggregate version after every confirmed domain change.
                job = frappe.get_doc("Knitting Job", job.name)
                job.save()
            event.result = frappe.as_json(result)
            event.voucher_type, event.voucher_name = result.get("voucher_type"), result.get("voucher")
            event.save()
            return response(event)
    except Exception:
        frappe.db.rollback(save_point=savepoint)
        raise


@frappe.whitelist()
def command_status(company, request_id):
    permissions.require(company, "jobs", history=True)
    name = frappe.db.get_value("Knitting Event", {"request_key": request_key(company, request_id)}, "name")
    if not name:
        return {"state": "not_found", "request_id": request_id}
    event = domain.reference("Knitting Event", name, company)
    return response(event)


@frappe.whitelist()
def snapshot(company, job=None):
    permissions.require(company, "jobs", history=True)
    finance = "financial_read" in permissions.capabilities()
    if job:
        domain.reference("Knitting Job", job, company)
    jobs = []
    fields = ["name", "modified", "customer", "kind", "material_mode", "due_date", "status", "target_kg", "revision", "programme"]
    if finance:
        fields += ["rate", "service_item"]
    for row in frappe.get_list("Knitting Job", filters={"company": company, **({"name": job} if job else {})}, fields=fields, order_by="modified desc", limit=200):
        row.programme = domain.json_value(row.programme, [])
        row.balances = domain.balances(row.name)
        if finance:
            row.rate = domain.money(row.rate or 0)
        jobs.append(row)
    limits = {"jobs": jobs}
    for key, doctype, fields in (
        ("rolls", "Knitting Roll", ["name", "job", "programme_line", "weight_kg", "state", "warehouse", "machine", "operator", "shift", "produced_at", "production", "delivery"]),
        ("lots", "Knitting Material Lot", ["name", "item", "party", "material_owner", "warehouse", "source_lot", "specification"]),
        ("machines", "Knitting Machine", ["name", "title", "dia", "gauge", "knit_type", "capacity_kg", "enabled"]),
        ("plans", "Knitting Plan", ["name", "job", "machine", "starts_at", "ends_at", "quantity_kg", "state"]),
        ("inspections", "Knitting QC", ["name", "job", "roll", "checker", "decision", "remarks", "creation"]),
        ("events", "Knitting Event", ["name", "job", "kind", "occurred_at", "cancelled", "result"]),
        ("subcontracts", "Knitting Subcontract", ["name", "job", "supplier", "target_kg", "status", "warehouse", "purchase_order"]),
        ("components", "Knitting Component", ["name", "machine", "component_type", "boundary_kg", "run_kg", "installed_at"]),
        ("holidays", "Knitting Holiday", ["name", "machine", "date", "description"]),
    ):
        # Event result JSON has a private field level; read it only after scoped row permission filtering.
        query_fields = [f for f in fields if f != "result"] if key == "events" else fields
        filters = {"company": company, **({"job": job} if job and frappe.get_meta(doctype).has_field("job") else {})}
        limits[key] = frappe.get_list(doctype, filters=filters, fields=query_fields, order_by="creation desc", limit=500)
    for event in limits["events"]:
        event.result = project(domain.json_value(frappe.db.get_value("Knitting Event", event.name, "result"), {}))
    for component in limits["components"]:
        component.remaining_kg = domain.kg(Decimal(component.boundary_kg) - Decimal(component.run_kg or "0"))
    if finance:
        limits["rates"] = frappe.get_list("Knitting Rate", filters={"company": company}, fields=["name", "customer", "fabric", "yarn_count", "gauge", "rate", "effective_from"], limit=500)
        for row in limits["rates"]:
            row.rate = domain.money(row.rate or 0)
    allocated = {}
    if limits["lots"]:
        for row in frappe.get_all("Knitting Ledger Entry", filters={"company": company, "lot": ["in", [l.name for l in limits["lots"]]], "custodian": "Warehouse"},
                                  fields=["lot", "job", "quantity_kg"]):
            key = (row.lot, row.job or None)
            allocated[key] = allocated.get(key, Decimal(0)) + Decimal(row.quantity_kg)
    for lot in limits["lots"]:
        lot.allocations = [{"job": job["name"], "quantity_kg": domain.kg(allocated.get((lot.name, job["name"]), 0))} for job in jobs]
        lot.general_kg = domain.kg(allocated.get((lot.name, None), 0))
    return {"version": 1, "company": company, "financial_read": finance, **limits,
            "integrations": [{"name": name, "status": "Not configured"} for name in ("E-Invoice", "E-Way Bill", "Payment gateway")]}


@frappe.whitelist()
def lookup(company, entity, query="", start=0):
    """Bounded permission-scoped selectors, never an arbitrary DocType/query endpoint."""
    if "configure" not in permissions.capabilities() or not permissions.company_allowed(company):
        permissions.require(company, "jobs", history=True)
    registry = {
        "Job": ("Knitting Job", ["name", "customer", "status", "modified", "programme"], {}),
        "Lot": ("Knitting Material Lot", ["name", "item", "party", "material_owner"], {}),
        "Machine": ("Knitting Machine", ["name", "title", "dia", "gauge"], {"enabled": 1}),
        "Roll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": ["not in", ["Split", "Cancelled", "Delivered"]]}),
        "ReleasedRoll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": "Released"}),
        "Delivery": ("Knitting Event", ["name", "job", "kind"], {"kind": "deliver", "cancelled": 0}),
        "Event": ("Knitting Event", ["name", "job", "kind"], {"cancelled": 0}),
        "Subcontract": ("Knitting Subcontract", ["name", "job", "supplier", "status"], {"status": "Open"}),
        "Component": ("Knitting Component", ["name", "machine", "component_type"], {}),
        "Customer": ("Customer", ["name", "customer_name as title"], {"disabled": 0}),
        "Supplier": ("Supplier", ["name", "supplier_name as title"], {"disabled": 0}),
        "Item": ("Item", ["name", "item_name as title", "stock_uom"], {"disabled": 0}),
        "Warehouse": ("Warehouse", ["name"], {"is_group": 0}),
        "Quotation": ("Quotation", ["name", "party_name", "docstatus", "modified"], {"knitting_event": ["is", "set"]}),
    }
    if entity not in registry or len(str(query)) > 120 or not str(start).isdigit() or int(start) > 1000000:
        frappe.throw("Choose a supported record selector and page.")
    doctype, fields, filters = registry[entity]
    if frappe.get_meta(doctype).has_field("company"):
        filters = {**filters, "company": company}
    rows = frappe.get_list(doctype, filters=filters, or_filters=[["name", "like", "%" + query + "%"]] if query else None,
                           fields=fields, order_by="modified desc, name", start=int(start), limit=51)
    for row in rows:
        if entity == "Job":
            row.programme = domain.json_value(row.programme, [])
            row.balances = domain.balances(row.name)
    return {"rows": rows[:50], "has_more": len(rows) > 50, "start": int(start)}


@frappe.whitelist()
def report(company, report, filters=None):
    from .reports import run
    return run(company, report, filters)


@frappe.whitelist()
def export(company, format, filters=None):
    from .exports import render
    return render(company, format, filters)
