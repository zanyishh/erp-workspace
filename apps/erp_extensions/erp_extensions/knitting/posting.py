"""Use ERPNext controllers for stock, valuation, taxes and the General Ledger."""
import frappe

from .domain import settings, reference


def common(event):
    company = frappe.get_cached_doc("Company", event.company)
    config = settings(event.company)
    return company, {"cost_center": config.get("cost_center") or company.cost_center,
                     "expense_account": config.get("expense_account") or company.stock_adjustment_account}


def submit(doc):
    doc.insert()
    doc.submit()
    return doc


def stock(event, purpose, rows, additional_costs=None):
    company, defaults = common(event)
    doc = frappe.get_doc({"doctype": "Stock Entry", "company": event.company, "stock_entry_type": purpose,
                          "knitting_event": event.name, "knitting_job": event.job})
    for row in rows:
        doc.append("items", {**defaults, **row})
    for row in additional_costs or []:
        doc.append("additional_costs", row)
    return submit(doc)


def delivery(event, job, rolls):
    from .domain import json_value
    doc = frappe.get_doc({"doctype": "Delivery Note", "company": event.company, "customer": job.customer,
                          "knitting_event": event.name, "knitting_job": job.name})
    for roll in rolls:
        doc.append("items", {"item_code": roll.fabric_item, "qty": roll.weight_kg, "rate": json_value(job.pricing, {}).get(roll.programme_line, job.rate),
                             "warehouse": roll.warehouse})
    return submit(doc)


def invoice(event, job, rows, *, preview=False):
    company, defaults = common(event)
    config = settings(event.company)
    doc = frappe.get_doc({"doctype": "Sales Invoice", "company": event.company, "customer": job.customer,
        "update_stock": 0, "knitting_event": event.name, "knitting_job": job.name})
    for row in rows:
        item = reference("Item", row["item_code"])
        if job.material_mode == "Customer" and item.is_stock_item:
            frappe.throw("Customer-material service billing must not sell a stock item.")
        values = {"cost_center": defaults["cost_center"], **row}
        if config.get("income_account"):
            values["income_account"] = config["income_account"]
        doc.append("items", values)
    return doc if preview else submit(doc)
