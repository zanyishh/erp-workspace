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


def current_rows(doctype, filters=None, fields=None, order_by=None, limit=None, pluck=None):
    """Current reads after a company lock, even under MariaDB repeatable-read snapshots."""
    if frappe.flags.get("knitting_service_write"):
        return frappe.db.get_values(doctype, filters, pluck or fields or ["name"], as_dict=not bool(pluck),
            for_update=True, order_by=order_by or "creation, name", limit=limit, pluck=bool(pluck))
    return frappe.get_all(doctype, filters=filters, fields=fields, order_by=order_by, limit=limit, pluck=pluck)


def insert(doctype, **values):
    from frappe.model.naming import make_autoname
    tags = {"Knitting Job": "JOB", "Knitting Event": "EVT", "Knitting Roll": "ROLL", "Knitting Material Lot": "LOT",
            "Knitting Machine": "MC", "Knitting Plan": "PLAN", "Knitting QC": "QC", "Knitting Subcontract": "SC", "Knitting Component": "COMP"}
    if doctype in tags and values.get("company"):
        abbr = frappe.get_cached_value("Company", values["company"], "abbr")
        prefix = settings(values["company"]).get("number_prefix", "KN")
        values["name"] = make_autoname(f"{prefix}-{abbr}-{tags[doctype]}-.YYYY.-.#####")
    return frappe.get_doc({"doctype": doctype, **values}).insert(set_name=values.get("name"))


def reference(doctype, name, company=None, *, lock=False):
    if not name:
        frappe.throw(f"Choose {doctype}.")
    doc = frappe.get_doc(doctype, name, for_update=lock or bool(frappe.flags.get("knitting_service_write")))
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
    where = "(job=%s or target_job=%s)" if job else "job is null"
    values = [job, job] if job else []
    if kind:
        where += " and kind=%s"
        values.append(kind)
    return frappe.db.sql("select name, job, target_job, kind, payload, result, occurred_at, creation from `tabKnitting Event` where cancelled=0 and " + where +
        " order by creation, name" + (" for update" if frappe.flags.get("knitting_service_write") else ""), values, as_dict=True)


def lot_balance(lot, job=None, custodian="Warehouse"):
    rows = current_rows("Knitting Ledger Entry", filters={"lot": lot, "job": job or ["is", "not set"], "custodian": custodian},
                          fields=["quantity_kg"])
    return sum((Decimal(row.quantity_kg) for row in rows), ZERO)


def ledger(event, lot, quantity, job=None, custodian="Warehouse", voucher=None, units="0"):
    return insert("Knitting Ledger Entry", company=event.company, job=job, lot=lot.name,
                  event=event.name, material_owner=lot.material_owner, party=lot.party,
                  custodian=custodian, warehouse=lot.warehouse, quantity_kg=kg(quantity), units=str(units),
                  voucher_type=voucher.doctype if voucher else None, voucher_name=voucher.name if voucher else None)


def balances(job):
    events = job_events(job)
    totals = {k: ZERO for k in ("received_kg", "consumed_kg", "returned_kg", "produced_kg", "delivered_kg", "billed_kg", "loss_kg", "fabric_transfer_in_kg", "fabric_transfer_out_kg", "yarn_transfer_in_kg", "yarn_transfer_out_kg")}
    for event in events:
        result = json_value(event.result, {})
        kind = event.kind
        if kind in ("transfer_fabric", "transfer_yarn"):
            prefix = "fabric" if kind == "transfer_fabric" else "yarn"
            totals[f"{prefix}_transfer_{'in' if event.target_job == job else 'out'}_kg"] += Decimal(result["quantity_kg"])
        if kind == "credit_invoice":
            totals["billed_kg"] -= Decimal(result["quantity_kg"])
        if kind == "return_fabric":
            totals["delivered_kg"] -= Decimal(result["quantity_kg"])
        key = {"receive_yarn": "received_kg", "allocate_yarn": "received_kg", "return_yarn": "returned_kg",
               "produce": "produced_kg", "produce_bulk": "produced_kg", "subcontract_receive": "produced_kg", "deliver": "delivered_kg", "invoice": "billed_kg"}.get(kind)
        if key:
            totals[key] += Decimal(result.get("quantity_kg", "0"))
        if kind in ("produce", "produce_bulk", "repack_yarn", "subcontract_receive"):
            totals["consumed_kg"] += Decimal(result.get("consumed_kg", "0"))
            totals["loss_kg"] += Decimal(result.get("loss_kg", "0"))
    entries = current_rows("Knitting Ledger Entry", filters={"job": job}, fields=["quantity_kg", "custodian"])
    totals["yarn_kg"] = sum((Decimal(e.quantity_kg) for e in entries if e.custodian == "Warehouse"), ZERO)
    totals["subcontract_kg"] = sum((Decimal(e.quantity_kg) for e in entries if (e.custodian or "").startswith("SC:")), ZERO)
    rolls = current_rows("Knitting Roll", filters={"job": job}, fields=["state", "weight_kg"])
    totals["fabric_kg"] = sum((Decimal(r.weight_kg) for r in rolls if r.state not in ("Delivered", "Split", "Cancelled")), ZERO)
    totals["unbilled_kg"] = totals["delivered_kg"] - totals["billed_kg"]
    return {key: kg(value) for key, value in totals.items()}


