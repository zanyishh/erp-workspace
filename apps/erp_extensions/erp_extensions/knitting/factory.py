"""Factory planning, subcontract custody and maintenance over the canonical event service."""
from datetime import timedelta
from decimal import Decimal

import frappe
from frappe.utils import get_datetime, getdate, now_datetime, today

from . import domain as d, posting


def create_machine(event, data, job):
    if not str(data.get("title", "")).strip() or not data.get("dia") or not data.get("gauge"):
        frappe.throw("Name the machine and specify dia and gauge.")
    capacity = d.decimal(data.get("capacity_kg"), positive=True)
    workstation = data.get("workstation")
    if workstation:
        d.reference("Workstation", workstation)
    else:
        workstation = frappe.get_doc({"doctype": "Workstation", "workstation_name": data["title"] + " " + frappe.generate_hash(length=5),
                                       "production_capacity": 1}).insert().name
    machine = d.insert("Knitting Machine", company=event.company, title=data["title"], workstation=workstation,
        dia=str(data["dia"]), gauge=str(data["gauge"]), knit_type=data.get("knit_type", "Tubular"),
        capacity_kg=d.kg(capacity), enabled=1)
    return {"machine": machine.name}


def holiday(event, data, job):
    if data.get("machine"):
        d.reference("Knitting Machine", data["machine"], event.company)
    day = getdate(data.get("date"))
    record = d.insert("Knitting Holiday", company=event.company, machine=data.get("machine"), date=day,
                      description=data.get("description", "Factory holiday"))
    return {"holiday": record.name, "date": str(day)}


def interval(data):
    if not data.get("starts_at") or not data.get("ends_at"):
        frappe.throw("Choose a start and finish time.")
    start, end = get_datetime(data["starts_at"]), get_datetime(data["ends_at"])
    if end <= start or end - start > timedelta(days=31):
        frappe.throw("The finish must follow the start within a 31-day planning window.")
    return start, end


def plan(event, data, job):
    from erp_extensions.api import _check_version
    machine = d.reference("Knitting Machine", data.get("machine"), event.company)
    line = d.programme(job, data.get("programme_line"))
    start, end = interval(data)
    quantity = d.decimal(data.get("quantity_kg"), positive=True)
    if not machine.enabled or any(str(line.get(k, "")).casefold() != str(machine.get(k, "")).casefold()
                                  for k in ("dia", "gauge", "knit_type") if line.get(k)):
        frappe.throw("The selected machine is not compatible with this programme.")
    if quantity > d.decimal(machine.capacity_kg) * Decimal(str((end - start).total_seconds())) / Decimal(8 * 3600):
        frappe.throw("The planned kg exceeds this machine's available capacity.")
    days = frappe.get_all("Knitting Holiday", filters={"company": event.company, "date": ["between", [start.date(), (end - timedelta(microseconds=1)).date()]]}, fields=["machine"])
    if any(not row.machine or row.machine == machine.name for row in days):
        frappe.throw("The allocation overlaps a holiday or machine shutdown.")
    record = d.reference("Knitting Plan", data["plan"], event.company) if data.get("plan") else None
    if record:
        _check_version(record, data.get("plan_modified"))
        if record.job != job.name or record.state not in ("Planned", "Started"):
            frappe.throw("Choose an active allocation from this job.")
    existing = frappe.get_all("Knitting Plan", filters={"company": event.company, "state": ["in", ["Planned", "Started"]]},
                             fields=["name", "job", "machine", "starts_at", "ends_at", "quantity_kg"])
    for row in existing:
        if record and row.name == record.name:
            continue
        if row.machine == machine.name and row.starts_at < end and row.ends_at > start:
            frappe.throw("Another allocation already occupies that machine/time.")
    allocated = sum((Decimal(r.quantity_kg) for r in existing if r.job == job.name and (not record or r.name != record.name)), d.ZERO)
    if allocated + quantity > Decimal(job.target_kg):
        frappe.throw("The plan exceeds this job's programme quantity.")
    for row in frappe.get_all("Knitting Event", filters={"company": event.company, "kind": "stoppage", "cancelled": 0}, fields=["payload"]):
        value = d.json_value(row.payload, {})
        if value.get("machine") == machine.name and get_datetime(value["starts_at"]) < end and get_datetime(value["ends_at"]) > start:
            frappe.throw("The allocation overlaps recorded machine stoppage.")
    previous = record.as_dict() if record else None
    record = record or frappe.new_doc("Knitting Plan")
    record.update({"company": event.company, "job": job.name, "machine": machine.name, "starts_at": start,
                   "ends_at": end, "quantity_kg": d.kg(quantity), "state": "Planned", "event": event.name})
    record.save()
    return {"plan": record.name, "machine": machine.name, "quantity_kg": d.kg(quantity), "previous": previous}


