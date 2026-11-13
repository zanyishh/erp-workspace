"""Knitting domain records and quantity invariants; no accounting mathematics in clients."""
from decimal import Decimal, InvalidOperation
from collections.abc import Mapping

import frappe
from frappe.utils import now_datetime

from . import permissions

ZERO = Decimal("0")


def decimal(value, *, positive=False, signed=False, precision=3):
    try:
        if isinstance(value, bool):
            raise ValueError()
        number = Decimal(str(value))
        if not number.is_finite() or abs(number) > Decimal("1000000000"):
            raise ValueError()
        if not signed and number < 0 or positive and number <= 0:
            raise ValueError()
        if number != number.quantize(Decimal(1).scaleb(-precision)):
            raise ValueError()
        return number
    except (InvalidOperation, ValueError, TypeError):
        frappe.throw("Enter a finite, valid quantity with the permitted precision.")


def kg(value):
    return f"{Decimal(str(value)):.3f}"


def money(value):
    return f"{Decimal(str(value)):.2f}"


def json_value(value, default=None):
    if value in (None, ""):
        return default
    return frappe.parse_json(value) if isinstance(value, str) else value


def insert(doctype, **values):
    return frappe.get_doc({"doctype": doctype, **values}).insert()


def reference(doctype, name, company=None):
    if not name:
        frappe.throw(f"Choose {doctype}.")
    doc = frappe.get_doc(doctype, name)
    doc.check_permission("read")
    if company and doc.meta.has_field("company") and doc.company != company:
        frappe.throw("The selected record belongs to another business.", frappe.PermissionError)
    return doc


def warehouse(name, company):
    doc = reference("Warehouse", name, company)
    if doc.is_group:
        frappe.throw("Choose a stock godown, not a warehouse group.")
    return doc.name


def settings(company):
    return json_value(permissions.profile(company).settings, {})


def job_events(job, kind=None):
    filters = {"job": job, "cancelled": 0}
    if kind:
        filters["kind"] = kind
    return frappe.get_all("Knitting Event", filters=filters,
                          fields=["name", "kind", "payload", "result", "occurred_at", "creation"], order_by="creation, name")


def lot_balance(lot, job=None, custodian="Warehouse"):
    rows = frappe.get_all("Knitting Ledger Entry", filters={"lot": lot, "job": job or ["is", "not set"], "custodian": custodian},
                          fields=["quantity_kg"])
    return sum((Decimal(row.quantity_kg) for row in rows), ZERO)


def ledger(event, lot, quantity, job=None, custodian="Warehouse", voucher=None, units="0"):
    return insert("Knitting Ledger Entry", company=event.company, job=job, lot=lot.name,
                  event=event.name, material_owner=lot.material_owner, party=lot.party,
                  custodian=custodian, warehouse=lot.warehouse, quantity_kg=kg(quantity), units=str(units),
                  voucher_type=voucher.doctype if voucher else None, voucher_name=voucher.name if voucher else None)


def balances(job):
    events = job_events(job)
    totals = {k: ZERO for k in ("received_kg", "consumed_kg", "returned_kg", "produced_kg", "delivered_kg", "billed_kg", "loss_kg")}
    for event in events:
        result = json_value(event.result, {})
        kind = event.kind
        key = {"receive_yarn": "received_kg", "allocate_yarn": "received_kg", "return_yarn": "returned_kg",
               "produce": "produced_kg", "subcontract_receive": "produced_kg", "deliver": "delivered_kg", "invoice": "billed_kg"}.get(kind)
        if key:
            totals[key] += Decimal(result.get("quantity_kg", "0"))
        if kind in ("produce", "repack_yarn"):
            totals["consumed_kg"] += Decimal(result.get("consumed_kg", "0"))
            totals["loss_kg"] += Decimal(result.get("loss_kg", "0"))
    entries = frappe.get_all("Knitting Ledger Entry", filters={"job": job}, fields=["quantity_kg", "custodian"])
    totals["yarn_kg"] = sum((Decimal(e.quantity_kg) for e in entries if e.custodian == "Warehouse"), ZERO)
    totals["subcontract_kg"] = sum((Decimal(e.quantity_kg) for e in entries if (e.custodian or "").startswith("SC:")), ZERO)
    rolls = frappe.get_all("Knitting Roll", filters={"job": job}, fields=["state", "weight_kg"])
    totals["fabric_kg"] = sum((Decimal(r.weight_kg) for r in rolls if r.state not in ("Delivered", "Split", "Cancelled")), ZERO)
    totals["unbilled_kg"] = totals["delivered_kg"] - totals["billed_kg"]
    return {key: kg(value) for key, value in totals.items()}


