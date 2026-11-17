"""Source-supported postal/tax enrichment; no guessed address components."""
from hashlib import sha256
from copy import deepcopy
import re


def india_gstin(value, country):
    """A display shape guard, not a registration or checksum verification."""
    if country != "India" or not isinstance(value, str):
        return None
    return value if re.fullmatch(r"[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]", value) else None


def _text(value):
    return str(value).strip() if value is not None else ""


def _address(source, prefix, key, title, links, kind, countries):
    fields = {"address_line1": _text(source.get(prefix + "address1")),
        "address_line2": "\n".join(v for v in (_text(source.get(prefix + "address2")), _text(source.get(prefix + "address3"))) if v),
        "city": _text(source.get(prefix + "city")), "state": _text(source.get(prefix + "state")),
        "country": _text(source.get(prefix + "country")), "pincode": _text(source.get(prefix + "zip_code"))}
    missing = [f for f in ("address_line1", "city", "country") if not fields[f]]
    issues = []
    if fields["country"] and fields["country"] not in countries:
        issues.append("country_not_in_native_catalogue")
    for f, value in fields.items():
        if len(value) > (240 if f.startswith("address_line") else 140):
            issues.append(f + "_exceeds_native_field_length")
    coverage = {"complete": not missing and not issues, "missing": missing, "issues": issues}
    if not coverage["complete"]:
        return None, coverage
    phone = _text(source.get(prefix + "phoneno"))
    if not phone and kind == "Billing":
        phone = _text(source.get("phoneno") or source.get("phone_no"))
    # The native Phone field is one short value; a list supplies no primary.
    if phone and (any(separator in phone for separator in (",", ";", "\n"))
                  or not re.fullmatch(r"[0-9 +_.*#()\-]{1,20}", phone)):
        coverage["phone_preserved_only_in_history"] = True
        phone = ""
    email = _text(source.get("shipp_email" if kind == "Shipping" else "email"))
    if email and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        coverage["contact_email_preserved_only_in_history"] = True
        email = ""
    return {"name": key, "address_title": title, "address_type": kind, **fields,
        "email_id": email, "phone": phone, "is_primary_address": int(kind == "Billing"),
        "is_shipping_address": int(kind == "Shipping"), "links": links}, coverage


def party_details(source, scope_name, *, supplier=False, countries):
    native_id = _text(source.get("id"))
    if not native_id.isdigit() or int(native_id) < 1:
        raise ValueError("A positive native party identity is required.")
    links = [{"link_doctype": "Customer", "link_name": "KP-PARTY-" + native_id}]
    if supplier:
        links.append({"link_doctype": "Supplier", "link_name": "KP-SUPPLIER-" + native_id})
    tax = _text(source.get("gstin"))
    if len(tax) > 140:
        raise ValueError("The original tax identifier exceeds the native field length.")
    updates = [{"doctype": r["link_doctype"], "name": r["link_name"], **({"tax_id": tax} if tax else {})} for r in links]
    prefix = "LEGACY-ADDR-" + sha256(scope_name.encode()).hexdigest()[:12] + "-PARTY-" + native_id
    addresses, coverage = [], {}
    for kind, source_prefix in (("Billing", "bill_"), ("Shipping", "shipp_")):
        address, observed = _address(source, source_prefix, prefix + "-" + kind.upper(), _text(source.get("party_name")), links, kind, countries)
        coverage[kind.lower()] = observed
        if address:
            addresses.append(address)
    if len(addresses) == 2:
        keys = ("address_line1", "address_line2", "city", "state", "country", "pincode", "email_id", "phone")
        if all(addresses[0][k] == addresses[1][k] for k in keys):
            addresses[0]["is_shipping_address"] = 1
            addresses.pop()
            coverage["shipping"]["shares_exact_billing_address"] = True
    email, phone = _text(source.get("email")), _text(source.get("phoneno"))
    contacts = []
    if email and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        email = ""
    if email or phone:
        contacts.append({"name": "LEGACY-CONTACT-" + sha256(scope_name.encode()).hexdigest()[:12] + "-PARTY-" + native_id,
            "company_name": _text(source.get("party_name")), "is_primary_contact": 1, "links": links,
            "email_ids": [{"email_id": email, "is_primary": 1}] if email else [],
            "phone_nos": [{"phone": phone, "is_primary_phone": 1}] if phone else []})
    return {"source_kind": "party", "native_id": native_id, "updates": updates, "addresses": addresses,
        "contacts": contacts,
        "address_coverage": coverage, "source_country": _text(source.get("bill_country")),
        "source_parent_phone_present": bool(_text(source.get("phoneno"))), "source_parent_email_present": bool(_text(source.get("email"))),
        "person_contacts_created": False}


def company_details(source, scope_name, target_company, *, countries):
    native_id = _text(source.get("id"))
    if native_id not in ("1", "2", "3", "4"):
        raise ValueError("A supported source company identity is required.")
    normalized = {**source, "zip_code": source.get("bill_zip_code"), "phoneno": source.get("phone_no")}
    key = "LEGACY-ADDR-" + sha256(scope_name.encode()).hexdigest()[:12] + "-COMPANY-" + native_id + "-BILLING"
    address, coverage = _address(normalized, "", key, _text(source.get("name")),
        [{"link_doctype": "Company", "link_name": target_company}], "Billing", countries)
    tax = _text(source.get("gstin"))
    return {"source_kind": "company", "native_id": native_id, "updates": [{"doctype": "Company", "name": target_company,
        **({"tax_id": tax} if tax else {})}], "addresses": [address] if address else [], "address_coverage": {"billing": coverage}}


