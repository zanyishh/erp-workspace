"""Operational report projections from immutable events and standard accounting sources."""
from datetime import datetime, time, timedelta
from decimal import Decimal

import frappe
from frappe.utils import getdate, get_datetime, today
from . import domain as d, permissions

REPORTS = {"breakage": "Component breakage", "shortages": "72-hour yarn coverage", "changes": "24-hour job changes", "unplanned": "Planning status", "jobs": "Job reconciliation", "yarn": "Yarn custody", "fabric": "Fabric in house", "rolls": "Roll traceability",
    "planning": "Machine allocations", "production": "Production and loss", "quality": "Quality history", "subcontract": "Subcontract reconciliation",
    "activity": "Transaction register", "components": "Component life", "stoppage": "Machine stoppage", "billing": "Source billing", "margin": "Margin before overhead"}
YARN_MOVEMENTS = {"yarn_inwards": "receive_yarn", "yarn_returns": "return_yarn"}
REPORTS.update(yarn_inwards="Yarn Inward Register", yarn_returns="Yarn Return Register")
FINANCIAL = {"billing", "margin"}


def filters(value):
    value = frappe.parse_json(value) if isinstance(value, str) else value or {}
    if not isinstance(value, dict) or set(value) - {"job", "mode", "from_date", "to_date", "start", "report", "roll", "event", "group_by", "kind", "machine", "operator", "production_operator", "production_machine", "employee", "customer", "shift", "warehouse", "source_lot", "party_dc_number", "fabric", "dia", "gauge"}:
        frappe.throw("Use supported report filters.")
    mode = value.get("mode", "as_of")
    if mode not in ("as_of", "period"):
        frappe.throw("Choose As of or Period.")
    end = getdate(value.get("to_date") or today())
    start = getdate(value.get("from_date") or end.replace(day=1)) if mode == "period" else getdate("1900-01-01")
    if start > end:
        frappe.throw("The report start cannot follow its finish.")
    offset = str(value.get("start", 0))
    if not offset.isdigit() or int(offset) > 1000000:
        frappe.throw("Choose a valid report page.")
    return {**value, "mode": mode, "from_date": str(start), "to_date": str(end), "start": int(offset),
            "begin": datetime.combine(start, time.min), "end": datetime.combine(end + timedelta(days=1), time.min)}


def event_rows(company, f, *, stoppage_intervals=False):
    where = {"company": company}
    related = set()
    if stoppage_intervals:
        # A maintenance interval can be entered after the machine returns to service.
        where.update(kind="stoppage", cancelled=0)
        if f.get("job"):
            where["job"] = f["job"]
    else:
        where["occurred_at"] = ["<", f["end"]]
        if f.get("job"):
            related.add(f["job"])
    if related:
        # Trace ancestors of transfers without scanning unrelated company history.
        while True:
            transfers = frappe.get_all("Knitting Event", filters={**where, "kind": "transfer_fabric"},
                or_filters=[["job", "in", list(related)], ["target_job", "in", list(related)]], fields=["job", "target_job"])
            expanded = related | {r.job for r in transfers if r.job} | {r.target_job for r in transfers if r.target_job}
            if expanded == related:
                break
            related = expanded
        for source_job in related:
            permissions.require_aggregate_scope(company, source_job)
    or_filters = [["job", "in", list(related)], ["target_job", "in", list(related)]] if related else None
    rows = frappe.get_all("Knitting Event", filters=where, fields=["name", "company", "job", "target_job", "kind", "actor", "payload", "result", "occurred_at", "reverses"],
                          or_filters=or_filters, order_by="occurred_at, creation, name", limit=100001)
    if len(rows) > 100000:
        frappe.throw("Narrow the report to a job before loading more than 100,000 source events.")
    permissions.require_event_sources(rows)
    for row in rows:
        row.payload, row.result = d.json_value(row.payload, {}), d.json_value(row.result, {})
    return rows


def quantity(value, field, sign):
    return sign * Decimal(value.get(field) or "0")


def voucher_expense(company, voucher, correction):
    criteria = {"company": company, "voucher_type": voucher["voucher_type"], "voucher_no": voucher["voucher"]}
    # ERPNext may mark original GL rows cancelled and append opposite entries.
    # The command event is created before the controller writes those reversals.
    if correction:
        criteria["creation"] = ["<", correction.creation]
    else:
        criteria["is_cancelled"] = 0
    entries = frappe.get_all("GL Entry", filters=criteria, fields=["account", "debit", "credit"])
    return sum((Decimal(str(row.debit)) - Decimal(str(row.credit)) for row in entries
                if frappe.get_cached_value("Account", row.account, "root_type") == "Expense"), d.ZERO)


