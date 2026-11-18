"""Versioned, fixed knitting commands; no arbitrary RPC and no automatic write replay."""
import hashlib
import json
import re
from collections.abc import Mapping
from contextlib import contextmanager
from decimal import Decimal

import frappe
from frappe.utils import now_datetime

from . import domain, permissions


@contextmanager
def _operation_savepoint(name, *, preview=False):
    frappe.db.savepoint(name)
    try:
        yield
    except frappe.QueryDeadlockError:
        # InnoDB already rolled back the whole transaction, including this savepoint.
        frappe.throw("Another update interrupted this request. Your changes were not saved. Please try again.")
    except Exception:
        frappe.db.rollback(save_point=name)
        raise
    else:
        if preview:
            # ERPNext controllers can create supporting data while calculating a preview.
            frappe.db.rollback(save_point=name)


def request_key(company, request_id):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", request_id):
        frappe.throw("A valid action request reference is required.")
    return hashlib.sha256(f"{frappe.local.site}|{frappe.session.user}|{company}|{request_id}".encode()).hexdigest()


def project(value, *, financial_read=None):
    if financial_read is None:
        financial_read = "financial_read" in permissions.capabilities()
    if financial_read:
        return value
    private = {"rate", "original_dc_rate", "amount", "valuation_rate", "charge_rate", "income_account", "expense_account", "grand_total", "pricing", "billing_customer"}
    if isinstance(value, Mapping):
        return {key: project(item, financial_read=False) for key, item in value.items() if key not in private}
    return [project(item, financial_read=False) for item in value] if isinstance(value, list) else value


def response(event):
    permissions.require_event_scope(event)
    return {"event": event.name, "action": event.kind, "data": project(domain.json_value(event.result, {}))}


@frappe.whitelist(methods=["POST"])
def command(company, action, payload, request_id, modified=None):
    from erp_extensions import operations
    data = frappe.parse_json(payload) if isinstance(payload, str) else payload
    return operations.execute(company, 'knitting', request_id,
        {'action': action, 'payload': data, 'modified': modified},
        lambda: _command(company, action, data, request_id, modified), action=action, optional=True)


def _command(company, action, payload, request_id, modified=None):
    data = frappe.parse_json(payload) if isinstance(payload, str) else payload
    if not isinstance(data, Mapping) or len(frappe.as_json(data)) > 262144:
        frappe.throw("A bounded, structured action payload is required.")
    from . import factory, procurement, batches
    actions = {**domain.ACTIONS, **factory.ACTIONS, **procurement.ACTIONS, **batches.ACTIONS}
    if action not in actions:
        frappe.throw("That knitting action is not supported.")
    capability, handler = actions[action]
    if action == 'produce_bulk':
        from .machines import reject_output_fields
        from .operators import reject_output_fields as reject_operator_output_fields
        reject_output_fields(data)
        reject_operator_output_fields(data)
        if data.get('production_machine') not in (None, ''):
            frappe.throw('Choose the original recorded machine separately for each production row.')
        if data.get('production_operator') not in (None, ''):
            frappe.throw('Choose the original production employee separately for each production row.')
    if "financial_read" not in permissions.capabilities():
        def financial_keys(value):
            if isinstance(value, Mapping):
                return any(k in {"rate", "valuation_rate", "charge_rate", "charge_item", "income_account", "expense_account", "billing_customer"} or
                           financial_keys(v) for k, v in value.items())
            return isinstance(value, list) and any(financial_keys(v) for v in value)
        if financial_keys(data):
            frappe.throw("This account cannot set financial values.", frappe.PermissionError)
    # Configuration is the common lock for scope changes and quantity-consuming commands.
    setup = permissions.require(company, capability)
    frappe.db.sql("select name from `tabWorkspace Industry Setup` where name=%s for update", setup.name)
    permissions.require(company, capability, current=True)
    key = request_key(company, request_id)
    try:
        digest = hashlib.sha256(json.dumps({"action": action, "payload": data, "modified": modified},
            sort_keys=True, separators=(",", ":"), allow_nan=False, default=str).encode()).hexdigest()
    except (ValueError, TypeError):
        frappe.throw("Use finite, supported values in the reviewed entry.")
    existing = frappe.db.get_value("Knitting Event", {"request_key": key}, "name", for_update=True)
    if existing:
        event = frappe.get_doc("Knitting Event", existing, for_update=True)
        if event.payload_hash != digest:
            frappe.throw("That request reference was already used with different values.")
        return response(event)
    job_name = data.get("job")
    if not job_name and action in ("bill_yarn", "return_consumable"):
        source_key = "receipt" if action == "bill_yarn" else "event"
        job_name = domain.reference("Knitting Event", data.get(source_key), company, lock=True).job
    job = domain.reference("Knitting Job", job_name, company, lock=True) if job_name else None
    if job:
        from erp_extensions.api import _check_version
        # Older source-only forms submit the event identity without a job version.
        if modified is not None or data.get("job"):
            _check_version(job, modified)
        if job.status != "Running" and action not in ("reopen_job",):
            frappe.throw("Reopen this job before posting more work.")
    elif action not in {"create_job", "receive_yarn", "create_yarn_order", "bill_yarn", "produce_batches", *factory.JOB_OPTIONAL}:
        frappe.throw("Select the source knitting job.")
    with _operation_savepoint("knitting_command"):
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


