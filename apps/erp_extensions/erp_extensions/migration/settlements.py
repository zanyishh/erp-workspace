"""Apply proved current settlements through native controllers, never historical dates."""
from collections import defaultdict
from decimal import Decimal
from hashlib import sha256
import json
import re
from contextvars import ContextVar

DOCTYPE = "Historical Settlement Binding"
_writing = ContextVar("historical_settlement_write", default=False)


def _money(value):
    if value is None or isinstance(value, (bool, float)) or value == "":
        raise ValueError("An exact settlement amount is required.")
    amount = Decimal(str(value))
    if not amount.is_finite() or amount < 0 or amount != amount.quantize(Decimal("0.01")):
        raise ValueError("Settlement amounts must be exact nonnegative currency values.")
    return amount


def validate_component(nodes, edges):
    if not nodes or not edges or not isinstance(nodes, dict) or not isinstance(edges, list):
        raise ValueError("A complete proved component is required.")
    scopes = {(n["company"], n["source_book"], n["finance_book"], n["accounting_party_id"]) for n in nodes.values()}
    if len(scopes) != 1:
        raise ValueError("Settlement endpoints must share original company, party and book.")
    totals, seen = defaultdict(Decimal), set()
    same = cross = 0
    for edge in edges:
        first, second = edge["first"], edge["second"]
        pair = tuple(sorted((first, second)))
        if first == second or pair in seen or first not in nodes or second not in nodes:
            raise ValueError("Duplicate, self or missing settlement endpoints are forbidden.")
        seen.add(pair)
        a, b = nodes[first], nodes[second]
        if {a["entry_type"], b["entry_type"]} != {"debit", "credit"}:
            raise ValueError("Settlement endpoints need opposite native directions.")
        amount = _money(edge["amount"])
        if not amount:
            raise ValueError("A settlement edge must have a positive saved amount.")
        totals[first] += amount
        totals[second] += amount
        if a["party_type"] == b["party_type"]:
            if a["party_account"] != b["party_account"]:
                raise ValueError("Same-role allocation requires one native control account.")
            same += 1
        elif {a["party_type"], b["party_type"]} == {"Customer", "Supplier"}:
            cross += 1
        else:
            raise ValueError("Only explicit Customer/Supplier roles are supported.")
    if set(totals) != set(nodes):
        raise ValueError("Every component node must be supported by its saved incident edges.")
    for name, node in nodes.items():
        if node["party_type"] not in ("Customer", "Supplier") or totals[name] != _money(node["adjusted"]) or totals[name] > _money(node["amount"]):
            raise ValueError("Saved adjusted controls must equal every incident amount without overallocation.")
    return {"same_account_edges": same, "cross_role_edges": cross, "nodes": len(nodes), "edges": len(edges)}


def install():
    import frappe
    from erp_extensions.knitting.install import field
    if not frappe.db.exists("DocType", DOCTYPE):
        frappe.get_doc({"doctype": "DocType", "name": DOCTYPE, "module": "Custom", "custom": 1,
            "autoname": "hash", "track_changes": 0,
            "fields": [field("source_scope", "Link", "Migration Scope", reqd=1),
                field("company", "Link", "Company", reqd=1), field("component_key", reqd=1, unique=1), field("evidence_sha256", reqd=1),
                field("proof_sha256", reqd=1), field("applied_at", "Datetime", reqd=1), field("proof", "JSON", reqd=1)],
            "permissions": [{"role": "System Manager", "read": 1}]}).insert()
    elif not frappe.get_meta(DOCTYPE).has_field("company"):
        doc = frappe.get_doc("DocType", DOCTYPE)
        doc.append("fields", field("company", "Link", "Company", reqd=1))
        doc.save()


def guard_write(doc, method=None):
    import frappe
    if doc.doctype == DOCTYPE and (not doc.is_new() or not _writing.get()):
        frappe.throw("Historical settlement evidence is immutable.", frappe.PermissionError)


def _is_payment(node):
    return node["entry_type"] == ("credit" if node["party_type"] == "Customer" else "debit")


