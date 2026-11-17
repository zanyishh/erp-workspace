#!/usr/bin/env python3
"""Offline exact ledger equations and source-period continuity; never imports."""
import argparse
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
import hashlib
import json
from pathlib import Path
import re

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_reports import response_failed, compare, exact_sum, selected_records
from check_knitpack_snapshot import check, identifier, write_private
from reconcile_knitpack_balances import number


ROUTES = {"accountLedgerPrint": "general", "getCashLedgerPrint": "cash", "getPartyLedgerPrint": "party"}
MASTERS = {"master-ledgers-fresh-session.json": "general", "master-cash-ledgers-fresh-session.json": "cash"}


def signed(debit, credit):
    debit, credit = number(debit), number(credit)
    return exact_sum([debit, credit.copy_negate()]) if debit is not None and credit is not None else None


def text_number(value):
    return format(value, "f") if value is not None else None


def general_projection_diagnostic(root):
    """Test the observed whole-unit presentation model without creating postings."""
    def whole(value):
        if value is None:
            return None
        with localcontext() as context:
            context.prec = max(28, len(value.as_tuple().digits) + max(value.adjusted(), 0) + 3)
            return value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN)
    result = {"posting_rule_proved": False, "model": "observed_half_even_whole_unit_projection_only",
              "row_projection_checks": {s: 0 for s in ("passed", "different", "unknown")},
              "row_findings": [], "control_comparisons": {}, "exact_amount_sums": {}, "rounded_row_sums": {}}
    amounts, rounded = {s: [] for s in ("debit", "credit")}, {s: [] for s in ("debit", "credit")}
    rows = root.get("ledg_list")
    master_side = root.get("ledger_info", {}).get("entry_type")
    for index, row in enumerate(rows if isinstance(rows, list) else [None]):
        row = row if isinstance(row, dict) else {}
        debit, credit, amount = (number(row.get(f)) for f in ("debit", "credit", "total"))
        side = ("debit" if debit is not None and debit > 0 and credit == 0 else
                "credit" if credit is not None and credit > 0 and debit == 0 else
                master_side if debit == 0 and credit == 0 and master_side in ("debit", "credit") else None)
        valid = side is not None and amount is not None and amount >= 0
        for column in ("debit", "credit"):
            exact = amount if valid and column == side else Decimal(0) if valid else None
            projected = whole(exact)
            amounts[column].append(exact)
            rounded[column].append(projected)
            comparison = compare([projected], row.get(column))
            result["row_projection_checks"][comparison["status"]] += 1
            if comparison["status"] != "passed":
                result["row_findings"].append({"row_index": index, "column": column, **comparison})
    opening = root.get("opbal") if isinstance(root.get("opbal"), dict) else {}
    closing = root.get("clbal") if isinstance(root.get("clbal"), dict) else {}
    controls = root.get("cdtotal") if isinstance(root.get("cdtotal"), dict) else {}
    op = signed(opening.get("debit"), opening.get("credit"))
    for column, control in (("debit", "dtotal"), ("credit", "ctotal")):
        exact, row_total = exact_sum(amounts[column]), exact_sum(rounded[column])
        result["exact_amount_sums"][column], result["rounded_row_sums"][column] = text_number(exact), text_number(row_total)
        opening_column = number(opening.get(column))
        net_opening = max(op if column == "debit" else op.copy_negate(), Decimal(0)) if op is not None else None
        with_opening, with_net_opening = exact_sum([opening_column, exact]), exact_sum([net_opening, exact])
        result["control_comparisons"][column] = {
            "cdtotal_vs_exact_amount_sum": compare([exact], controls.get(control)),
            "cdtotal_vs_sum_of_rounded_rows": compare([row_total], controls.get(control)),
            "cdtotal_vs_rounded_exact_sum": compare([whole(exact)], controls.get(control)),
            "cdtotal_vs_opening_plus_exact_sum": compare([with_opening], controls.get(control)),
            "cdtotal_vs_rounded_opening_plus_exact_sum": compare([whole(with_opening)], controls.get(control)),
            "cdtotal_vs_net_opening_plus_exact_sum": compare([with_net_opening], controls.get(control)),
            "cdtotal_vs_rounded_net_opening_plus_exact_sum": compare([whole(with_net_opening)], controls.get(control))}
    exact_net = signed(exact_sum(amounts["debit"]), exact_sum(amounts["credit"]))
    source_closing = signed(closing.get("debit"), closing.get("credit"))
    result["closing_vs_opening_plus_exact_movements"] = compare([op, exact_net], source_closing)
    result["closing_vs_rounded_opening_plus_exact_movements"] = compare([whole(exact_sum([op, exact_net]))], source_closing)
    return result