@frappe.whitelist()
def command_status(company, request_id):
    setup = permissions.require(company, "jobs", history=True)
    frappe.db.sql("select name from `tabWorkspace Industry Setup` where name=%s for update", setup.name)
    name = frappe.db.get_value("Knitting Event", {"request_key": request_key(company, request_id)}, "name", for_update=True)
    if not name:
        return {"state": "not_found", "request_id": request_id}
    event = domain.reference("Knitting Event", name, company, lock=True)
    return response(event)


@frappe.whitelist()
@permissions.snapshot_link_checks()
def snapshot(company, job=None):
    from .registers import snapshot as read_snapshot
    return read_snapshot(company, job)


@frappe.whitelist()
@permissions.snapshot_link_checks()
def register(company, collection, job=None, start=0, query="", state=None, production_date=None, from_date=None, to_date=None, customer=None, category=None):
    from .registers import page
    return page(company, collection, job, start, query, state, production_date, from_date, to_date, customer, category)


@frappe.whitelist()
@permissions.snapshot_link_checks()
def overview(company):
    from .registers import overview as read_overview
    return read_overview(company)


@frappe.whitelist()
@permissions.snapshot_link_checks()
def roll(company, job, roll):
    from .registers import roll as read_roll
    return read_roll(company, job, roll)