def _outstanding(node, journal=None):
    from erpnext.accounts.doctype.payment_entry.payment_entry import get_outstanding_on_journal_entry
    amount, _ = get_outstanding_on_journal_entry(journal or node["journal"], node["party_type"], node["party"])
    return Decimal(str(amount or 0))


def _reconcile(payment, against_journal, amount):
    import frappe
    from erpnext.accounts.utils import reconcile_against_document
    doc = frappe.get_doc("Journal Entry", payment["journal"], for_update=True)
    direction = "credit_in_account_currency" if payment["party_type"] == "Customer" else "debit_in_account_currency"
    rows = [r for r in doc.accounts if r.account == payment["party_account"] and r.party_type == payment["party_type"]
            and r.party == payment["party"] and not r.reference_type and not r.reference_name and Decimal(str(r.get(direction) or 0)) > 0]
    if len(rows) != 1 or Decimal(str(rows[0].get(direction))) < amount:
        frappe.throw("The native unmatched payment row differs from the proved current component.")
    if _outstanding(payment, against_journal) < amount:
        frappe.throw("The native charge has insufficient outstanding amount for this saved reference.")
    row = rows[0]
    old_flag = frappe.flags.get("ignore_party_validation")
    try:
        reconcile_against_document([frappe._dict({"voucher_type": "Journal Entry", "voucher_no": doc.name,
            "voucher_detail_no": row.name, "against_voucher_type": "Journal Entry", "against_voucher": against_journal,
            "account": row.account, "party_type": row.party_type, "party": row.party, "dr_or_cr": direction,
            "unreconciled_amount": float(row.get(direction)), "unadjusted_amount": float(row.get(direction)),
            "allocated_amount": float(amount), "exchange_rate": 1, "difference_amount": 0,
            "cost_center": row.cost_center, "precision": 2})])
    finally:
        frappe.flags.ignore_party_validation = old_flag


def _offset(a, b, amount, component_key):
    import frappe
    rows = []
    for node in (a, b):
        credit = node["entry_type"] == "debit"
        row = {"account": node["party_account"], "party_type": node["party_type"], "party": node["party"],
            "debit_in_account_currency": 0 if credit else float(amount), "credit_in_account_currency": float(amount) if credit else 0,
            "exchange_rate": 1, "account_currency": "INR", "cost_center": node["cost_center"]}
        if not _is_payment(node):
            row.update(reference_type="Journal Entry", reference_name=node["journal"])
        rows.append(row)
    doc = frappe.get_doc({"doctype": "Journal Entry", "voucher_type": "Journal Entry", "company": a["company"],
        "finance_book": a["finance_book"], "posting_date": frappe.utils.today(), "accounts": rows,
        "user_remark": "Current migration offset of proved customer/supplier balances: " + component_key})
    doc.insert()
    doc.submit()
    for node in (a, b):
        if _is_payment(node):
            _reconcile(node, doc.name, amount)
    entries = frappe.get_all("GL Entry", filters={"voucher_type": "Journal Entry", "voucher_no": doc.name, "is_cancelled": 0},
        fields=["company", "finance_book", "debit", "credit", "party_type", "party", "account"])
    expected = {(n["party_type"], n["party"], n["party_account"]): (-amount if n["entry_type"] == "debit" else amount) for n in (a, b)}
    actual = defaultdict(Decimal)
    for row in entries:
        if row.company != a["company"] or row.finance_book != a["finance_book"]:
            frappe.throw("The current offset crossed company or book boundaries.")
        actual[(row.party_type, row.party, row.account)] += Decimal(str(row.debit)) - Decimal(str(row.credit))
    if dict(actual) != expected or sum(actual.values(), Decimal(0)) != 0:
        frappe.throw("The current offset changed the combined original party balance.")
    return doc.name