def programme_produced(job, line):
    total = ZERO
    for event in job_events(job.name):
        payload, value = json_value(event.payload, {}), json_value(event.result, {})
        if not value:
            continue
        if event.job == job.name and event.kind in ("produce", "subcontract_receive") and payload.get("programme_line") == line:
            total += Decimal(value["quantity_kg"])
        if event.job == job.name and event.kind == "produce_bulk":
            total += sum((Decimal(row["quantity_kg"]) for row in value.get("entries", []) if row.get("programme_line") == line), ZERO)
        if event.target_job == job.name and event.kind == "transfer_fabric" and value.get("target_programme_line") == line:
            total += Decimal(value["quantity_kg"])
    return total


def programme(job, line):
    lines = json_value(job.programme, [])
    match = next((p for p in lines if p["id"] == line), None)
    if not match:
        frappe.throw("Choose a programme line belonging to this job.")
    return match


def line_pricing(company, customer, lines, fallback="0", overrides=None):
    config = settings(company)
    result = {}
    for line in lines:
        filters = {"company": company, "customer": customer, "fabric": line.get("fabric", ""),
                   "effective_from": ["<=", frappe.utils.today()]}
        if config.get("rate_lookup") == "FabricCountGauge":
            filters.update(yarn_count=line.get("yarn_count", ""), gauge=line.get("gauge", ""))
        found = current_rows("Knitting Rate", filters=filters, fields=["rate"], order_by="effective_from desc, creation desc", limit=1)
        value = (overrides or {}).get(line["id"], found[0].rate if found else fallback)
        result[line["id"]] = money(decimal(value, precision=2))
    return result


def validate_programme(lines):
    if not isinstance(lines, list) or not lines or len(lines) > 100:
        frappe.throw("Add at least one fabric programme line.")
    seen, total = set(), ZERO
    for line in lines:
        if not isinstance(line, Mapping) or not isinstance(line.get("id"), str) or line["id"] in seen:
            frappe.throw("Each programme line needs a unique identity.")
        seen.add(line["id"])
        allowed = {"id", "fabric", "colour", "gsm", "ll", "gauge", "dia", "knit_type", "target_kg", "fabric_item",
                   "yarn_count", "finish_dia", "finish_gsm", "brand", "construct", "organic", "regenagri"}
        if set(line) - allowed:
            frappe.throw("Programme contains an unsupported or private field.")
        total += decimal(line.get("target_kg"), positive=True)
        for key, limit in (("gsm", 2), ("ll", 3)):
            values = line.get(key, [])
            if not isinstance(values, list) or len(values) > limit:
                frappe.throw("Programme permits up to two GSM and three LL values.")
            for value in values:
                decimal(value, positive=True)
        for key in ("id", "fabric", "colour", "gauge", "dia", "knit_type", "yarn_count", "brand", "construct"):
            if line.get(key) is not None and (not isinstance(line[key], str) or len(line[key]) > 140):
                frappe.throw("Use clear text for the programme specification.")
        if line.get("fabric_item"):
            reference("Item", line["fabric_item"])
    return total