def programme(job, line):
    lines = json_value(job.programme, [])
    match = next((p for p in lines if p["id"] == line), None)
    if not match:
        frappe.throw("Choose a programme line belonging to this job.")
    return match


def create_job(event, data, job):
    customer = reference("Customer", data.get("customer"))
    mode, kind = data.get("material_mode", "Customer"), data.get("kind", "Order")
    if mode not in ("Customer", "Owned") or kind not in ("Order", "Sample"):
        frappe.throw("Choose valid material ownership and order/sample kind.")
    target = decimal(data.get("target_kg"), positive=True)
    lines = data.get("programme")
    if not isinstance(lines, list) or not lines or len(lines) > 100:
        frappe.throw("Add at least one fabric programme line.")
    seen, total = set(), ZERO
    for line in lines:
        if not isinstance(line, Mapping) or not isinstance(line.get("id"), str) or line["id"] in seen:
            frappe.throw("Each programme line needs a unique identity.")
        seen.add(line["id"])
        total += decimal(line.get("target_kg"), positive=True)
        if len(line.get("gsm", [])) > 2 or len(line.get("ll", [])) > 3:
            frappe.throw("Programme permits up to two GSM and three LL values.")
        if line.get("fabric_item"):
            reference("Item", line["fabric_item"])
    if total != target:
        frappe.throw("Programme line quantities must equal the job target.")
    service = data.get("service_item") or settings(event.company).get("service_item")
    if service:
        item = reference("Item", service)
        if item.is_stock_item:
            frappe.throw("Choose a non-stock knitting service item.")
    rate = decimal(data.get("rate", "0"), precision=2)
    job = insert("Knitting Job", company=event.company, customer=customer.name,
                 fabric_owner=customer.name if mode == "Customer" else None, kind=kind, material_mode=mode,
                 status="Running", target_kg=kg(target), programme=frappe.as_json(lines), revision=1,
                 rate=rate, service_item=service, due_date=data.get("due_date"), notes=data.get("notes"))
    return {"job": job.name, "quantity_kg": kg(target)}


def receive_yarn(event, data, job):
    from . import posting
    item = reference("Item", data.get("item"))
    if not item.is_stock_item:
        frappe.throw("Yarn receipts require a stock item measured in kilograms.")
    if item.stock_uom != "Kg":
        frappe.throw("Configure the yarn item's stock unit as Kg before receiving it.")
    owner = data.get("material_owner", "Customer")
    if owner not in ("Customer", "Owned"):
        frappe.throw("Choose Customer or Owned material.")
    party = data.get("party") if owner == "Customer" else None
    if owner == "Customer":
        reference("Customer", party)
        if job and (job.material_mode == "Owned" or party != job.fabric_owner):
            frappe.throw("The material owner does not match this job.")
    quantity = decimal(data.get("quantity_kg"), positive=True)
    units = decimal(data.get("units", "0"), precision=0)
    godown = warehouse(data.get("warehouse") or settings(event.company).get("warehouse"), event.company)
    lot = insert("Knitting Material Lot", company=event.company, item=item.name, party=party, material_owner=owner,
                 warehouse=godown, source_lot=data.get("source_lot"), specification=frappe.as_json(data.get("specification", {})))
    voucher = posting.stock(event, "Material Receipt", [{"item_code": item.name, "qty": quantity, "t_warehouse": godown,
                  "basic_rate": decimal(data.get("valuation_rate"), positive=True, precision=2)}]) if owner == "Owned" else None
    ledger(event, lot, quantity, job.name if job else None, voucher=voucher, units=units)
    return {"lot": lot.name, "quantity_kg": kg(quantity), "voucher": voucher.name if voucher else None}