def apply_component(scope_name, component_id, bindings, edges, evidence_sha256):
    """All edges or none. Bindings are {record_name: explicit native posting mapping}."""
    import frappe
    from . import finance, service
    frappe.only_for("System Manager")
    if not isinstance(evidence_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", evidence_sha256):
        frappe.throw("The proved source graph hash is required.")
    with service.locked_scope(scope_name) as scope:
        nodes, specs = {}, {}
        for name, mapping in bindings.items():
            record = service.get_record_for_effect(name, mapping.get("company"), "financial")
            if record["source_scope"] != scope_name:
                frappe.throw("The original record belongs to another migration scope.")
            f = record["business_data"]["financial"]
            spec = finance.build_journal_spec(record, mapping, approved_opening_date=scope["opening_effective_date"],
                shared_cash_approved=scope.get("shared_cash_policy") == "shared_pool")
            bound = service.authority(scope_name, spec["economic_key"], "financial")
            if not bound or bound.target_doctype != "Journal Entry" or bound.proof_sha256 != spec["proof_hash"]:
                frappe.throw("Post and verify the exact native financial authority before reconciliation.")
            finance.verify_journal(bound.target_name, spec)
            specs[name] = spec
            nodes[name] = {"company": record["company"], "source_book": record["source_book"], "finance_book": mapping["finance_book"],
                "accounting_party_id": f["accounting_party_id"], "amount": f["amount"], "adjusted": f.get("source_adjusted_amount"),
                "entry_type": f["entry_type"], "party_type": mapping["party_type"], "party": mapping["party"],
                "party_account": mapping["party_account"], "cost_center": mapping["cost_center"], "journal": bound.target_name}
        try:
            counts = validate_component(nodes, edges)
        except (ValueError, KeyError) as exc:
            frappe.throw(str(exc))
        component_key = sha256(json.dumps([scope_name, str(component_id)]).encode()).hexdigest()
        proof_hash = sha256(json.dumps({"evidence": evidence_sha256, "component": str(component_id),
            "nodes": {name: specs[name]["proof_hash"] for name in sorted(specs)},
            "edges": sorted(edges, key=lambda e: (e["first"], e["second"]))}, sort_keys=True).encode()).hexdigest()
        old = frappe.db.get_value(DOCTYPE, {"component_key": component_key}, ["name", "proof_sha256", "proof"], as_dict=True)
        if old:
            if old.proof_sha256 != proof_hash:
                frappe.throw("This component already has different immutable reconciliation evidence.")
            return {"created": False, "binding": old.name, **json.loads(old.proof)}
        savepoint = "historical_settlement_" + frappe.generate_hash(length=12)
        frappe.db.savepoint(savepoint)
        try:
            offsets = []
            for edge in edges:
                a, b, amount = nodes[edge["first"]], nodes[edge["second"]], _money(edge["amount"])
                if a["party_type"] == b["party_type"]:
                    payment, charge = (a, b) if _is_payment(a) else (b, a)
                    _reconcile(payment, charge["journal"], amount)
                else:
                    offsets.append(_offset(a, b, amount, component_key))
            remaining = {}
            for name, node in nodes.items():
                expected = (_money(node["amount"]) - _money(node["adjusted"])) * (-1 if _is_payment(node) else 1)
                actual = _outstanding(node)
                if actual != expected:
                    frappe.throw("Native outstanding differs from the proved conserved source component.")
                finance.verify_journal(node["journal"], specs[name])
                remaining[name] = format(actual, "f")
            applied_at = str(frappe.utils.now_datetime())
            proof = {**counts, "offset_journals": offsets, "outstanding_at_application": remaining,
                "applied_at": applied_at, "historical_allocation_date_claimed": False, "original_amounts_and_dates_preserved": True}
            doc = frappe.get_doc({"doctype": DOCTYPE, "source_scope": scope_name, "company": next(iter(nodes.values()))["company"], "component_key": component_key,
                "evidence_sha256": evidence_sha256, "proof_sha256": proof_hash, "applied_at": applied_at, "proof": json.dumps(proof, sort_keys=True)})
            token = _writing.set(True)
            try:
                doc.insert(ignore_permissions=True)
            finally:
                _writing.reset(token)
        except Exception:
            frappe.db.rollback(save_point=savepoint)
            raise
        return {"created": True, "binding": doc.name, **proof}
