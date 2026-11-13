"""Operational report projections from immutable events and standard accounting sources."""
from datetime import datetime, time, timedelta
from decimal import Decimal

import frappe
from frappe.utils import getdate, get_datetime, today
from . import domain as d, permissions

REPORTS = {"breakage": "Component breakage", "shortages": "72-hour yarn coverage", "changes": "24-hour job changes", "unplanned": "Planning status", "jobs": "Job reconciliation", "yarn": "Yarn custody", "fabric": "Fabric in house", "rolls": "Roll traceability",
    "planning": "Machine allocations", "production": "Production and loss", "quality": "Quality history", "subcontract": "Subcontract reconciliation",
    "activity": "Transaction register", "components": "Component life", "stoppage": "Machine stoppage", "billing": "Source billing", "margin": "Margin before overhead"}
FINANCIAL = {"billing", "margin"}


def filters(value):
    value = frappe.parse_json(value) if isinstance(value, str) else value or {}
    if not isinstance(value, dict) or set(value) - {"job", "mode", "from_date", "to_date", "start", "report", "roll", "event", "group_by", "kind", "machine", "operator", "employee", "customer", "shift", "fabric", "dia", "gauge"}:
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


def event_rows(company, f, *, all_history=False):
    where = {"company": company, "occurred_at": ["<", f["end"]]}
    related = {f["job"]} if f.get("job") else set()
    if related and all_history:
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
    rows = frappe.get_all("Knitting Event", filters=where, fields=["name", "job", "target_job", "kind", "actor", "payload", "result", "occurred_at", "reverses"],
                          or_filters=or_filters, order_by="occurred_at, creation, name", limit=100001)
    if len(rows) > 100000:
        frappe.throw("Narrow the report to a job before loading more than 100,000 source events.")
    cancelled = {row.reverses for row in rows if row.kind == "cancel_event"}
    result = []
    for row in rows:
        if row.name in cancelled or row.kind == "cancel_event":
            continue
        if not all_history and row.occurred_at < f["begin"]:
            continue
        row.payload, row.result = d.json_value(row.payload, {}), d.json_value(row.result, {})
        if not all_history and f.get("job") and row.job != f["job"] and row.target_job != f["job"]:
            continue
        result.append(row)
    return result