def return_yarn(event, data, job):
    from . import posting
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = decimal(data.get("quantity_kg"), positive=True)
    if quantity > lot_balance(lot.name, job.name):
        frappe.throw("The return exceeds this job's remaining yarn.")
    voucher = posting.stock(event, "Material Issue", [{"item_code": lot.item, "qty": quantity, "s_warehouse": lot.warehouse}]) if lot.material_owner == "Owned" else None
    ledger(event, lot, -quantity, job.name, voucher=voucher)
    return {"lot": lot.name, "quantity_kg": kg(quantity), "voucher": voucher.name if voucher else None}


def allocate_yarn(event, data, job):
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = decimal(data.get("quantity_kg"), positive=True)
    if quantity > lot_balance(lot.name) or lot.material_owner == "Customer" and lot.party != job.fabric_owner:
        frappe.throw("The general lot does not have a matching available owner allocation.")
    ledger(event, lot, -quantity)
    ledger(event, lot, quantity, job.name)
    return {"lot": lot.name, "quantity_kg": kg(quantity)}


def transfer_yarn(event, data, job):
    from erp_extensions.api import _check_version
    target = reference("Knitting Job", data.get("target_job"), event.company)
    _check_version(target, data.get("target_modified"))
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = decimal(data.get("quantity_kg"), positive=True)
    if target.name == job.name or target.status != "Running" or quantity > lot_balance(lot.name, job.name):
        frappe.throw("Choose another running job and an available yarn quantity.")
    if lot.material_owner == "Customer" and lot.party != target.fabric_owner:
        frappe.throw("Transfer cannot change the material's owner.")
    ledger(event, lot, -quantity, job.name)
    ledger(event, lot, quantity, target.name)
    target.save()
    return {"lot": lot.name, "quantity_kg": kg(quantity), "target_job": target.name}


