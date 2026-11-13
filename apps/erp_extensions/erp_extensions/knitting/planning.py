"""Current queue outlook. Explicit input demand, never an invented knitting conversion formula."""
from datetime import timedelta
from decimal import Decimal, ROUND_CEILING
import frappe
from frappe.utils import now_datetime, today
from . import domain as d


def project(company, report, f):
    if f["mode"] != "as_of" or f["to_date"] != today():
        frappe.throw("Factory outlook uses the current queue. Choose As of today; historical allocations remain in Machine allocations.")
    now = now_datetime()
    jobs = frappe.get_list("Knitting Job", filters={"company": company, "status": "Running", **({"name": f["job"]} if f.get("job") else {})}, fields=["name", "customer", "target_kg"], limit=10000)
    by_job = {j.name: j for j in jobs}
    balances = {j.name: d.balances(j.name) for j in jobs}
    plans = frappe.get_list("Knitting Plan", filters={"company": company, "state": ["in", ["Planned", "Started"]]},
        fields=["name", "job", "machine", "starts_at", "ends_at", "quantity_kg", "produced_kg", "required_yarn_kg", "state"], order_by="starts_at, name", limit=10000)
    plans = [p for p in plans if p.job in by_job]
    rows = []
    if report == "shortages":
        available = {name: Decimal(b["yarn_kg"]) for name, b in balances.items()}
        for plan in plans:
            if plan.starts_at > now + timedelta(hours=72) or plan.ends_at <= now:
                continue
            b = balances[plan.job]
            job_remaining = max(d.ZERO, Decimal(by_job[plan.job].target_kg) - Decimal(b["produced_kg"]) - Decimal(b["fabric_transfer_in_kg"]))
            remaining = min(job_remaining, Decimal(plan.quantity_kg) - Decimal(plan.produced_kg or 0))
            if not remaining:
                continue
            demand = (Decimal(plan.required_yarn_kg) * remaining / Decimal(plan.quantity_kg)).quantize(Decimal(".001"), rounding=ROUND_CEILING) if plan.required_yarn_kg else None
            stock = available[plan.job]
            shortage = max(d.ZERO, demand - stock) if demand is not None else None
            if demand is not None:
                available[plan.job] = max(d.ZERO, stock - demand)
            rows.append({"plan": plan.name, "job": plan.job, "customer": by_job[plan.job].customer, "machine": plan.machine,
                "starts_at": plan.starts_at, "remaining_kg": d.kg(remaining), "required_yarn_kg": d.kg(demand) if demand is not None else None,
                "available_yarn_kg": d.kg(stock), "shortage_kg": d.kg(shortage) if shortage is not None else None,
                "coverage": "Input demand not specified" if demand is None else "Short" if shortage else "Covered"})
        columns = ["plan", "job", "customer", "machine", "starts_at", "remaining_kg", "required_yarn_kg", "available_yarn_kg", "shortage_kg", "coverage"]
    elif report == "changes":
        previous = {}
        for plan in plans:
            before = previous.get(plan.machine)
            if before and before.job != plan.job and now <= plan.starts_at <= now + timedelta(hours=24):
                rows.append({"machine": plan.machine, "current_job": before.job, "job": plan.job, "change_at": plan.starts_at, "remaining_kg": d.kg(Decimal(plan.quantity_kg) - Decimal(plan.produced_kg or 0))})
            previous[plan.machine] = plan
        columns = ["machine", "current_job", "job", "change_at", "remaining_kg"]
    else:
        for job in jobs:
            b = balances[job.name]
            remaining = max(d.ZERO, Decimal(job.target_kg) - Decimal(b["produced_kg"]) - Decimal(b["fabric_transfer_in_kg"]))
            planned = sum((Decimal(p.quantity_kg) - Decimal(p.produced_kg or 0) for p in plans if p.job == job.name), d.ZERO)
            rows.append({"job": job.name, "customer": job.customer, "remaining_kg": d.kg(remaining), "planned_kg": d.kg(planned), "unplanned_kg": d.kg(max(d.ZERO, remaining - planned)), "status": "Completed programme" if not remaining else "Fully planned" if planned >= remaining else "Partly planned" if planned else "Unplanned"})
        columns = ["job", "customer", "remaining_kg", "planned_kg", "unplanned_kg", "status"]
    return rows, columns, {"records": len(rows), "outlook_from": str(now), "horizon_hours": 72 if report == "shortages" else 24 if report == "changes" else "current"}