def roll_states(company, events, f):
    names = [e.name for e in events]
    if not names:
        return []
    rows = frappe.get_all("Knitting Roll", filters={"company": company, "production": ["in", names]},
        fields=["name", "job", "programme_line", "weight_kg", "machine", "operator", "shift", "produced_at", "production", "parent_roll", "job_revision", "specification"])
    states = {r.name: "Awaiting QC" for r in rows}
    origins = {e.name: e for e in events}
    attribution_fields = ('production_machine_record', 'production_machine_label', 'production_machine_code',
        'production_operator_record', 'production_operator_label', 'production_operator_number')
    for row in rows:
        origin = origins[row.production]
        row.job = origin.job
        # A saved production pointer alone does not establish output membership.
        attribution = origin.result if row.name in origin.result.get('rolls', []) else {}
        if origin.kind == 'produce_bulk':
            # A programme can occur more than once with different machines or people.
            attribution = next((entry for entry in origin.result.get('entries', [])
                if row.name in entry.get('rolls', [])), {})
        row.update({key: attribution.get(key) for key in attribution_fields})
        spec = d.json_value(row.pop("specification"), {})
        row._dimension_spec, row._dimension_job = spec, row.job
        row.programme_line = spec.get("id", row.programme_line)
        row.update({key: spec.get(key) for key in ("fabric", "dia", "gauge")})
    # Children are historical only from their split event onward.
    splits = {child: e for e in events if e.kind == "split_roll" for child in e.result.get("rolls", [])}
    for row in rows:
        if row.parent_roll and row.name not in splits:
            states.pop(row.name, None)
    for event in events:
        r = event.result
        if event.kind == "quality" and r.get("roll") in states:
            states[r["roll"]] = r["decision"]
        if event.kind == "split_roll":
            states[r["parent_roll"]] = "Split"
            parent = next((row for row in rows if row.name == r["parent_roll"]), None)
            for child in r["rolls"]:
                states[child] = r["previous_state"]
                if parent:
                    for row in rows:
                        if row.name == child:
                            row.job, row.programme_line = parent.job, parent.programme_line
                            row.update({key: parent.get(key) for key in attribution_fields})
        if event.kind == "return_fabric":
            for name in r["rolls"]:
                states[name] = "Awaiting QC"
        if event.kind == "transfer_fabric":
            for row in rows:
                if row.name in r["rolls"]:
                    row.job, row.programme_line = r["target_job"], r["target_programme_line"]
                    states[row.name] = "Awaiting QC"
        if event.kind == "deliver":
            for name in r["rolls"]:
                states[name] = "Delivered"
    return [{**row, "state": states[row.name]} for row in rows if row.name in states and (not f.get("job") or row.job == f["job"]) and (f["mode"] != "period" or row.produced_at >= f["begin"])]


def batch_states(events, job=None):
    """Reconstruct aggregate stock from immutable snapshots, never today's batch."""
    batches = {}
    for event in events:
        result = event.result
        if event.kind in ("migration_stock_initialization", "produce_batch"):
            snapshots = result.get("batches", []) if event.kind == "migration_stock_initialization" else [result["batch_snapshot"]]
            for source in snapshots:
                if source.get("job") != event.job or source.get("name") in batches:
                    frappe.throw("The batch source snapshot needs review.")
                spec = source.get("specification") or {}
                batches[source["name"]] = {"name": source["name"], "job": source["job"],
                    "programme_line": source["programme_line"], "record_type": "Fabric batch",
                    "quantity_kg": Decimal(source["quantity_kg"]), "roll_count": Decimal(source["rolls"]),
                    "state": source["state"], "source_reference": source.get("source_reference"),
                    "captured_at": (source.get("captured_at") or event.occurred_at) if event.kind == "migration_stock_initialization" else None,
                    "produced_at": source.get("produced_at"), "production": source.get("production"),
                    "_dimension_spec": spec,
                    **{key: source.get(key) for key in ("machine", "operator", "production_operator_record", "production_operator_label", "production_operator_number", "production_machine_record", "production_machine_label", "production_machine_code", "shift", "warehouse", "job_revision")},
                    **{key: spec.get(key) for key in ("fabric", "dia", "gauge")}}
        elif event.kind in ("review_batch", "deliver_batch", "return_batch"):
            row = batches.get(result.get("batch"))
            if row is None or row["job"] != event.job:
                frappe.throw("This batch has no verified source snapshot. Review its production or Imported history.")
            if event.kind == "review_batch":
                row["state"] = result["state"]
            else:
                sign = -1 if event.kind == "deliver_batch" else 1
                row["quantity_kg"] += sign * Decimal(result["quantity_kg"])
                row["roll_count"] += sign * Decimal(result["roll_count"])
                if event.kind == "return_batch":
                    row["state"] = "Awaiting review"
    return [{**row, "quantity_kg": d.kg(row["quantity_kg"]), "roll_count": str(int(row["roll_count"]))}
        for row in batches.values() if not job or row["job"] == job]