def create_component(event, data, job):
    machine = d.reference("Knitting Machine", data.get("machine"), event.company)
    if data.get("component_type") not in ("Needle", "Sinker", "Cylinder", "Dial"):
        frappe.throw("Choose a supported machine component.")
    boundary = d.decimal(data.get("boundary_kg"), positive=True)
    component = d.insert("Knitting Component", company=event.company, machine=machine.name,
        component_type=data["component_type"], item=data.get("item"), boundary_kg=d.kg(boundary), run_kg="0.000", installed_at=event.occurred_at)
    return {"component": component.name}


def replace_component(event, data, job):
    component = d.reference("Knitting Component", data.get("component"), event.company)
    if not data.get("reason"):
        frappe.throw("Give the reason for replacement.")
    previous = component.run_kg
    component.run_kg, component.installed_at = "0.000", event.occurred_at
    if data.get("boundary_kg"):
        component.boundary_kg = d.kg(d.decimal(data["boundary_kg"], positive=True))
    component.save()
    return {"component": component.name, "machine": component.machine, "previous_run_kg": previous,
            "boundary_kg": component.boundary_kg, "reason": data["reason"]}


def stoppage(event, data, job):
    machine = d.reference("Knitting Machine", data.get("machine"), event.company)
    start, end = interval(data)
    if not data.get("reason"):
        frappe.throw("Record the stoppage reason.")
    return {"machine": machine.name, "minutes": str(Decimal(str((end - start).total_seconds())) / 60),
            "starts_at": str(start), "ends_at": str(end), "reason": data["reason"]}


def create_subcontract(event, data, job):
    supplier = d.reference("Supplier", data.get("supplier"))
    quantity, rate = d.decimal(data.get("target_kg"), positive=True), d.decimal(data.get("rate", "0"), precision=2)
    if quantity > Decimal(job.target_kg):
        frappe.throw("The subcontract cannot exceed the programme.")
    config = d.settings(event.company)
    service = d.reference("Item", data.get("service_item") or job.service_item or config.get("service_item"))
    if service.is_stock_item:
        frappe.throw("Subcontract service uses a non-stock purchase item.")
    godown = data.get("warehouse")
    if job.material_mode == "Owned":
        if godown:
            d.warehouse(godown, event.company)
        else:
            parent = frappe.db.get_value("Warehouse", {"company": event.company, "is_group": 1, "parent_warehouse": ["is", "not set"]}, "name")
            godown = frappe.get_doc({"doctype": "Warehouse", "warehouse_name": "Knitting SC " + frappe.generate_hash(length=7),
                "company": event.company, "parent_warehouse": parent, "is_group": 0}).insert().name
    order = frappe.get_doc({"doctype": "Purchase Order", "company": event.company, "supplier": supplier.name,
        "schedule_date": today(), "knitting_event": event.name, "knitting_job": job.name,
        "items": [{"item_code": service.name, "qty": quantity, "rate": rate, "schedule_date": today()}]})
    posting.submit(order)
    sub = d.insert("Knitting Subcontract", company=event.company, job=job.name, supplier=supplier.name,
        target_kg=d.kg(quantity), rate=rate, status="Open", warehouse=godown, purchase_order=order.name, service_item=service.name)
    return {"subcontract": sub.name, "purchase_order": order.name, "quantity_kg": d.kg(quantity)}