def repack_yarn(event, data, job):
    from . import posting
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    used, output, loss = (decimal(data.get(k), positive=k != "loss_kg") for k in ("input_kg", "output_kg", "loss_kg"))
    if used != output + loss or used > lot_balance(lot.name, job.name):
        frappe.throw("Processing output plus declared loss must equal available input kg.")
    units = decimal(data.get("output_units", 0), precision=0)
    new = insert("Knitting Material Lot", company=event.company, item=lot.item, party=lot.party,
        material_owner=lot.material_owner, warehouse=lot.warehouse, source_lot=lot.name, specification=lot.specification,
        charge_item=lot.charge_item, charge_rate=lot.charge_rate)
    voucher = posting.stock(event, "Repack", [{"item_code": lot.item, "qty": used, "s_warehouse": lot.warehouse},
        {"item_code": lot.item, "qty": output, "t_warehouse": lot.warehouse, "is_finished_item": 1}]) if lot.material_owner == "Owned" else None
    ledger(event, lot, -used, job.name, voucher=voucher)
    ledger(event, new, output, job.name, voucher=voucher, units=units)
    return {"lot": new.name, "input_lot": lot.name, "quantity_kg": kg(output), "loss_kg": kg(loss),
            "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def revise_job(event, data, job):
    if not data.get("reason"):
        frappe.throw("Give a reason for the programme or commercial revision.")
    before = {"rate": money(job.rate or 0), "programme": json_value(job.programme, []), "target_kg": job.target_kg}
    if "rate" in data:
        job.rate = decimal(data["rate"], precision=2)
    if "programme" in data:
        lines = data["programme"]
        if not isinstance(lines, list) or not lines or len({p.get("id") for p in lines}) != len(lines):
            frappe.throw("Revision needs distinct programme line identities.")
        for line in json_value(job.programme, []):
            produced = sum((Decimal(r.weight_kg) for r in frappe.get_all("Knitting Roll",
                filters={"job": job.name, "programme_line": line["id"], "state": ["not in", ["Split", "Cancelled"]]}, fields=["weight_kg"])), ZERO)
            replacement = next((p for p in lines if p.get("id") == line["id"]), None)
            if produced and (replacement is None or decimal(replacement["target_kg"]) < produced):
                frappe.throw("A revision cannot discard already produced fabric.")
        job.target_kg = kg(sum((decimal(p["target_kg"], positive=True) for p in lines), ZERO))
        job.programme = frappe.as_json(lines)
    job.revision += 1
    job.save()
    return {"job": job.name, "revision": job.revision, "previous": before, "reason": data["reason"]}


def split_roll(event, data, job):
    roll = reference("Knitting Roll", data.get("roll"), event.company)
    weights = data.get("weights_kg")
    if roll.job != job.name or roll.state in ("Delivered", "Split", "Cancelled") or not data.get("reason"):
        frappe.throw("Only an undelivered roll can be split, with a recorded reason.")
    if not isinstance(weights, list) or not 2 <= len(weights) <= 100:
        frappe.throw("Enter two to 100 child roll weights.")
    weights = [decimal(w, positive=True) for w in weights]
    if sum(weights, ZERO) != Decimal(roll.weight_kg):
        frappe.throw("Child roll weights must equal the original roll weight.")
    children = []
    for weight in weights:
        child = insert("Knitting Roll", **{key: roll.get(key) for key in ("company", "job", "programme_line", "job_revision", "fabric_item",
            "warehouse", "machine", "operator", "shift", "produced_at", "state", "production", "specification")},
            weight_kg=kg(weight), parent_roll=roll.name)
        children.append(child.name)
    previous = roll.state
    roll.state = "Split"
    roll.save()
    return {"rolls": children, "parent_roll": roll.name, "quantity_kg": roll.weight_kg, "previous_state": previous}


def produce(event, data, job):
    from . import posting
    line = programme(job, data.get("programme_line"))
    weights = data.get("weights_kg")
    if not isinstance(weights, list) or not weights or len(weights) > 200:
        frappe.throw("Enter between one and 200 roll weights.")
    weights = [decimal(w, positive=True) for w in weights]
    quantity, loss = sum(weights, ZERO), decimal(data.get("loss_kg", "0"))
    produced = sum((Decimal(r.weight_kg) for r in frappe.get_all("Knitting Roll",
        filters={"job": job.name, "programme_line": line["id"], "state": ["not in", ["Cancelled", "Split"]]}, fields=["weight_kg"])), ZERO)
    excess = decimal(settings(event.company).get("allow_production_excess_pct", "0"))
    if produced + quantity > decimal(line["target_kg"]) * (Decimal(1) + excess / 100):
        frappe.throw("Roll production exceeds the remaining programme.")
    inputs = data.get("inputs")
    if not isinstance(inputs, list) or not inputs or len(inputs) > 100:
        frappe.throw("Select the source yarn lots and actual consumption.")
    lots, total, seen = [], ZERO, set()
    for entry in inputs:
        lot = reference("Knitting Material Lot", entry.get("lot"), event.company)
        consumed = decimal(entry.get("quantity_kg"), positive=True)
        if lot.name in seen or consumed > lot_balance(lot.name, job.name):
            frappe.throw("Yarn consumption exceeds the selected lot allocation.")
        seen.add(lot.name)
        if lot.material_owner == "Customer" and (job.material_mode != "Customer" or lot.party != job.fabric_owner):
            frappe.throw("A different owner's material cannot be consumed by this job.")
        if entry.get("charge_item"):
            item = reference("Item", entry["charge_item"])
            if item.is_stock_item:
                frappe.throw("A separate material charge must use a non-stock billing item.")
            decimal(entry.get("charge_rate"), precision=2)
        lots.append((lot, consumed, entry))
        total += consumed
    if total != quantity + loss:
        frappe.throw("Consumed kg must equal fabric kg plus the explicitly declared process loss.")
    godown = warehouse(data.get("warehouse") or settings(event.company).get("warehouse"), event.company)
    machine = reference("Knitting Machine", data["machine"], event.company) if data.get("machine") else None
    if machine and not machine.enabled:
        frappe.throw("The selected machine is unavailable.")
    fabric_item = line.get("fabric_item") or settings(event.company).get("fabric_item")
    owned_rows = [{"item_code": lot.item, "qty": used, "s_warehouse": lot.warehouse} for lot, used, _ in lots if lot.material_owner == "Owned"]
    voucher = None
    if job.material_mode == "Owned":
        item = reference("Item", fabric_item)
        if not item.is_stock_item or item.stock_uom != "Kg":
            frappe.throw("Owned fabric requires a stock item measured in Kg.")
        owned_rows.append({"item_code": fabric_item, "qty": quantity, "t_warehouse": godown, "is_finished_item": 1})
        voucher = posting.stock(event, "Repack", owned_rows)
    elif owned_rows:
        voucher = posting.stock(event, "Material Issue", owned_rows)
    for lot, used, _ in lots:
        ledger(event, lot, -used, job.name, voucher=voucher if lot.material_owner == "Owned" else None)
    rolls = []
    for weight in weights:
        roll = insert("Knitting Roll", company=event.company, job=job.name, programme_line=line["id"],
            job_revision=job.revision, weight_kg=kg(weight), fabric_item=fabric_item, warehouse=godown,
            machine=machine.name if machine else None, operator=frappe.session.user, shift=data.get("shift"),
            produced_at=event.occurred_at, state="Awaiting QC", production=event.name, specification=frappe.as_json(line))
        rolls.append(roll.name)
    return {"rolls": rolls, "quantity_kg": kg(quantity), "consumed_kg": kg(total), "loss_kg": kg(loss),
            "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def quality(event, data, job):
    roll = reference("Knitting Roll", data.get("roll"), event.company)
    if roll.job != job.name or roll.state in ("Delivered", "Split", "Cancelled"):
        frappe.throw("This roll cannot be inspected in the selected job.")
    decision = data.get("decision")
    if decision not in ("Released", "On Hold", "Rework", "Rejected"):
        frappe.throw("Choose a quality decision.")
    previous = roll.state
    check = insert("Knitting QC", company=event.company, job=job.name, roll=roll.name, checker=frappe.session.user,
        decision=decision, defects=frappe.as_json(data.get("defects", [])), remarks=data.get("remarks"), event=event.name)
    roll.state = decision
    roll.save()
    return {"inspection": check.name, "roll": roll.name, "previous_state": previous, "decision": decision}


def deliver(event, data, job):
    from . import posting
    names = data.get("rolls")
    if not isinstance(names, list) or not names or len(set(names)) != len(names):
        frappe.throw("Select distinct rolls to deliver.")
    rolls = [reference("Knitting Roll", name, event.company) for name in names]
    if any(r.job != job.name or r.state != "Released" for r in rolls):
        frappe.throw("Only released, undelivered rolls from this job can be delivered.")
    voucher = posting.delivery(event, job, rolls) if job.material_mode == "Owned" else None
    for roll in rolls:
        roll.state, roll.delivery = "Delivered", event.name
        roll.save()
    return {"rolls": names, "quantity_kg": kg(sum((Decimal(r.weight_kg) for r in rolls), ZERO)), "rate": money(job.rate or 0),
            "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def delivery_billed(job, delivery):
    total = ZERO
    for event in job_events(job, "invoice"):
        for row in json_value(event.result, {}).get("allocations", []):
            if row["delivery"] == delivery:
                total += Decimal(row["quantity_kg"])
    return total


def invoice(event, data, job):
    from . import posting
    names = data.get("deliveries")
    if not isinstance(names, list) or not names or len(set(names)) != len(names):
        frappe.throw("Select distinct confirmed source deliveries.")
    remaining = decimal(data["quantity_kg"], positive=True) if data.get("quantity_kg") else None
    allocations, rows, total = [], [], ZERO
    for name in names:
        source = reference("Knitting Event", name, event.company)
        if source.job != job.name or source.kind != "deliver" or source.cancelled:
            frappe.throw("Invoice sources must be confirmed deliveries from this job.")
        value = json_value(source.result, {})
        available = Decimal(value["quantity_kg"]) - delivery_billed(job.name, name)
        quantity = min(available, remaining) if remaining is not None else available
        if quantity <= 0:
            continue
        rate = decimal(value.get("rate", job.rate), precision=2)
        item = job.service_item if job.material_mode == "Customer" else reference("Knitting Roll", value["rolls"][0], event.company).fabric_item
        if not item:
            frappe.throw("Configure the service or fabric billing item before invoicing.")
        rows.append({"item_code": item, "qty": quantity, "rate": rate, "knitting_delivery": name})
        allocations.append({"delivery": name, "quantity_kg": kg(quantity)})
        total += quantity
        if remaining is not None:
            remaining -= quantity
    if total <= 0 or remaining is not None and remaining > 0:
        frappe.throw("The invoice exceeds the confirmed unbilled delivery quantity.")
    # Charge auxiliary owned inputs proportionally to fabric billed, without issuing stock again.
    if job.material_mode == "Customer" and settings(event.company).get("lycra_charge") == "Separate":
        produced = Decimal(balances(job.name)["produced_kg"])
        for production in job_events(job.name, "produce"):
            for source in json_value(production.payload, {}).get("inputs", []):
                if source.get("charge_item"):
                    lot = reference("Knitting Material Lot", source["lot"], event.company)
                    if lot.material_owner == "Owned":
                        rows.append({"item_code": source["charge_item"], "qty": Decimal(source["quantity_kg"]) * total / produced,
                                     "rate": decimal(source["charge_rate"], precision=2)})
    doc = posting.invoice(event, job, rows)
    return {"invoice": doc.name, "quantity_kg": kg(total), "amount": money(doc.grand_total), "allocations": allocations,
            "voucher": doc.name, "voucher_type": "Sales Invoice"}


def close_job(event, data, job):
    value = balances(job.name)
    if any(Decimal(value[key]) != 0 for key in ("yarn_kg", "fabric_kg", "unbilled_kg", "subcontract_kg")):
        frappe.throw("Reconcile remaining yarn, fabric, subcontract custody and unbilled deliveries before closure.")
    if Decimal(value["produced_kg"]) < Decimal(job.target_kg):
        frappe.throw("Complete or explicitly revise the remaining programme before closure.")
    job.status = "Completed"
    job.save()
    return {"job": job.name, "status": job.status}


def reopen_job(event, data, job):
    if not data.get("reason"):
        frappe.throw("Give a reason for reopening the job.")
    job.status = "Running"
    job.save()
    return {"job": job.name, "status": job.status}


def cancel_event(event, data, job):
    source = reference("Knitting Event", data.get("event"), event.company)
    if source.job != job.name or source.cancelled or not data.get("reason"):
        frappe.throw("Choose an active source event and give a correction reason.")
    result = json_value(source.result, {})
    if source.kind == "deliver" and delivery_billed(job.name, source.name) > 0:
        frappe.throw("Cancel or credit dependent invoices before cancelling this delivery.")
    if source.kind not in ("invoice", "deliver", "quality"):
        frappe.throw("This event has material dependencies; use an explicit return, transfer or adjustment.")
    if result.get("voucher"):
        doc = reference(result["voucher_type"], result["voucher"], event.company)
        doc.check_permission("cancel")
        doc.cancel()
    if source.kind == "deliver":
        for name in result["rolls"]:
            roll = reference("Knitting Roll", name, event.company)
            roll.state, roll.delivery = "Released", None
            roll.save()
    if source.kind == "quality":
        roll = reference("Knitting Roll", result["roll"], event.company)
        if roll.state == "Delivered" or frappe.db.exists("Knitting QC", {"roll": roll.name, "creation": [">", source.creation]}):
            frappe.throw("A later inspection or delivery depends on this quality decision.")
        roll.state = result["previous_state"]
        roll.save()
    source.cancelled = 1
    source.save()
    event.reverses = source.name
    return {"cancelled_event": source.name, "reason": data["reason"]}


ACTIONS = {
    "create_job": ("new_job", create_job), "receive_yarn": ("materials", receive_yarn),
    "return_yarn": ("materials", return_yarn), "allocate_yarn": ("materials", allocate_yarn), "transfer_yarn": ("materials", transfer_yarn),
    "repack_yarn": ("materials", repack_yarn), "revise_job": ("new_job", revise_job), "split_roll": ("production", split_roll),
    "produce": ("production", produce), "quality": ("quality", quality),
    "deliver": ("delivery", deliver), "invoice": ("billing", invoice), "close_job": ("lifecycle", close_job),
    "reopen_job": ("lifecycle", reopen_job), "cancel_event": ("lifecycle", cancel_event),
}
