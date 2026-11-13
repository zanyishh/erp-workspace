"""Yarn procurement retains the original PO, receipt, invoice and stock controllers."""
from decimal import Decimal
import frappe
from frappe.utils import today
from . import domain as d, posting


def clear_flags(doc):
    doc.flags = frappe._dict()
    for row in doc.get_all_children():
        row.flags = frappe._dict()
    return doc


def create_order(event, data, job):
    supplier = d.reference("Supplier", data.get("supplier"))
    item = d.reference("Item", data.get("item"))
    if not item.is_stock_item or item.stock_uom != "Kg":
        frappe.throw("Choose a stock yarn item measured in Kg.")
    qty, rate = d.decimal(data.get("quantity_kg"), positive=True), d.decimal(data.get("rate"), precision=2)
    doc = frappe.get_doc({"doctype": "Purchase Order", "company": event.company, "supplier": supplier.name,
        "schedule_date": data.get("schedule_date") or today(), "knitting_event": event.name, "knitting_job": event.job,
        "items": [{"item_code": item.name, "qty": qty, "rate": rate, "schedule_date": data.get("schedule_date") or today()}]})
    posting.submit(doc)
    return {"purchase_order": doc.name, "quantity_kg": d.kg(qty), "amount": d.money(doc.grand_total), "voucher": doc.name, "voucher_type": doc.doctype}


def receive_order(event, data, quantity, warehouse):
    order = d.reference("Purchase Order", data["purchase_order"], event.company)
    if order.docstatus != 1 or len(order.items) != 1 or order.items[0].item_code != data["item"] or data.get("material_owner") != "Owned":
        frappe.throw("Choose a submitted matching yarn purchase order for owned stock.")
    source = d.reference("Knitting Event", order.knitting_event, event.company) if order.knitting_event else None
    if not source or source.kind != "create_yarn_order":
        frappe.throw("Choose an original reviewed yarn purchase order.")
    if quantity > Decimal(str(order.items[0].qty)) - Decimal(str(order.items[0].received_qty or 0)):
        frappe.throw("Receipt exceeds the purchase order's remaining quantity.")
    from erpnext.buying.doctype.purchase_order.purchase_order import make_purchase_receipt
    doc = clear_flags(make_purchase_receipt(order.name))
    if len(doc.items) != 1:
        frappe.throw("The original purchase item cannot be matched.")
    doc.items[0].qty, doc.items[0].received_qty, doc.items[0].warehouse = quantity, quantity, warehouse
    doc.knitting_event, doc.knitting_job = event.name, event.job
    return posting.submit(doc)


def bill(event, data, job):
    source = d.reference("Knitting Event", data.get("receipt"), event.company)
    if source.kind != "receive_yarn" or source.cancelled:
        frappe.throw("Choose an active owned-yarn receipt.")
    if job and job.name != source.job:
        frappe.throw("Bill this receipt in its original job context.")
    event.job = source.job
    value = d.json_value(source.result, {})
    payload = d.json_value(source.payload, {})
    if payload.get("material_owner") != "Owned":
        frappe.throw("Customer-custody receipts cannot create a supplier yarn bill.")
    billed = sum((Decimal(d.json_value(e.result, {}).get("quantity_kg", "0")) for e in d.current_rows("Knitting Event", filters={"company": event.company, "kind": "bill_yarn", "cancelled": 0}, fields=["result"]) if d.json_value(e.result, {}).get("receipt") == source.name), d.ZERO)
    qty = d.decimal(data.get("quantity_kg", Decimal(value["quantity_kg"]) - billed), positive=True)
    if qty + billed > Decimal(value["quantity_kg"]):
        frappe.throw("The bill exceeds this receipt's unbilled quantity.")
    if value.get("voucher_type") == "Purchase Receipt":
        from erpnext.stock.doctype.purchase_receipt.purchase_receipt import make_purchase_invoice
        doc = clear_flags(make_purchase_invoice(value["voucher"]))
        if len(doc.items) != 1:
            frappe.throw("The original receipt item cannot be matched.")
        doc.items[0].qty = qty
    else:
        supplier = d.reference("Supplier", data.get("supplier"))
        receipt = d.reference("Stock Entry", value.get("voucher"), event.company)
        if len(receipt.items) != 1:
            frappe.throw("Match a single original yarn receipt item.")
        doc = frappe.get_doc({"doctype": "Purchase Invoice", "company": event.company, "supplier": supplier.name,
            "items": [{"item_code": receipt.items[0].item_code, "qty": qty, "rate": receipt.items[0].basic_rate,
                "expense_account": posting.common(event)[1]["expense_account"]}]})
    doc.update_stock, doc.knitting_event, doc.knitting_job = 0, event.name, source.job
    for row in doc.items:
        row.knitting_receipt = source.name
    posting.submit(doc)
    return {"receipt": source.name, "invoice": doc.name, "quantity_kg": d.kg(qty), "amount": d.money(doc.grand_total),
        "voucher": doc.name, "voucher_type": doc.doctype}


ACTIONS = {"create_yarn_order": ("billing", create_order), "bill_yarn": ("billing", bill)}