def roll_states(company, events, f):
    names = [e.name for e in events]
    if not names:
        return []
    rows = frappe.get_all("Knitting Roll", filters={"company": company, "production": ["in", names]},
        fields=["name", "job", "programme_line", "weight_kg", "machine", "produced_at", "production", "parent_roll", "job_revision"])
    states = {r.name: "Awaiting QC" for r in rows}
    origins = {e.name: e for e in events}
    for row in rows:
        row.job = origins[row.production].job
        row.programme_line = d.json_value(frappe.db.get_value("Knitting Roll", row.name, "specification"), {}).get("id", row.programme_line)
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
    events = event_rows(company, f)
    if f.get("customer"):
        events = [e for e in events if e.job and frappe.db.get_value("Knitting Job", e.job, "customer") == f["customer"]]
    history = event_rows(company, f, all_history=True)
    event_by_name = {e.name: e for e in history}
    rows, columns = [], []
    summary = {}
    if report in ("shortages", "changes", "unplanned"):
        from .planning import project
        rows, columns, summary = project(company, report, f)
    elif report == "jobs":
        columns = ["job", "customer", "received_kg", "consumed_kg", "returned_kg", "produced_kg", "delivered_kg", "billed_kg", "loss_kg", "yarn_kg", "subcontract_kg", "fabric_kg", "unbilled_kg", "fabric_transfer_in_kg", "fabric_transfer_out_kg", "yarn_transfer_in_kg", "yarn_transfer_out_kg"]
        jobs = frappe.get_list("Knitting Job", filters={"company": company, **({"name": f["job"]} if f.get("job") else {})}, fields=["name", "customer", "creation"], limit=100000)
        historical_rolls = roll_states(company, history, {**f, "mode": "as_of"})
        for job in jobs:
            if job.creation >= f["end"]:
                continue
            totals = {k: d.ZERO for k in columns if k.endswith("_kg")}
            for event in events:
                if event.job != job.name and event.target_job != job.name:
                    continue
                r = event.result
                if event.kind == "credit_invoice":
                    totals["billed_kg"] -= Decimal(r["quantity_kg"])
                if event.kind == "return_fabric":
                    totals["delivered_kg"] -= Decimal(r["quantity_kg"])
                if event.kind in ("transfer_fabric", "transfer_yarn"):
                    prefix = "fabric" if event.kind == "transfer_fabric" else "yarn"
                    totals[f"{prefix}_transfer_{'in' if event.target_job == job.name else 'out'}_kg"] += Decimal(r["quantity_kg"])
                key = {"receive_yarn": "received_kg", "allocate_yarn": "received_kg", "return_yarn": "returned_kg", "produce": "produced_kg", "produce_bulk": "produced_kg",
                    "subcontract_receive": "produced_kg", "deliver": "delivered_kg", "invoice": "billed_kg"}.get(event.kind)
                if key:
                    totals[key] += Decimal(r.get("quantity_kg", "0"))
                if event.kind in ("produce", "produce_bulk", "repack_yarn", "subcontract_receive"):
                    totals["consumed_kg"] += Decimal(r.get("consumed_kg", "0"))
                    totals["loss_kg"] += Decimal(r.get("loss_kg", "0"))
            for entry in frappe.get_all("Knitting Ledger Entry", filters={"company": company, "job": job.name}, fields=["quantity_kg", "custodian", "event"]):
                if entry.event in event_by_name:
                    key = "yarn_kg" if entry.custodian == "Warehouse" else "subcontract_kg"
                    totals[key] += Decimal(entry.quantity_kg)
            totals["fabric_kg"] = sum((Decimal(r["weight_kg"]) for r in historical_rolls if r["job"] == job.name and r["state"] not in ("Split", "Delivered", "Cancelled")), d.ZERO)
            totals["unbilled_kg"] = totals["delivered_kg"] - totals["billed_kg"]
            rows.append({"job": job.name, "customer": job.customer, **{k: d.kg(v) for k, v in totals.items()}})
    elif report == "yarn":
        dimensions = ["lot", "job", "material_owner", "party", "custodian", "warehouse"]
        columns = [*dimensions, "quantity_kg", "units"]
        totals = {}
        unit_totals = {}
        for entry in frappe.get_all("Knitting Ledger Entry", filters={"company": company, **({"job": f["job"]} if f.get("job") else {})}, fields=[*columns, "event"]):
            if entry.event not in (event_by_name if f["mode"] == "as_of" else {e.name: e for e in events}):
                continue
            key = tuple(entry.get(k) for k in dimensions)
            totals[key] = totals.get(key, d.ZERO) + Decimal(entry.quantity_kg)
            unit_totals[key] = unit_totals.get(key, d.ZERO) + Decimal(entry.units or "0")
        rows = [{**dict(zip(dimensions, key)), "quantity_kg": d.kg(q), "units": str(unit_totals[key])} for key, q in totals.items() if q or unit_totals[key]]
        summary["quantity_kg"] = d.kg(sum(totals.values(), d.ZERO))
        summary["units"] = str(sum(unit_totals.values(), d.ZERO))
    elif report in ("rolls", "fabric"):
        columns = ["name", "job", "programme_line", "weight_kg", "state", "machine", "produced_at", "job_revision", "parent_roll"]
        rows = roll_states(company, history, {**f, "mode": "as_of"} if report == "fabric" else f)
        if report == "fabric":
            rows = [r for r in rows if r["state"] not in ("Delivered", "Split", "Cancelled")]
        summary["quantity_kg"] = d.kg(sum((Decimal(r["weight_kg"]) for r in rows if r["state"] != "Split"), d.ZERO))
    elif report in ("production", "stoppage", "planning", "quality"):
        kinds = {"production": ("produce", "produce_bulk", "subcontract_receive"), "stoppage": ("stoppage",), "planning": ("plan",), "quality": ("quality",)}[report]
        columns = {"production": ["event", "job", "occurred_at", "machine", "quantity_kg", "consumed_kg", "loss_kg"],
            "stoppage": ["event", "machine", "starts_at", "ends_at", "minutes", "reason"],
            "planning": ["plan", "job", "machine", "starts_at", "ends_at", "quantity_kg"],
            "quality": ["event", "job", "roll", "decision", "remarks", "occurred_at"]}[report]
        for event in events:
            if event.kind in kinds:
                entries = event.result.get("entries", []) if event.kind == "produce_bulk" else [{**event.payload, **event.result}]
                rows.extend({**entry, "event": event.name, "job": event.job, "operator": event.actor, "occurred_at": event.occurred_at} for entry in entries)
        if report == "planning" and f["mode"] == "as_of":
            rows = list({r["plan"]: r for r in rows}.values())
        if report == "production":
            summary["quantity_kg"] = d.kg(sum((Decimal(r["quantity_kg"]) for r in rows), d.ZERO))
            summary["loss_kg"] = d.kg(sum((Decimal(r["loss_kg"]) for r in rows), d.ZERO))
    elif report == "subcontract":
        columns = ["subcontract", "job", "supplier", "ordered_kg", "issued_kg", "received_kg", "returned_kg", "custody_kg", "billed_kg"]
        for event in history:
            if event.kind != "create_subcontract" or f.get("job") and event.job != f["job"]:
                continue
            sub = event.result["subcontract"]
            totals = {"issued_kg": d.ZERO, "received_kg": d.ZERO, "returned_kg": d.ZERO, "billed_kg": d.ZERO}
            for move in history:
                key = {"subcontract_issue": "issued_kg", "subcontract_receive": "received_kg", "subcontract_return": "returned_kg", "subcontract_bill": "billed_kg"}.get(move.kind)
                if key and move.result.get("subcontract") == sub:
                    totals[key] += Decimal(move.result["quantity_kg"])
            custody = sum((Decimal(e.quantity_kg) for e in frappe.get_all("Knitting Ledger Entry", filters={"company": company, "custodian": "SC:" + sub}, fields=["quantity_kg", "event"]) if e.event in event_by_name), d.ZERO)
            rows.append({"subcontract": sub, "job": event.job, "supplier": event.payload["supplier"], "ordered_kg": event.result["quantity_kg"], "custody_kg": d.kg(custody), **{k: d.kg(v) for k, v in totals.items()}})
    elif report == "components":
        columns = ["component", "machine", "component_type", "boundary_kg", "run_kg", "remaining_kg"]
        components = {}
        for event in history:
            p, r = event.payload, event.result
            if event.kind == "create_component":
                components[r["component"]] = {"component": r["component"], "machine": p["machine"], "component_type": p["component_type"], "boundary_kg": p["boundary_kg"], "run": d.ZERO}
            elif event.kind == "replace_component" and r["component"] in components:
                components[r["component"]].update(run=d.ZERO, boundary_kg=r["boundary_kg"])
            elif event.kind in ("produce", "produce_bulk", "subcontract_receive"):
                batches = r.get("entries", []) if event.kind == "produce_bulk" else [{**r, "machine": p.get("machine")}]
                for batch in batches:
                    for component in components.values():
                        if component["machine"] == batch.get("machine"):
                            component["run"] += Decimal(batch["quantity_kg"])
        rows = [{**c, "run_kg": d.kg(c["run"]), "boundary_kg": d.kg(c["boundary_kg"]), "remaining_kg": d.kg(Decimal(c["boundary_kg"]) - c["run"])} for c in components.values()]
    elif report == 'breakage':
        columns = ['event', 'job', 'component', 'component_type', 'machine', 'operator', 'employee', 'gauge', 'dia', 'fabric', 'quantity', 'reason', 'occurred_at']
        rows = [{**e.result, 'event': e.name, 'occurred_at': e.occurred_at} for e in events if e.kind == 'component_breakage']
        summary['quantity'] = str(sum((Decimal(r['quantity']) for r in rows), d.ZERO))
    elif report == "activity":
        columns = ["event", "job", "kind", "operator", "occurred_at", "machine", "programme_line", "quantity_kg", "loss_kg"]
        rows = [{"event": e.name, "job": e.job, "kind": e.kind, "operator": e.actor, "occurred_at": e.occurred_at,
            "machine": e.payload.get("machine"), "programme_line": e.payload.get("programme_line"),
            "quantity_kg": e.result.get("quantity_kg"), "loss_kg": e.result.get("loss_kg")} for e in events]
    else:
        columns = ["event", "job", "invoice", "posting_date", "currency", "quantity_kg", "net_amount", "tax_amount", "grand_total", "outstanding"]
        cost = d.ZERO
        for event in events:
            if event.kind in ("invoice", "credit_invoice"):
                doc = d.reference("Sales Invoice", event.result["invoice"], company)
                rows.append({"event": event.name, "job": event.job, "invoice": doc.name, "posting_date": doc.posting_date, "currency": frappe.get_cached_value("Company", company, "default_currency"),
                    "quantity_kg": d.kg(Decimal(event.result["quantity_kg"]) * (-1 if event.kind == "credit_invoice" else 1)), "net_amount": d.money(doc.base_net_total), "tax_amount": d.money(doc.base_total_taxes_and_charges),
                    "grand_total": d.money(doc.base_grand_total), "outstanding": d.money(doc.outstanding_amount * doc.conversion_rate)})
            if event.kind in ("produce", "produce_bulk", "subcontract_receive", "subcontract_bill", "deliver", "return_fabric"):
                vouchers = event.result.get("vouchers", []) or ([{"voucher": event.result["voucher"]}] if event.result.get("voucher") else [])
                for voucher in vouchers:
                    for gl in frappe.get_all("GL Entry", filters={"company": company, "voucher_no": voucher["voucher"], "is_cancelled": 0}, fields=["account", "debit", "credit"]):
                        if frappe.get_cached_value("Account", gl.account, "root_type") == "Expense":
                            cost += Decimal(str(gl.debit)) - Decimal(str(gl.credit))
        net = sum((Decimal(r["net_amount"]) for r in rows), d.ZERO)
        summary = {"net_amount": d.money(net), "posted_cost": d.money(cost), "margin_before_overhead": d.money(net - cost)}
    dimensions = ("customer", "machine", "operator", "employee", "gauge", "shift", "day", "hour", "fabric", "dia", "programme_line", "kind")
    group = f.get("group_by")
    if group and group not in dimensions:
        frappe.throw("Choose a supported report grouping.")
    for row in rows:
        job = row.get("job")
        if job:
            row["customer"] = frappe.db.get_value("Knitting Job", job, "customer")
        if row.get("occurred_at"):
            row["day"] = str(row["occurred_at"])[:10]
            row["hour"] = str(row["occurred_at"])[:13] + ":00"
        if row.get("event"):
            source = event_by_name.get(row["event"])
            if source:
                row.setdefault("operator", source.actor)
                row.setdefault("kind", source.kind)
                for key in ("shift", "programme_line", "machine"):
                    row.setdefault(key, source.payload.get(key))
                spec = frappe.db.get_value("Knitting Roll", {"production": source.name, **({"programme_line": row["programme_line"]} if row.get("programme_line") else {})}, "specification") if source.kind in ("produce", "produce_bulk", "subcontract_receive") else None
                if spec:
                    spec = d.json_value(spec, {})
                    row.update({key: spec.get(key) for key in ("fabric", "dia", "gauge")})
    for key in ("customer", "machine", "operator", "shift", "fabric", "dia", "kind"):
        if f.get(key):
            rows = [row for row in rows if str(row.get(key) or "") == str(f[key])]
    if report in ("production", "activity", "planning", "stoppage", "quality"):
        columns = list(dict.fromkeys([*columns, "customer", "operator", "shift", "fabric", "dia", "programme_line"]))
    if group:
        numeric = [key for key in columns if key.endswith("_kg") or key in ("quantity", "units", "minutes", "net_amount", "tax_amount", "grand_total", "outstanding")]
        grouped = {}
        for row in rows:
            key = str(row.get(group) or "Unspecified")
            entry = grouped.setdefault(key, {group: key, "records": 0, **{n: d.ZERO for n in numeric}})
            entry["records"] += 1
            for key in numeric:
                entry[key] += Decimal(str(row.get(key) or 0))
        rows = [{**row, **{key: d.kg(row[key]) if key.endswith("_kg") else str(row[key]) if key in ('quantity', 'units') else d.money(row[key]) for key in numeric}} for row in grouped.values()]
        columns = [group, "records", *numeric]
    if report == "production":
        summary = {"quantity_kg": d.kg(sum((Decimal(row.get("quantity_kg") or 0) for row in rows), d.ZERO)),
                   "loss_kg": d.kg(sum((Decimal(row.get("loss_kg") or 0) for row in rows), d.ZERO))}
    # Only declared output columns can cross the permission boundary.
    rows = [{key: row.get(key) for key in columns} for row in rows]
    rows.sort(key=lambda r: tuple(str(r.get(k) or "") for k in columns[:2]))
    count = len(rows)
    if paged:
        rows = rows[f["start"]:f["start"] + 100]
    return {"version": 1, "company": company, "report": report, "title": REPORTS[report], "mode": f["mode"], "from_date": f["from_date"], "to_date": f["to_date"],
        "columns": [{"key": k, "label": k.replace("_", " ").title(), "type": "kg" if k.endswith("_kg") else "text"} for k in columns],
        "rows": rows, "summary": summary, "row_count": count, "start": f["start"], "has_more": paged and count > f["start"] + 100,
        "basis": "Quantities through end date; period flows use the selected dates while custody is closing balance. Financial amounts use company currency and current outstanding."}