def subcontract(data, job, company):
    sub = d.reference("Knitting Subcontract", data.get("subcontract"), company)
    if sub.job != job.name or sub.status != "Open":
        frappe.throw("Choose an open subcontract belonging to this job.")
    return sub


def subcontract_issue(event, data, job):
    sub = subcontract(data, job, event.company)
    lot = d.reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = d.decimal(data.get("quantity_kg"), positive=True)
    if quantity > d.lot_balance(lot.name, job.name):
        frappe.throw("The issue exceeds the source job's available yarn.")
    if lot.material_owner == "Customer" and lot.party != job.fabric_owner:
        frappe.throw("The material owner does not match the subcontract job.")
    voucher = posting.stock(event, "Material Transfer", [{"item_code": lot.item, "qty": quantity,
        "s_warehouse": lot.warehouse, "t_warehouse": sub.warehouse}]) if lot.material_owner == "Owned" else None
    d.ledger(event, lot, -quantity, job.name, voucher=voucher)
    d.ledger(event, lot, quantity, job.name, custodian="SC:" + sub.name, voucher=voucher)
    return {"subcontract": sub.name, "lot": lot.name, "quantity_kg": d.kg(quantity), "voucher": voucher.name if voucher else None}


def sc_events(sub, kind):
    return [r for r in d.job_events(sub.job, kind) if d.json_value(r.result, {}).get("subcontract") == sub.name]


def subcontract_receive(event, data, job):
    sub = subcontract(data, job, event.company)
    received = sum((Decimal(d.json_value(r.result, {})["quantity_kg"]) for r in sc_events(sub, "subcontract_receive")), d.ZERO)
    quantity = sum((d.decimal(w, positive=True) for w in data.get("weights_kg", [])), d.ZERO)
    if quantity <= 0 or received + quantity > Decimal(sub.target_kg):
        frappe.throw("Fabric receipt exceeds the subcontract target.")
    extra = None
    if job.material_mode == "Owned":
        _, defaults = posting.common(event)
        extra = [{"expense_account": defaults["expense_account"], "description": "Agreed subcontract service",
                  "amount": quantity * Decimal(str(sub.rate))}]
    result = d.produce(event, data, job, custodian="SC:" + sub.name, source_warehouse=sub.warehouse, additional_costs=extra)
    result["subcontract"] = sub.name
    return result


def subcontract_return(event, data, job):
    sub = subcontract(data, job, event.company)
    lot = d.reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = d.decimal(data.get("quantity_kg"), positive=True)
    if quantity > d.lot_balance(lot.name, job.name, "SC:" + sub.name):
        frappe.throw("The return exceeds material held at this subcontractor.")
    voucher = posting.stock(event, "Material Transfer", [{"item_code": lot.item, "qty": quantity,
        "s_warehouse": sub.warehouse, "t_warehouse": lot.warehouse}]) if lot.material_owner == "Owned" else None
    d.ledger(event, lot, -quantity, job.name, custodian="SC:" + sub.name, voucher=voucher)
    d.ledger(event, lot, quantity, job.name, voucher=voucher)
    return {"subcontract": sub.name, "quantity_kg": d.kg(quantity), "lot": lot.name, "voucher": voucher.name if voucher else None}


def subcontract_bill(event, data, job):
    sub = subcontract(data, job, event.company)
    received = sum((Decimal(d.json_value(r.result, {})["quantity_kg"]) for r in sc_events(sub, "subcontract_receive")), d.ZERO)
    billed = sum((Decimal(d.json_value(r.result, {})["quantity_kg"]) for r in sc_events(sub, "subcontract_bill")), d.ZERO)
    quantity = d.decimal(data.get("quantity_kg", received - billed), positive=True)
    if quantity > received - billed:
        frappe.throw("The subcontract bill exceeds unbilled received fabric.")
    from erpnext.buying.doctype.purchase_order.purchase_order import make_purchase_invoice
    doc = make_purchase_invoice(sub.purchase_order)
    doc.flags = frappe._dict()
    for row in doc.get_all_children():
        row.flags = frappe._dict()
    if len(doc.items) != 1:
        frappe.throw("The subcontract purchase source does not match its single service item.")
    doc.items[0].qty = quantity
    if job.material_mode == "Owned":
        doc.items[0].expense_account = posting.common(event)[1]["expense_account"]
    doc.knitting_event, doc.knitting_job = event.name, job.name
    posting.submit(doc)
    return {"subcontract": sub.name, "invoice": doc.name, "quantity_kg": d.kg(quantity), "amount": d.money(doc.grand_total),
            "voucher": doc.name, "voucher_type": doc.doctype}