def audit(source, report_source, annual_only=False, report_manifest=None):
    baseline = check(source.resolve())
    result = {"version": 1, "import_allowed": False, "all_balances_reconciled": False,
              "report_archive_completeness": "unknown", "selected_evidence_integrity": {"issues": [], "verified_files": 0},
              "selection": "annual_named_files" if annual_only else "all_manifested_ledger_routes",
              "evidence_manifest": [], "partitions": [], "carry_forward": [], "book_ambiguities": [], "identity_issues": [], "scope_coverage": [],
              "voucher_book_evidence": {"verified_headers": 0, "native_party_header_observations": 0, "conflicting_header_keys": 0},
              "cash_cross_company_ambiguities": [],
              "cash_header_correspondence": {"candidate_tuple_matches": 0, "candidate_company_matches_requested": 0,
                  "candidate_company_differs_from_requested": 0, "unresolved_candidate_rows": 0,
                  "absolute_net_amount": {"passed": 0, "different": 0, "unknown": 0}, "findings": []},
              "master_ledger_ids": {"general": [], "cash": [], "party": []},
              "cdtotal_semantics": "Feed-supplied Total Debit/Credit fields, separately displayed from transaction sums; whether they include opening balances is unproved. Comparisons to movement sums are diagnostic.",
              "limitations": [
                  "Equations concern observed report partitions. Matching arithmetic cannot establish complete source transactions or account coverage.",
                  "Null, blank and missing debit/credit values stay unknown. An explicitly empty transaction array sums to zero only for that observed report scope.",
                  "Returned book identity needs explicit sec_acc evidence. Requested filters alone do not prove that the service separated books.",
                  "Identical book returns are flagged and never added together. Differing returns would also need source book identity before import.",
                  "Carry-forward checks compare the exact closing and next opening controls for adjacent requested periods within each ledger/company/requested-book scope; no dates are repaired or inferred from fiscal labels.",
                  "closing_amount/type are not used to infer debit/credit signs; original explicit debit and credit columns define the checked equation.",
                  "General and cash ledgers are separate source ID namespaces. Their report totals are never combined into a trial balance.",
                  "A party sec_accF field can echo request context and is not book proof. Native row sec_acc or an identity/date-matched original voucher header proves movement book only; it does not assign opening/closing controls to that book.",
                  "Native voucher headers from voucher prints or party-ledger rows are joined only by company and native voucher ID, with exact original date agreement. Unmatched or conflicting headers never supply a guessed book.",
                  "Cash-ledger voucher_id has no proved native entity mapping in available source evidence; numeric/date coincidences are not used to assign its book.",
                  "Cash company_info can echo the requested company while accounting data is shared. Company ownership is unknown; multi-field native-header correspondence is diagnostic, never automatic company/book attribution.",
              ]}
    if not baseline["integrity"]["valid"] or not baseline["identity"]["valid"]:
        result["selected_evidence_integrity"]["issues"].append("baseline_integrity_or_identity_failed")
        return result
    issues = result["selected_evidence_integrity"]["issues"]

    def selected(entry):
        if entry.get("file") in MASTERS:
            return True
        if "/getVoucherPrint/" in entry["path"]:
            return True
        if not any("/" + route + "/" in entry["path"] for route in ROUTES):
            return False
        return not annual_only or bool(re.fullmatch(r"c\d+-((general|party)-ledgers-book[012]|cash-ledger-\d+-book0)-fy\d{4}\.json", str(entry.get("audit_original_file", entry.get("file")))))

    manifest_hash, records = selected_records(report_source.resolve(), selected, issues, report_manifest)
    result["selected_evidence_integrity"].update(captured_manifest_sha256=manifest_hash, verified_files=len(records))
    voucher_headers, native_contexts = defaultdict(list), defaultdict(list)
    def remember_context(row, path):
        native_contexts[identifier(row.get("id"))].append({field: row.get(field) for field in (
            "companymas_id", "id", "sec_acc", "v_date", "v_no", "cash_ledger", "amt")} | {"path": path})
    for entry, payload, path in records:
        if response_failed(payload):
            continue
        result["evidence_manifest"].append({"file": entry["file"], "sha256": entry["sha256"], "bytes": entry["bytes"]})
        if entry["file"] in MASTERS:
            rows = payload.get("result")
            if not isinstance(rows, list) or payload.get("isLogin") is False:
                issues.append("invalid_ledger_master_catalogue")
                continue
            ids = [identifier(row.get("id")) if isinstance(row, dict) else None for row in rows]
            if None in ids or len(set(ids)) != len(ids):
                issues.append("invalid_or_duplicate_master_ledger_ids")
                continue
            result["master_ledger_ids"][MASTERS[entry["file"]]] = sorted(ids, key=int)
        if "/getVoucherPrint/" in entry["path"]:
            root, filters = payload.get("root"), entry.get("filters")
            voucher = root.get("voucher") if isinstance(root, dict) else None
            comp = root.get("company_info") if isinstance(root, dict) else None
            if (not isinstance(voucher, dict) or not isinstance(comp, dict) or not isinstance(filters, dict)
                    or not identifier(voucher.get("id")) or identifier(voucher.get("id")) != identifier(filters.get("id"))
                    or identifier(voucher.get("companymas_id")) not in baseline["companies"]
                    or identifier(comp.get("id")) != identifier(voucher.get("companymas_id"))
                    or str(voucher.get("sec_acc")) not in ("0", "1", "2") or not iso_date(voucher.get("v_date"))):
                result["identity_issues"].append({"path": path, "kind": "invalid_original_voucher_header"})
                continue
            key = (identifier(voucher["companymas_id"]), identifier(voucher["id"]))
            voucher_headers[key].append((str(voucher["sec_acc"]), voucher["v_date"], path))
            remember_context(voucher, path)
            result["voucher_book_evidence"]["verified_headers"] += 1
    for entry, payload, path in records:
        if response_failed(payload):
            continue
        if "/getPartyLedgerPrint/" not in entry["path"] or not isinstance(payload.get("root"), list):
            continue
        filters = entry.get("filters")
        if not isinstance(filters, dict):
            continue
        company = identifier(filters.get("companymas_id"))
        for root in payload["root"]:
            if (not isinstance(root, dict) or not isinstance(root.get("company_info"), dict)
                    or identifier(root["company_info"].get("id")) != company or company not in baseline["companies"]
                    or not isinstance(root.get("party_info"), dict) or not isinstance(root.get("ledg_list"), list)):
                continue
            party = identifier(root["party_info"].get("id"))
            for row in root["ledg_list"]:
                if (not isinstance(row, dict) or not identifier(row.get("id")) or identifier(row.get("companymas_id")) != company
                        or identifier(row.get("party_id")) != party or str(row.get("sec_acc")) not in ("0", "1", "2")
                        or not iso_date(row.get("v_date"))):
                    continue
                voucher_headers[(company, identifier(row["id"]))].append((str(row["sec_acc"]), row["v_date"], path))
                remember_context(row, path)
                result["voucher_book_evidence"]["native_party_header_observations"] += 1
    result["voucher_book_evidence"]["conflicting_header_keys"] = sum(len({(b, d) for b, d, _ in values}) > 1 for values in voucher_headers.values())
    period_groups, book_groups, cash_company_groups = defaultdict(list), defaultdict(list), defaultdict(list)
    for entry, payload, path in records:
        if response_failed(payload):
            continue
        if entry["file"] in MASTERS or "/getVoucherPrint/" in entry["path"]:
            continue
        route = next(route for route in ROUTES if "/" + route + "/" in entry["path"])
        kind, roots, filters = ROUTES[route], payload.get("root"), entry.get("filters")
        if not isinstance(roots, list) or not isinstance(filters, dict):
            result["identity_issues"].append({"path": path, "kind": "invalid_ledger_root_or_context"})
            continue
        company, book = identifier(filters.get("companymas_id")), str(filters.get("sec_acc"))
        start, end = filters.get("from_date"), filters.get("to_date")
        requested_ids = set()
        if kind == "party":
            query_ids = str(filters.get("party_id", ""))
            if re.fullmatch(r"\d+(,\d+)*", query_ids):
                requested_ids = {identifier(value) for value in query_ids.split(",")}
        seen = set()
        for root in roots:
            if not isinstance(root, dict):
                result["identity_issues"].append({"path": path, "kind": "invalid_ledger_object"})
                continue
            info, comp = root.get("party_info" if kind == "party" else "ledger_info"), root.get("company_info")
            control_id = "party_id" if kind == "party" else "ledger_id"
            ledger = identifier(info.get("id")) if isinstance(info, dict) else None
            rows, opening, closing, controls = root.get("ledg_list"), root.get("opbal"), root.get("clbal"), root.get("cdtotal")
            key = (kind, company, ledger, book, start, end)
            valid = (company in baseline["companies"] and ledger is not None and isinstance(comp, dict)
                     and identifier(comp.get("id")) == company and iso_date(start) and iso_date(end) and start <= end
                     and root.get("fdate") == start and root.get("tdate") == end and isinstance(rows, list)
                     and ledger not in seen and book in ("0", "1", "2"))
            seen.add(ledger)
            requested_ledger = identifier(filters.get("ledger_id"))
            if requested_ledger and requested_ledger != ledger:
                valid = False
            for control in (opening, closing):
                if not isinstance(control, dict) or identifier(control.get(control_id)) != ledger:
                    valid = False
            if kind == "party" and (not requested_ids or ledger not in requested_ids or identifier(root.get("party_id")) != ledger):
                valid = False
            masters = result["master_ledger_ids"][kind]
            if masters and ledger not in masters:
                valid = False
            returned_books, actual_book_rows = [], defaultdict(list)
            header_linked_rows, unresolved_book_rows = 0, 0
            if "sec_acc" in root:
                returned_books.append(str(root["sec_acc"]))
            if isinstance(rows, list):
                for row_index, row in enumerate(rows):
                    if not isinstance(row, dict):
                        valid = False
                        continue
                    row_date = row.get("date" if kind == "cash" else "v_date")
                    if (not iso_date(row_date) or not (iso_date(start) and iso_date(end)) or not start <= row_date <= end
                            or identifier(row.get({"general": "ledger_id", "cash": "cash_ledger_id", "party": "party_id"}[kind])) != ledger
                            or (kind != "cash" and identifier(row.get("companymas_id")) != company)):
                        valid = False
                    row_book = str(row["sec_acc"]) if "sec_acc" in row and str(row["sec_acc"]) in ("0", "1", "2") else None
                    voucher_id = identifier(row.get({"general": "v_id", "cash": "voucher_id", "party": "id"}[kind]))
                    if kind == "cash":
                        candidates = {}
                        for candidate in native_contexts.get(voucher_id, []):
                            if (isinstance(row.get("v_no"), str) and row["v_no"] and candidate["v_no"] == row["v_no"]
                                    and candidate["v_date"] == row_date and identifier(candidate["cash_ledger"]) == ledger):
                                candidate_key = (identifier(candidate["companymas_id"]), str(candidate["sec_acc"]), str(candidate["amt"]))
                                candidates[candidate_key] = candidate
                        correspondence = result["cash_header_correspondence"]
                        if len(candidates) == 1:
                            candidate_key, candidate = next(iter(candidates.items()))
                            correspondence["candidate_tuple_matches"] += 1
                            same_company = candidate_key[0] == company
                            correspondence["candidate_company_matches_requested" if same_company else "candidate_company_differs_from_requested"] += 1
                            net, amount = signed(row.get("debit"), row.get("credit")), number(candidate["amt"])
                            comparison = compare([net.copy_abs() if net is not None else None], amount.copy_abs() if amount is not None else None)
                            correspondence["absolute_net_amount"][comparison["status"]] += 1
                            if not same_company or comparison["status"] != "passed":
                                correspondence["findings"].append({"path": path, "row_index": row_index, "source_voucher_id": voucher_id,
                                    "requested_company_id": company, "candidate_native_company_id": candidate_key[0],
                                    "candidate_native_book": candidate_key[1], "header_path": candidate["path"],
                                    "amount_comparison": comparison, "ownership_assignment": "unknown_not_applied"})
                        else:
                            correspondence["unresolved_candidate_rows"] += 1
                    evidence = voucher_headers.get((company, voucher_id), []) if kind != "cash" else []
                    proven = {(b, d) for b, d, _ in evidence}
                    if len(proven) == 1:
                        native_book, native_date = next(iter(proven))
                        if native_date == row_date and (row_book is None or row_book == native_book):
                            row_book = native_book
                            header_linked_rows += 1
                        else:
                            result["identity_issues"].append({"path": path, "source_key": list(key), "kind": "voucher_original_date_or_book_conflict"})
                            row_book = None
                    elif len(proven) > 1:
                        row_book = None
                    if row_book is not None:
                        returned_books.append(row_book)
                        actual_book_rows[row_book].append(row)
                    else:
                        unresolved_book_rows += 1
            book_proof = "passed" if returned_books and all(value == book for value in returned_books) and (
                "sec_acc" in root or isinstance(rows, list) and len(returned_books) == len(rows)) else "unknown"
            if returned_books and any(value != book for value in returned_books):
                book_proof = "different"
            op = signed(opening.get("debit"), opening.get("credit")) if isinstance(opening, dict) else None
            cl = signed(closing.get("debit"), closing.get("credit")) if isinstance(closing, dict) else None
            debits = exact_sum([number(row.get("debit")) if isinstance(row, dict) else None for row in rows]) if isinstance(rows, list) else None
            credits = exact_sum([number(row.get("credit")) if isinstance(row, dict) else None for row in rows]) if isinstance(rows, list) else None
            movement = signed(debits, credits)
            equation = compare([op, movement], cl) if valid else {"status": "unknown", "reason": "source_identity_or_period_unresolved"}
            partition = {"source_key": list(key), "path": path, "kind": kind, "source_company_id": company,
                         "source_ledger_id": ledger, "requested_book": book, "from_date": start, "to_date": end,
                         "source_identity_and_period_valid": valid and kind != "cash", "source_request_context_and_period_consistent": valid,
                         "company_attribution": "unknown_cash_report_scope" if kind == "cash" else "returned_company_ids_consistent",
                         "returned_book_identity": book_proof,
                         "balance_control_book_identity": "unknown", "voucher_header_linked_entry_rows": header_linked_rows,
                         "unresolved_movement_book_rows": unresolved_book_rows, "movements_by_proven_actual_book": {},
                         "observed_entry_rows": len(rows) if isinstance(rows, list) else None,
                         "opening_net": text_number(op), "movement_debit": text_number(debits), "movement_credit": text_number(credits),
                         "movement_net": text_number(movement), "closing_net": text_number(cl), "balance_equation": equation,
                         "cdtotal_vs_movements_diagnostic": {}, "closing_display_interpretation": "unknown_not_used_for_signs",
                         "returned_ledger_object_sha256": hashlib.sha256(json.dumps(root, sort_keys=True, default=str).encode()).hexdigest(),
                         "returned_accounting_data_sha256": hashlib.sha256(json.dumps(
                             {field: root.get(field) for field in ("opbal", "clbal", "pendbal", "cdtotal", "ledg_list")}, sort_keys=True, default=str).encode()).hexdigest()}
            if kind == "general":
                partition["whole_unit_projection_diagnostic"] = general_projection_diagnostic(root)
            for field, total in (("dtotal", debits), ("ctotal", credits)):
                if valid and isinstance(controls, dict) and identifier(controls.get(control_id)) == ledger:
                    partition["cdtotal_vs_movements_diagnostic"][field] = compare([total], controls.get(field))
                    source_control = number(controls.get(field))
                    opening_column = number(opening.get("debit" if field == "dtotal" else "credit"))
                    delta = signed(source_control, total)
                    net_opening_column = max(op if field == "dtotal" else op.copy_negate(), 0) if op is not None else None
                    partition["cdtotal_vs_movements_diagnostic"][field]["pattern"] = {
                        "source_control_is_explicit_zero": source_control == 0 if source_control is not None else None,
                        "absolute_difference_equals_opening_column": delta.copy_abs() == opening_column.copy_abs() if delta is not None and opening_column is not None else None,
                        "control_equals_opening_plus_movements": compare([opening_column, total], source_control)["status"],
                        "control_equals_net_opening_column_plus_movements": compare([net_opening_column, total], source_control)["status"]}
                else:
                    partition["cdtotal_vs_movements_diagnostic"][field] = {"status": "unknown"}
            for actual_book, movement_rows in actual_book_rows.items():
                debit = exact_sum([number(row.get("debit")) for row in movement_rows])
                credit = exact_sum([number(row.get("credit")) for row in movement_rows])
                partition["movements_by_proven_actual_book"][actual_book] = {"rows": len(movement_rows),
                    "debit": text_number(debit), "credit": text_number(credit), "net": text_number(signed(debit, credit)),
                    "opening_and_closing_assignment": "unknown"}
            if not valid:
                result["identity_issues"].append({"path": path, "source_key": list(key), "kind": "ledger_company_identity_or_original_period_mismatch"})
            result["partitions"].append(partition)
            period_groups[(kind, company, ledger, book)].append(partition)
            book_groups[(kind, company, ledger, start, end)].append(partition)
            if kind == "cash":
                cash_company_groups[(ledger, book, start, end)].append(partition)
        requested_ledger = identifier(filters.get("ledger_id"))
        expected = requested_ids if kind == "party" else {requested_ledger} if requested_ledger else set(result["master_ledger_ids"][kind])
        result["scope_coverage"].append({"path": path, "kind": kind, "source_company_id": company, "requested_book": book,
            "from_date": start, "to_date": end, "returned_distinct_ids": len(seen - {None}),
            "requested_or_catalogue_ids": len(expected), "coverage_basis": "explicit_party_request" if kind == "party" else "master_catalogue",
            "requested_ids_without_returned_partition": sorted(expected - seen, key=int) if None not in expected else [],
            "unexpected_returned_ids": sorted(seen - expected - {None}, key=int) if expected else [],
            "complete_source_population": "unknown"})
    for key, partitions in period_groups.items():
        for previous in partitions:
            if not iso_date(previous["to_date"]):
                continue
            next_day = (date.fromisoformat(previous["to_date"]) + timedelta(days=1)).isoformat()
            for following in partitions:
                if following["from_date"] != next_day:
                    continue
                valid = previous["source_request_context_and_period_consistent"] and following["source_request_context_and_period_consistent"]
                comparison = compare([previous["closing_net"]], following["opening_net"]) if valid else {"status": "unknown"}
                result["carry_forward"].append({"source_key": list(key), "previous_to_date": previous["to_date"],
                    "next_from_date": following["from_date"], "paths": [previous["path"], following["path"]], "comparison": comparison})
    for key, partitions in book_groups.items():
        if len({p["requested_book"] for p in partitions}) < 2:
            continue
        result["book_ambiguities"].append({"source_key_without_book": list(key),
            "requested_books": sorted({p["requested_book"] for p in partitions}),
            "returned_ledger_objects_identical": len({p["returned_ledger_object_sha256"] for p in partitions}) == 1,
            "returned_accounting_data_identical": len({p["returned_accounting_data_sha256"] for p in partitions}) == 1,
            "returned_book_identity": "unknown" if any(p["returned_book_identity"] != "passed" for p in partitions) else "explicit",
            "paths": sorted({p["path"] for p in partitions}), "combined_posting_allowed": False})
    for key, partitions in cash_company_groups.items():
        if len({p["source_company_id"] for p in partitions}) < 2:
            continue
        result["cash_cross_company_ambiguities"].append({"source_cash_ledger_id": key[0], "requested_book": key[1],
            "from_date": key[2], "to_date": key[3], "requested_company_ids": sorted({p["source_company_id"] for p in partitions}),
            "returned_accounting_data_identical": len({p["returned_accounting_data_sha256"] for p in partitions}) == 1,
            "observed_rows_per_requested_company": {p["source_company_id"]: p["observed_entry_rows"] for p in partitions},
            "paths": sorted({p["path"] for p in partitions}), "company_ownership": "unknown", "combined_posting_allowed": False})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("--annual-only", action="store_true", help="Select the requested annual ledger filename series and master catalogues")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if destination.suffix != ".json" or any(destination.is_relative_to(folder.resolve()) for folder in (args.source, args.report_source)):
        parser.error("Write the private JSON report outside both read-only archives.")
    report = audit(args.source, args.report_source, args.annual_only)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    counts = {state: sum(p["balance_equation"]["status"] == state for p in report["partitions"]) for state in ("passed", "different", "unknown")}
    print(json.dumps({"import_allowed": False, "partitions": len(report["partitions"]), "balance_equations": counts,
                      "identity_issue_count": len(report["identity_issues"]), "report": str(destination)}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
