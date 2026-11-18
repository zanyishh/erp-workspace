#!/usr/bin/env python3
"""Corroborate captured current allocation state, without inventing settlement events."""
import argparse
from collections import Counter, defaultdict
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re

from audit_knitpack_tally import iso_date
from audit_knitpack_voucher_children import ALLOC, FULL, native_key
from check_knitpack_snapshot import identifier, response_failed, write_private
from inventory_knitpack_reports import records
from reconcile_knitpack_balances import number


# Manually reviewed public edit screen: load model, bind val, serialize model.
REVIEWED_UI_SHA256 = "65ffa95c652567763476898c7889424c41aa6ca0c84171867bdf5e926623f55d"
HEADER_FIELDS = ("party_id", "entry_type", "v_date", "v_no", "acc_type", "amt", "adj_val", "pend_amt", "cancelled", "finyear")
MONEY_FIELDS = {"amt", "adj_val", "pend_amt"}
OPENING = re.compile(r"^accv2/accounts/getopbal/(\d+)/(\d+)/([012])$")


def pair_key(first, second):
    return tuple(sorted((first, second)))


def analyse(headers, views, *, ui_contract_verified=False):
    counts = Counter(conserved_current_state_edges=0)
    tainted, candidates, witnesses = defaultdict(set), defaultdict(list), defaultdict(list)
    observations, view_controls, seen_views, recaptures = [], [], {}, []
    for view in views:
        key = tuple(view["source_key"])
        source = headers.get(key)
        rows = view.get("rows")
        signature = (view.get("scope_valid", True), json.dumps(rows, sort_keys=True, default=str))
        if key in seen_views:
            same = seen_views[key] == signature
            counts["identical_view_recaptures" if same else "conflicting_view_recaptures"] += 1
            recaptures.append({"source_key": list(key), "identical": same, "source_file": view.get("source_file"),
                               "source_sha256": view.get("source_sha256")})
            if not same:
                tainted[key].add("conflicting_request_scope_versions")
            continue
        seen_views[key] = signature
        if not source or not isinstance(rows, list) or view.get("scope_valid", True) is not True:
            tainted[key].add("view_scope_or_native_header_unresolved")
            counts["unresolved_views"] += 1
            continue
        amounts, targets_seen = [], set()
        for index, row in enumerate(rows):
            amount = number(row.get("val")) if isinstance(row, dict) else None
            amounts.append(amount)
            if amount is None:
                tainted[key].add("invalid_allocation_amount")
                continue
            if amount == 0:
                counts["zero_candidate_rows"] += 1
                continue
            if amount < 0:
                tainted[key].add("negative_value_semantics_unresolved")
                counts["negative_value_rows"] += 1
                continue
            counts["positive_rows"] += 1
            target_key = (key[0], identifier(row.get("id")), key[2])
            target = headers.get(target_key)
            row_scope_ok = (all(identifier(row[field]) == expected for field, expected in
                (("companymas_id", key[0]), ("party_id", identifier(source.get("party_id")))) if field in row)
                and ("sec_acc" not in row or str(row["sec_acc"]) == key[2]))
            identity_ok = bool(target and identifier(target.get("party_id")) == identifier(source.get("party_id"))
                and row_scope_ok
                and (iso_date(row.get("v_date")) or target.get("acc_type") == "opening-balance")
                and target.get("v_date") == row.get("v_date")
                and target.get("v_no") == row.get("v_no"))
            observation = {"request_key": list(key), "row_index": index, "target_key": list(target_key),
                "value": str(amount), "identity_corroborated": identity_ok,
                "internal_endpoints": [row.get("acc_id"), row.get("toaccid")],
                "source_file": view.get("source_file"), "source_sha256": view.get("source_sha256")}
            observations.append(observation)
            if not identity_ok:
                tainted[key].add("positive_target_identity_unresolved")
                counts["positive_target_identity_unresolved"] += 1
                continue
            if target_key in targets_seen:
                tainted[key].add("repeated_positive_target_in_view")
                tainted[target_key].add("repeated_positive_target_in_view")
            targets_seen.add(target_key)
            left, right = ((key[0], identifier(row.get(field)), key[2]) for field in ("acc_id", "toaccid"))
            lh, rh = headers.get(left), headers.get(right)
            if (lh and rh and left != right and identifier(lh.get("party_id")) == identifier(source.get("party_id"))
                    and identifier(rh.get("party_id")) == identifier(source.get("party_id"))
                    and {lh.get("entry_type"), rh.get("entry_type")} == {"debit", "credit"}):
                witnesses[pair_key(left, right)].append(observation)
            if key == target_key:
                counts["positive_self_summary_rows"] += 1
                continue
            if {source.get("entry_type"), target.get("entry_type")} != {"debit", "credit"}:
                tainted[key].add("same_or_unknown_entry_type")
                tainted[target_key].add("same_or_unknown_entry_type")
                counts["positive_same_or_unknown_entry_type_rows"] += 1
                continue
            candidates[pair_key(key, target_key)].append(observation)
        total = sum(amounts, Decimal(0)) if all(value is not None for value in amounts) else None
        adjusted = number(source.get("adj_val"))
        same = total is not None and adjusted is not None and total == adjusted
        if not same:
            tainted[key].add("view_sum_differs_native_adjusted")
        counts["view_sum_matches_adjusted" if same else "view_sum_differs_adjusted"] += 1
        view_controls.append({"source_key": list(key), "observed_sum": str(total) if total is not None else None,
                              "native_adjusted": str(adjusted) if adjusted is not None else None, "equal": same})

    adjacency, incident = defaultdict(set), defaultdict(lambda: Decimal(0))
    edges = []
    for pair, rows in candidates.items():
        amounts = {number(row["value"]) for row in rows}
        amount = next(iter(amounts)) if len(amounts) == 1 else None
        first, second = pair
        adjacency[first].add(second)
        adjacency[second].add(first)
        for key in pair:
            if amount is None:
                tainted[key].add("reciprocal_amount_conflict")
            else:
                incident[key] += amount
        direct = any({identifier(value) for value in row["internal_endpoints"]} == {first[1], second[1]} for row in rows)
        same_witness = [row for row in witnesses.get(pair, []) if number(row["value"]) == amount]
        evidence = ("direct_internal_endpoints" if direct else "same_amount_endpoint_witness_in_another_view"
                    if same_witness else "endpoint_witness_with_different_amount" if witnesses.get(pair)
                    else "ui_reference_context_only")
        counts["edge_evidence_" + evidence] += 1
        edges.append({"first": list(first), "second": list(second), "amount": str(amount) if amount is not None else None,
            "observations": rows, "endpoint_evidence": evidence, "same_amount_witnesses": same_witness,
            "source_document_dates": [headers[key].get("v_date") for key in pair],
            "source_allocation_child_id": None, "source_allocation_effective_date": None})

    node_controls = {}
    for key, header in headers.items():
        amount, adjusted, pending = (number(header.get(field)) for field in ("amt", "adj_val", "pend_amt"))
        if adjusted is None or incident[key] != adjusted:
            tainted[key].add("incident_sum_differs_native_adjusted")
        if amount is None or adjusted is None or amount < 0 or adjusted < 0 or adjusted > amount:
            tainted[key].add("native_amount_capacity_unresolved")
        if str(header.get("cancelled")) != "0":
            tainted[key].add("cancelled_state_unresolved")
        if adjusted != 0 and key not in seen_views and header.get("acc_type") != "opening-balance":
            tainted[key].add("adjusted_voucher_view_missing")
        pending_status = "unknown" if None in (amount, adjusted, pending) else "equal" if amount == adjusted + pending else "different"
        counts["native_amount_adjusted_pending_" + pending_status] += 1
        node_controls[key] = {"source_key": list(key), "original_date": header.get("v_date"), "source_fiscal_id": header.get("finyear"),
            "source_record_type": header.get("acc_type"), "original_date_status": "valid" if iso_date(header.get("v_date")) else "invalid_or_missing",
            "native_amount": str(amount) if amount is not None else None, "native_adjusted": str(adjusted) if adjusted is not None else None,
            "incident_sum": str(incident[key]), "native_pending": str(pending) if pending is not None else None,
            "amount_adjusted_pending_diagnostic": pending_status, "issues": sorted(tainted[key])}
    components, visited = [], set()
    for initial in headers:
        if initial in visited:
            continue
        nodes, remaining = set(), [initial]
        while remaining:
            key = remaining.pop()
            if key not in nodes:
                nodes.add(key)
                remaining.extend(adjacency[key] - nodes)
        visited.update(nodes)
        selected = [index for index, edge in enumerate(edges) if tuple(edge["first"]) in nodes]
        problems = Counter(problem for key in nodes for problem in tainted[key])
        status = ("unresolved" if problems else "no_allocation_needed" if not selected else
                  "conserved_current_state" if ui_contract_verified else "conserved_without_reviewed_ui_contract")
        counts[status + "_components"] += 1
        counts[status + "_nodes"] += len(nodes)
        counts[status + "_edges"] += len(selected)
        index = len(components)
        for edge_index in selected:
            edges[edge_index]["component"] = index
            edges[edge_index]["status"] = status
        components.append({"nodes": [list(key) for key in sorted(nodes)], "edge_indices": selected,
                           "status": status, "issue_counts": dict(problems)})
    return {"version": 1, "import_allowed": False, "historical_settlement_events_reconstructed": False,
            "ui_contract_verified": ui_contract_verified, "counts": dict(counts), "components": components,
            "edges": edges, "node_controls": list(node_controls.values()), "view_controls": view_controls,
            "view_recaptures": recaptures,
            "positive_observations": observations,
            "limits": ["Conserved current UI state is distinct from a history of settlement events.",
                "Self rows summarize the current voucher; they are never self-allocations.",
                "No source allocation child ID or effective time is invented; destination reference children would receive new IDs.",
                "Native pending-field comparisons are separate diagnostics, not demonstrated UI persistence equations.",
                "Native opening identities can support current references while an invalid/missing original date still blocks dated historical posting.",
                "Company/book ownership, invoice-voucher mapping, monetary postings and all financial controls still require approval."]}