def close_subcontract(event, data, job):
    sub = subcontract(data, job, event.company)
    entries = frappe.get_all("Knitting Ledger Entry", filters={"company": event.company, "job": job.name, "custodian": "SC:" + sub.name}, fields=["quantity_kg"])
    remaining = sum((Decimal(r.quantity_kg) for r in entries), d.ZERO)
    received = sum((Decimal(d.json_value(r.result, {})["quantity_kg"]) for r in sc_events(sub, "subcontract_receive")), d.ZERO)
    billed = sum((Decimal(d.json_value(r.result, {})["quantity_kg"]) for r in sc_events(sub, "subcontract_bill")), d.ZERO)
    if remaining != 0 or received != Decimal(sub.target_kg) or billed != received:
        frappe.throw("Reconcile subcontract custody, fabric receipt and bills before completion.")
    sub.status = "Completed"
    sub.save()
    return {"subcontract": sub.name, "status": sub.status}


def issue_consumable(event, data, job):
    item = d.reference("Item", data.get("item"))
    if not item.is_stock_item or not data.get("reason"):
        frappe.throw("Select a stock item and give an issue reason.")
    quantity = d.decimal(data.get("quantity"), positive=True)
    godown = d.warehouse(data.get("warehouse") or d.settings(event.company).get("warehouse"), event.company)
    lot = d.reference("Knitting Material Lot", data["lot"], event.company) if data.get("lot") else None
    if lot and (lot.item != item.name or lot.material_owner != "Owned" or quantity > d.lot_balance(lot.name, job.name if job else None)):
        frappe.throw("Consumable issue must use an available owned lot.")
    if data.get("machine"):
        d.reference("Knitting Machine", data["machine"], event.company)
    voucher = posting.stock(event, "Material Issue", [{"item_code": item.name, "qty": quantity, "s_warehouse": godown}])
    if lot:
        d.ledger(event, lot, -quantity, job.name if job else None, voucher=voucher)
    return {"item": item.name, "quantity": d.kg(quantity), "lot": lot.name if lot else None, "warehouse": godown,
            "valuation_rate": d.money(voucher.items[0].basic_rate), "voucher": voucher.name, "voucher_type": voucher.doctype}


def return_consumable(event, data, job):
    source = d.reference("Knitting Event", data.get("event"), event.company)
    if source.kind != "issue_consumable" or source.cancelled or source.job != (job.name if job else None) or not data.get("reason"):
        frappe.throw("Choose a matching consumable issue and return reason.")
    value = d.json_value(source.result, {})
    quantity = d.decimal(data.get("quantity"), positive=True)
    returned = sum((Decimal(d.json_value(r.result, {}).get("quantity", "0")) for r in d.job_events(source.job, "return_consumable")
                    if d.json_value(r.result, {}).get("issue") == source.name), d.ZERO)
    if quantity + returned > Decimal(value["quantity"]):
        frappe.throw("Return exceeds the original unused issue quantity.")
    voucher = posting.stock(event, "Material Receipt", [{"item_code": value["item"], "qty": quantity,
        "t_warehouse": value["warehouse"], "basic_rate": value["valuation_rate"]}])
    if value.get("lot"):
        lot = d.reference("Knitting Material Lot", value["lot"], event.company)
        d.ledger(event, lot, quantity, job.name if job else None, voucher=voucher)
    return {"issue": source.name, "quantity": d.kg(quantity), "voucher": voucher.name, "voucher_type": voucher.doctype}


