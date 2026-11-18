"""Exact native financial authority for immutable historical business records."""
from datetime import date
from decimal import Decimal, InvalidOperation, localcontext
from hashlib import sha256
import json
from contextvars import ContextVar


VOUCHER_TYPES = frozenset({"sales", "purchase", "receipt", "payment", "tdsrecieve", "creditnote", "debitnote",
                           "creditadj", "debitadj", "opening-balance"})


def _text(value):
    return isinstance(value, str) and bool(value) and value == value.strip()


def _date(value):
    try:
        return isinstance(value, str) and date.fromisoformat(value).isoformat() == value
    except (TypeError, ValueError):
        return False


def _money(value):
    try:
        if isinstance(value, (bool, float)) or value is None or value == "":
            raise ValueError("Supply an exact native decimal amount.")
        amount = Decimal(str(value))
        if not amount.is_finite() or amount < 0 or amount != amount.quantize(Decimal("0.01")):
            raise ValueError("The native amount must be nonnegative and exactly representable at currency precision.")
        return amount
    except (InvalidOperation, TypeError):
        raise ValueError("Supply an exact native decimal amount.") from None


def _sum(values):
    with localcontext() as context:
        context.prec = 50
        return sum(values, Decimal(0))


def build_journal_spec(record, mapping, *, approved_opening_date=None, shared_cash_approved=False):
    """Compile one native voucher; supplied account mappings are never guessed."""
    financial = record.get("business_data", {}).get("financial")
    if not isinstance(financial, dict) or financial.get("voucher_type") not in VOUCHER_TYPES:
        raise ValueError("The record needs a supported native financial type.")
    opening = financial["voucher_type"] == "opening-balance"
    authority_kind = ("accv2.opening", "opening") if opening else ("accv2.voucher", "voucher")
    if (record.get("namespace"), record.get("family")) != authority_kind:
        raise ValueError("Only the native voucher or opening may post; original invoices remain linked nonposting records.")
    for key in ("source_scope", "source_key", "native_id", "company"):
        if not _text(record.get(key)):
            raise ValueError("The record needs its immutable source and company identity.")
    if (str(record.get("source_company_id")) not in {"1", "2", "3", "4"} or str(record.get("source_book")) not in {"0", "1", "2"}
            or any(str(record.get(k)) != str(mapping.get(k)) for k in ("source_company_id", "source_book", "company"))
            or not _text(mapping.get("finance_book"))):
        raise ValueError("Choose the exact company and nonblank mapped source book.")
    if (financial.get("currency") != mapping.get("currency") or financial.get("currency") != "INR"
            or financial.get("entry_type") not in {"debit", "credit"} or not isinstance(financial.get("cancelled"), bool)):
        raise ValueError("Currency, native debit/credit direction and cancellation state must be explicit.")
    if (not _text(financial.get("accounting_party_id")) or mapping.get("accounting_party_id") != financial["accounting_party_id"]
            or mapping.get("party_type") not in {"Customer", "Supplier"}
            or any(not _text(mapping.get(k)) for k in ("party", "party_account", "cost_center"))):
        raise ValueError("Map the native accounting party; the invoice customer cannot replace it.")
    original, effective = record.get("original_date_raw"), record.get("effective_date")
    if not _date(effective):
        raise ValueError("An effective posting date is required.")
    if _date(original):
        if original != effective or record.get("date_basis") != "original":
            raise ValueError("The original business date must be preserved.")
    elif not (opening and record.get("date_basis") == "approved_opening" and _date(approved_opening_date) and effective == approved_opening_date):
        raise ValueError("Only the scope-approved undated opening policy can supply a date.")
    amount = _money(financial.get("amount"))
    basis = mapping.get("counter_basis")
    if opening:
        valid_basis = basis == "approved_opening_equity"
    elif financial.get("general_ledger_id") not in (None, "", "0"):
        valid_basis = basis == "native_general_account" and mapping.get("general_ledger_id") == financial["general_ledger_id"]
    elif financial.get("cash_ledger_id") not in (None, "", "0"):
        valid_basis = (basis == "native_cashbook_movement" and shared_cash_approved
                       and mapping.get("cash_ledger_id") == financial["cash_ledger_id"])
    else:
        valid_basis = basis == "native_document_type" and financial["voucher_type"] == "sales"
    if not valid_basis:
        raise ValueError("The counterpart needs an explicit source-account or approved opening mapping.")
    result = {"source_key": record["source_key"], "economic_key": record["source_key"], "effect_kind": "financial",
              "source_amount": format(amount, "f"), "original_date_raw": original, "effective_date": effective,
              "source_parties": {"accounting_party_id": financial["accounting_party_id"], "invoice_party_id": financial.get("invoice_party_id")},
              "posting_required": amount != 0 and not financial["cancelled"], "posting_authority": "native_voucher_journal",
              "settlement_references_inferred": False}
    if not result["posting_required"]:
        result["reason"] = "source_cancelled" if financial["cancelled"] else "explicit_zero_native_amount"
        result["proof_hash"] = sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
        return result
    side = financial["entry_type"]
    opposite = "credit" if side == "debit" else "debit"

    def line(account, value, direction):
        if not _text(account) or direction not in {"debit", "credit"}:
            raise ValueError("Each native posting component needs its mapped account and direction.")
        return {"account": account, "account_currency": financial["currency"], "exchange_rate": 1,
                "debit_in_account_currency": format(value if direction == "debit" else Decimal(0), "f"),
                "credit_in_account_currency": format(value if direction == "credit" else Decimal(0), "f"),
                "cost_center": mapping["cost_center"]}

    party_line = line(mapping["party_account"], amount, side)
    party_line.update(party_type=mapping["party_type"], party=mapping["party"], is_advance="No")
    components = mapping.get("counter_components")
    if components is None:
        components = [{"account": mapping.get("counter_account"), "amount": format(amount, "f")}]
    if not isinstance(components, list) or not components:
        raise ValueError("Explicit counterpart components are required.")
    accounts = [party_line]
    for component in components:
        if not isinstance(component, dict) or component.get("account") == mapping["party_account"]:
            raise ValueError("Counterpart components cannot silently cancel the party account.")
        value = _money(component.get("amount"))
        if value == 0:
            continue
        accounts.append(line(component.get("account"), value, component.get("entry_type", opposite)))
    debit = _sum(Decimal(a["debit_in_account_currency"]) for a in accounts)
    credit = _sum(Decimal(a["credit_in_account_currency"]) for a in accounts)
    if debit != credit or len(accounts) < 2:
        raise ValueError("Counterpart components must balance the exact native party amount.")
    result["journal"] = {"doctype": "Journal Entry", "voucher_type": "Opening Entry" if opening else "Journal Entry",
        "company": mapping["company"], "finance_book": mapping["finance_book"], "posting_date": effective,
        "is_opening": "Yes" if opening else "No", "multi_currency": 0,
        "user_remark": f"Historical {financial['voucher_type']} · {financial.get('source_reference') or record['native_id']}",
        "accounts": accounts}
    result["proof_hash"] = sha256(json.dumps(result, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return result


BOOK_BINDING = "Historical Finance Book Binding"
_binding_write = ContextVar("historical_finance_binding_write", default=False)
SCOPED_TYPES = (BOOK_BINDING, "Historical Settlement Binding")


def resolve_book(selected, bindings, reference_books):
    """Bound companies use explicit books; ordinary companies retain native behavior."""
    if not bindings:
        return selected
    books = {row["finance_book"] for row in bindings}
    primary = [row["finance_book"] for row in bindings if str(row["source_book"]) == "0"]
    if len(books) != len(bindings) or len(primary) != 1:
        raise ValueError("The company needs unique mapped books and one primary book.")
    references = set(reference_books)
    if len(references) > 1 or not references.issubset(books):
        raise ValueError("Financial references must belong to one verified company book.")
    result = selected or (next(iter(references)) if references else primary[0])
    if result not in books or (references and references != {result}):
        raise ValueError("The selected book differs from the referenced transaction.")
    return result


def install():
    import frappe
    from frappe.custom.doctype.custom_field.custom_field import create_custom_fields
    from erp_extensions.knitting.install import field
    if not frappe.db.exists("DocType", BOOK_BINDING):
        frappe.get_doc({"doctype": "DocType", "name": BOOK_BINDING, "module": "Custom", "custom": 1,
            "autoname": "hash", "track_changes": 0,
            "fields": [field("source_scope", "Link", "Migration Scope", reqd=1),
                field("company", "Link", "Company", reqd=1), field("source_company_id", reqd=1),
                field("source_book", reqd=1), field("finance_book", "Link", "Finance Book", reqd=1, unique=1),
                field("mapping_key", reqd=1, unique=1)],
            "permissions": [{"role": "System Manager", "read": 1}]}).insert()
    create_custom_fields({dt: [{"fieldname": "finance_book", "label": "Finance Book", "fieldtype": "Link",
        "options": "Finance Book", "insert_after": "company", "no_copy": 0}]
        for dt in ("Sales Invoice", "Purchase Invoice", "Payment Entry") if not frappe.get_meta(dt).has_field("finance_book")})


def guard_book_binding(doc, method=None):
    import frappe
    if doc.doctype == BOOK_BINDING and (not doc.is_new() or not _binding_write.get()):
        frappe.throw("Historical company and book bindings are immutable.", frappe.PermissionError)


def has_permission(doc, ptype, user=None, **kwargs):
    import frappe
    from . import service
    from erp_extensions.knitting.permissions import company_allowed
    if doc.doctype not in SCOPED_TYPES:
        return True
    user = user or frappe.session.user
    if ptype not in ("read", "select") or (user != "Administrator" and "System Manager" not in frappe.get_roles(user)):
        return False
    scope = service.get_scope(doc.source_scope)
    if user not in scope["allowed_users"]:
        return False
    if doc.get("company"):
        return doc.company in scope["company_bindings"].values() and company_allowed(doc.company, user)
    return all(company_allowed(c, user) for c in scope["company_bindings"].values())


def query_conditions(user=None, doctype=None):
    import frappe
    from . import service
    from erp_extensions.knitting.permissions import companies
    if doctype not in SCOPED_TYPES:
        return ""
    user = user or frappe.session.user
    if user != "Administrator" and "System Manager" not in frappe.get_roles(user):
        return "1=0"
    permitted = {c.name for c in companies(user)}
    scopes = [row.name for row in frappe.get_all(service.SCOPE, fields=["name", "scope_data"])
        if user in json.loads(row.scope_data)["allowed_users"] and permitted.intersection(json.loads(row.scope_data)["company_bindings"].values())]
    if not scopes or not permitted:
        return "1=0"
    return (f"`tab{doctype}`.`source_scope` in (" + ",".join(frappe.db.escape(n) for n in scopes) + ") and "
        f"`tab{doctype}`.`company` in (" + ",".join(frappe.db.escape(c) for c in permitted) + ")")


def configure_books(scope_name, bindings):
    """Install exactly three caller-named books per company; no postings or commits."""
    import frappe
    from . import service
    frappe.only_for("System Manager")
    if not isinstance(bindings, list) or len(bindings) != 12:
        frappe.throw("Map all four companies and all three source books.")
    keys = {(str(r.get("source_company_id")), str(r.get("source_book"))) for r in bindings}
    if keys != {(str(c), str(b)) for c in range(1, 5) for b in range(3)}:
        frappe.throw("Map each source company and book exactly once.")
    if len({r.get("finance_book") for r in bindings}) != 12 or any(not _text(r.get("finance_book")) for r in bindings):
        frappe.throw("Each company and source book needs a distinct named Finance Book.")
    with service.locked_scope(scope_name) as scope:
        service.require_scope_write(scope)
        for row in bindings:
            company_id, book = str(row["source_company_id"]), str(row["source_book"])
            company = scope["company_bindings"][company_id]
            other = frappe.db.get_value(BOOK_BINDING, {"company": company, "source_book": book},
                ["source_scope", "finance_book"], as_dict=True)
            if other:
                if other.source_scope != scope_name or other.finance_book != row["finance_book"]:
                    frappe.throw("This company and source book already have a different binding.")
                continue
            if not frappe.db.exists("Finance Book", row["finance_book"]):
                frappe.get_doc({"doctype": "Finance Book", "finance_book_name": row["finance_book"]}).insert()
            key = sha256(json.dumps([scope_name, company_id, book]).encode()).hexdigest()
            doc = frappe.get_doc({"doctype": BOOK_BINDING, "source_scope": scope_name, "company": company,
                "source_company_id": company_id, "source_book": book, "finance_book": row["finance_book"], "mapping_key": key})
            token = _binding_write.set(True)
            try:
                doc.insert(ignore_permissions=True)
            finally:
                _binding_write.reset(token)
    return {"bindings": 12}


def _bindings(company):
    import frappe
    if not frappe.db.exists("DocType", BOOK_BINDING):
        return []
    return frappe.get_all(BOOK_BINDING, filters={"company": company},
        fields=["source_scope", "source_company_id", "source_book", "finance_book"])


def enforce_book(doc):
    import frappe
    bindings = _bindings(doc.get("company"))
    if doc.get("finance_book") and frappe.db.exists("DocType", BOOK_BINDING):
        owner = frappe.db.get_value(BOOK_BINDING, {"finance_book": doc.finance_book}, "company")
        if owner and owner != doc.company:
            frappe.throw("This Finance Book belongs to another company.")
    if not bindings:
        return
    references = []
    candidates = []
    if doc.doctype == "Journal Entry":
        candidates = [(r.reference_type, r.reference_name) for r in doc.get("accounts", [])]
    elif doc.doctype == "Payment Entry":
        candidates = [(r.reference_doctype, r.reference_name) for r in doc.get("references", [])]
    if doc.get("return_against"):
        candidates.append((doc.doctype, doc.return_against))
    if doc.get("amended_from"):
        candidates.append((doc.doctype, doc.amended_from))
    for doctype, name in candidates:
        if not name or doctype not in ("Journal Entry", "Sales Invoice", "Purchase Invoice", "Payment Entry"):
            continue
        source = frappe.db.get_value(doctype, name, ["company", "finance_book"], as_dict=True)
        if not source or source.company != doc.company:
            frappe.throw("A financial reference belongs to another company or is unavailable.")
        references.append(source.finance_book)
    try:
        doc.finance_book = resolve_book(doc.get("finance_book"), bindings, references)
    except ValueError as exc:
        frappe.throw(str(exc))


class FinanceBookMixin:
    """Opt-in company mappings propagate the same book into native GL and PLE."""
    def validate(self):
        enforce_book(self)
        return super().validate()

    def get_gl_dict(self, *args, **kwargs):
        row = super().get_gl_dict(*args, **kwargs)
        if _bindings(self.company):
            enforce_book(self)
            row["finance_book"] = self.finance_book
        return row


def verify_journal(name, spec):
    """Read native controller output; never create or repair GL/PLE rows directly."""
    import frappe
    from collections import defaultdict
    journal = spec["journal"]
    doc = frappe.get_doc("Journal Entry", name)
    if (doc.docstatus != 1 or doc.company != journal["company"] or doc.finance_book != journal["finance_book"]
            or str(doc.posting_date) != journal["posting_date"]):
        frappe.throw("The historical journal no longer matches its authority.")
    expected, actual = defaultdict(Decimal), defaultdict(Decimal)
    for row in journal["accounts"]:
        key = (row["account"], row.get("party_type") or "", row.get("party") or "")
        expected[key] += Decimal(row["debit_in_account_currency"]) - Decimal(row["credit_in_account_currency"])
    entries = frappe.get_all("GL Entry", filters={"voucher_type": "Journal Entry", "voucher_no": name, "is_cancelled": 0},
        fields=["company", "finance_book", "posting_date", "account", "party_type", "party", "account_currency", "debit", "credit"])
    for row in entries:
        if (row.company != doc.company or row.finance_book != doc.finance_book or str(row.posting_date) != str(doc.posting_date)
                or row.account_currency != "INR"):
            frappe.throw("Native ledger company, book, currency or date does not match the source authority.")
        actual[(row.account, row.party_type or "", row.party or "")] += Decimal(str(row.debit)) - Decimal(str(row.credit))
    if not entries or dict(actual) != dict(expected):
        frappe.throw("Native ledger amounts differ from the exact source posting components.")
    payments = frappe.get_all("Payment Ledger Entry", filters={"voucher_type": "Journal Entry", "voucher_no": name, "delinked": 0},
        fields=["company", "finance_book", "party_type", "party"])
    party = journal["accounts"][0]
    if not payments or any(p.company != doc.company or p.finance_book != doc.finance_book or p.party_type != party["party_type"]
                           or p.party != party["party"] for p in payments):
        frappe.throw("The native party ledger is missing or has different company/book ownership.")
    return {"journal": name, "gl_entries": len(entries), "payment_ledger_entries": len(payments), "exact_amounts_verified": True}


def post_record(record_name, mapping):
    """Atomic native journal + immutable authority; retry rechecks, never reposts."""
    import frappe
    from . import service
    record = service.get_record_for_effect(record_name, mapping.get("company"), "financial")
    with service.locked_scope(record["source_scope"]) as scope:
        binding = next((b for b in _bindings(record["company"]) if b.source_scope == record["source_scope"]
                        and b.source_book == record["source_book"]), None)
        if not binding or binding.finance_book != mapping.get("finance_book"):
            frappe.throw("The source book must have its immutable company binding before posting.")
        try:
            spec = build_journal_spec(record, mapping, approved_opening_date=scope["opening_effective_date"],
                                      shared_cash_approved=scope.get("shared_cash_policy") == "shared_pool")
        except ValueError as exc:
            frappe.throw(str(exc))
        if not spec["posting_required"]:
            return {"created": False, "posting_required": False, "reason": spec["reason"]}
        previous = service.authority(record["source_scope"], spec["economic_key"], "financial")
        if previous:
            if previous.target_doctype != "Journal Entry" or previous.proof_sha256 != spec["proof_hash"]:
                frappe.throw("This native source already has a different financial authority.")
            return {"created": False, **verify_journal(previous.target_name, spec)}
        savepoint = "historical_finance_" + frappe.generate_hash(length=12)
        frappe.db.savepoint(savepoint)
        try:
            doc = frappe.get_doc(spec["journal"]).insert()
            doc.submit()
            proof = verify_journal(doc.name, spec)
            service.bind_authority(record_name, "financial", spec["economic_key"], "Journal Entry", doc.name, spec["proof_hash"])
        except Exception:
            frappe.db.rollback(save_point=savepoint)
            raise
        return {"created": True, **proof}


def verify_party_controls(scope_name, controls):
    """Compare native GL net to every original unified party/company/book control."""
    import frappe
    from collections import defaultdict
    from . import service
    frappe.only_for("System Manager")
    scope = service.get_scope(scope_name)
    if controls.get("scope") != scope_name:
        frappe.throw("The monetary controls belong to another source scope.")
    rows, lookup, expected = controls.get("groups", []), {}, {}
    bindings = frappe.get_all(BOOK_BINDING, filters={"source_scope": scope_name},
        fields=["company", "source_company_id", "source_book", "finance_book"])
    books = {(b.source_company_id, b.source_book): b.finance_book for b in bindings}
    for row in rows:
        source_key = (row["source_company_id"], row["source_party_id"], row["source_book"])
        if (scope["company_bindings"].get(source_key[0]) != row["company"] or books.get((source_key[0], source_key[2])) != row["finance_book"]
                or source_key in expected):
            frappe.throw("The monetary control identity or target book is inconsistent.")
        expected[source_key] = Decimal(row["native_signed_amount"])
        for role, target in row["target_parties"].items():
            key = (row["company"], row["finance_book"], role, target["party"], target["account"])
            if key in lookup:
                frappe.throw("Two original parties share one native balance identity.")
            lookup[key] = source_key
    authorities = frappe.get_all(service.AUTHORITY, filters={"source_scope": scope_name, "effect_kind": "financial"},
        fields=["target_doctype", "target_name"])
    authority_complete = (len(authorities) == controls["native_journals_required"]
        and all(r.target_doctype == "Journal Entry" for r in authorities)
        and len({r.target_name for r in authorities}) == len(authorities))
    entries = frappe.get_all("GL Entry", filters={"company": ["in", list(scope["company_bindings"].values())],
        "finance_book": ["in", list(books.values())], "party_type": ["in", ["Customer", "Supplier"]], "is_cancelled": 0},
        fields=["company", "finance_book", "party_type", "party", "account", "debit", "credit", "voucher_type", "voucher_no"], limit_page_length=0)
    actual, unexpected = defaultdict(Decimal), []
    for entry in entries:
        key = (entry.company, entry.finance_book, entry.party_type, entry.party, entry.account)
        if key not in lookup:
            unexpected.append(dict(entry))
        else:
            actual[lookup[key]] += Decimal(str(entry.debit)) - Decimal(str(entry.credit))
    comparisons = [{"source_key": list(key), "expected_native_net": format(value, "f"), "actual_native_net": format(actual[key], "f"),
        "difference": format(actual[key] - value, "f"), "equal": actual[key] == value} for key, value in expected.items()]
    return {"financial_authorities_complete": authority_complete, "financial_authority_count": len(authorities),
        "company_party_book_groups": len(comparisons), "equal_groups": sum(r["equal"] for r in comparisons),
        "unexpected_party_rows": unexpected, "comparisons": comparisons,
        "all_native_party_balances_equal": authority_complete and not unexpected and all(r["equal"] for r in comparisons),
        "source_report_projection_proved_separately": True}