def yarn_movement_rows(company, report, events, f):
    columns = ["occurred_at", "event", "quantity_kg", "units", "customer", "job", "item",
               "lot", "source_lot", "warehouse", "material_owner"]
    if report == "yarn_inwards":
        columns.extend(["party_dc_number", "party_dc_date"])
    movements = {e.name: e for e in events if e.kind == YARN_MOVEMENTS[report]}
    if not movements:
        return columns, []
    where = {"company": company, "event": ["in", list(movements)], "custodian": "Warehouse"}
    if f.get("warehouse"):
        where["warehouse"] = f["warehouse"]
    entries = frappe.get_all("Knitting Ledger Entry", filters=where,
        fields=["event", "quantity_kg", "units", "job", "party", "lot", "warehouse", "material_owner"])
    lots = {entry.lot for entry in entries}
    lot_data = {lot.name: lot for lot in frappe.get_list("Knitting Material Lot",
        filters={"company": company, "name": ["in", sorted(lots)]},
        fields=["name", "source_lot", "item"], limit=len(lots))} if lots else {}
    rows = []
    direction = -1 if report == "yarn_returns" else 1
    for entry in entries:
        event = movements[entry.event]
        lot = lot_data.get(entry.lot)
        if lot is None:
            frappe.throw("A material lot in this register is unavailable.", frappe.PermissionError)
        rows.append({**entry, "occurred_at": event.occurred_at, "customer": entry.party,
            "quantity_kg": d.kg(direction * Decimal(entry.quantity_kg)),
            "units": str(direction * Decimal(entry.units)) if entry.units not in (None, "") else None,
            "source_lot": lot.source_lot, "item": lot.item,
            "party_dc_number": event.result.get("party_dc_number"), "party_dc_date": event.result.get("party_dc_date")})
    return columns, rows


def require_supported_history(company, f):
    # Current captured stock does not establish any earlier movements or zeros.
    criteria = {"company": company, "migration_cutoff": [">=" if f["mode"] == "as_of" else ">",
        f["end"] if f["mode"] == "as_of" else f["begin"]]}
    if f.get("job"):
        criteria["name"] = f["job"]
    if f.get("customer"):
        criteria["customer"] = f["customer"]
    if frappe.db.exists("Knitting Job", criteria):
        frappe.throw("This operational report is unavailable before the imported stock capture. "
            "Use Imported history for original dates and transactions, or choose dates after the capture.")