def create_estimate(event, data, job):
    customer = d.reference("Customer", data.get("customer"))
    service = d.reference("Item", data.get("service_item") or d.settings(event.company).get("service_item"))
    if service.is_stock_item:
        frappe.throw("Estimate the knitting service with a non-stock item.")
    quantity, rate = d.decimal(data.get("target_kg"), positive=True), d.decimal(data.get("rate"), precision=2)
    lines = data.get("programme")
    if not isinstance(lines, list) or sum((d.decimal(p["target_kg"], positive=True) for p in lines), d.ZERO) != quantity:
        frappe.throw("Estimate programme lines must equal its quantity.")
    quote = frappe.get_doc({"doctype": "Quotation", "company": event.company, "quotation_to": "Customer", "party_name": customer.name,
        "knitting_event": event.name, "knitting_programme": frappe.as_json(lines), "knitting_material_mode": data.get("material_mode", "Customer"),
        "items": [{"item_code": service.name, "qty": quantity, "rate": rate}]})
    quote.insert()
    return {"quotation": quote.name, "modified": str(quote.modified), "quantity_kg": d.kg(quantity), "amount": d.money(quote.grand_total)}


def estimate_source(data, company):
    from erp_extensions.api import _check_version
    quote = d.reference("Quotation", data.get("quotation"), company)
    _check_version(quote, data.get("quotation_modified"))
    if not quote.knitting_event or quote.quotation_to != "Customer" or len(quote.items) != 1:
        frappe.throw("Choose an original knitting estimate with one trusted service line.")
    return quote


def accept_estimate(event, data, job):
    quote = estimate_source(data, event.company)
    if quote.docstatus != 0:
        frappe.throw("Only a draft estimate can be accepted.")
    quote.submit()
    return {"quotation": quote.name, "modified": str(quote.modified)}


def job_from_estimate(event, data, job):
    quote = estimate_source(data, event.company)
    if quote.docstatus != 1 or frappe.db.exists("Knitting Job", {"quotation": quote.name}):
        frappe.throw("Accept this estimate first; it can create only one knitting job.")
    row = quote.items[0]
    result = d.create_job(event, {"customer": quote.party_name, "target_kg": d.kg(row.qty), "rate": d.money(row.rate),
        "service_item": row.item_code, "programme": d.json_value(quote.knitting_programme, []),
        "material_mode": quote.knitting_material_mode or "Customer"}, None)
    created = frappe.get_doc("Knitting Job", result["job"])
    created.quotation = quote.name
    created.save()
    event.job = created.name
    return result


def create_rate(event, data, job):
    customer = d.reference("Customer", data.get("customer"))
    if not data.get("fabric"):
        frappe.throw("Choose the fabric for the agreed party rate.")
    config = d.settings(event.company)
    if config.get("rate_lookup") == "FabricCountGauge" and (not data.get("yarn_count") or not data.get("gauge")):
        frappe.throw("This business prices by fabric, yarn count and gauge.")
    row = d.insert("Knitting Rate", company=event.company, customer=customer.name, fabric=data["fabric"],
        yarn_count=data.get("yarn_count"), gauge=data.get("gauge"), rate=d.decimal(data.get("rate"), precision=2),
        effective_from=getdate(data.get("effective_from") or today()))
    return {"rate_record": row.name}


ACTIONS = {"create_machine": ("factory", create_machine), "holiday": ("planning", holiday), "plan": ("planning", plan),
    "create_component": ("factory", create_component), "replace_component": ("factory", replace_component), "stoppage": ("factory", stoppage),
    "create_subcontract": ("factory", create_subcontract), "subcontract_issue": ("materials", subcontract_issue),
    "subcontract_receive": ("factory", subcontract_receive), "subcontract_return": ("materials", subcontract_return),
    "subcontract_bill": ("billing", subcontract_bill), "close_subcontract": ("factory", close_subcontract),
    "issue_consumable": ("factory", issue_consumable), "return_consumable": ("factory", return_consumable),
    "create_estimate": ("billing", create_estimate), "accept_estimate": ("billing", accept_estimate), "job_from_estimate": ("new_job", job_from_estimate),
    "create_rate": ("billing", create_rate)}

JOB_OPTIONAL = {"create_machine", "holiday", "create_component", "replace_component", "stoppage", "create_estimate", "accept_estimate", "job_from_estimate",
                "issue_consumable", "return_consumable", "create_rate"}