def create_job(event, data, job):
    customer = reference("Customer", data.get("customer"))
    mode, kind = data.get("material_mode", "Customer"), data.get("kind", "Order")
    if mode not in ("Customer", "Owned") or kind not in ("Order", "Sample"):
        frappe.throw("Choose valid material ownership and order/sample kind.")
    target = decimal(data.get("target_kg"), positive=True)
    lines = data.get("programme")
    total = validate_programme(lines)
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
                 rate=rate, charge_policy=settings(event.company).get("lycra_charge", "Included"), pricing=frappe.as_json(line_pricing(event.company, customer.name, lines, rate, data.get("pricing"))),
                 service_item=service, due_date=data.get("due_date"), notes=data.get("notes"))
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
    if data.get("charge_item"):
        charge = reference("Item", data["charge_item"])
        if charge.is_stock_item or owner != "Owned":
            frappe.throw("Only owned auxiliary materials use a non-stock charge item.")
        decimal(data.get("charge_rate"), precision=2)
    lot = insert("Knitting Material Lot", company=event.company, item=item.name, party=party, material_owner=owner,
                 warehouse=godown, source_lot=data.get("source_lot"), specification=frappe.as_json(data.get("specification", {})), charge_item=data.get("charge_item"), charge_rate=data.get("charge_rate"))
    voucher = None
    if data.get("purchase_order"):
        from .procurement import receive_order
        voucher = receive_order(event, data, quantity, godown)
    elif owner == "Owned":
        voucher = posting.stock(event, "Material Receipt", [{"item_code": item.name, "qty": quantity, "t_warehouse": godown,
                  "basic_rate": decimal(data.get("valuation_rate"), positive=True, precision=2)}])
    ledger(event, lot, quantity, job.name if job else None, voucher=voucher, units=units)
    return {"lot": lot.name, "quantity_kg": kg(quantity), "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def return_yarn(event, data, job):
    from . import posting
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = decimal(data.get("quantity_kg"), positive=True)
    if quantity > lot_balance(lot.name, job.name if job else None):
        frappe.throw("The return exceeds this job's remaining yarn.")
    voucher = posting.stock(event, "Material Issue", [{"item_code": lot.item, "qty": quantity, "s_warehouse": lot.warehouse}]) if lot.material_owner == "Owned" else None
    ledger(event, lot, -quantity, job.name if job else None, voucher=voucher)
    return {"lot": lot.name, "quantity_kg": kg(quantity), "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


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
    event.target_job = target.name
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
        validate_programme(lines)
        if not isinstance(lines, list) or not lines or len({p.get("id") for p in lines}) != len(lines):
            frappe.throw("Revision needs distinct programme line identities.")
        for line in json_value(job.programme, []):
            produced = programme_produced(job, line["id"])
            replacement = next((p for p in lines if p.get("id") == line["id"]), None)
            if produced and (replacement is None or decimal(replacement["target_kg"]) < produced):
                frappe.throw("A revision cannot discard already produced fabric.")
        job.target_kg = kg(sum((decimal(p["target_kg"], positive=True) for p in lines), ZERO))
        job.programme = frappe.as_json(lines)
    if "rate" in data or data.get("refresh_rates") or "programme" in data or "pricing" in data:
        lines = json_value(job.programme, [])
        override = data.get("pricing") or ({p["id"]: money(job.rate) for p in lines} if "rate" in data else None)
        job.pricing = frappe.as_json(line_pricing(event.company, job.customer, lines, job.rate or "0", override))
    job.revision += 1
    job.save()
    return {"job": job.name, "revision": job.revision, "previous": before, "reason": data["reason"]}


def charge_shares(weights, charges):
    """Largest-remainder allocation conserves three-decimal material quantities across rolls."""
    result = [[] for _ in weights]
    total = sum(weights, ZERO)
    for charge in charges:
        milli = int(Decimal(charge["quantity_kg"]) * 1000)
        exact = [Decimal(milli) * w / total for w in weights]
        shares = [int(v) for v in exact]
        missing = milli - sum(shares)
        for index in sorted(range(len(weights)), key=lambda i: exact[i] - shares[i], reverse=True)[:missing]:
            shares[index] += 1
        for index, value in enumerate(shares):
            if value:
                result[index].append({**charge, "quantity_kg": kg(Decimal(value) / 1000)})
    return result


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
    shares = charge_shares(weights, json_value(roll.charges, []))
    for index, weight in enumerate(weights):
        child = insert("Knitting Roll", **{key: roll.get(key) for key in ("company", "job", "programme_line", "job_revision", "fabric_item",
            "warehouse", "machine", "operator", "shift", "produced_at", "state", "production", "specification")},
            weight_kg=kg(weight), parent_roll=roll.name, charges=frappe.as_json(shares[index]))
        children.append(child.name)
    previous = roll.state
    roll.state = "Split"
    roll.save()
    return {"rolls": children, "parent_roll": roll.name, "quantity_kg": roll.weight_kg, "previous_state": previous}


def produce(event, data, job, *, custodian="Warehouse", source_warehouse=None, additional_costs=None):
    from . import posting
    line = programme(job, data.get("programme_line"))
    weights = data.get("weights_kg")
    if not isinstance(weights, list) or not weights or len(weights) > 200:
        frappe.throw("Enter between one and 200 roll weights.")
    weights = [decimal(w, positive=True) for w in weights]
    quantity, loss = sum(weights, ZERO), decimal(data.get("loss_kg", "0"))
    produced = programme_produced(job, line["id"])
    excess = decimal(settings(event.company).get("allow_production_excess_pct", "0"))
    if produced + quantity > decimal(line["target_kg"]) * (Decimal(1) + excess / 100):
        frappe.throw("Roll production exceeds the remaining programme.")
    inputs = data.get("inputs")
    if not isinstance(inputs, list) or not inputs or len(inputs) > 100:
        frappe.throw("Select the source yarn lots and actual consumption.")
    lots, total, seen = [], ZERO, set()
    for entry in inputs:
        entry = dict(entry)
        lot = reference("Knitting Material Lot", entry.get("lot"), event.company)
        consumed = decimal(entry.get("quantity_kg"), positive=True)
        if lot.name in seen or consumed > lot_balance(lot.name, job.name, custodian):
            frappe.throw("Yarn consumption exceeds the selected lot allocation.")
        seen.add(lot.name)
        if lot.material_owner == "Customer" and (job.material_mode != "Customer" or lot.party != job.fabric_owner):
            frappe.throw("A different owner's material cannot be consumed by this job.")
        if lot.material_owner == "Owned" and lot.charge_item:
            entry.setdefault("charge_item", lot.charge_item)
            entry.setdefault("charge_rate", money(lot.charge_rate or 0))
        if job.material_mode == "Customer" and lot.material_owner == "Owned" and (job.charge_policy or settings(event.company).get("lycra_charge")) == "Separate" and not entry.get("charge_item"):
            frappe.throw("Ask the accounts manager to set this owned material lot's separate charge item and rate before production.")
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
    if machine and (not machine.enabled or any(str(line.get(k, "")).casefold() != str(machine.get(k, "")).casefold() for k in ("dia", "gauge", "knit_type") if line.get(k))):
        frappe.throw("The selected machine is unavailable or incompatible with this fabric.")
    fabric_item = line.get("fabric_item") or settings(event.company).get("fabric_item")
    owned_rows = [{"item_code": lot.item, "qty": used, "s_warehouse": source_warehouse or lot.warehouse} for lot, used, _ in lots if lot.material_owner == "Owned"]
    voucher = None
    if job.material_mode == "Owned":
        item = reference("Item", fabric_item)
        if not item.is_stock_item or item.stock_uom != "Kg":
            frappe.throw("Owned fabric requires a stock item measured in Kg.")
        owned_rows.append({"item_code": fabric_item, "qty": quantity, "t_warehouse": godown, "is_finished_item": 1})
        voucher = posting.stock(event, "Repack", owned_rows, additional_costs=additional_costs)
    elif owned_rows:
        voucher = posting.stock(event, "Material Issue", owned_rows)
    for lot, used, _ in lots:
        ledger(event, lot, -used, job.name, custodian=custodian, voucher=voucher if lot.material_owner == "Owned" else None)
    charges = [{"item": entry["charge_item"], "quantity_kg": kg(used), "rate": money(decimal(entry["charge_rate"], precision=2))} for lot, used, entry in lots if lot.material_owner == "Owned" and entry.get("charge_item")] if job.material_mode == "Customer" and (job.charge_policy or settings(event.company).get("lycra_charge")) == "Separate" else []
    shares = charge_shares(weights, charges)
    rolls = []
    for index, weight in enumerate(weights):
        roll = insert("Knitting Roll", company=event.company, job=job.name, programme_line=line["id"],
            job_revision=job.revision, weight_kg=kg(weight), fabric_item=fabric_item, warehouse=godown,
            machine=machine.name if machine else None, operator=frappe.session.user, shift=data.get("shift"),
            produced_at=event.occurred_at, state="Awaiting QC", production=event.name, specification=frappe.as_json(line), charges=frappe.as_json(shares[index]))
        rolls.append(roll.name)
    plan_progress = []
    if machine:
        remaining = quantity
        for entry in current_rows("Knitting Plan", filters={"job": job.name, "machine": machine.name, "programme_line": line["id"], "state": ["in", ["Planned", "Started"]]}, fields=["name"], order_by="starts_at, name"):
            record = reference("Knitting Plan", entry.name, event.company)
            previous = record.produced_kg or "0.000"
            used = min(remaining, Decimal(record.quantity_kg) - Decimal(previous))
            if used <= 0:
                continue
            record.produced_kg = kg(Decimal(previous) + used)
            record.state = "Completed" if Decimal(record.produced_kg) == Decimal(record.quantity_kg) else "Started"
            record.save()
            plan_progress.append({"plan": record.name, "before_kg": previous, "after_kg": record.produced_kg, "state": record.state, "modified_after": str(record.modified)})
            remaining -= used
            if not remaining:
                break
    component_progress = []
    if machine:
        for component in current_rows("Knitting Component", filters={"company": event.company, "machine": machine.name}, pluck="name"):
            record = frappe.get_doc("Knitting Component", component)
            before = record.run_kg or "0.000"
            record.run_kg = kg(Decimal(before) + quantity)
            record.save()
            component_progress.append({"component": record.name, "before_kg": before, "after_kg": record.run_kg, "modified_after": str(record.modified)})
    return {"rolls": rolls, "quantity_kg": kg(quantity), "consumed_kg": kg(total), "loss_kg": kg(loss), "plan_progress": plan_progress, "component_progress": component_progress,
            "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def quality(event, data, job):
    roll = reference("Knitting Roll", data.get("roll"), event.company)
    if roll.job != job.name or roll.state in ("Delivered", "Split", "Cancelled"):
        frappe.throw("This roll cannot be inspected in the selected job.")
    decision = data.get("decision")
    if decision not in ("Released", "On Hold", "Rework", "Rejected"):
        frappe.throw("Choose a quality decision.")
    defects = []
    for name in data.get("defects", []):
        definition = reference("Knitting Master", name, event.company)
        if definition.category != "QC defect" or not definition.enabled:
            frappe.throw("Select active quality defect definitions.")
        defects.append({"master": definition.name, "title": definition.title, **json_value(definition.specification, {})})
    previous = roll.state
    check = insert("Knitting QC", company=event.company, job=job.name, roll=roll.name, checker=frappe.session.user,
        decision=decision, defects=frappe.as_json(defects), remarks=data.get("remarks"), event=event.name)
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
    lines = {}
    prices = json_value(job.pricing, {})
    for roll in rolls:
        if roll.programme_line not in lines:
            lines[roll.programme_line] = {"programme_line": roll.programme_line, "quantity_kg": ZERO,
                "rate": prices.get(roll.programme_line, money(job.rate or 0)), "fabric_item": roll.fabric_item}
        lines[roll.programme_line]["quantity_kg"] += Decimal(roll.weight_kg)
    for value in lines.values():
        value["quantity_kg"] = kg(value["quantity_kg"])
    charges = [{**charge, "programme_line": roll.programme_line} for roll in rolls for charge in json_value(roll.charges, [])]
    return {"rolls": names, "quantity_kg": kg(sum((Decimal(r.weight_kg) for r in rolls), ZERO)), "lines": list(lines.values()), "charges": charges, "rate": money(job.rate or 0),
            "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


def delivery_billed(job, delivery, line=None):
    total = ZERO
    for event in job_events(job):
        if event.kind not in ("invoice", "credit_invoice"):
            continue
        for row in json_value(event.result, {}).get("allocations", []):
            if row["delivery"] == delivery and (line is None or row.get("programme_line") == line):
                total += Decimal(row["quantity_kg"]) * (-1 if event.kind == "credit_invoice" else 1)
    return total


def invoice(event, data, job, *, preview=False):
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
        for line in value.get("lines", [{"programme_line": None, "quantity_kg": value["quantity_kg"], "rate": value.get("rate", job.rate)}]):
            available = Decimal(line["quantity_kg"]) - returned_delivery(job.name, name, line["programme_line"]) - delivery_billed(job.name, name, line["programme_line"])
            quantity = min(available, remaining) if remaining is not None else available
            if quantity <= 0:
                continue
            rate = decimal(line["rate"], precision=2)
            item = job.service_item if job.material_mode == "Customer" else line.get("fabric_item")
            if not item:
                frappe.throw("Configure the service or fabric billing item before invoicing.")
            rows.append({"item_code": item, "qty": quantity, "rate": rate, "knitting_delivery": name})
            allocations.append({"delivery": name, "programme_line": line["programme_line"], "quantity_kg": kg(quantity)})
            total += quantity
            if remaining is not None:
                remaining -= quantity
    if total <= 0 or remaining is not None and remaining > 0:
        frappe.throw("The invoice exceeds the confirmed unbilled delivery quantity.")
    # Source deliveries retain the exact auxiliary item, quantity and rate approved for their rolls.
    if job.material_mode == "Customer":
        for name in names:
            source = reference("Knitting Event", name, event.company)
            value = json_value(source.result, {})
            for charge in value.get("charges", []):
                selected = sum((Decimal(a["quantity_kg"]) for a in allocations if a["delivery"] == name and a["programme_line"] == charge["programme_line"]), ZERO)
                delivered = sum((Decimal(row["quantity_kg"]) for row in value["lines"] if row["programme_line"] == charge["programme_line"]), ZERO)
                if selected:
                    rows.append({"item_code": charge["item"], "qty": Decimal(charge["quantity_kg"]) * selected / delivered, "rate": decimal(charge["rate"], precision=2)})
    doc = posting.invoice(event, job, rows, preview=preview)
    if preview:
        return doc
    if data.get("preview_hash"):
        from .api import invoice_signature
        if data["preview_hash"] != invoice_signature(doc):
            frappe.throw("Invoice totals changed. Review the current ERP totals before confirming again.")
    return {"invoice": doc.name, "quantity_kg": kg(total), "amount": money(doc.grand_total), "allocations": allocations,
            "voucher": doc.name, "voucher_type": "Sales Invoice"}


def close_job(event, data, job):
    value = balances(job.name)
    if any(Decimal(value[key]) != 0 for key in ("yarn_kg", "fabric_kg", "unbilled_kg", "subcontract_kg")):
        frappe.throw("Reconcile remaining yarn, fabric, subcontract custody and unbilled deliveries before closure.")
    if Decimal(value["produced_kg"]) + Decimal(value["fabric_transfer_in_kg"]) < Decimal(job.target_kg):
        frappe.throw("Complete or explicitly revise the remaining programme before closure.")
    if frappe.db.exists("Knitting Subcontract", {"job": job.name, "status": "Open"}):
        frappe.throw("Complete the open subcontract orders before job closure.")
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
    job_name = job.name if job else None
    source = reference("Knitting Event", data.get("event"), event.company)
    if source.job != job_name or source.cancelled or not data.get("reason"):
        frappe.throw("Choose an active source event and give a correction reason.")
    result = json_value(source.result, {})
    if source.kind == "invoice" and any(json_value(e.result, {}).get("invoice_event") == source.name for e in job_events(job_name, "credit_invoice")):
        frappe.throw("Correct dependent credits before cancelling this invoice.")
    if source.kind == "deliver" and returned_delivery(job_name, source.name) > 0:
        frappe.throw("This delivery has physical returns; retain its linked history.")
    if source.kind == "deliver" and delivery_billed(job_name, source.name) > 0:
        frappe.throw("Cancel or credit dependent invoices before cancelling this delivery.")
    if source.kind in ("subcontract_bill", "subcontract_receive"):
        sub = reference("Knitting Subcontract", result["subcontract"], event.company)
        if sub.status != "Open":
            frappe.throw("Reopen the subcontract before correcting its source records.")
        if source.kind == "subcontract_receive":
            received = sum((Decimal(json_value(e.result, {})["quantity_kg"]) for e in job_events(job_name, "subcontract_receive") if json_value(e.result, {}).get("subcontract") == sub.name), ZERO)
            billed = sum((Decimal(json_value(e.result, {})["quantity_kg"]) for e in job_events(job_name, "subcontract_bill") if json_value(e.result, {}).get("subcontract") == sub.name), ZERO)
            if received - Decimal(result["quantity_kg"]) < billed:
                frappe.throw("Correct dependent subcontract bills before reversing the fabric receipt.")
    if source.kind == "receive_yarn":
        lot = reference("Knitting Material Lot", result["lot"], event.company)
        if current_rows("Knitting Ledger Entry", filters={"lot": lot.name, "event": ["!=", source.name]}, fields=["name"]):
            frappe.throw("This receipt has later material activity. Use an explicit return or adjustment.")
        ledger(event, lot, -Decimal(result["quantity_kg"]), job_name)
    if source.kind == "create_yarn_order":
        for receipt in current_rows("Knitting Event", filters={"company": event.company, "kind": "receive_yarn", "cancelled": 0}, fields=["payload"]):
            if json_value(receipt.payload, {}).get("purchase_order") == result["purchase_order"]:
                frappe.throw("Cancel dependent unused receipts before cancelling the yarn order.")
    if source.kind in ("produce", "produce_bulk", "subcontract_receive"):
        rolls = [reference("Knitting Roll", name, event.company) for name in result["rolls"]]
        if any(r.job != job_name or r.state != "Awaiting QC" or current_rows("Knitting Roll", filters={"parent_roll": r.name, "state": ["!=", "Cancelled"]}, fields=["name"]) for r in rolls):
            frappe.throw("Correct dependent inspections, splits or deliveries before cancelling production.")
        vouchers = result.get("vouchers", []) or ([{"voucher": result["voucher"], "voucher_type": result["voucher_type"]}] if result.get("voucher") else [])
        for voucher in reversed(vouchers):
            doc = reference(voucher["voucher_type"], voucher["voucher"], event.company)
            doc.check_permission("cancel")
            doc.cancel()
        for entry in current_rows("Knitting Ledger Entry", filters={"event": source.name}, fields=["lot", "job", "quantity_kg", "custodian"]):
            lot = reference("Knitting Material Lot", entry.lot, event.company)
            ledger(event, lot, -Decimal(entry.quantity_kg), entry.job, custodian=entry.custodian)
        batches = result.get("entries", []) if source.kind == "produce_bulk" else [result]
        checked_components, checked_plans = set(), set()
        for batch in reversed(batches):
            for progress in reversed(batch.get("component_progress", [])):
                component = reference("Knitting Component", progress["component"], event.company)
                if component.run_kg != progress["after_kg"] or component.name not in checked_components and str(component.modified) != progress.get("modified_after", str(component.modified)):
                    frappe.throw("Later component use or replacement depends on this production.")
                checked_components.add(component.name)
                component.run_kg = progress["before_kg"]
                component.save()
            for progress in reversed(batch.get("plan_progress", [])):
                plan = reference("Knitting Plan", progress["plan"], event.company)
                if plan.produced_kg != progress["after_kg"] or plan.name not in checked_plans and str(plan.modified) != progress.get("modified_after", str(plan.modified)):
                    frappe.throw("Later production or replanning depends on this allocation.")
                checked_plans.add(plan.name)
                overlaps = current_rows("Knitting Plan", filters={"company": event.company, "machine": plan.machine, "name": ["!=", plan.name], "state": ["in", ["Planned", "Started"]], "starts_at": ["<", plan.ends_at], "ends_at": [">", plan.starts_at]}, fields=["name"])
                if overlaps:
                    frappe.throw("A newer machine allocation occupies this slot. Replan it before reversing production.")
                plan.produced_kg = progress["before_kg"]
                plan.state = "Planned" if Decimal(plan.produced_kg) == 0 else "Started"
                plan.save()
        for roll in rolls:
            roll.state = "Cancelled"
            roll.save()
    if source.kind == "credit_invoice":
        original_invoice = reference("Knitting Event", result["invoice_event"], event.company)
        for allocation in result["allocations"]:
            delivery = reference("Knitting Event", allocation["delivery"], event.company)
            lines = json_value(delivery.result, {})["lines"]
            source_qty = sum((Decimal(r["quantity_kg"]) for r in lines if r["programme_line"] == allocation["programme_line"]), ZERO)
            if delivery_billed(job_name, delivery.name, allocation["programme_line"]) + Decimal(allocation["quantity_kg"]) > source_qty - returned_delivery(job_name, delivery.name, allocation["programme_line"]):
                frappe.throw("Physical returns or rebilling depend on this credit; correct them before cancellation.")
    if source.kind == "return_fabric":
        for name in result["rolls"]:
            roll = reference("Knitting Roll", name, event.company)
            if roll.job != job_name or roll.state != "Awaiting QC" or roll.delivery:
                frappe.throw("Later inspection or movement depends on this fabric return.")
            roll.state, roll.delivery = "Delivered", result["delivery"]
            roll.save()
    if source.kind == "split_roll":
        parent = reference("Knitting Roll", result["parent_roll"], event.company)
        for name in result["rolls"]:
            child = reference("Knitting Roll", name, event.company)
            if child.job != job_name or child.state != result["previous_state"] or current_rows("Knitting Roll", filters={"parent_roll": name, "state": ["!=", "Cancelled"]}, fields=["name"]):
                frappe.throw("Correct dependent work before reversing this split.")
            child.state = "Cancelled"
            child.save()
        parent.state = result["previous_state"]
        parent.save()
    if source.kind == "transfer_fabric":
        target = reference("Knitting Job", source.target_job, event.company)
        for previous in result["previous"]:
            roll = reference("Knitting Roll", previous["roll"], event.company)
            if roll.job != target.name or roll.state != "Awaiting QC":
                frappe.throw("Later work depends on the transferred roll; correct it before reversing reassignment.")
            roll.job, roll.programme_line, roll.job_revision, roll.state = previous["job"], previous["programme_line"], previous["job_revision"], previous["state"]
            roll.save()
        target.save()
        event.target_job = target.name
    if source.kind not in ("invoice", "deliver", "quality", "produce", "produce_bulk", "transfer_fabric", "split_roll", "credit_invoice", "return_fabric", "receive_yarn", "bill_yarn", "create_yarn_order", "subcontract_receive", "subcontract_bill"):
        frappe.throw("This event has material dependencies; use an explicit return, transfer or adjustment.")
    if result.get("voucher") and source.kind not in ("produce", "produce_bulk", "subcontract_receive"):
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
        later = frappe.db.sql("""select q.name from `tabKnitting QC` q join `tabKnitting Event` e on e.name=q.event
            where q.roll=%s and q.event!=%s and q.creation>%s and e.cancelled=0 limit 1""", (roll.name, source.name, source.creation))
        if roll.job != job_name or roll.state == "Delivered" or later:
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


def produce_bulk(event, data, job):
    entries = data.get("entries")
    if not isinstance(entries, list) or not 1 <= len(entries) <= 50 or sum(len(e.get("weights_kg", [])) for e in entries if isinstance(e, Mapping)) > 1000:
        frappe.throw("Review one to 50 production lines with at most 1,000 rolls.")
    result = {"rolls": [], "quantity_kg": ZERO, "consumed_kg": ZERO, "loss_kg": ZERO, "vouchers": [], "entries": []}
    for entry in entries:
        if not isinstance(entry, Mapping):
            frappe.throw("Each bulk row must contain production details.")
        value = produce(event, entry, job)
        result["rolls"].extend(value["rolls"])
        result["entries"].append({**value, **{k: entry.get(k) for k in ("programme_line", "machine", "shift")}})
        for key in ("quantity_kg", "consumed_kg", "loss_kg"):
            result[key] += Decimal(value[key])
        if value.get("voucher"):
            result["vouchers"].append({"voucher": value["voucher"], "voucher_type": value["voucher_type"]})
        event.result = frappe.as_json({**result, **{key: kg(result[key]) for key in ("quantity_kg", "consumed_kg", "loss_kg")}})
        event.save()
    return {**result, **{key: kg(result[key]) for key in ("quantity_kg", "consumed_kg", "loss_kg")}}


def adjust_yarn(event, data, job):
    from . import posting
    lot = reference("Knitting Material Lot", data.get("lot"), event.company)
    quantity = decimal(data.get("quantity_kg"), signed=True)
    if not quantity or not str(data.get("reason", "")).strip():
        frappe.throw("Enter a non-zero count difference and the adjustment reason.")
    custodian = "Warehouse"
    godown = lot.warehouse
    if data.get("subcontract"):
        sub = reference("Knitting Subcontract", data["subcontract"], event.company)
        if not job or sub.job != job.name or sub.status != "Open":
            frappe.throw("Choose this job's open subcontract.")
        custodian, godown = "SC:" + sub.name, sub.warehouse
    if quantity < 0 and -quantity > lot_balance(lot.name, job.name if job else None, custodian):
        frappe.throw("The adjustment cannot make custody negative.")
    voucher = None
    if lot.material_owner == "Owned":
        row = {"item_code": lot.item, "qty": abs(quantity), "s_warehouse" if quantity < 0 else "t_warehouse": godown}
        if quantity > 0:
            row["basic_rate"] = decimal(data.get("valuation_rate"), positive=True, precision=2)
        voucher = posting.stock(event, "Material Issue" if quantity < 0 else "Material Receipt", [row])
    ledger(event, lot, quantity, job.name if job else None, custodian=custodian, voucher=voucher)
    return {"lot": lot.name, "quantity_kg": kg(quantity), "custodian": custodian, "reason": data["reason"],
        "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None}


ACTIONS.update({"produce_bulk": ("production", produce_bulk), "adjust_yarn": ("lifecycle", adjust_yarn)})



def transfer_fabric(event, data, job):
    from erp_extensions.api import _check_version
    target = reference("Knitting Job", data.get("target_job"), event.company)
    _check_version(target, data.get("target_modified"))
    line = programme(target, data.get("target_programme_line"))
    names = data.get("rolls")
    if target.name == job.name or target.status != "Running" or target.material_mode != job.material_mode or target.fabric_owner != job.fabric_owner:
        frappe.throw("Transfer only between running jobs with the same material ownership.")
    if not data.get("reason") or not isinstance(names, list) or not names or len(set(names)) != len(names):
        frappe.throw("Select distinct undelivered rolls and give the transfer reason.")
    rolls = [reference("Knitting Roll", name, event.company) for name in names]
    quantity = sum((Decimal(r.weight_kg) for r in rolls), ZERO)
    existing = sum((Decimal(r.weight_kg) for r in current_rows("Knitting Roll", filters={"job": target.name, "programme_line": line["id"], "state": ["not in", ["Split", "Cancelled"]]}, fields=["weight_kg"])), ZERO)
    if existing + quantity > decimal(line["target_kg"]):
        frappe.throw("Transferred fabric exceeds the destination programme balance.")
    previous = []
    for roll in rolls:
        spec = json_value(roll.specification, {})
        if roll.job != job.name or roll.state in ("Delivered", "Split", "Cancelled") or any(str(spec.get(k) or "").casefold() != str(line.get(k) or "").casefold() for k in ("fabric", "colour", "dia", "gauge", "knit_type")):
            frappe.throw("Transfer matching undelivered fabric only; a transfer cannot alter its physical specification.")
        previous.append({"roll": roll.name, "job": job.name, "programme_line": roll.programme_line, "state": roll.state, "job_revision": roll.job_revision})
        roll.job, roll.programme_line, roll.job_revision, roll.state = target.name, line["id"], target.revision, "Awaiting QC"
        roll.save()
    target.save()
    event.target_job = target.name
    return {"rolls": names, "target_job": target.name, "target_programme_line": line["id"], "quantity_kg": kg(quantity), "previous": previous, "reason": data["reason"]}


ACTIONS["transfer_fabric"] = ("lifecycle", transfer_fabric)


def credited_allocations(job, invoice):
    totals = {}
    for event in job_events(job, "credit_invoice"):
        value = json_value(event.result, {})
        if value.get("invoice_event") == invoice:
            for row in value["allocations"]:
                key = (row["delivery"], row.get("programme_line"))
                totals[key] = totals.get(key, ZERO) + Decimal(row["quantity_kg"])
    return totals


def credit_invoice(event, data, job):
    from . import posting
    source = reference("Knitting Event", data.get("invoice_event"), event.company)
    if source.kind != "invoice" or source.job != job.name or source.cancelled or not data.get("reason"):
        frappe.throw("Select this job's active source invoice and a credit reason.")
    value = json_value(source.result, {})
    original = reference("Sales Invoice", value["invoice"], event.company)
    quantity = decimal(data.get("quantity_kg"), positive=True)
    remaining, credited = quantity, credited_allocations(job.name, source.name)
    selected, weights = [], []
    for index, allocation in enumerate(value["allocations"]):
        key = (allocation["delivery"], allocation.get("programme_line"))
        available = Decimal(allocation["quantity_kg"]) - credited.get(key, ZERO)
        used = min(remaining, available)
        if used > 0:
            selected.append({**allocation, "quantity_kg": kg(used)})
        weights.append(used)
        remaining -= used
    if remaining:
        frappe.throw("The credit exceeds the source invoice's uncredited kg.")
    from erpnext.accounts.doctype.sales_invoice.sales_invoice import make_sales_return
    doc = make_sales_return(original.name)
    doc.flags = frappe._dict()
    for row in doc.get_all_children():
        row.flags = frappe._dict()
    rows = []
    for index, source_item in enumerate(original.items):
        qty = weights[index] if index < len(weights) else Decimal(str(source_item.qty)) * quantity / Decimal(value["quantity_kg"])
        if not qty:
            continue
        mapped = next((row for row in doc.items if row.sales_invoice_item == source_item.name), None)
        if mapped is None:
            frappe.throw("The original invoice item could not be matched for credit.")
        mapped.qty, mapped.knitting_delivery = -qty, source_item.knitting_delivery
        rows.append(mapped)
    doc.set("items", rows)
    doc.update_stock, doc.knitting_event, doc.knitting_job = 0, event.name, job.name
    posting.submit(doc)
    return {"invoice": doc.name, "invoice_event": source.name, "quantity_kg": kg(quantity), "allocations": selected,
        "amount": money(doc.grand_total), "reason": data["reason"], "voucher": doc.name, "voucher_type": doc.doctype}


def returned_delivery(job, delivery, line=None):
    total = ZERO
    for event in job_events(job, "return_fabric"):
        value = json_value(event.result, {})
        if value.get("delivery") == delivery:
            for row in value["allocations"]:
                if line is None or row["programme_line"] == line:
                    total += Decimal(row["quantity_kg"])
    return total


def return_fabric(event, data, job):
    from . import posting
    source = reference("Knitting Event", data.get("delivery"), event.company)
    if source.kind != "deliver" or source.job != job.name or source.cancelled or not data.get("reason"):
        frappe.throw("Select an active delivery from this job and a return reason.")
    names = data.get("rolls")
    if not isinstance(names, list) or not names or len(names) != len(set(names)):
        frappe.throw("Select distinct delivered rolls.")
    rolls = [reference("Knitting Roll", name, event.company) for name in names]
    if any(r.job != job.name or r.delivery != source.name or r.state != "Delivered" for r in rolls):
        frappe.throw("Only the selected source delivery's current rolls can be returned.")
    allocations = {}
    for roll in rolls:
        allocations[roll.programme_line] = allocations.get(roll.programme_line, ZERO) + Decimal(roll.weight_kg)
    delivered = json_value(source.result, {})
    for line, quantity in allocations.items():
        source_qty = sum((Decimal(r["quantity_kg"]) for r in delivered["lines"] if r["programme_line"] == line), ZERO)
        if source_qty - returned_delivery(job.name, source.name, line) - quantity < delivery_billed(job.name, source.name, line):
            frappe.throw("Credit the corresponding billed kg before returning this fabric.")
    voucher = None
    if job.material_mode == "Owned":
        from erpnext.stock.doctype.delivery_note.delivery_note import make_sales_return
        voucher = make_sales_return(delivered["voucher"])
        voucher.flags = frappe._dict()
        for row in voucher.get_all_children():
            row.flags = frappe._dict()
        original = reference("Delivery Note", delivered["voucher"], event.company)
        stock = {}
        for roll in rolls:
            key = (roll.fabric_item, roll.warehouse)
            stock[key] = stock.get(key, ZERO) + Decimal(roll.weight_kg)
        rows = []
        for row in voucher.items:
            key = (row.item_code, row.warehouse)
            quantity = min(stock.get(key, ZERO), abs(Decimal(str(row.qty))))
            if quantity:
                row.qty = -quantity
                stock[key] -= quantity
                rows.append(row)
        if any(stock.values()):
            frappe.throw("Return stock does not match the original delivery items.")
        voucher.set("items", rows)
        voucher.knitting_event, voucher.knitting_job = event.name, job.name
        posting.submit(voucher)
    for roll in rolls:
        roll.state, roll.delivery = "Awaiting QC", None
        roll.save()
    return {"delivery": source.name, "rolls": names, "quantity_kg": kg(sum(allocations.values(), ZERO)),
        "allocations": [{"programme_line": line, "quantity_kg": kg(quantity)} for line, quantity in allocations.items()],
        "voucher": voucher.name if voucher else None, "voucher_type": voucher.doctype if voucher else None, "reason": data["reason"]}


ACTIONS.update({"credit_invoice": ("billing", credit_invoice), "return_fabric": ("delivery", return_fabric)})
