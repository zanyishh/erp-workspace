"""Provision and verify linked purchasing and selling journeys on the isolated site."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess

ROOT = Path(__file__).resolve().parents[3]
CONNECT = """
import json
import os
import frappe
from frappe.utils import today
from frappe.utils.password import update_password

os.chdir("/home/frappe/frappe-bench/sites")
frappe.init(site="native-test.localhost", sites_path=".")
frappe.connect()
if frappe.local.site != "native-test.localhost" or not frappe.db.exists("Company", "ERP Native Verification"):
    raise RuntimeError("This fixture requires the isolated native verification site.")
frappe.set_user("Administrator")
"""

PROVISION = """
company = d["company"]
def first(doctype, filters):
    return frappe.db.get_value(doctype, filters, "name")

warehouses = {"company": company, "is_group": 0, "disabled": 0}
warehouse = first("Warehouse", {**warehouses, "name": ["like", "Stores%"]}) or first("Warehouse", warehouses)
if not warehouse:
    raise RuntimeError("Create a leaf warehouse for the verification company first.")
roles = [
    "Sales User", "Sales Manager", "Purchase User", "Purchase Manager",
    "Stock User", "Stock Manager", "Accounts User", "Accounts Manager",
]
user = frappe.get_doc({
    "doctype": "User", "email": d["username"], "first_name": "Sample trade clerk",
    "user_type": "System User", "send_welcome_email": 0, "roles": [{"role": r} for r in roles],
}).insert()
update_password(user.name, d["password"])
frappe.get_doc({
    "doctype": "User Permission", "user": user.name, "allow": "Company",
    "for_value": company, "apply_to_all_doctypes": 1, "is_default": 1,
}).insert()
frappe.get_doc({
    "doctype": "Customer", "customer_name": d["customer"], "customer_type": "Company",
    "customer_group": first("Customer Group", {"is_group": 0}),
    "territory": first("Territory", {"is_group": 0}),
}).insert()
frappe.get_doc({
    "doctype": "Supplier", "supplier_name": d["supplier"], "supplier_type": "Company",
    "supplier_group": first("Supplier Group", {"is_group": 0}),
}).insert()
item = frappe.get_doc({
    "doctype": "Item", "item_code": d["item"], "item_name": "Pilot packing carton",
    "stock_uom": "Nos", "is_stock_item": 1, "item_group": first("Item Group", {"is_group": 0}),
    "item_defaults": [{"company": company, "default_warehouse": warehouse}],
}).insert()
for price_list, rate in [("Standard Buying", 30), ("Standard Selling", 50)]:
    frappe.get_doc({
        "doctype": "Item Price", "price_list": price_list,
        "item_code": item.name, "price_list_rate": rate,
    }).insert()
frappe.db.commit()
print(json.dumps({
    "warehouse": warehouse, "date": today(), "roles": roles,
    "cash": frappe.db.get_value("Company", company, "default_cash_account"),
}))
"""

PROVISION_OWNER = """
from erp_extensions import api, onboarding

frappe.set_user("Guest")
onboarding.register_owner("Pilot Owner", d["username"], d["password"], d["company"], "general")
frappe.db.commit()
frappe.set_user(d["username"])
def first_leaf(doctype):
    return frappe.get_list(doctype, filters={"is_group": 0}, pluck="name", limit=1)[0]

def create(doctype, values):
    return api.save({"doctype": doctype, "__islocal": 1, **values})["doc"]["name"]

customer = create("Customer", {"customer_name":d["customer"], "customer_type":"Company",
    "customer_group":first_leaf("Customer Group"), "territory":first_leaf("Territory")})
supplier = create("Supplier", {"supplier_name":d["supplier"], "supplier_type":"Company",
    "supplier_group":first_leaf("Supplier Group")})
warehouse = frappe.get_list("Warehouse", filters={"is_group":0, "company":d["company"]}, pluck="name", limit=1)[0]
create("Item", {"item_code":d["item"], "item_name":"Pilot packing carton", "is_stock_item":1,
    "stock_uom":"Nos", "item_group":first_leaf("Item Group"),
    "item_defaults":[{"company":d["company"], "default_warehouse":warehouse}]})
for price_list, rate in [("Standard Buying", 30), ("Standard Selling", 50)]:
    create("Item Price", {"price_list":price_list, "item_code":d["item"], "price_list_rate":rate})
frappe.db.commit()
print(json.dumps({"customer":customer, "supplier":supplier, "warehouse":warehouse, "date":today(),
    "cash":frappe.get_doc("Company", d["company"]).default_cash_account}))
"""

VERIFY = """
from decimal import Decimal