@frappe.whitelist()
def lookup(company, entity, query="", start=0, job=None):
    """Bounded permission-scoped selectors, never an arbitrary DocType/query endpoint."""
    if entity == 'ProductionOperator':
        from .operators import choices
        return choices(company, query, start, job)
    if entity == 'ProductionMachine':
        from .machines import choices
        return choices(company, query, start, job)
    if entity == "SalesTaxTemplate":
        permissions.require(company, "billing", history=True)
    if "configure" not in permissions.capabilities() or not permissions.company_allowed(company):
        permissions.require(company, "jobs", history=True)
    registry = {
        "ClosingJob": ("Knitting Job", ["name", "source_reference", "customer", "status", "modified", "programme"], {"status": "Running"}),
        "Job": ("Knitting Job", ["name", "source_reference", "customer", "status", "material_mode", "modified", "programme"], {}),
        "Lot": ("Knitting Material Lot", ["name", "item", "party", "material_owner"], {}),
        "Machine": ("Knitting Machine", ["name", "title", "dia", "gauge"], {"enabled": 1}),
        "Roll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": ["not in", ["Split", "Cancelled", "Delivered"]]}),
        "LabelRoll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": ["not in", ["Split", "Cancelled"]]}),
        "ReleasedRoll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": "Released"}),
        "InvoiceEvent": ("Knitting Event", ["name", "job", "kind"], {"kind": "invoice", "cancelled": 0}),
        "DeliveredRoll": ("Knitting Roll", ["name", "job", "state", "weight_kg"], {"state": "Delivered"}),
        "Delivery": ("Knitting Event", ["name", "job", "kind"], {"kind": ["in", ["deliver", "deliver_batch"]], "cancelled": 0}),
        "BillingDelivery": ("Knitting Event", ["name", "job", "kind"], {"kind": ["in", ["deliver", "deliver_batch", "migration_delivery_reference"]], "cancelled": 0}),
        "RollDelivery": ("Knitting Event", ["name", "job", "kind"], {"kind": "deliver", "cancelled": 0}),
        "CompanyEvent": ("Knitting Event", ["name", "job", "kind"], {"job": ["is", "not set"], "kind": ["in", domain.CORRECTABLE], "cancelled": 0}),
        "CompletedSubcontract": ("Knitting Subcontract", ["name", "job", "supplier", "status"], {"status": "Completed"}),
        "Event": ("Knitting Event", ["name", "job", "kind"], {"kind": ["in", domain.CORRECTABLE], "cancelled": 0}),
        "ConsumableIssue": ("Knitting Event", ["name", "job", "kind"], {"kind": "issue_consumable", "cancelled": 0}),
        "Subcontract": ("Knitting Subcontract", ["name", "job", "supplier", "status"], {"status": "Open"}),
        "Plan": ("Knitting Plan", ["name", "job", "machine", "programme_line", "starts_at", "ends_at", "quantity_kg", "required_yarn_kg", "modified"], {"state": ["in", ["Planned", "Started"]]}),
        "Master": ("Knitting Master", ["name", "category", "title", "enabled", "modified", "specification"], {}),
        "Defect": ("Knitting Master", ["name", "title", "specification"], {"category": "QC defect", "enabled": 1}),
        "Component": ("Knitting Component", ["name", "machine", "component_type"], {}),
        "Customer": ("Customer", ["name", "customer_name as title"], {"disabled": 0}),
        "JobCustomer": ("Customer", ["name", "customer_name as title"], {}),
        "SalesTaxTemplate": ("Sales Taxes and Charges Template", ["name", "title"], {"disabled": 0}),
        "Supplier": ("Supplier", ["name", "supplier_name as title"], {"disabled": 0}),
        "Item": ("Item", ["name", "item_name as title", "stock_uom"], {"disabled": 0}),
        "StockKgItem": ("Item", ["name", "item_name as title", "stock_uom"], {"disabled": 0, "is_stock_item": 1, "stock_uom": "Kg"}),
        "ServiceItem": ("Item", ["name", "item_name as title", "stock_uom"], {"disabled": 0, "is_stock_item": 0}),
        "Warehouse": ("Warehouse", ["name"], {"is_group": 0}),
        "User": ("User", ["name", "full_name as title"], {"enabled": 1}),
        "Employee": ("Employee", ["name", "employee_name as title"], {"status": "Active"}),
        "PurchaseOrder": ("Purchase Order", ["name", "supplier", "modified"], {"docstatus": 1, "knitting_event": ["is", "set"]}),
        "YarnReceipt": ("Knitting Event", ["name", "job", "kind"], {"kind": "receive_yarn", "cancelled": 0}),
        "Quotation": ("Quotation", ["name", "party_name", "docstatus", "modified"], {"knitting_event": ["is", "set"]}),
    }
    if entity not in registry or len(str(query)) > 120 or not str(start).isdigit() or int(start) > 1000000:
        frappe.throw("Choose a supported record selector and page.")
    doctype, fields, filters = registry[entity]
    if entity == "JobCustomer":
        permissions.require(company, "jobs", history=True)
        parties = frappe.get_list("Knitting Job", filters={"company": company}, pluck="customer", limit=0)
        filters = {"name": ["in", sorted(set(parties))]}
    if frappe.get_meta(doctype).has_field("company"):
        filters = {**filters, "company": company}
    if job and frappe.get_meta(doctype).has_field("job") and "job" not in filters:
        domain.reference("Knitting Job", job, company)
        filters = {**filters, "job": job}
    from .registers import (JOB_ORDER, JOB_ORDER_FIELD, customer_names, customer_name_matches,
                            literal_search_pattern, original_reference_matches)
    pattern = literal_search_pattern(query) if doctype == "Knitting Job" or entity == "JobCustomer" else "%" + query + "%"
    search = [[field, "like", pattern] for field in ("name", "title", "source_reference", "customer", "supplier", "item", "customer_name", "supplier_name", "item_name")
        if field == "name" or frappe.get_meta(doctype).has_field(field)] if query else None
    if doctype == "Knitting Job":
        fields = [*fields, "source_record", "job_date", JOB_ORDER_FIELD]
        matches = customer_name_matches(query, literal=True)
        if matches:
            search.append(["customer", "in", matches])
        references = original_reference_matches(company, query)
        if references:
            search.append(["name", "in", references])
    rows = frappe.get_list(doctype, filters=filters, or_filters=search,
                           fields=fields, order_by=JOB_ORDER if doctype == "Knitting Job" else "modified desc, name", start=int(start), limit=51)
    if doctype == "Knitting Job":
        customer_names(rows)
    for row in rows:
        if doctype == "Knitting Event":
            result = domain.json_value(frappe.db.get_value("Knitting Event", row.name, "result"), {})
            reference = result.get("invoice") or result.get("purchase_order") or result.get("lot") or result.get("subcontract") or ""
            row.title = row.kind.replace("_", " ").title() + (" · " + reference if reference else "")
            if row.kind == 'migration_delivery_reference':
                row.title = 'Original delivery ' + str(result.get('source_reference') or row.name)
                if result.get('original_date'):
                    row.title += ' · ' + str(result['original_date'])
            if row.job and entity in ("YarnReceipt", "ConsumableIssue"):
                row.job_modified = frappe.db.get_value("Knitting Job", row.job, "modified")
        if entity == "Job":
            row.programme = domain.json_value(row.programme, [])
            try:
                row.balances = domain.balances(row.name)
            except permissions.SourceReconciliationError:
                row.balances = None
                row.reconciliation_available = False
    result = {"rows": rows[:50], "has_more": len(rows) > 50, "start": int(start)}
    if entity in ("Job", "ClosingJob"):
        from erp_extensions.migration.dimensions import programmes
        programmes(company, result["rows"])
        if entity == "ClosingJob":
            for row in result["rows"]:
                row.pop("programme", None)
    if entity == "Customer":
        result["can_create"] = bool(frappe.has_permission("Customer", "create"))
    return result


