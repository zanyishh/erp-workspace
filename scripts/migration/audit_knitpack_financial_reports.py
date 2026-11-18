#!/usr/bin/env python3
"""Offline invoice/voucher observations from completed, manifested report files.

No source requests, source changes, accounting adjustments or imports are made.
"""
import argparse
from collections import Counter, defaultdict
from datetime import date
import json
from pathlib import Path

from audit_knitpack_reports import response_failed, compare, selected_records
from check_knitpack_snapshot import check, identifier, write_private
from reconcile_knitpack_balances import number


ROUTES = {"getInvoiceRegPrint": "invoicereg", "getInvoiceDetRegPrint": "invoicedetreg", "getVoucherRegister": "statement"}
HEADER_FIELDS = ("total_rolls_pcs", "total_kgs", "total_value", "taxable_value", "sgst_value", "cgst_value",
                 "igst_value", "tcs_value", "invoice_value", "r_invoice_value")
IDENTITY_FIELDS = ("invoice_date", "finyear", "invoice_type", "cancelled", "party_id")
VOUCHER_FIELDS = ("amt", "taxable_value", "sgst_amt", "cgst_amt", "igst_amt", "without_tax_value", "tax_value")


def one_number(rows, field):
    values = {number(row.get(field)) for row in rows}
    return next(iter(values)) if len(values) == 1 and None not in values else None


def iso_date(value):
    try:
        return isinstance(value, str) and date.fromisoformat(value).isoformat() == value
    except ValueError:
        return False


def voucher_header_coverage(report_source, companies, report_manifest=None):
    """Compare complete native header fields; never emit field values or tokens."""
    issues = []
    manifest, records = selected_records(report_source.resolve(), lambda e: any("/" + route + "/" in e["path"]
        for route in ("getPartyLedgerPrint", "getVoucherPrint", "getVoucherRegister")), issues, report_manifest)
    party, prints, registers = defaultdict(list), [], set()
    for entry, payload, path in records:
        if response_failed(payload):
            continue
        root, filters = payload.get("root"), entry.get("filters")
        if not isinstance(filters, dict):
            continue
        if "/getPartyLedgerPrint/" in entry["path"] and isinstance(root, list):
            company = identifier(filters.get("companymas_id"))
            for ledger in root:
                if (company not in companies or not isinstance(ledger, dict) or not isinstance(ledger.get("company_info"), dict)
                        or identifier(ledger["company_info"].get("id")) != company or not isinstance(ledger.get("party_info"), dict)
                        or not isinstance(ledger.get("ledg_list"), list)):
                    continue
                party_id = identifier(ledger["party_info"].get("id"))
                for row in ledger["ledg_list"]:
                    if (not isinstance(row, dict) or identifier(row.get("companymas_id")) != company
                            or identifier(row.get("party_id")) != party_id or not identifier(row.get("id"))
                            or str(row.get("sec_acc")) not in ("0", "1", "2") or not iso_date(row.get("v_date"))):
                        continue
                    party[(company, identifier(row["id"]), str(row["sec_acc"]))].append((row, path))
        elif "/getVoucherPrint/" in entry["path"] and isinstance(root, dict):
            row, company_info = root.get("voucher"), root.get("company_info")
            if (not isinstance(row, dict) or not isinstance(company_info, dict) or not identifier(row.get("id"))
                    or identifier(row.get("id")) != identifier(filters.get("id")) or identifier(row.get("companymas_id")) not in companies
                    or identifier(company_info.get("id")) != identifier(row.get("companymas_id"))
                    or str(row.get("sec_acc")) not in ("0", "1", "2") or not iso_date(row.get("v_date"))):
                issues.append("invalid_native_voucher_print_identity")
                continue
            prints.append(((identifier(row["companymas_id"]), identifier(row["id"]), str(row["sec_acc"])), row, path))
        elif "/getVoucherRegister/" in entry["path"] and isinstance(root, dict):
            company = identifier(filters.get("companymas_id"))
            if company not in companies or not isinstance(root.get("company_info"), dict) or identifier(root["company_info"].get("id")) != company:
                continue
            for row in root.get("statement", []):
                if isinstance(row, dict) and identifier(row.get("id")) and str(filters.get("sec_acc")) in ("0", "1", "2"):
                    registers.add((company, identifier(row["id"]), str(filters["sec_acc"])))
    counts = {"prints": len(prints), "all_header_fields_present_and_exact": 0, "print_missing_party": 0, "header_difference_or_missing_fields": 0}
    header_fields, missing_fields, mismatched_fields, findings = set(), Counter(), Counter(), []
    conflicts = {key for key, values in party.items() if len({json.dumps(row, sort_keys=True, default=str) for row, _ in values}) > 1}
    for key, header, path in prints:
        header_fields.update(header)
        if key not in party:
            counts["print_missing_party"] += 1
            findings.append({"key": list(key), "kind": "print_missing_party", "path": path})
            continue
        missing, mismatched = set(), set()
        for row, _ in party[key]:
            missing.update(set(header) - set(row))
            mismatched.update(field for field in header if field in row and header[field] != row[field])
        if not missing and not mismatched:
            counts["all_header_fields_present_and_exact"] += 1
        else:
            counts["header_difference_or_missing_fields"] += 1
            missing_fields.update(missing)
            mismatched_fields.update(mismatched)
            findings.append({"key": list(key), "kind": "header_difference", "missing_fields": sorted(missing),
                "mismatch_fields": sorted(mismatched), "paths": [path] + [p for _, p in party[key]]})
    return {"captured_manifest_sha256": manifest, "selected_integrity_issues": issues, "selected_files": len(records),
        "counts": counts, "party_distinct_company_id_book_keys": len(party), "register_distinct_company_id_book_keys": len(registers),
        "print_header_field_names": sorted(header_fields), "header_schema_status": "observed_print_fields" if header_fields else "unknown_no_print_sample",
        "missing_header_field_counts": dict(missing_fields), "mismatched_header_field_counts": dict(mismatched_fields),
        "party_conflicting_keys": [list(key) for key in sorted(conflicts)],
        "register_ids_without_party_header": [list(key) for key in sorted(registers - party.keys())],
        "register_keys_with_conflicting_party_versions": [list(key) for key in sorted(registers & conflicts)],
        "register_keys_missing_observed_header_fields": [list(key) for key in sorted(registers & party.keys())
            if any(not header_fields.issubset(row) for row, _ in party[key])], "print_comparison_findings": findings,
        "limitation": "Exact sampled header overlap and captured register coverage do not prove unobserved print-only signatures/attachments or complete financial balances."}