def apply_enrichment(scope_name, package):
    """Trusted console helper. Native controllers run; no commits or raw SQL writes."""
    import frappe
    from . import service
    from erp_extensions.knitting.permissions import company_allowed
    if getattr(frappe.local, "request", None) or not frappe.conf.get("erp_customer_migration_enabled"):
        frappe.throw("Run verified master enrichment from the dedicated workspace console.")
    frappe.only_for("System Manager")
    scope = service.get_scope(scope_name)
    if (package.get("scope") != scope_name or package.get("manifest_sha256") != scope["manifest_sha256"]
            or frappe.session.user not in scope["allowed_users"] or not all(company_allowed(c) for c in scope["company_bindings"].values())):
        frappe.throw("Master enrichment requires the approved scope and all four company permissions.", frappe.PermissionError)
    savepoint = "historical_master_" + frappe.generate_hash(length=12)
    frappe.db.savepoint(savepoint)
    result = {"master_updates": 0, "addresses_created": 0, "addresses_reused": 0, "primary_links_set": 0,
              "business_contacts_created": 0, "business_contacts_reused": 0}
    try:
        for entity in package["entities"]:
            if entity.get("source_kind") not in ("party", "company"):
                frappe.throw("Use a supported original master family.")
            native_id = entity["native_id"]
            allowed = {("Company", scope["company_bindings"][native_id])} if entity["source_kind"] == "company" else {
                ("Customer", "KP-PARTY-" + native_id), ("Supplier", "KP-SUPPLIER-" + native_id)}
            for update in entity["updates"]:
                if (update["doctype"], update["name"]) not in allowed or set(update) - {"doctype", "name", "tax_id"}:
                    frappe.throw("The native master update does not match its source identity.")
                doc = frappe.get_doc(update["doctype"], update["name"], for_update=True)
                doc.check_permission("write")
                if "tax_id" in update and doc.get("tax_id") != update["tax_id"]:
                    if doc.get("tax_id"):
                        frappe.throw("A native tax identifier differs from the original source; no value was overwritten.")
                    doc.tax_id = update["tax_id"]
                    doc.save()
                    result["master_updates"] += 1
            for address in entity["addresses"]:
                if set(address) - {"name", "address_title", "address_type", "address_line1", "address_line2", "city", "state", "country", "pincode",
                                   "email_id", "phone", "is_primary_address", "is_shipping_address", "links"}:
                    frappe.throw("Use only the reviewed original postal fields; audit fields cannot be supplied.")
                links = {(r["link_doctype"], r["link_name"]) for r in address["links"]}
                if not links or not links.issubset(allowed):
                    frappe.throw("An address links a different native source identity.")
                if frappe.db.exists("Address", address["name"]):
                    doc = frappe.get_doc("Address", address["name"], for_update=True)
                    doc.check_permission("read")
                    keys = set(address) - {"name", "links"}
                    if any((doc.get(k) or "") != (address[k] or "") for k in keys) or {(r.link_doctype, r.link_name) for r in doc.links} != links:
                        frappe.throw("An existing native address differs from the frozen source projection.")
                    result["addresses_reused"] += 1
                else:
                    doc = frappe.get_doc({"doctype": "Address", **deepcopy(address)})
                    doc.insert(set_name=address["name"])
                    result["addresses_created"] += 1
                if address["is_primary_address"]:
                    for doctype, name in links:
                        field = {"Customer": "customer_primary_address", "Supplier": "supplier_primary_address"}.get(doctype)
                        if field:
                            master = frappe.get_doc(doctype, name, for_update=True)
                            if master.get(field) not in (None, "", doc.name):
                                frappe.throw("A different native primary address is already selected; no address was overwritten.")
                            if master.get(field) != doc.name:
                                master.set(field, doc.name)
                                master.save()
                                result["primary_links_set"] += 1
            for contact in entity.get("contacts", []):
                if set(contact) - {"name", "company_name", "is_primary_contact", "links", "email_ids", "phone_nos"}:
                    frappe.throw("Use only the reviewed original business contact fields.")
                links = {(r["link_doctype"], r["link_name"]) for r in contact["links"]}
                if not links or not links.issubset(allowed) or contact.get("first_name") or contact.get("last_name"):
                    frappe.throw("A business contact must preserve its source organization without an invented person.")
                if frappe.db.exists("Contact", contact["name"]):
                    doc = frappe.get_doc("Contact", contact["name"], for_update=True)
                    doc.check_permission("read")
                    emails = [{"email_id": r.email_id, "is_primary": r.is_primary} for r in doc.email_ids]
                    phones = [{"phone": r.phone, "is_primary_phone": r.is_primary_phone} for r in doc.phone_nos]
                    if (doc.company_name != contact["company_name"] or emails != contact["email_ids"] or phones != contact["phone_nos"]
                            or {(r.link_doctype, r.link_name) for r in doc.links} != links or doc.first_name or doc.last_name):
                        frappe.throw("An existing native business contact differs from the source projection.")
                    result["business_contacts_reused"] += 1
                else:
                    doc = frappe.get_doc({"doctype": "Contact", **deepcopy(contact)})
                    doc.insert(set_name=contact["name"])
                    result["business_contacts_created"] += 1
                for doctype, name in links:
                    field = {"Customer": "customer_primary_contact", "Supplier": "supplier_primary_contact"}.get(doctype)
                    if field:
                        master = frappe.get_doc(doctype, name, for_update=True)
                        if master.get(field) not in (None, "", doc.name):
                            frappe.throw("A different native primary contact is already selected; no contact was overwritten.")
                        if master.get(field) != doc.name:
                            master.set(field, doc.name)
                            master.save()
    except Exception:
        frappe.db.rollback(save_point=savepoint)
        raise
    return result