balances, stock, invoices, linked = {}, {}, {}, []
for flow, movement, total in [("Sales", "Delivery Note", 100), ("Purchase", "Purchase Receipt", 150)]:
    selling = flow == "Sales"
    order_type = flow + " Order"
    bill_type = flow + " Invoice"
    records = d[flow]
    assert set(records) == {order_type, movement, bill_type, "Payment Entry"}
    docs = {kind: frappe.get_doc(kind, name) for kind, name in records.items()}
    for kind, doc in docs.items():
        assert doc.company == d["company"] and doc.owner == d["username"] and doc.docstatus == 1, doc.name
        if kind != order_type:
            entries = frappe.get_all("GL Entry", filters={
                "voucher_type": kind, "voucher_no": doc.name, "is_cancelled": 0,
            }, fields=["debit", "credit"])
            assert entries, doc.name
            debits = sum(Decimal(str(row.debit)) for row in entries)
            credits = sum(Decimal(str(row.credit)) for row in entries)
            assert debits == credits and debits > 0, doc.name
            balances[doc.name] = {"debits": str(debits), "credits": str(credits)}
    bill, order, shipment, payment = (docs[key] for key in [bill_type, order_type, movement, "Payment Entry"])
    assert bill.grand_total == total and bill.outstanding_amount == 0
    invoices[bill_type] = {"total": bill.grand_total, "outstanding": bill.outstanding_amount}
    assert len(payment.references) == 1
    assert payment.references[0].reference_name == bill.name and payment.references[0].allocated_amount == total
    assert order.per_billed == 100 and (order.per_delivered if selling else order.per_received) == 100
    assert shipment.items[0].get("against_sales_order" if selling else "purchase_order") == order.name
    assert bill.items[0].get("delivery_note" if selling else "purchase_receipt") == shipment.name
    rows = frappe.get_all("Stock Ledger Entry", filters={
        "voucher_no": shipment.name, "voucher_type": movement,
        "item_code": d["item"], "is_cancelled": 0,
    }, fields=["actual_qty", "stock_value_difference", "warehouse"])
    assert len(rows) == 1 and rows[0].warehouse == d["warehouse"]
    assert rows[0].actual_qty == (-2 if selling else 5)
    assert rows[0].stock_value_difference == (-60 if selling else 150)
    stock[shipment.name] = {"qty": rows[0].actual_qty, "value": rows[0].stock_value_difference}
    linked.append([order.name, shipment.name, bill.name, payment.name])
ending = frappe.db.get_value("Bin", {"item_code": d["item"], "warehouse": d["warehouse"]},
                             ["actual_qty", "stock_value"], as_dict=True)
assert ending.actual_qty == 3 and ending.stock_value == 90
assert "System Manager" not in frappe.get_roles(d["username"])
print(json.dumps({"site": frappe.local.site, "actor": d["username"], "system_manager": False,
                  "linked": linked, "invoice": invoices, "gl": balances, "movements": stock,
                  "ending_bin": ending}, default=str))
"""


def on_site(fixture, script):
    command = [
        "docker", "--context", "colima-erp", "compose", "-f", "infrastructure/erpnext/compose.yaml",
        "exec", "-T", "native-test-backend", "/home/frappe/frappe-bench/env/bin/python", "-",
    ]
    result = subprocess.run(command, cwd=ROOT, input=CONNECT + f"\nd = {fixture!r}\n" + script,
                            text=True, capture_output=True)
    if result.returncode:
        message = result.stderr
        if "password" in fixture:
            message = message.replace(fixture["password"], "[redacted]")
        raise RuntimeError(message)
    return json.loads(result.stdout.strip().splitlines()[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["provision", "provision-owner", "verify"])
    parser.add_argument("folder", type=Path, help="A directory under the workspace's ignored .local folder")
    args = parser.parse_args()
    folder = args.folder.resolve()
    if not folder.is_relative_to(ROOT / ".local"):
        parser.error("Store rehearsal credentials and evidence under .local.")
    folder.mkdir(exist_ok=True, parents=True)
    path = folder / "erp-fixture.json"
    if args.action != "verify":
        suffix = secrets.token_hex(6)
        owner = args.action == "provision-owner"
        fixture = {
            "company": f"Pilot Trade {suffix}" if owner else "ERP Native Verification",
            "username": f"clerk-{suffix}@example.invalid",
            "password": secrets.token_urlsafe(27),
            "customer": f"Pilot buyer {suffix}",
            "supplier": f"Pilot supplier {suffix}",
            "item": f"PILOT-CARTON-{suffix}",
        }
        with os.fdopen(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "w") as out:
            json.dump(fixture, out)
        fixture.update(on_site(fixture, PROVISION_OWNER if owner else PROVISION))
        path.write_text(json.dumps(fixture))
        print(f"Created a synthetic {'owner' if owner else 'clerk'} and trading records.")
    else:
        fixture = json.loads(path.read_text())
        data = {k: fixture[k] for k in ("company", "warehouse", "username", "item")}
        for flow in ("Purchase", "Sales"):
            data[flow] = json.loads((folder / f"{flow.lower()}-records.json").read_text())
        evidence = on_site(data, VERIFY)
        (folder / "trade-ledgers.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print("Verified all eight submitted vouchers, both paid invoices, GL entries and ending stock.")


if __name__ == "__main__":
    main()
