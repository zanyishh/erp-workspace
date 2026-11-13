"""Repeatable synthetic exploration records. This module refuses every non-test site."""
import frappe
from . import api
from erp_extensions import workspace

COMPANY = "ERP Native Verification"


def seed():
    if frappe.local.site != "native-test.localhost" or frappe.session.user != "Administrator":
        raise RuntimeError("Synthetic knitting setup requires Administrator on native-test.localhost")
    from .install import install
    install()
    customer = "Demo Knitting Mills"
    if not frappe.db.exists("Customer", customer):
        frappe.get_doc({"doctype": "Customer", "customer_name": customer, "customer_type": "Company",
            "customer_group": frappe.db.get_value("Customer Group", {"is_group": 0}, "name"),
            "territory": frappe.db.get_value("Territory", {"is_group": 0}, "name")}).insert()
    items = {}
    for key, stock in (("yarn", 1), ("fabric", 1), ("lycra", 1), ("service", 0), ("material_charge", 0)):
        name = "DEMO-KNIT-" + key.upper().replace("_", "-")
        if not frappe.db.exists("Item", name):
            frappe.get_doc({"doctype": "Item", "item_code": name, "item_name": "Demo knitting " + key.replace("_", " "),
                "item_group": frappe.db.get_value("Item Group", {"is_group": 0}, "name"), "stock_uom": "Kg",
                "is_stock_item": stock, "is_sales_item": 1, "is_purchase_item": 1}).insert()
        items[key] = name
    warehouse = frappe.db.get_value("Warehouse", {"company": COMPANY, "is_group": 0}, "name")
    profile = workspace.permissions.profile(COMPANY)
    if not profile:
        workspace.configure(COMPANY, {"state": "Active", "warehouse": warehouse, "service_item": items["service"],
            "fabric_item": items["fabric"], "number_prefix": "KN", "lycra_charge": "Included", "rate_lookup": "Fabric"})
    job = frappe.db.get_value("Knitting Job", {"company": COMPANY, "customer": customer}, "name")
    if not job and (not profile or profile.state == "Active"):
        job = api.command(COMPANY, "create_job", {"customer": customer, "kind": "Order", "material_mode": "Customer",
            "target_kg": "88.000", "rate": "100.00", "programme": [{"id": "P1", "fabric": "Single jersey",
                "colour": "Natural", "dia": "30", "gauge": "24", "knit_type": "Tubular", "gsm": [180], "ll": ["2.70"],
                "target_kg": "88.000", "fabric_item": items["fabric"]}], "notes": "Synthetic exploration job. No customer data."},
            "demo-job-" + frappe.generate_hash(length=20))["data"]["job"]
    machines = frappe.get_all("Knitting Machine", filters={"company": COMPANY, "title": "Demo circular 01"}, pluck="name")
    if not machines and (not profile or profile.state == "Active"):
        api.command(COMPANY, "create_machine", {"title": "Demo circular 01", "dia": "30", "gauge": "24", "knit_type": "Tubular", "capacity_kg": "150.000"}, "demo-machine-01")
    frappe.db.commit()
    return {"site": frappe.local.site, "company": COMPANY, "job": job, "customer": customer, "items": items, "warehouse": warehouse}