def audit(source, report_source, report_manifest=None):
    baseline = check(source.resolve())
    result = {"version": 1, "import_allowed": False, "financial_balances": "unknown",
              "voucher_invoice_linkage": "unknown_no_explicit_foreign_key", "voucher_invoice_linkage_scope": "flattened_reports_only; explicit native references are audited separately", "report_archive_completeness": "unknown",
              "selected_evidence_integrity": {"issues": [], "verified_files": 0}, "identity_issues": [], "findings": [],
              "checks": {name: {"passed": 0, "different": 0, "unknown": 0} for name in (
                  "header_fields", "line_quantity_totals", "line_value_diagnostic", "detail_report_controls", "voucher_export_overlap")},
              "companies": {}, "scopes": [],
              "limitations": [
                  "Only manifested invoice and voucher report files are selected. This does not certify the growing archive complete.",
                  "Invoice parent keys use companymas_id plus invoice_id with inv_id corroboration; flattened id fields are not assumed to identify the invoice.",
                  "Repeated header fields and report controls are overlapping source observations, not independent accounting or receivable balances.",
                  "Line value versus total_value is diagnostic only: complete source add/less, rounding and tax semantics remain required. Differences are never adjusted or silently tolerated.",
                  "Voucher keys include source company, account type, secondary-account scope and source ID. Numeric ID or printed-number coincidence never links a voucher to an invoice.",
                  "The voucher ctotal field has no established arithmetic contract; null does not mean zero or a reconciled ledger.",
                  "Detail rows lack a validated unique line ID. Sums use the observed rows of each report separately; repeated exports are not merged into transaction totals.",
                  "Empty report scopes do not prove an empty company. General invoice rows require a separate validated identity/line contract.",
                  "Original dates are compared exactly. Non-ISO values remain unresolved and are not interpreted or repaired.",
              ]}
    if not baseline["integrity"]["valid"] or not baseline["identity"]["valid"]:
        result["selected_evidence_integrity"]["issues"].append("baseline_integrity_or_identity_failed")
        return result
    result["voucher_header_coverage"] = voucher_header_coverage(report_source, set(baseline["companies"]), report_manifest)
    for company in baseline["companies"]:
        result["companies"][company] = {"header_files": 0, "detail_files": 0, "voucher_files": 0,
            "observed_header_rows": 0, "observed_detail_rows": 0, "observed_voucher_rows": 0,
            "general_invoice_rows_not_reconciled": 0, "distinct_header_invoices": 0, "distinct_detail_invoices": 0,
            "header_detail_overlap_invoices": 0, "distinct_vouchers": 0, "header_without_details": [], "details_without_header": [],
            "header_by_source_fiscal_year_id": {}, "balances": "unknown"}
    issues = result["selected_evidence_integrity"]["issues"]
    manifest_hash, records = selected_records(report_source.resolve(), lambda e: any("/" + route + "/" in e["path"] for route in ROUTES), issues, report_manifest)
    result["selected_evidence_integrity"].update(captured_manifest_sha256=manifest_hash, verified_files=len(records))
    headers, details, vouchers = defaultdict(list), [], defaultdict(list)
    detail_keys = set()

    def numeric(check_name, values, control, field, paths, key=None):
        observation = compare(values, control)
        result["checks"][check_name][observation["status"]] += 1
        if observation["status"] != "passed":
            result["findings"].append({"check": check_name, "field": field, "paths": sorted(set(paths)),
                                       "source_key": list(key) if key else None, **observation})

    def identity(kind, path, key=None):
        result["identity_issues"].append({"kind": kind, "path": path, "source_key": list(key) if key else None})

    for entry, payload, path in records:
        if response_failed(payload):
            continue
        route = next(route for route in ROUTES if "/" + route + "/" in entry["path"])
        root, filters = payload.get("root"), entry.get("filters")
        if not isinstance(root, dict) or not isinstance(filters, dict):
            identity("invalid_report_root_or_context", path)
            continue
        company = identifier(filters.get("companymas_id"))
        info = root.get("company_info")
        rows = root.get(ROUTES[route])
        if (company not in result["companies"] or not isinstance(info, dict) or identifier(info.get("id")) != company
                or not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows)):
            identity("invalid_company_context_or_rows", path)
            continue
        invoice = route != "getVoucherRegister"
        if any("companymas_id" in row and identifier(row["companymas_id"]) != company for row in rows):
            identity("row_company_mismatch", path)
            continue
        if invoice and any(identifier(row.get("companymas_id")) != company or not identifier(row.get("invoice_id"))
                           or identifier(row.get("invoice_id")) != identifier(row.get("inv_id")) for row in rows):
            identity("invalid_invoice_parent_identity", path)
            continue
        if not invoice and any(not identifier(row.get("id")) or str(row.get("acc_type")) != str(filters.get("acc_type")) for row in rows):
            identity("invalid_voucher_identity_or_type", path)
            continue
        dates = [row.get("invoice_date" if invoice else "v_date") for row in rows]
        scope = {"path": path, "source_company_id": company, "route": route, "rows": len(rows),
                 "original_iso_date_rows": sum(iso_date(value) for value in dates),
                 "unresolved_date_rows": sum(not iso_date(value) for value in dates),
                 "original_iso_dates": sorted({value for value in dates if iso_date(value)}),
                 "requested_from_date": filters.get("from_date"), "requested_to_date": filters.get("to_date"),
                 "root_dates_equal_request": root.get("fdate") == filters.get("from_date") and root.get("tdate") == filters.get("to_date")}
        result["scopes"].append(scope)
        stats = result["companies"][company]
        if route == "getInvoiceRegPrint":
            stats["header_files"] += 1
            stats["observed_header_rows"] += len(rows)
            general = root.get("gen_invoice")
            stats["general_invoice_rows_not_reconciled"] += len(general) if isinstance(general, list) else 0
            for row in rows:
                headers[(company, identifier(row["invoice_id"]))].append((row, path))
        elif route == "getInvoiceDetRegPrint":
            stats["detail_files"] += 1
            stats["observed_detail_rows"] += len(rows)
            grouped = defaultdict(list)
            for row in rows:
                key = (company, identifier(row["invoice_id"]))
                grouped[key].append(row)
                detail_keys.add(key)
            for key, group in grouped.items():
                details.append((key, group, path))
            for control, field in (("cgst_value", "cgst"), ("sgst_value", "sgst"), ("igst_value", "igst"), ("invoice_value", "item_val")):
                numeric("detail_report_controls", [row.get(field) for row in rows], root.get(control), control, [path])
        else:
            stats["voucher_files"] += 1
            stats["observed_voucher_rows"] += len(rows)
            scope["ctotal_status"] = "unknown_semantics" if root.get("ctotal") is not None else "unknown_missing"
            for row in rows:
                key = (company, str(row["acc_type"]), str(filters.get("sec_acc")), identifier(row["id"]))
                vouchers[key].append((row, path))

    for key, detail_rows, path in details:
        matched = headers.get(key)
        if not matched:
            continue
        header_rows = [row for row, _ in matched]
        all_rows = header_rows + detail_rows
        if (any(len({str(row.get(field)) for row in all_rows}) != 1 or any(row.get(field) is None for row in all_rows) for field in IDENTITY_FIELDS)
                or any(not iso_date(row.get("invoice_date")) for row in all_rows)):
            identity("invoice_date_or_identity_conflict", path, key)
            continue
        paths = [p for _, p in matched] + [path]
        for field in HEADER_FIELDS:
            numeric("header_fields", [one_number(detail_rows, field)], one_number(header_rows, field), field, paths, key)
        for header_field, detail_field in (("total_kgs", "kgs"), ("total_rolls_pcs", "rolls_pcs")):
            numeric("line_quantity_totals", [row.get(detail_field) for row in detail_rows], one_number(header_rows, header_field), header_field, paths, key)
        numeric("line_value_diagnostic", [row.get("value") for row in detail_rows], one_number(header_rows, "total_value"), "total_value", paths, key)

    for key, observations in vouchers.items():
        result["companies"][key[0]]["distinct_vouchers"] += 1
        if len(observations) < 2:
            continue
        rows = [row for row, _ in observations]
        paths = [path for _, path in observations]
        if len(set(paths)) != len(paths):
            identity("duplicate_voucher_key_within_report", paths[0], key)
            continue
        if len({row.get("v_date") for row in rows}) != 1 or any(not iso_date(row.get("v_date")) for row in rows):
            identity("voucher_original_date_conflict", paths[0], key)
            continue
        for field in VOUCHER_FIELDS:
            for row in rows[1:]:
                numeric("voucher_export_overlap", [row.get(field)], rows[0].get(field), field, paths, key)
    for company, stats in result["companies"].items():
        company_headers = {key[1] for key in headers if key[0] == company}
        company_details = {key[1] for key in detail_keys if key[0] == company}
        stats.update(distinct_header_invoices=len(company_headers), distinct_detail_invoices=len(company_details),
                     header_detail_overlap_invoices=len(company_headers & company_details),
                     header_without_details=sorted(company_headers - company_details, key=int),
                     details_without_header=sorted(company_details - company_headers, key=int))
        for key, values in headers.items():
            if key[0] != company:
                continue
            years = {identifier(row.get("finyear")) for row, _ in values}
            if len(years) == 1 and None not in years:
                year = next(iter(years))
                stats["header_by_source_fiscal_year_id"][year] = stats["header_by_source_fiscal_year_id"].get(year, 0) + 1
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if (destination.suffix != ".json" or destination.is_relative_to(args.source.resolve())
            or destination.is_relative_to(args.report_source.resolve())):
        parser.error("Write the private JSON audit outside both read-only archives.")
    report = audit(args.source, args.report_source)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    print(json.dumps({"import_allowed": False, "verified_selected_files": report["selected_evidence_integrity"]["verified_files"],
                      "identity_issue_count": len(report["identity_issues"]), "checks": report["checks"], "report": str(destination)}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
