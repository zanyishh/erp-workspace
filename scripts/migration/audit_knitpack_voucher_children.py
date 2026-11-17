#!/usr/bin/env python3
"""Audit captured native tax children and allocation candidates, offline only."""
import argparse
from collections import Counter, defaultdict
from datetime import date
import hashlib
import json
from pathlib import Path
import re

from audit_knitpack_reports import compare, exact_sum
from audit_knitpack_tally import iso_date
from check_knitpack_snapshot import identifier, response_failed, write_private
from inventory_knitpack_reports import records
from reconcile_knitpack_balances import number


TAX_FIELDS = ("taxable_value", "cgst_value", "sgst_value", "igst_value")
MONEY_FIELDS = (*TAX_FIELDS, "amt", "adj_val", "pend_amt")
HEADER_FIELDS = ("party_id", "entry_type", "v_date", "finyear", *MONEY_FIELDS, "cancelled", "created_time", "updated_time")
FULL = re.compile(r"^accv2/accounts/getvoucher/(\d+)$")
ALLOC = re.compile(r"^accv2/accounts/getAdjInfowithTaxType/(\d+)/(\d+)/(debit|credit)/([012])/(\d+)$")


def native_key(row):
    company, name, book = identifier(row.get("companymas_id")), identifier(row.get("id")), str(row.get("sec_acc"))
    return (company, name, book) if company and name and book in ("0", "1", "2") else None


def compact_compare(values, control):
    result = compare(values, control)
    return {"status": "passed"} if result["status"] == "passed" else result


