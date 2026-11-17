"""Explicit source service tax choices; no default, item rewrite or historical posting."""
from decimal import Decimal, InvalidOperation
from hashlib import sha256
import json
import re

from .master_details import india_gstin


def proof_hash(package):
    return sha256(json.dumps({k: v for k, v in package.items() if k != "proof_hash"},
        sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def compile_options(*, scope, manifest_sha256, hsns, companies, company_bindings, evidence):
    service = [r for r in hsns if r.get("hsn_type") == "service"]
    if len(service) != 1 or str(service[0].get("status")) != "1":
        raise ValueError("One explicitly enabled source service HSN definition is required.")
    hsn = service[0]
    if not re.fullmatch(r"[1-9][0-9]*", str(hsn.get("id", ""))) or not re.fullmatch(r"[0-9]{4,8}", str(hsn.get("hsn", ""))):
        raise ValueError("Preserve an explicit native service HSN identity and code.")
    try:
        rates = {k: Decimal(str(hsn[k])) for k in ("cgst", "sgst", "igst", "percentage")}
        if (any(not value.is_finite() or value <= 0 for value in rates.values())
                or rates["cgst"] + rates["sgst"] != rates["igst"] or rates["igst"] != rates["percentage"]):
            raise ValueError("The explicit service tax components do not agree.")
    except (InvalidOperation, KeyError) as error:
        raise ValueError("The service tax components must be supplied exact numbers.") from error
    if (set(companies) != {"1", "2", "3", "4"} or set(company_bindings) != set(companies)
            or len(set(company_bindings.values())) != 4 or not all(company_bindings.values())):
        raise ValueError("Use the four distinct approved source/company bindings.")
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256) or not evidence:
        raise ValueError("A fixed source manifest and evidence are required.")
    result = {"scope": scope, "manifest_sha256": manifest_sha256, "evidence": evidence,
        "source_hsn": {k: hsn[k] for k in ("id", "hsn_type", "hsn", "status", "cgst", "sgst", "igst", "percentage")},
        "companies": [], "changes_historical_postings": False, "changes_items": False,
        "applicability": "Choose the appropriate native template explicitly for each new invoice; no default is assigned."}
    for native_id in sorted(companies):
        source = companies[native_id]
        gst = source.get("gstin")
        if (str(source.get("id")) != native_id or source.get("country") != "India"
                or not isinstance(gst, str) or not gst.strip() or len(gst) > 140):
            raise ValueError("Each original Indian company must retain its own supplied tax identifier.")
        templates = [{"title": f"Service HSN {hsn['hsn']} - CGST and SGST", "is_default": 0,
                      "rates": {k.upper(): str(rates[k]) for k in ("cgst", "sgst")}},
                     {"title": f"Service HSN {hsn['hsn']} - IGST", "is_default": 0,
                      "rates": {"IGST": str(rates["igst"])}}]
        result["companies"].append({"source_company_id": native_id, "company": company_bindings[native_id],
            "country": "India", "source_gstin": gst, "templates": templates,
            "review_issues": [] if india_gstin(gst, "India") else ["Original tax identifier fails GST format; optional rates do not certify registration."]})
    result["proof_hash"] = proof_hash(result)
    return result


def apply_options(scope_name, package):
    """Dedicated-site console only. Native controllers, one transaction, caller commits."""
    import frappe
    from . import service
    from erp_extensions.knitting.permissions import company_allowed
    if getattr(frappe.local, "request", None) or not frappe.conf.get("erp_customer_migration_enabled"):
        frappe.throw("Run verified tax setup from the dedicated workspace console.")
    frappe.only_for("System Manager")
    with service.locked_scope(scope_name) as scope:
        if (package.get("scope") != scope_name or package.get("manifest_sha256") != scope["manifest_sha256"]
                or package.get("proof_hash") != proof_hash(package) or frappe.session.user not in scope["allowed_users"]
                or not all(company_allowed(c) for c in scope["company_bindings"].values())):
            frappe.throw("Use the fixed tax options for the approved four-company scope.", frappe.PermissionError)
        originals = {row["source_company_id"]: {"id": row["source_company_id"], "country": row["country"],
            "gstin": row["source_gstin"]} for row in package["companies"]}
        expected = compile_options(scope=scope_name, manifest_sha256=scope["manifest_sha256"], hsns=[package["source_hsn"]],
            companies=originals, company_bindings=scope["company_bindings"], evidence=package["evidence"])
        if expected != package:
            frappe.throw("The tax choices differ from their exact source definition.")
        savepoint = "service_tax_" + frappe.generate_hash(length=12)
        frappe.db.savepoint(savepoint)
        result = {"accounts_created": 0, "accounts_reused": 0, "templates_created": 0, "templates_reused": 0,
                  "default_templates_assigned": 0, "proof_hash": package["proof_hash"]}
        try:
            for entry in package["companies"]:
                company = frappe.get_doc("Company", entry["company"], for_update=True)
                company.check_permission("write")
                if company.country != "India" or company.tax_id != entry["source_gstin"] or company.default_currency != "INR":
                    frappe.throw("The native company country, currency or GST identity differs from its source.")
                parents = frappe.get_all("Account", filters={"company": company.name, "account_name": "Duties and Taxes",
                    "root_type": "Liability", "account_type": "Tax", "is_group": 1}, pluck="name")
                if len(parents) != 1:
                    frappe.throw("A unique native Duties and Taxes liability group is required.")
                accounts = {}
                for component in ("CGST", "SGST", "IGST"):
                    names = frappe.get_all("Account", filters={"company": company.name,
                        "account_name": ["in", ["Output " + component, "Service Output " + component]]}, pluck="name")
                    if len(names) > 1:
                        frappe.throw("Choose one existing output-tax account before preparing service templates.")
                    if names:
                        account = frappe.get_doc("Account", names[0], for_update=True)
                        if (account.parent_account != parents[0] or account.root_type != "Liability" or account.account_type != "Tax"
                                or account.is_group or account.disabled or account.account_currency != "INR"):
                            frappe.throw("An existing output-tax account has different native accounting semantics.")
                        result["accounts_reused"] += 1
                    else:
                        account = frappe.get_doc({"doctype": "Account", "account_name": "Service Output " + component,
                            "company": company.name, "parent_account": parents[0], "account_type": "Tax", "is_group": 0,
                            "account_currency": "INR"}).insert()
                        result["accounts_created"] += 1
                    accounts[component] = account.name
                for template in entry["templates"]:
                    taxes = [{"charge_type": "On Net Total", "account_head": accounts[k], "rate": float(Decimal(rate)),
                              "cost_center": company.cost_center,
                              "description": f"{k} - HSN {package['source_hsn']['hsn']}"} for k, rate in template["rates"].items()]
                    names = frappe.get_all("Sales Taxes and Charges Template", filters={"company": company.name,
                        "title": template["title"]}, pluck="name")
                    if len(names) > 1:
                        frappe.throw("The service tax template identity is duplicated.")
                    if names:
                        doc = frappe.get_doc("Sales Taxes and Charges Template", names[0], for_update=True)
                        doc.check_permission("read")
                        if (doc.disabled or doc.is_default or doc.tax_category or len(doc.taxes) != len(taxes)
                                or any(row.charge_type != value["charge_type"] or row.account_head != value["account_head"]
                                       or Decimal(str(row.rate)) != Decimal(str(value["rate"])) or row.description != value["description"]
                                       or row.included_in_print_rate or row.included_in_paid_amount or row.row_id
                                       or (row.cost_center or None) != (value["cost_center"] or None)
                                       or row.project or row.dont_recompute_tax
                                       or row.set_by_item_tax_template or row.is_tax_withholding_account
                                       for row, value in zip(doc.taxes, taxes))):
                            frappe.throw("An existing service template differs; no tax setting was overwritten.")
                        result["templates_reused"] += 1
                    else:
                        frappe.get_doc({"doctype": "Sales Taxes and Charges Template", "company": company.name,
                            "title": template["title"], "is_default": 0, "disabled": 0, "taxes": taxes}).insert()
                        result["templates_created"] += 1
            return result
        except Exception:
            frappe.db.rollback(save_point=savepoint)
            raise
