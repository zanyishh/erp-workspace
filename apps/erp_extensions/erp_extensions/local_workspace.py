"""Console-only development bootstrap, restricted to the isolated native site."""
import secrets

import frappe
from frappe.utils import add_days, today

SITE = "native-test.localhost"
COMPANY = "Kaveri Loomworks"
ACCOUNT = "local-owner@workspace.example.invalid"
GENERAL_COMPANY = "Meridian Trading"
GENERAL_ACCOUNT = "local-general-owner@workspace.example.invalid"


def provision():
    """Return independent demo credentials through the private provisioning pipe."""
    if frappe.local.site != SITE or frappe.session.user != "Administrator" or getattr(frappe.local, "request", None):
        raise RuntimeError("Run local workspace provisioning from the isolated site's console.")
    general = _provision_company(GENERAL_COMPANY, GENERAL_ACCOUNT, "general")
    knitting = _provision_company(COMPANY, ACCOUNT, "knitting")
    frappe.db.commit()
    return {**general, "workspaces": [general, knitting]}


def _provision_company(company, account, industry):
    from erp_extensions import onboarding
    from erp_extensions.knitting import api as knitting
    from erp_extensions.knitting.permissions import profile
    from frappe.core.doctype.user.user import generate_keys
    from frappe.utils.password import get_decrypted_password

    if not frappe.db.exists("User", account):
        if frappe.db.exists("Company", company):
            raise RuntimeError("The local sample company name is already in use.")
        frappe.set_user("Guest")
        try:
            onboarding.register_owner("Local Workspace Owner", account, secrets.token_urlsafe(36), company, industry)
        finally:
            frappe.set_user("Administrator")
    roles = set(frappe.get_roles(account))
    membership = frappe.db.get_value(onboarding.MEMBER, {"member_user": account}, ["company","team_role"], as_dict=True)
    if not membership or (membership.company,membership.team_role)!=(company,"owner") or "System Manager" in roles:
        raise RuntimeError("Local workspace account has an unexpected company or role.")
    key=frappe.db.get_value("User", account, "api_key")
    secret=get_decrypted_password("User",account,"api_secret",raise_exception=False) if key else None
    if not key or not secret:
        credentials=generate_keys(account)
        key,secret=credentials["api_key"],credentials["api_secret"]
    frappe.set_user(account)
    try:
        from erp_extensions.workspace import context
        workspace=context()
        if [c.name for c in workspace["companies"]] != [company]:
            raise RuntimeError("Local sample account must be restricted to its own company.")
        if workspace["knitting_enabled"] != (industry == "knitting"):
            raise RuntimeError("Local sample company has an unexpected industry configuration.")
        sample = {}
        customer_names = (("Vaigai Cotton Traders", "Nilgiri Apparel Studio") if industry == "knitting"
                          else ("Atlas Office Supplies", "Harbour Retail Studio"))
        for title in customer_names:
            existing = frappe.db.get_value("Customer",{"customer_name":title,"owner":account}, "name")
            sample[title]=existing or frappe.get_doc({"doctype":"Customer","customer_name":title,
                "customer_type":"Company","customer_group":"Commercial","territory":"India"}).insert().name
        setup=profile(company)
        settings=frappe.parse_json(setup.settings or "{}") if setup else {}
        if industry == "knitting":
            item=settings.get("service_item")
        else:
            item_code = "Business services - " + frappe.get_cached_value("Company", company, "abbr")
            item = frappe.db.get_value("Item", {"item_code": item_code, "owner": account}, "name")
            if not item:
                item = frappe.get_doc({"doctype": "Item", "item_code": item_code, "item_name": "Business services",
                    "item_group": frappe.db.get_value("Item Group", {"is_group": 0}, "name", order_by="creation asc"),
                    "stock_uom": "Nos", "is_stock_item": 0, "is_sales_item": 1,
                    "item_defaults": [{"company": company}]}).insert().name
        if not item:
            raise RuntimeError("Local sample workspace is missing its service item.")
        samples = ((
            ("Cotton jersey knitting · 180 GSM",24,185,"posted"),
            ("Rib collar finishing · 12 gauge",16,140,"posted"),
            ("Interlock sampling · natural cotton",8,225,"draft"),
        ) if industry == "knitting" else (
            ("Inventory planning consultation",12,1500,"posted"),
            ("Delivery coordination",8,950,"posted"),
            ("Annual support plan",1,24000,"draft"),
        ))
        for n, (label,qty,rate,status) in enumerate(samples):
            marker = f"Local sample invoice {n+1}" if industry == "knitting" else f"Local general sample invoice {n+1}"
            if frappe.db.exists("Sales Invoice",{"company":company, "po_no":marker}):
                continue
            doc=frappe.get_doc({"doctype":"Sales Invoice","company":company,"customer":list(sample.values())[n%2],
                "po_no":marker,"posting_date":today(),"due_date":add_days(today(),14),
                "items":[{"item_code":item,"item_name":label,"description":label,"qty":qty,"rate":rate}]})
            doc.insert()
            if status=="posted":
                doc.submit()
        if industry == "knitting" and setup.state=="Active" and not frappe.db.exists("Knitting Job",{"company":company}):
            knitting.command(company,"create_job",{"customer":next(iter(sample.values())),"kind":"Order",
                "material_mode":"Customer","target_kg":"24.000","rate":"185",
                "programme":[{"id":"P1","fabric":"Single jersey","colour":"Natural cotton","target_kg":"24.000",
                              "dia":"30","gauge":"24","knit_type":"Tubular"}]},"local-sample-kaveri-first-order")
    finally:
        frappe.set_user("Administrator")
    return {"site":SITE,"company":company,"account":account,"key":key,"secret":secret,"industry":industry}