def audit(folder, manifest=None):
    folder = folder.resolve()
    manifest = (folder / "manifest.jsonl").read_bytes() if manifest is None else manifest
    issues, versions, full_reports, allocation_entries, counts = [], defaultdict(dict), [], [], Counter()

    def remember(row):
        key = native_key(row)
        if key:
            signature = tuple(number(row.get(f)) if f in MONEY_FIELDS else json.dumps(row.get(f), sort_keys=True) for f in HEADER_FIELDS)
            versions[key][signature] = {f: row.get(f) for f in HEADER_FIELDS}

    for line, entry, payload in records(folder, manifest, issues, "reports"):
        full, allocation = FULL.fullmatch(entry["path"]), ALLOC.fullmatch(entry["path"])
        if full:
            counts["full_requests"] += 1
        if allocation:
            counts["allocation_requests"] += 1
            allocation_entries.append(entry)
        if response_failed(payload):
            continue
        roots = payload.get("root")
        roots = roots if isinstance(roots, list) else [roots] if isinstance(roots, dict) else []
        for root in roots:
            if not isinstance(root, dict):
                continue
            native = root.get("ledg_list") if isinstance(root.get("ledg_list"), list) else []
            if isinstance(root.get("voucher"), dict):
                native = [*native, root["voucher"]]
            for row in native:
                if isinstance(row, dict):
                    remember(row)
        if not full:
            continue
        value = payload.get("result")
        key = native_key(value) if isinstance(value, dict) else None
        filters = entry.get("filters") or {}
        request_ok = bool(key and key[1] == identifier(full[1]) and
            all(identifier(filters[f]) == key[index] for f, index in (("companymas_id", 0), ("voucher_id", 1)) if f in filters) and
            ("sec_acc" not in filters or str(filters["sec_acc"]) == key[2]))
        if not request_ok:
            counts["full_request_identity_or_response_failures"] += 1
            continue
        remember(value)
        rows = value.get("tax_list")
        rows_valid = isinstance(rows, list)
        rows = rows if rows_valid else []
        children, child_ids, identity_bad = [], set(), 0 if rows_valid else 1
        for index, row in enumerate(rows):
            child, parent = (identifier(row.get("id")), identifier(row.get("voucher_id"))) if isinstance(row, dict) else (None, None)
            valid = bool(child and parent == key[1] and child not in child_ids)
            if not valid:
                identity_bad += 1
            if child:
                child_ids.add(child)
            children.append({"row": index, "source_child_id": child, "source_parent_id": parent, "identity_valid": valid,
                             "source_created_time": row.get("created_time") if isinstance(row, dict) else None,
                             "source_updated_time": row.get("updated_time") if isinstance(row, dict) else None,
                             "source_cancelled": row.get("cancelled") if isinstance(row, dict) else None})
        tax_controls = {field: compact_compare([row.get(field) for row in rows], value.get(field)) for field in TAX_FIELDS} if rows and not identity_bad else {}
        full_reports.append({"source_file": entry["file"], "source_sha256": entry["sha256"], "source_key": list(key),
                             "source_posting_date": value.get("v_date"), "source_fiscal_id": value.get("finyear"),
                             "source_created_time": value.get("created_time"), "source_updated_time": value.get("updated_time"),
                             "tax_list_rows": len(rows), "valid_native_tax_children": sum(row["identity_valid"] for row in children),
                             "tax_child_identity_issues": identity_bad, "tax_children": children, "tax_controls": tax_controls,
                             "tax_comparisons_are_business_gate_controls": False,
                             "tax_comparison_applicability": "Raw field diagnostics; voucher-type applicability and historical tax mode are unproved.",
                             "header_tax_components_vs_amt_diagnostic": compact_compare([value.get(f) for f in TAX_FIELDS], value.get("amt")) if rows and not identity_bad else {"status": "not_applicable_or_unresolved"},
                             "debit_advice_list": {"type": type(value.get("debit_advice_list")).__name__,
                                 "rows": len(value["debit_advice_list"]) if isinstance(value.get("debit_advice_list"), list) else None,
                                 "row_fields": sorted({f for row in value.get("debit_advice_list", []) if isinstance(row, dict) for f in row if "session" not in f.lower()}) if isinstance(value.get("debit_advice_list"), list) else []},
                             "removed_tax_list_rows": len(value["removed_tax_list"]) if isinstance(value.get("removed_tax_list"), list) else None})
    headers = {key: next(iter(value.values())) for key, value in versions.items() if len(value) == 1}
    for full in full_reports:
        full["comparison_header_conflict"] = tuple(full["source_key"]) not in headers
    allocations = []
    selected_manifest = "".join(json.dumps(entry) + "\n" for entry in allocation_entries).encode()
    for _, entry, payload in records(folder, selected_manifest, issues, "allocation_responses"):
        request = ALLOC.fullmatch(entry["path"])
        company, party, entry_type, book, voucher = request.groups()
        company, party, voucher = identifier(company), identifier(party), identifier(voucher)
        key = (company, voucher, book)
        source = headers.get(key)
        filters = entry.get("filters") or {}
        request_ok = bool(source and identifier(source.get("party_id")) == party and source.get("entry_type") == entry_type and
            all(identifier(filters[f]) == expected for f, expected in (("companymas_id", company), ("voucher_id", voucher), ("party_id", party)) if f in filters) and
            ("sec_acc" not in filters or str(filters["sec_acc"]) == book) and ("entry_type" not in filters or filters["entry_type"] == entry_type))
        value = payload.get("result")
        rows = value.get("adj_list") if isinstance(value, dict) else None
        returned_book = str(value.get("acc_type")) if isinstance(value, dict) else None
        if not request_ok or returned_book != book or not isinstance(rows, list) or response_failed(payload):
            counts["allocation_request_identity_or_response_failures"] += 1
            allocations.append({"source_file": entry["file"], "source_sha256": entry["sha256"], "source_key": list(key),
                                "status": "current_header_identity_or_response_unresolved",
                                "returned_book_scope_indicator": returned_book, "returned_book_matches_request": returned_book == book})
            continue
        row_counts, nonzero_or_problem, amounts, target_ids = Counter(), [], [], Counter()
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                row_counts["invalid_rows"] += 1
                amounts.append(None)
                continue
            target_id, amount = identifier(row.get("id")), number(row.get("val"))
            target = headers.get((company, target_id, book))
            target_ok = bool(target and identifier(target.get("party_id")) == party and iso_date(row.get("v_date"))
                             and target.get("v_date") == row.get("v_date"))
            amounts.append(amount)
            if target_id:
                target_ids[target_id] += 1
            if not target_ok:
                row_counts["target_identity_unresolved_rows"] += 1
            left, right = identifier(row.get("acc_id")), identifier(row.get("toaccid"))
            endpoints = bool(target_ok and voucher != target_id and (
                (left == voucher and right == target_id and row.get("entry_type") == entry_type and row.get("toentrytype") == target.get("entry_type")) or
                (left == target_id and right == voucher and row.get("entry_type") == target.get("entry_type") and row.get("toentrytype") == entry_type)))
            if amount is None:
                row_counts["missing_or_invalid_amount_rows"] += 1
            elif amount == 0:
                row_counts["zero_value_rows"] += 1
            elif amount > 0:
                row_counts["positive_explicit_endpoint_candidates" if endpoints else "positive_unresolved_endpoint_rows"] += 1
            else:
                row_counts["negative_value_rows"] += 1
            try:
                later = date.fromisoformat(row.get("v_date")) > date.fromisoformat(source.get("v_date"))
            except (TypeError, ValueError):
                later = None
                row_counts["invalid_or_missing_original_date_rows"] += 1
            if later:
                row_counts["zero_value_future_target_rows" if amount == 0 else "nonzero_or_unknown_future_target_rows"] += 1
            if amount != 0 or not target_ok:
                nonzero_or_problem.append({"row": index, "source_target_voucher_id": target_id, "target_identity_corroborated": target_ok,
                    "source_target_document_date": row.get("v_date"), "source_acc_id": row.get("acc_id"), "source_toaccid": row.get("toaccid"),
                    "observed_value": format(amount, "f") if amount is not None else None,
                    "endpoint_classification": "explicit_directional_candidate_not_persistence_proof" if endpoints else "unresolved_endpoint",
                    "target_later_than_current_document_date": later})
        val_sum = exact_sum(amounts)
        allocations.append({"source_file": entry["file"], "source_sha256": entry["sha256"], "source_key": list(key),
            "status": "candidate_list_observed_not_proven_saved_edges", "source_document_date": source.get("v_date"),
            "returned_book_scope_indicator": returned_book, "returned_book_matches_request": True,
            "source_fiscal_id": source.get("finyear"), "row_observations": len(rows), "distinct_target_voucher_ids": len(target_ids),
            "repeated_target_voucher_id_values": sum(count > 1 for count in target_ids.values()),
            "row_id_semantics": "target_voucher_candidate_id; native allocation ID unproved", "allocation_effective_dates": "not_supplied",
            "row_counts": {field: row_counts[field] for field in ("invalid_rows", "target_identity_unresolved_rows", "missing_or_invalid_amount_rows", "zero_value_rows", "positive_explicit_endpoint_candidates", "positive_unresolved_endpoint_rows", "negative_value_rows", "invalid_or_missing_original_date_rows", "zero_value_future_target_rows", "nonzero_or_unknown_future_target_rows")},
            "diagnostics": {"observed_val_sum_vs_saved_adj_val": compact_compare(amounts, source.get("adj_val")),
                            "observed_val_sum_plus_saved_pending_vs_amt": compact_compare([val_sum, number(source.get("pend_amt"))], source.get("amt")),
                            "semantics": "display sum compared to saved header only; client does not assign adj_val or pend_amt from this sum"},
            "nonzero_or_identity_problem_rows": nonzero_or_problem})
    totals = Counter()
    for full in full_reports:
        totals["tax_rows"] += full["tax_list_rows"]
        totals["valid_native_tax_child_observations"] += full["valid_native_tax_children"]
        totals["tax_child_identity_issues"] += full["tax_child_identity_issues"]
        for result in full["tax_controls"].values():
            totals["tax_field_comparisons_" + result["status"]] += 1
    for allocation in allocations:
        totals.update(allocation.get("row_counts", {}))
    copied = {tuple(row["source_key"]) for row in full_reports}
    allocation_keys = {tuple(row["source_key"]) for row in allocations}
    eligible = {key for key, row in headers.items() if identifier(row.get("party_id")) and row.get("entry_type") in ("credit", "debit")}
    return {"version": 1, "import_allowed": False, "proven_persisted_allocation_edges": 0,
            "proven_persisted_allocation_edges_semantics": "Historical native allocation-row identity only; the separate current-state auditor can corroborate final references without such source child IDs.",
            "manifest_sha256": hashlib.sha256(manifest).hexdigest(), "manifest_entries": len(manifest.splitlines()),
            "integrity": {"valid": not issues, "issues": issues}, "request_counts": dict(counts),
            "native_header_keys": len(versions), "conflicting_header_keys": sum(len(value) > 1 for value in versions.values()),
            "coverage": {"distinct_full_voucher_keys": len(copied), "native_header_keys_without_full_copy": len(versions.keys() - copied),
                "native_header_keys_without_full_copy_ids": [list(key) for key in sorted(versions.keys() - copied)],
                "native_headers_matching_allocation_request_shape": len(eligible), "distinct_allocation_request_keys": len(allocation_keys),
                "matching_native_headers_without_allocation_response": len(eligible - allocation_keys),
                "complete_source_population": False},
            "summary_counts": dict(totals), "full_vouchers": full_reports, "allocation_responses": allocations,
            "limitations": [
                "Only captured, manifested responses are examined; acquisition may continue. Headers and candidate lists are not an atomic source snapshot.",
                "Saved tax_list IDs with matching voucher_id are native child evidence. Duplicate/wrong-parent identities withhold child-sum comparisons.",
                "Tax comparisons sum the saved raw child fields without recalculating rates or applying tolerance. The public client recalculates these fields interactively; historical tax_type/rounding semantics are not supplied, so discrepancies are not repaired.",
                "Allocation row.id can identify the current voucher, a different voucher or a separately corroborated opening obligation, not an allocation-line ID. This child audit does not reconstruct historical settlement events. A separate current-state conservation audit can support destination references without inventing source child IDs or effective dates.",
                "The public allocation client only sums val into display accumulators. Equality with saved adj_val/pend_amt is diagnostic, not a proved persistence equation.",
                "Zero-value and later-dated candidates remain candidate observations; they are not imported as historical allocations. Negative values are preserved without inventing reversal semantics.",
                "No source save, recalculation, automatic allocation, tax edit, import or posting is performed. All balances and operational import remain gated."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    target = args.report.resolve()
    if target.is_relative_to(args.reports.resolve()) or target.suffix != ".json":
        parser.error("Write private JSON evidence outside the read-only source archive.")
    manifest = (args.reports / "manifest.jsonl").read_bytes()
    write_private(target.with_name(target.stem + ".manifest.jsonl"), manifest.decode("utf-8"))
    report = audit(args.reports, manifest)
    write_private(target, json.dumps(report, indent=2) + "\n")
    print(json.dumps({"full_voucher_responses": len(report["full_vouchers"]), "allocation_responses": len(report["allocation_responses"]),
                      "integrity_issue_count": len(report["integrity"]["issues"]), "proven_persisted_allocation_edges": 0, "import_allowed": False}))
    return 0 if report["integrity"]["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