def run(company, report, value=None, *, paged=True):
    permissions.require(company, "reports", history=True)
    if report not in REPORTS:
        frappe.throw("Choose a supported knitting report.")
    if report in FINANCIAL and "financial_read" not in permissions.capabilities():
        frappe.throw("This report includes financial values.", frappe.PermissionError)
    f = filters(value)
    permissions.require_aggregate_scope(company, f.get("job"))
    if f.get("job"):
        d.reference("Knitting Job", f["job"], company)
    require_supported_history(company, f)
    stoppage_intervals = report == "stoppage" and f["mode"] == "period"
    journal = event_rows(company, f, stoppage_intervals=stoppage_intervals)
    sources = {e.name: e for e in journal}
    corrections = {e.reverses for e in journal if e.reverses}
    history = [e for e in journal if e.name not in corrections and not e.reverses]
    period_flows = f["mode"] == "period" and report in {"jobs", "production", "subcontract", "billing", "margin", "yarn"}
    candidates = journal if period_flows or report == "activity" else history
    events = []
    for entry in candidates:
        if (not stoppage_intervals and entry.occurred_at < f["begin"]) or (f.get("job") and f["job"] not in (entry.job, entry.target_job)):
            continue
        if period_flows and entry.reverses:
            source = sources[entry.reverses]
            entry = frappe._dict({**entry, "kind": source.kind, "payload": source.payload, "result": source.result})
        events.append(entry)
    if f.get("customer") and report not in YARN_MOVEMENTS:
        events = [e for e in events if e.job and frappe.db.get_value("Knitting Job", e.job, "customer") == f["customer"]]
    event_by_name = {e.name: e for e in events}
    rows, columns = [], []
    summary = {}
    if report in ("shortages", "changes", "unplanned"):
        from .planning import project
        rows, columns, summary = project(company, report, f)
    elif report == "jobs":
        columns = ["job", "customer", "received_kg", "consumed_kg", "returned_kg", "produced_kg", "captured_produced_kg", "delivered_kg", "captured_delivered_kg", "billed_kg", "captured_billed_kg", "loss_kg", "yarn_kg", "subcontract_kg", "fabric_kg", "unbilled_kg", "fabric_transfer_in_kg", "fabric_transfer_out_kg", "yarn_transfer_in_kg", "yarn_transfer_out_kg"]
        jobs = frappe.get_list("Knitting Job", filters={"company": company, **({"name": f["job"]} if f.get("job") else {})}, fields=["name", "customer", "job_date", "creation"], limit=100000)
        historical_rolls = roll_states(company, history, {**f, "mode": "as_of"})
        historical_batches = batch_states(history, f.get("job"))
        for job in jobs:
            if getdate(job.job_date or job.creation) >= f["end"].date():
                continue
            totals = {k: d.ZERO for k in columns if k.endswith("_kg")}
            for event in events:
                if event.job != job.name and event.target_job != job.name:
                    continue
                r = event.result
                sign = -1 if event.reverses else 1
                if event.kind == "migration_stock_initialization" and f["mode"] == "as_of":
                    captured = sum((Decimal(row["quantity_kg"]) for row in r.get("programme_output", [])), d.ZERO)
                    totals["captured_produced_kg"] += captured
                    totals["produced_kg"] += captured
                if event.kind == "migration_billing_initialization" and f["mode"] == "as_of":
                    for key in ("delivered_kg", "billed_kg"):
                        captured = Decimal(r["captured_" + key])
                        totals["captured_" + key] += captured
                        totals[key] += captured
                if event.kind == "credit_invoice":
                    totals["billed_kg"] -= quantity(r, "quantity_kg", sign)
                if event.kind in ("return_fabric", "return_batch"):
                    totals["delivered_kg"] -= quantity(r, "quantity_kg", sign)
                if event.kind in ("transfer_fabric", "transfer_yarn"):
                    prefix = "fabric" if event.kind == "transfer_fabric" else "yarn"
                    totals[f"{prefix}_transfer_{'in' if event.target_job == job.name else 'out'}_kg"] += quantity(r, "quantity_kg", sign)
                key = {"receive_yarn": "received_kg", "allocate_yarn": "received_kg", "return_yarn": "returned_kg", "produce": "produced_kg", "produce_bulk": "produced_kg", "produce_batch": "produced_kg",
                    "subcontract_receive": "produced_kg", "deliver": "delivered_kg", "deliver_batch": "delivered_kg", "invoice": "billed_kg"}.get(event.kind)
                if key:
                    totals[key] += quantity(r, "quantity_kg", sign)
                if event.kind in ("produce", "produce_bulk", "produce_batch", "repack_yarn", "subcontract_receive"):
                    totals["consumed_kg"] += quantity(r, "consumed_kg", sign)
                    totals["loss_kg"] += quantity(r, "loss_kg", sign)
            for entry in frappe.get_all("Knitting Ledger Entry", filters={"company": company, "job": job.name}, fields=["quantity_kg", "custodian", "event"]):
                if entry.event in sources:
                    key = "yarn_kg" if entry.custodian == "Warehouse" else "subcontract_kg"
                    totals[key] += Decimal(entry.quantity_kg)
            totals["fabric_kg"] = sum((Decimal(r["weight_kg"]) for r in historical_rolls if r["job"] == job.name and r["state"] not in ("Split", "Delivered", "Cancelled")), d.ZERO)
            totals["fabric_kg"] += sum((Decimal(r["quantity_kg"]) for r in historical_batches if r["job"] == job.name), d.ZERO)
            totals["unbilled_kg"] = totals["delivered_kg"] - totals["billed_kg"]
            rows.append({"job": job.name, "customer": job.customer, **{k: d.kg(v) for k, v in totals.items()}})
    elif report in YARN_MOVEMENTS:
        columns, rows = yarn_movement_rows(company, report, events, f)
    elif report == "yarn":
        dimensions = ["lot", "job", "material_owner", "party", "custodian", "warehouse"]
        columns = [*dimensions, "quantity_kg", "units"]
        totals = {}
        unit_totals = {}
        for entry in frappe.get_all("Knitting Ledger Entry", filters={"company": company, **({"job": f["job"]} if f.get("job") else {})}, fields=[*columns, "event"]):
            if entry.event not in event_by_name:
                continue
            key = tuple(entry.get(k) for k in dimensions)
            totals[key] = totals.get(key, d.ZERO) + Decimal(entry.quantity_kg)
            unit_totals[key] = unit_totals.get(key, d.ZERO) + Decimal(entry.units or "0")
        rows = [{**dict(zip(dimensions, key)), "quantity_kg": d.kg(q), "units": str(unit_totals[key])} for key, q in totals.items() if q or unit_totals[key]]
    elif report in ("rolls", "fabric"):
        columns = ["name", "job", "programme_line", "weight_kg", "state", "machine", "operator", "shift", "fabric", "dia", "gauge", "produced_at", "job_revision", "parent_roll"]
        if report == "rolls":
            columns.remove("produced_at")
            columns.insert(0, "produced_at")
        rows = roll_states(company, history, {**f, "mode": "as_of"} if report == "fabric" else f)
        if report == "fabric":
            rows = [r for r in rows if r["state"] not in ("Delivered", "Split", "Cancelled")]
            columns.extend(["record_type", "quantity_kg", "roll_count", "source_reference", "captured_at", "production"])
            rows = [{**r, "record_type": "Individual roll", "quantity_kg": r["weight_kg"], "roll_count": "1"} for r in rows]
            rows.extend(batch_states(history, f.get("job")))
    elif report in ("production", "stoppage", "planning", "quality"):
        kinds = {"production": ("produce", "produce_bulk", "produce_batch", "subcontract_receive"), "stoppage": ("stoppage",), "planning": ("plan",), "quality": ("quality", "review_batch")}[report]
        columns = {"production": ["event", "job", "occurred_at", "machine", "quantity_kg", "roll_count", "consumed_kg", "loss_kg"],
            "stoppage": ["event", "machine", "minutes", "starts_at", "ends_at", "reason", "warehouse", "shift"],
            "planning": ["plan", "job", "machine", "starts_at", "ends_at", "quantity_kg"],
            "quality": ["event", "job", "roll", "batch", "decision", "remarks", "occurred_at"]}[report]
        for event in events:
            if event.kind in kinds:
                entries = event.result.get("entries", []) if event.kind == "produce_bulk" else [{**event.payload, **event.result}]
                for entry in entries:
                    row = {**entry, "event": event.name, "job": event.job, "operator": event.actor, "occurred_at": event.occurred_at}
                    if report == "production" and event.reverses:
                        row["operator"] = sources[event.reverses].actor
                    if event.kind == "stoppage":
                        for key in ("warehouse", "shift"):
                            row[key] = event.result.get(key)
                        if stoppage_intervals:
                            begin = max(get_datetime(row["starts_at"]), f["begin"])
                            end = min(get_datetime(row["ends_at"]), f["end"])
                            if end <= begin:
                                continue
                            row["minutes"] = str(Decimal(str((end - begin).total_seconds())) / 60)
                    if event.kind == "review_batch":
                        row["decision"] = event.result["state"]
                    if report == "production":
                        # Attribution is resolved by the posting service; payload labels are never evidence.
                        attribution = entry if event.kind == 'produce_bulk' else event.result
                        for key in ('production_operator_record', 'production_operator_label', 'production_operator_number',
                                'production_machine_record', 'production_machine_label', 'production_machine_code'):
                            row[key] = attribution.get(key)
                        row["roll_count"] = str(entry["roll_count"] if "roll_count" in entry else len(entry.get("rolls", [])))
                    if event.reverses and report == "production":
                        for field in ("quantity_kg", "consumed_kg", "loss_kg"):
                            row[field] = d.kg(quantity(entry, field, -1))
                        row["roll_count"] = str(-int(row["roll_count"]))
                    rows.append(row)
        if report == "planning" and f["mode"] == "as_of":
            rows = list({r["plan"]: r for r in rows}.values())
    elif report == "subcontract":
        columns = ["subcontract", "job", "supplier", "ordered_kg", "issued_kg", "received_kg", "returned_kg", "custody_kg", "billed_kg"]
        for event in history:
            if event.kind != "create_subcontract" or f.get("job") and event.job != f["job"]:
                continue
            sub = event.result["subcontract"]
            totals = {"issued_kg": d.ZERO, "received_kg": d.ZERO, "returned_kg": d.ZERO, "billed_kg": d.ZERO}
            for move in events:
                key = {"subcontract_issue": "issued_kg", "subcontract_receive": "received_kg", "subcontract_return": "returned_kg", "subcontract_bill": "billed_kg"}.get(move.kind)
                if key and move.result.get("subcontract") == sub:
                    totals[key] += quantity(move.result, "quantity_kg", -1 if move.reverses else 1)
            custody = sum((Decimal(e.quantity_kg) for e in frappe.get_all("Knitting Ledger Entry", filters={"company": company, "custodian": "SC:" + sub}, fields=["quantity_kg", "event"]) if e.event in sources), d.ZERO)
            ordered = event.result["quantity_kg"] if event.occurred_at >= f["begin"] else d.kg(d.ZERO)
            rows.append({"subcontract": sub, "job": event.job, "supplier": event.payload["supplier"], "ordered_kg": ordered, "custody_kg": d.kg(custody), **{k: d.kg(v) for k, v in totals.items()}})
    elif report == "components":
        columns = ["component", "machine", "component_type", "boundary_kg", "run_kg", "remaining_kg"]
        components = {}
        for event in history:
            p, r = event.payload, event.result
            if event.kind == "create_component":
                components[r["component"]] = {"component": r["component"], "machine": p["machine"], "component_type": p["component_type"], "boundary_kg": p["boundary_kg"], "run": d.ZERO}
            elif event.kind == "replace_component" and r["component"] in components:
                components[r["component"]].update(run=d.ZERO, boundary_kg=r["boundary_kg"])
            elif event.kind in ("produce", "produce_bulk", "produce_batch", "subcontract_receive"):
                batches = r.get("entries", []) if event.kind == "produce_bulk" else [{**r, "machine": p.get("machine")}]
                for batch in batches:
                    for component in components.values():
                        if component["machine"] == batch.get("machine"):
                            component["run"] += Decimal(batch["quantity_kg"])
        rows = [{**c, "run_kg": d.kg(c["run"]), "boundary_kg": d.kg(c["boundary_kg"]), "remaining_kg": d.kg(Decimal(c["boundary_kg"]) - c["run"])} for c in components.values()]
    elif report == 'breakage':
        columns = ['event', 'job', 'component', 'component_type', 'machine', 'operator', 'employee', 'gauge', 'dia', 'fabric', 'quantity', 'reason', 'occurred_at']
        rows = [{**e.result, 'event': e.name, 'occurred_at': e.occurred_at} for e in events if e.kind == 'component_breakage']
    elif report == "activity":
        columns = ["event", "job", "kind", "reverses", "operator", "occurred_at", "machine", "programme_line", "quantity_kg", "loss_kg"]
        rows = [{"event": e.name, "job": e.job, "kind": e.kind, "operator": e.actor, "occurred_at": e.occurred_at,
            "reverses": e.reverses, "machine": e.payload.get("machine"), "programme_line": e.payload.get("programme_line"),
            "quantity_kg": e.result.get("quantity_kg"), "loss_kg": e.result.get("loss_kg")} for e in events]
    else:
        columns = ["event", "job", "invoice", "posting_date", "currency", "quantity_kg", "net_amount", "tax_amount", "grand_total", "outstanding"]
        cost_kinds = {"produce", "produce_bulk", "subcontract_receive", "subcontract_bill", "deliver", "return_fabric"}
        cost_sources = {e.reverses or e.name for e in events if e.kind in cost_kinds}
        # A later cancellation also affects how ERPNext currently stores historical GL rows.
        source_corrections = {row.reverses: row for row in frappe.get_all("Knitting Event",
            filters={"company": company, "reverses": ["in", list(cost_sources)]}, fields=["reverses", "creation"])} if cost_sources else {}
        for event in events:
            sign = -1 if event.reverses else 1
            if event.kind in ("invoice", "credit_invoice"):
                doc = d.reference("Sales Invoice", event.result["invoice"], company)
                kg_sign = -sign if event.kind == "credit_invoice" else sign
                rows.append({"event": event.name, "job": event.job, "invoice": doc.name, "posting_date": doc.posting_date, "currency": frappe.get_cached_value("Company", company, "default_currency"),
                    "quantity_kg": d.kg(quantity(event.result, "quantity_kg", kg_sign)), "net_amount": d.money(sign * doc.base_net_total), "tax_amount": d.money(sign * doc.base_total_taxes_and_charges),
                    "grand_total": d.money(sign * doc.base_grand_total), "outstanding": d.money(doc.outstanding_amount * doc.conversion_rate if doc.docstatus == 1 else 0)})
            if event.kind in cost_kinds:
                vouchers = event.result.get("vouchers", []) or ([event.result] if event.result.get("voucher") else [])
                batches = {entry["voucher"]: entry for entry in event.result.get("entries", []) if entry.get("voucher")}
                for voucher in vouchers:
                    batch = batches.get(voucher["voucher"], {})
                    cost = sign * voucher_expense(company, voucher, source_corrections.get(event.reverses or event.name))
                    rows.append({"event": event.name, "job": event.job, "_posted_cost": cost,
                        **{key: batch[key] for key in ("machine", "shift", "programme_line") if key in batch}})
    dimensions = ("customer", "machine", "operator", "production_operator", "production_machine", "employee", "gauge", "shift", "day", "hour", "fabric", "dia", "programme_line", "kind")
    group = f.get("group_by")
    if report in YARN_MOVEMENTS:
        dimensions = ("customer", "day", "hour", "warehouse", "source_lot")
    if group and group not in dimensions and not (report == "rolls" and group == "employee_hour"):
        frappe.throw("Choose a supported report grouping.")
    for row in rows:
        row['production_operator'] = row.get('production_operator_record')
        row['production_machine'] = row.get('production_machine_record')
        job = row.get("job")
        if job and not row.get("customer"):
            row["customer"] = frappe.db.get_value("Knitting Job", job, "customer")
        timestamp = row.get("produced_at") if report == "rolls" else row.get("occurred_at")
        if timestamp:
            row["day"] = str(timestamp)[:10]
            row["hour"] = str(timestamp)[:13] + ":00"
        if row.get("event"):
            source = event_by_name.get(row["event"])
            if source:
                row.setdefault("operator", source.actor)
                row.setdefault("kind", source.kind)
                for key in ("shift", "programme_line", "machine"):
                    row.setdefault(key, source.payload.get(key))
                spec = None
                if source.kind == "produce_batch":
                    spec = source.result.get("batch_snapshot", {}).get("specification")
                elif source.kind in ("produce", "produce_bulk", "subcontract_receive"):
                    spec = frappe.db.get_value("Knitting Roll", {"production": source.reverses or source.name,
                        **({"programme_line": row["programme_line"]} if row.get("programme_line") else {})}, "specification")
                if spec:
                    spec = d.json_value(spec, {})
                    row.update({key: spec.get(key) for key in ("fabric", "dia", "gauge")})
                    row['_dimension_spec'] = spec
    from erp_extensions.migration.dimensions import report_rows
    report_rows(company, rows)
    if any('source_dia_id' in row for row in rows):
        columns = list(dict.fromkeys([*columns, 'source_dia_id']))
    for key in ("customer", "machine", "operator", "production_operator", "production_machine", "employee", "gauge", "shift", "warehouse", "source_lot", "party_dc_number", "fabric", "dia", "kind"):
        if f.get(key):
            rows = [row for row in rows if str(row.get(key) or "") == str(f[key])]
    # Summaries describe all matching source rows regardless of grouping or page.
    if report in ("rolls", "fabric"):
        quantity_key = "quantity_kg" if report == "fabric" else "weight_kg"
        summary["quantity_kg"] = d.kg(sum((Decimal(row[quantity_key]) for row in rows if row["state"] != "Split"), d.ZERO))
        if report == "fabric":
            summary["roll_count"] = str(sum((Decimal(row["roll_count"]) for row in rows), d.ZERO))
    elif report == "stoppage":
        summary["minutes"] = format(sum((Decimal(row["minutes"]) for row in rows), d.ZERO), ".2f")
    elif report == "breakage":
        summary["quantity"] = str(sum((Decimal(row["quantity"]) for row in rows), d.ZERO))
    elif report == "production":
        summary = {key: d.kg(sum((Decimal(row.get(key) or 0) for row in rows), d.ZERO)) for key in ("quantity_kg", "loss_kg")}
    elif report == "yarn" or report in YARN_MOVEMENTS:
        summary["quantity_kg"] = d.kg(sum((Decimal(row["quantity_kg"]) for row in rows), d.ZERO))
        summary["units"] = (None if any(row.get("units") is None for row in rows)
            else str(sum((Decimal(row["units"]) for row in rows), d.ZERO)))
    elif report in ("shortages", "changes", "unplanned"):
        summary["records"] = len(rows)
    elif report in FINANCIAL:
        # Cost vouchers participate in the same filters but do not appear as invoices.
        cost = sum((row["_posted_cost"] for row in rows if "_posted_cost" in row), d.ZERO)
        rows = [row for row in rows if "_posted_cost" not in row]
        net = sum((Decimal(row["net_amount"]) for row in rows), d.ZERO)
        summary = {"net_amount": d.money(net), "posted_cost": d.money(cost), "margin_before_overhead": d.money(net - cost)}
    if report in ("production", "activity", "planning", "stoppage", "quality"):
        columns = list(dict.fromkeys([*columns, "customer", "operator", "shift", "fabric", "dia", "programme_line"]))
    if report in ('production', 'fabric', 'rolls'):
        columns.extend(['production_operator_record', 'production_operator_label', 'production_operator_number',
            'production_machine_record', 'production_machine_label', 'production_machine_code'])
    if group:
        numeric = [key for key in columns if key.endswith("_kg") or key in ("quantity", "units", "roll_count", "minutes", "net_amount", "tax_amount", "grand_total", "outstanding")]
        grouped = {}
        group_fields = ["hour", "production_operator"] if group == "employee_hour" else [group]
        for row in rows:
            identity = {field: str(row.get(field) or "Unspecified") for field in group_fields}
            entry = grouped.setdefault(tuple(identity.values()), {**identity, "records": 0, **{n: d.ZERO for n in numeric}})
            if 'production_operator' in group_fields:
                entry['production_operator_label'] = row.get('production_operator_label') or 'Unrecorded'
                entry['production_operator_number'] = row.get('production_operator_number')
            if group == 'production_machine':
                entry['production_machine_label'] = row.get('production_machine_label') or 'Unrecorded'
                entry['production_machine_code'] = row.get('production_machine_code')
            entry["records"] += 1
            for key in numeric:
                if report == "rolls" and key == "weight_kg" and row["state"] == "Split":
                    continue
                if ((key == "weight_kg" and row.get("record_type") == "Fabric batch")
                        or (report in YARN_MOVEMENTS and key == "units" and row.get("units") is None)):
                    entry[key] = None
                elif entry[key] is not None:
                    entry[key] += Decimal(str(row.get(key) or 0))
        rows = [{**row, **{key: None if row[key] is None else d.kg(row[key]) if key.endswith("_kg") else str(row[key]) if key in ('quantity', 'units', 'roll_count') else d.money(row[key]) for key in numeric}} for row in grouped.values()]
        columns = list(group_fields)
        if 'production_operator' in group_fields:
            columns.extend(['production_operator_label', 'production_operator_number'])
        if group == 'production_machine':
            columns.extend(['production_machine_label', 'production_machine_code'])
        columns.extend(["records", *numeric])
    # Only declared output columns can cross the permission boundary.
    rows = [{key: row.get(key) for key in columns} for row in rows]
    rows.sort(key=lambda r: tuple(str(r.get(k) or "") for k in columns[:2]))
    count = len(rows)
    if paged:
        rows = rows[f["start"]:f["start"] + 100]
    return {"version": 1, "company": company, "report": report, "title": REPORTS[report], "mode": f["mode"], "from_date": f["from_date"], "to_date": f["to_date"],
        "columns": [{"key": k, "label": "Roll history records" if report == "rolls" and k == "records" else k.replace("_", " ").title(),
            "type": "kg" if k.endswith("_kg") else "text"} for k in columns],
        "rows": rows, "summary": summary, "row_count": count, "start": f["start"], "has_more": paged and count > f["start"] + 100,
        "basis": "Confirmed quantities for the selected receipt or return dates. Units come from the recorded custody movement." if report in YARN_MOVEMENTS else
            "Minutes are the portion of each recorded maintenance interval inside the selected dates." if stoppage_intervals else
            "Quantities through end date; period flows use the selected dates while custody is closing balance. "
            "Imported batches begin at their captured baseline; original movements remain in Imported history. "
            "Batch quantity and count are aggregate measurements, not individual roll weights. "
            "Financial amounts use company currency and current outstanding."}