@frappe.whitelist()
def report(company, report, filters=None):
    from .reports import run
    return run(company, report, filters)


@frappe.whitelist()
def export(company, format, filters=None):
    from .exports import render
    return render(company, format, filters)



def invoice_review(doc):
    from erp_extensions.invoices import _precision, payable_total
    precision = _precision('grand_total', doc.currency)
    payable = payable_total(doc)

    def money(value):
        return domain.money(value, precision)

    return {"currency": doc.currency, "precision": precision,
        "net_total": money(doc.net_total), "tax_total": money(doc.total_taxes_and_charges), "grand_total": money(doc.grand_total),
        "rounding_adjustment": money(Decimal(str(payable)) - Decimal(str(doc.grand_total))),
        "payable_total": money(payable), "customer": doc.customer,
        "customer_name": doc.customer_name, "due_date": str(doc.due_date) if doc.due_date else None,
        "tax_template": doc.taxes_and_charges or None, "no_tax": bool(doc.flags.get("knitting_tax_choice", {}).get("no_tax")),
        "items": [{"item": row.item_code, "quantity": format(Decimal(str(row.qty)).normalize(), "f"),
                   "rate": format(Decimal(str(row.rate)).normalize(), "f"), "amount": money(row.amount), "uom": row.uom} for row in doc.items],
        "taxes": [{"description": row.description, "account": row.account_head, "rate": str(row.rate),
                   "amount": money(row.tax_amount_after_discount_amount)} for row in doc.taxes]}


def invoice_signature(doc):
    return hashlib.sha256(json.dumps(invoice_review(doc), sort_keys=True, separators=(",", ":"), default=str).encode()).hexdigest()


@frappe.whitelist(methods=["POST"])
def invoice_preview(company, payload, modified=None):
    setup = permissions.require(company, "billing")
    frappe.db.sql('select name from `tabWorkspace Industry Setup` where name=%s for update',setup.name)
    permissions.require(company,'billing',current=True)
    data = frappe.parse_json(payload) if isinstance(payload, str) else payload
    if not isinstance(data, Mapping):
        frappe.throw("Review a structured invoice entry.")
    job = domain.reference("Knitting Job", data.get("job"), company, lock=True)
    from erp_extensions.api import _check_version, _preview_prices
    _check_version(job, modified)
    with _operation_savepoint("knitting_invoice_preview", preview=True):
        event = frappe._dict(company=company, job=job.name, name=None)
        with permissions.service_write(), _preview_prices():
            doc = domain.invoice(event, data, job, preview=True)
            doc.set("__islocal", True)
            doc._set_defaults()
            doc.set_docstatus()
            doc._action = "save"
            doc.check_permission("create")
            doc.run_method("before_validate")
            doc.run_method("validate")
            result = invoice_review(doc)
            result["preview_hash"] = invoice_signature(doc)
            return result
