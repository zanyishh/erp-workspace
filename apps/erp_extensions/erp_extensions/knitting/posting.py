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


def validate_tax_choice(doc):
    choice = doc.flags.get("knitting_tax_choice")
    if not choice:
        return
    if choice["no_tax"]:
        if doc.taxes or doc.total_taxes_and_charges:
            frappe.throw("The invoice added taxes after No tax was selected. Review its tax settings.")
        # Party defaults may fill the template link even when native automatic tax rows are disabled.
        doc.taxes_and_charges = None
    elif doc.taxes_and_charges != choice["tax_template"]:
        frappe.throw("The invoice tax template changed. Review the invoice again.")


def invoice(event, job, rows, *, preview=False, tax_template=None, no_tax=False):
    if not isinstance(no_tax, bool) or tax_template is not None and not isinstance(tax_template, str):
        frappe.throw("Select a tax template or explicitly choose No tax.")
    tax_template = (tax_template or "").strip()
    if bool(tax_template) == no_tax:
        frappe.throw("Select a tax template or explicitly choose No tax, but not both.")
    if tax_template:
        template = reference("Sales Taxes and Charges Template", tax_template, event.company)
        if template.disabled or not template.taxes:
            frappe.throw("Select an active tax template with configured tax rows.")
    company, defaults = common(event)
    config = settings(event.company)
    billing_customer = job.get("billing_customer") or job.customer
    reference("Customer", billing_customer)
    doc = frappe.get_doc({"doctype": "Sales Invoice", "company": event.company, "customer": billing_customer,
        "finance_book": job.get("finance_book"),
        "update_stock": 0, "knitting_event": event.name, "knitting_job": job.name})
    doc.flags.knitting_tax_choice = {"tax_template": tax_template or None, "no_tax": no_tax}
    doc.flags.dont_auto_add_taxes = True
    if tax_template:
        doc.taxes_and_charges = tax_template
        doc.append_taxes_from_master()
    for row in rows:
        item = reference("Item", row["item_code"])
        if job.material_mode == "Customer" and item.is_stock_item:
            frappe.throw("Customer-material service billing must not sell a stock item.")
        values = {"cost_center": defaults["cost_center"], **row}
        if config.get("income_account"):
            values["income_account"] = config["income_account"]
        doc.append("items", values)
    return doc if preview else submit(doc)