def audit(folder, manifest, ui_asset):
    issues, versions, views, full_keys = [], defaultdict(dict), [], set()
    captures = []
    opening_counts = Counter()
    opening_scope_diagnostics = []

    def remember(row):
        key = native_key(row)
        if key:
            signature = tuple(number(row.get(field)) if field in MONEY_FIELDS else json.dumps(row.get(field), sort_keys=True) for field in HEADER_FIELDS)
            versions[key][signature] = {field: row.get(field) for field in HEADER_FIELDS}

    for _, entry, payload in records(folder.resolve(), manifest, issues, "reports"):
        if response_failed(payload):
            continue
        roots = payload.get("root")
        for root in roots if isinstance(roots, list) else [roots]:
            if not isinstance(root, dict):
                continue
            native = root.get("ledg_list") if isinstance(root.get("ledg_list"), list) else []
            if isinstance(root.get("voucher"), dict):
                native = [*native, root["voucher"]]
            for row in native:
                if isinstance(row, dict):
                    remember(row)
        full = FULL.fullmatch(entry["path"])
        if full:
            value = payload.get("result")
            key = native_key(value) if isinstance(value, dict) else None
            f = entry.get("filters") or {}
            if (key and key[1] == identifier(full[1])
                    and all(identifier(f[field]) == key[index] for field, index in (("companymas_id", 0), ("voucher_id", 1)) if field in f)
                    and ("sec_acc" not in f or str(f["sec_acc"]) == key[2])):
                full_keys.add(key)
                remember(value)
        if ALLOC.fullmatch(entry["path"]):
            captures.append((entry, payload))
        opening = OPENING.fullmatch(entry["path"])
        if opening:
            opening_counts["scoped_responses"] += 1
            value = payload.get("result")
            row = value.get("d") if isinstance(value, dict) else None
            company, party, book = opening.groups()
            if row is False:
                same_context = str(value.get("acc_type")) == book
                opening_counts["explicit_no_record" if same_context else "false_with_different_or_missing_context"] += 1
                if not same_context:
                    opening_scope_diagnostics.append({"source_file": entry["file"], "source_sha256": entry["sha256"],
                        "requested_company_party_book": [company, party, book], "returned_context": value.get("acc_type"),
                        "native_record_supplied": False, "absence_in_requested_book_proved": False})
                continue
            key = native_key(row) if isinstance(row, dict) else None
            if (key and key[0] == company and key[2] == book and identifier(row.get("party_id")) == party
                    and str(value.get("acc_type")) == book and row.get("acc_type") == "opening-balance"):
                remember(row)
                opening_counts["native_records_scoped"] += 1
            else:
                opening_counts["scope_or_response_unresolved"] += 1
        elif entry["path"] == "accv2/accounts/getOpenningBalancelist/0":
            # The list's suffix is not a proved book filter; retain each explicit native scope.
            for row in payload.get("result", []) if isinstance(payload.get("result"), list) else []:
                if isinstance(row, dict) and native_key(row) and row.get("acc_type") == "opening-balance":
                    remember(row)
                    opening_counts["list_native_record_observations"] += 1
    headers = {key: next(iter(value.values())) for key, value in versions.items() if len(value) == 1}
    for entry, payload in captures:
        company, party, entry_type, book, voucher = ALLOC.fullmatch(entry["path"]).groups()
        key, value, f = (company, voucher, book), payload.get("result"), entry.get("filters") or {}
        source = headers.get(key)
        valid = bool(source and identifier(source.get("party_id")) == party and source.get("entry_type") == entry_type
            and isinstance(value, dict) and str(value.get("acc_type")) == book
            and all(identifier(f[field]) == expected for field, expected in (("companymas_id", company), ("party_id", party), ("voucher_id", voucher)) if field in f)
            and ("sec_acc" not in f or str(f["sec_acc"]) == book) and ("entry_type" not in f or f["entry_type"] == entry_type))
        views.append({"source_key": list(key), "scope_valid": valid, "rows": value.get("adj_list") if isinstance(value, dict) else None,
                      "source_file": entry["file"], "source_sha256": entry["sha256"], "retrieved_at_utc": entry.get("retrieved_at_utc")})
    ui_hash = hashlib.sha256(ui_asset.read_bytes()).hexdigest()
    report = analyse(headers, views, ui_contract_verified=ui_hash == REVIEWED_UI_SHA256 and not issues)
    report.update(manifest_sha256=hashlib.sha256(manifest).hexdigest(), manifest_entries=len(manifest.splitlines()),
        integrity_issues=issues, native_header_keys=len(versions), conflicting_native_header_keys=sum(len(value) > 1 for value in versions.values()),
        copied_full_native_keys=len(full_keys), allocation_views=len(views), reviewed_ui_sha256=ui_hash,
        native_opening_evidence=dict(opening_counts),
        opening_scope_diagnostics=opening_scope_diagnostics,
        capture_times_utc=sorted({view["retrieved_at_utc"] for view in views if view["retrieved_at_utc"]}))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path)
    parser.add_argument("--ui-asset", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    target = args.report.resolve()
    if target.is_relative_to(args.reports.resolve()) or target.suffix != ".json":
        parser.error("Write private JSON evidence outside the source archive.")
    manifest = (args.reports / "manifest.jsonl").read_bytes()
    write_private(target.with_name(target.stem + ".manifest.jsonl"), manifest.decode())
    result = audit(args.reports, manifest, args.ui_asset)
    write_private(target, json.dumps(result, indent=2) + "\n")
    print(json.dumps({"native_header_keys": result["native_header_keys"], "copied_full_native_keys": result["copied_full_native_keys"],
                      "allocation_views": result["allocation_views"], "counts": result["counts"], "import_allowed": False}))
    return 2 if result["integrity_issues"] or result["conflicting_native_header_keys"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
