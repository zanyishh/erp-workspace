"""Check an explicit offline historical-book plan; never connect, post or authorize import."""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re


COMPANIES = frozenset({"1", "2", "3", "4"})
# Only source books corroborated by native historical records are recognized.
BOOKS = frozenset({"0", "1", "2"})
POSTING_TYPES = frozenset({"Sales Invoice", "Purchase Invoice", "Payment Entry", "Journal Entry"})


def identifier(value):
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    text = str(value)
    return text if text and text == text.strip() else None


def scope(row):
    if not isinstance(row, dict):
        return None
    key = tuple(identifier(row.get(field)) for field in ("instance", "company_id", "book_id"))
    return key if all(part is not None for part in key) and key[1] in COMPANIES and key[2] in BOOKS else None


def identity(row):
    key = scope(row)
    if not key:
        return None
    detail = tuple(identifier(row.get(field)) for field in ("module", "record_type", "native_id"))
    return (*key, *detail) if all(detail) else None


def original_date(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return False
    try:
        date.fromisoformat(value)
        return True
    except ValueError:
        return False


def evidence(value):
    """Only validate a locator's shape. Its source meaning/hash needs the archive audits."""
    return (isinstance(value, dict) and isinstance(value.get("file"), str) and bool(value["file"])
            and isinstance(value.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", value["sha256"]) is not None
            and isinstance(value.get("pointer"), str) and value["pointer"].startswith("/"))


def audit(plan):
    issues = []

    def issue(code, collection, index=None):
        issues.append({"code": code, "collection": collection, "index": index})

    def rows(name):
        values = plan.get(name) if isinstance(plan, dict) else None
        if not isinstance(values, list) or any(not isinstance(row, dict) for row in values):
            issue("collection_invalid", name)
            return []
        return values

    mappings, documents, cash = rows("mappings"), rows("documents"), rows("shared_cash_ownership")
    scopes, company_targets, target_companies, book_targets, company_sets = {}, {}, {}, {}, {}
    for index, mapping in enumerate(mappings):
        key = scope(mapping)
        company, book = identifier(mapping.get("target_company")), identifier(mapping.get("finance_book"))
        if not key or not company or not book:
            issue("mapping_incomplete", "mappings", index)
            continue
        if key in scopes:
            issue("duplicate_scope_mapping", "mappings", index)
        scopes[key] = (company, book)
        source_company = key[:2]
        if source_company in company_targets and company_targets[source_company] != company:
            issue("source_company_split", "mappings", index)
        if company in target_companies and target_companies[company] != source_company:
            issue("target_company_shared", "mappings", index)
        if book in book_targets and book_targets[book] != key:
            issue("finance_book_shared", "mappings", index)
        company_targets[source_company], target_companies[company], book_targets[book] = company, source_company, key
        company_sets.setdefault(key[0], set()).add(key[1])
    if not company_sets or any(companies != COMPANIES for companies in company_sets.values()):
        issue("four_company_mapping_required", "mappings")

    keys, targets = set(), set()
    for index, document in enumerate(documents):
        key = identity(document.get("source"))
        if not key:
            issue("source_identity_incomplete", "documents", index)
            continue
        if key in keys:
            issue("duplicate_source_key", "documents", index)
        keys.add(key)
        mapped = scopes.get(key[:3])
        if mapped != (document.get("target_company"), document.get("finance_book")):
            issue("document_book_mapping_mismatch", "documents", index)
        if not evidence(document.get("source_book_evidence")):
            issue("native_book_evidence_missing", "documents", index)
        if not original_date(document.get("source_date")) or document.get("source_date") != document.get("posting_date"):
            issue("original_date_not_preserved", "documents", index)
        target = (document.get("target_doctype"), identifier(document.get("target_name")))
        if target[0] not in POSTING_TYPES or not target[1] or document.get("posting_authority") != "native_document":
            issue("posting_authority_unsupported", "documents", index)
        if target in targets:
            issue("duplicate_target_key", "documents", index)
        targets.add(target)

    for index, document in enumerate(documents):
        key = identity(document.get("source"))
        if not key:
            continue
        accounts = document.get("account_references")
        if not isinstance(accounts, list) or not accounts:
            issue("source_account_references_missing", "documents", index)
            accounts = []
        for account in accounts:
            if not isinstance(account, dict) or not identifier(account.get("native_id")) or not identifier(account.get("namespace")) or not evidence(account.get("evidence")):
                issue("source_account_references_missing", "documents", index)
                continue
            basis = account.get("ownership_basis")
            if basis == "approved_shared_cash":
                matches = [row for row in cash if row.get("instance") == key[0]
                           and row.get("namespace") == account["namespace"]
                           and identifier(row.get("native_id")) == identifier(account["native_id"])]
                approved = len(matches) == 1 and matches[0].get("status") == "approved" and evidence(matches[0].get("decision_evidence"))
                allowed = matches[0].get("company_books", []) if approved else []
                if not isinstance(allowed, list) or not any(scope({"instance": key[0], **row}) == key[:3] for row in allowed if isinstance(row, dict)):
                    issue("shared_cash_ownership_unresolved", "documents", index)
            elif basis != "native_company" or identifier(account.get("owner_company_id")) != key[1]:
                issue("account_ownership_unresolved", "documents", index)
        references = document.get("references")
        if not isinstance(references, list):
            issue("source_posting_references_missing", "documents", index)
            continue
        for reference in references:
            other = identity(reference.get("source")) if isinstance(reference, dict) else None
            if not other or other not in keys:
                issue("reference_target_missing", "documents", index)
            if other and other[:3] != key[:3]:
                issue("reference_cross_company_or_book", "documents", index)
            if not isinstance(reference, dict) or reference.get("relation") not in {"against_voucher", "return_against", "allocation"}:
                issue("reference_relation_unsupported", "documents", index)
                continue
            if not evidence(reference.get("evidence")):
                issue("native_reference_evidence_missing", "documents", index)
            if reference["relation"] == "allocation":
                historical = (reference.get("evidence_kind") == "saved_native_edge"
                    and identifier(reference.get("native_edge_key")) and original_date(reference.get("effective_date")))
                current_state = (reference.get("evidence_kind") == "conserved_current_state"
                    and evidence(reference.get("component_conservation_evidence")))
                if not evidence(reference.get("evidence")) or not (historical or current_state):
                    issue("saved_allocation_evidence_missing", "documents", index)
    if not documents:
        issue("document_plan_empty", "documents")
    return {"version": 1, "contract_valid": not issues, "import_allowed": False, "balances_verified": False,
            "distinct_document_keys": len(keys), "mapped_company_books": len(scopes), "issues": issues,
            "limits": ["Evidence locators are shape-checked, not verified or interpreted here.",
                       "Approved ownership is an asserted input requiring separate recorded user authorization.",
                       "No amounts, complete posting legs, target runtime behavior or business completeness are certified."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    raw = args.plan.read_bytes()
    report = audit(json.loads(raw))
    report["plan_sha256"] = hashlib.sha256(raw).hexdigest()
    args.report.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with os.fdopen(os.open(args.report, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    args.report.chmod(0o600)
    print(json.dumps({key: report[key] for key in ("contract_valid", "import_allowed", "balances_verified", "mapped_company_books")}))
    return 0 if report["contract_valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
