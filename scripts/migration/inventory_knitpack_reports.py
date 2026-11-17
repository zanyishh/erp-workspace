#!/usr/bin/env python3
"""Inventory captured report evidence offline; never certifies balances or imports.

The CLI captures both manifests before examining bytes. Only captured entries are
read, and output contains structural statistics, IDs and original date ranges,
never customer row values, template variables or authentication material.
"""
import argparse
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re

from check_knitpack_snapshot import identifier, response_failed, write_private


SENSITIVE = re.compile(r"session|password|token|cookie|variable|currentuserinfo", re.I)
DATE_FIELD = re.compile(r"(^date$|date$|_time$|_at$|^created_t$|^updated_t$)", re.I)
ATTACHMENT_FIELD = re.compile(r"attachment|(^|_)(file|filename|file_url|photo|image|cmp_logo)($|_)", re.I)
MASTER_ROUTES = {"listCompany": "company_master", "getCompany": "company_master", "listGodown": "godown_master",
                 "getGodown": "godown_master", "listLedger": "ledger_master", "listCashLedger": "cash_ledger_master"}
MASTER_DATASETS = {"company_info", "party_info", "party", *MASTER_ROUTES.values()}
OBJECT_DATASETS = {"job", "voucher", "ledger_info", "cordinator_info"}
SUMMARY_DATASETS = {"prgm_chart", "mc_wise", "dia_wise", "fab_var_wise", "root_groups"}
DOMAINS = {
    "scope_and_masters": MASTER_DATASETS,
    "job_programme": {"job", "order_inward", "prgm_chart", "joborderregs"},
    "yarn_receipts": {"yarninward"},
    "production_and_rolls": {"production", "production_with_roll_no", "prodreports"},
    "fabric_delivery": {"fabricdc", "fab_dc"},
    "sales_invoices": {"invoice", "invoicereg", "invoicedetreg", "gen_invoice", "invoice_det_register"},
    "subcontract": {"sc_order_inward", "subcontract", "yarndelivery", "scyarnreturns", "fabricreceipt", "scbillregs"},
    "stock_adjustments_returns_and_transfers": {"yarnreturns", "stockadjreg", "yarnstocksdj", "sc_stock_adj", "fabricstockadj", "trans_in", "trans_out", "job_trans_in", "job_trans_out", "fabric_trans", "dia_trans", "fabric_transfer"},
    "accounting_postings": {"voucher", "statement", "ledg_list", "bill_det_register", "invoice_det_register", "po_det_register"},
    "opening_and_closing_controls": {"jobyarnstocks", "jobfabricstocks"},
    "source_audit_and_cancellations": set(),
    "attachments": set(),
}


def present(value):
    return value is not None and value != "" and value != [] and value != {}


def safe_row(row):
    if isinstance(row, dict):
        return {key: safe_row(value) for key, value in row.items() if not SENSITIVE.search(key)}
    return [safe_row(value) for value in row] if isinstance(row, list) else row


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), default=str).encode()).hexdigest()


def family(route):
    parts = [part for part in route.replace("{URI}", "").split("?", 1)[0].split("/") if part]
    for index, part in enumerate(parts):
        if part.lower() == "getdata":
            # The final getdata segment is authentication, never report identity.
            return "/".join([parts[0], *parts[index + 1:-1]])
    return parts[-2] if parts and (parts[-1].isdigit() or parts[-1] == "{PASS}") else parts[-1] if parts else "unknown"


def records(folder, raw_manifest, issues, label):
    seen = set()
    try:
        lines = raw_manifest.decode("utf-8").splitlines()
    except UnicodeError:
        issues.append({"archive": label, "kind": "invalid_manifest_encoding"})
        return
    for number, line in enumerate(lines, 1):
        try:
            entry = json.loads(line)
            if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
                raise ValueError()
            relative = Path(entry["file"])
            path = folder / relative
            if (relative.is_absolute() or ".." in relative.parts or not relative.parts
                    or not path.resolve().is_relative_to(folder)
                    or any(p.is_symlink() for p in [path, *path.parents] if p.is_relative_to(folder))):
                raise ValueError()
            if str(relative) in seen:
                raise ValueError()
            seen.add(str(relative))
            raw = path.read_bytes()
            if type(entry.get("bytes")) is not int or len(raw) != entry["bytes"] or hashlib.sha256(raw).hexdigest() != entry.get("sha256"):
                issues.append({"archive": label, "line": number, "kind": "file_size_or_hash_mismatch"})
                continue
            payload = json.loads(raw, parse_float=Decimal)
            if not isinstance(payload, dict):
                raise ValueError()
        except (OSError, ValueError, KeyError, TypeError):
            issues.append({"archive": label, "line": number, "kind": "invalid_manifest_entry_or_payload"})
            continue
        yield number, entry, payload


def date_value(value):
    if not isinstance(value, str):
        return None
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return date.fromisoformat(value).isoformat()
        if re.match(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}", value):
            datetime.fromisoformat(value)
            return value
    except ValueError:
        pass
    return None


def inventory(source, reports, *, source_manifest=None, report_manifest=None):
    source, reports = source.resolve(), reports.resolve()
    if source_manifest is None:
        source_manifest = (source / "manifest.jsonl").read_bytes()
    if report_manifest is None:
        report_manifest = (reports / "manifest.jsonl").read_bytes()
    issues, identity_issues = [], Counter()
    companies, indexed, job_companies = {"1", "2", "3", "4"}, defaultdict(set), defaultdict(set)
    original_dates, date_comparisons, date_findings = defaultdict(set), Counter(), []
    source_rows = [record for record in records(source, source_manifest, issues, "source")
                   if not response_failed(record[2])]
    for _, entry, payload in source_rows:
        result, route = payload.get("result"), entry["path"]
        if route.endswith("/listCompany") and isinstance(result, list):
            companies.update(identifier(row.get("id")) for row in result if isinstance(row, dict))
        if "/getInward/" in route and isinstance(result, dict) and date_value(result.get("jobdate")):
            original_dates[(identifier(result.get("companymas_id")), identifier(result.get("id")))].add(result["jobdate"])
        if route.endswith("/getInwardListForProgChart") and isinstance(result, dict):
            params = (entry.get("filters") or {}).get("getParams", {})
            try:
                params = json.loads(params) if isinstance(params, str) else params
                company = identifier(params.get("companymas_id"))
                if not company:
                    raise ValueError()
            except (ValueError, TypeError, AttributeError):
                identity_issues["invalid_index_company"] += 1
                continue
            for row in result.get("items", []):
                job = identifier(row.get("id")) if isinstance(row, dict) else None
                if job:
                    indexed[company].add(job)
                    job_companies[job].add(company)
    companies.discard(None)
    groups, report_files = {}, []
    history_jobs, history_requests, ledger_jobs = defaultdict(set), defaultdict(set), defaultdict(set)
    warehouse = defaultdict(lambda: {"master": set(), "master_records": 0, "transaction": set(), "context": set(), "references": 0})
    attachments, response_counts = Counter(), Counter()
    production = Counter()

    def warehouse_master(payload):
        value = payload.get("result")
        values = value if isinstance(value, list) else [value] if isinstance(value, dict) else []
        for row in values:
            godown, company = identifier(row.get("id")), identifier(row.get("company_id"))
            if godown:
                warehouse[godown]["master_records"] += 1
                if company:
                    warehouse[godown]["master"].add(company)

    for _, entry, payload in source_rows:
        if re.search(r"/(getGodown/|listGodown$)", entry["path"]):
            warehouse_master(payload)

    def add_rows(route, dataset, company, rows, file_number, root_company):
        key = (route, dataset, company or "unresolved")
        if key not in groups:
            groups[key] = {"route_family": route, "dataset": dataset, "company_scope": company or "unresolved",
                           "files": set(), "rows": 0, "non_objects": 0, "fields": defaultdict(Counter),
                           "nonnull": Counter(), "dates": defaultdict(lambda: {"valid": 0, "invalid_or_ambiguous": 0, "missing_or_empty": 0, "values": set()}),
                           "hashes": Counter(), "ids": defaultdict(lambda: defaultdict(set)), "id_counts": defaultdict(Counter),
                           "company_mismatches": 0, "fiscal_values": defaultdict(set), "godowns": set()}
        group = groups[key]
        group["files"].add(file_number)
        for row in rows:
            group["rows"] += 1
            if not isinstance(row, dict):
                group["non_objects"] += 1
                continue
            clean = safe_row(row)
            digest = fingerprint(clean)
            group["hashes"][digest] += 1
            row_company = identifier(row.get("companymas_id") or row.get("company_id"))
            if row_company and company and row_company != company:
                group["company_mismatches"] += 1
                identity_issues["row_company_conflict"] += 1
            godown = identifier(row.get("godown_id"))
            if godown:
                group["godowns"].add(godown)
                warehouse[godown]["references"] += 1
                if row_company:
                    warehouse[godown]["transaction"].add(row_company)
                elif company:
                    warehouse[godown]["context"].add(company)
            for field, value in clean.items():
                group["fields"][field][type(value).__name__] += 1
                if present(value):
                    group["nonnull"][field] += 1
                if field in ("finyear", "fiscal_year", "sec_acc") and present(value):
                    group["fiscal_values"][field].add(str(value))
                if field == "id" or field.endswith("_id") or field.endswith("masid"):
                    ident = identifier(value)
                    if ident:
                        group["ids"][field][ident].add(digest)
                        group["id_counts"][field][ident] += 1
                if DATE_FIELD.search(field):
                    stats = group["dates"][field]
                    original = date_value(value)
                    if original is not None:
                        stats["valid"] += 1
                        stats["values"].add(original)
                    elif present(value):
                        stats["invalid_or_ambiguous"] += 1
                    else:
                        stats["missing_or_empty"] += 1
                if ATTACHMENT_FIELD.search(field) and present(value):
                    attachments[field] += 1
            if dataset in ("production", "production_with_roll_no", "prodreports"):
                production[dataset + "_rows"] += 1
                if dataset == "prodreports" and identifier(row.get("id")):
                    production["detail_rows_with_id"] += 1
                if dataset == "production_with_roll_no" and present(row.get("qc_roll_no")):
                    production["history_rows_with_qc_roll_no"] += 1
                if "roll_entry" in row:
                    value = row["roll_entry"]
                    try:
                        value = json.loads(value) if isinstance(value, str) else value
                        production["roll_entry_parsed_" + type(value).__name__] += 1
                    except ValueError:
                        production["roll_entry_non_json_string"] += 1

    def consume_root(number, entry, root, route):
        filters = entry.get("filters") if isinstance(entry.get("filters"), dict) else {}
        declared = identifier(filters.get("companymas_id") or filters.get("company_id"))
        company_info = root.get("company_info")
        root_company = identifier(company_info.get("id")) if isinstance(company_info, dict) else None
        is_history = route.endswith("JobTransHistory")
        is_job_ledger = route.endswith("ViewJobLedgerreport")
        job = identifier(filters.get("jobmas_id")) if is_history else identifier(filters.get("id")) if is_job_ledger else None
        header = root.get("job") if is_job_ledger else root.get("voucher")
        header_company = identifier(header.get("companymas_id")) if isinstance(header, dict) else None
        owners = job_companies.get(job, set())
        index_company = next(iter(owners)) if len(owners) == 1 else None
        evidence = {c for c in (declared, root_company, index_company, header_company) if c}
        company = declared or index_company or root_company or header_company
        if len(evidence) > 1:
            identity_issues["company_context_conflict"] += 1
        if company and company not in companies:
            identity_issues["unknown_company"] += 1
        if is_history:
            if len(owners) != 1:
                identity_issues["ambiguous_history_company"] += 1
            elif job:
                history_requests[index_company].add(job)
            order = root.get("order_inward")
            valid_order = isinstance(order, list) and bool(order) and all(isinstance(row, dict) and identifier(row.get("id")) == job for row in order)
            bad_links = 0
            for values in root.values():
                if not isinstance(values, list):
                    continue
                for row in values:
                    if not isinstance(row, dict):
                        bad_links += 1
                        continue
                    if "jobmas_id" in row and identifier(row["jobmas_id"]) != job:
                        bad_links += 1
                    row_company = identifier(row.get("companymas_id"))
                    if row_company and index_company and row_company != index_company:
                        bad_links += 1
            if not valid_order:
                identity_issues["history_order_identity_missing_or_different"] += 1
            if bad_links:
                identity_issues["history_link_conflict_rows"] += bad_links
            if valid_order and not bad_links and len(owners) == 1 and len(evidence) == 1:
                history_jobs[index_company].add(job)
        if is_job_ledger:
            if isinstance(header, dict) and identifier(header.get("id")) == job and len(owners) == 1 and len(evidence) == 1 and header_company == index_company:
                ledger_jobs[index_company].add(job)
            else:
                identity_issues["job_ledger_header_identity_unresolved"] += 1
        if is_history or is_job_ledger:
            rows = root.get("order_inward", []) if is_history else [header]
            values = {row.get("jobdate") for row in rows if isinstance(row, dict) and isinstance(row.get("jobdate"), str)}
            baseline = original_dates.get((index_company, job), set())
            outcome = "unknown"
            if len(baseline) == 1 and values and all(date_value(value) for value in values):
                outcome = "matched" if values == baseline else "different"
            date_comparisons[outcome] += 1
            if outcome == "different":
                identity_issues["original_job_date_disagreement"] += 1
                date_findings.append({"manifest_line": number, "source_company_id": index_company, "source_job_id": job,
                                      "archived_original_job_dates": sorted(baseline), "report_original_job_dates": sorted(values)})
        file_record = {"manifest_line": number, "file_sha256": entry["sha256"], "route_family": route,
                       "request_company_id": declared, "root_company_id": root_company,
                       "resolved_company_id": company, "company_context_consistent": len(evidence) <= 1,
                       "requested_job_id": job, "date_filter_fields": {k: v for k, v in filters.items() if k in ("from_date", "to_date", "asondate")},
                       "scope_filter_fields": {k: v for k, v in filters.items() if k in ("sec_acc", "cancelled", "type", "in_type", "inv_type", "invoice_type", "statement_type", "stock_type", "receiptbilledtype", "dctype", "job_type", "order_type", "godown_id")},
                       "reported_range_fields": {k: root[k] for k in ("fdate", "tdate", "from_date", "to_date") if k in root}, "dataset_rows": {}}
        for dataset, rows in root.items():
            if SENSITIVE.search(dataset):
                continue
            if dataset in MASTER_DATASETS | OBJECT_DATASETS and isinstance(rows, dict):
                rows = [rows]
            if isinstance(rows, list):
                file_record["dataset_rows"][dataset] = len(rows)
                add_rows(route, dataset, company, rows, number, root_company)
        report_files.append(file_record)

    for number, entry, payload in records(reports, report_manifest, issues, "reports"):
        response_counts["verified_manifest_files"] += 1
        route = family(entry["path"])
        root = payload.get("root")
        if route.endswith("JobTransHistory"):
            requested_job = identifier((entry.get("filters") or {}).get("jobmas_id"))
            owners = job_companies.get(requested_job, set())
            if len(owners) == 1:
                history_requests[next(iter(owners))].add(requested_job)
        if response_failed(payload):
            response_counts["failed_with_root" if isinstance(root, (dict, list)) else "without_structured_root"] += 1
            continue
        if route in MASTER_ROUTES and isinstance(payload.get("result"), (dict, list)):
            value = payload["result"]
            root = {MASTER_ROUTES[route]: value if isinstance(value, list) else [value]}
            response_counts["structured_master_responses"] += 1
            if route in ("getGodown", "listGodown"):
                warehouse_master(payload)
        elif isinstance(root, (dict, list)):
            response_counts["structured_report_roots"] += 1
        else:
            response_counts["without_structured_root"] += 1
            continue
        if isinstance(root, list):
            if not root:
                consume_root(number, entry, {"root_groups": []}, route)
            for block in root:
                if not isinstance(block, dict):
                    identity_issues["non_object_root_group"] += 1
                    continue
                consume_root(number, entry, {**block, "root_groups": [block]}, route)
        else:
            consume_root(number, entry, root, route)

    datasets = []
    for group in groups.values():
        dates = {}
        for field, stats in group["dates"].items():
            values = sorted(stats["values"])
            dates[field] = {k: v for k, v in stats.items() if k != "values"}
            dates[field].update({"distinct_original_values": len(values), "min_original": min(values) if values else None,
                                 "max_original": max(values) if values else None, "missing_field_rows": group["rows"] - sum(group["fields"][field].values()),
                                 "range_basis": "original_strings_only; timestamp lexical bounds do not normalize timezone"})
        candidates = {}
        for field, identities in group["ids"].items():
            counts = group["id_counts"][field]
            candidates[field] = {"rows_with_valid_numeric_id": sum(counts.values()), "distinct_values": len(identities),
                                 "repeated_values": sum(count > 1 for count in counts.values()),
                                 "values_with_different_rows": sum(len(hashes) > 1 for hashes in identities.values()),
                                 "role": "unverified_row_key_candidate" if field == "id" else "unverified_link_or_header_key_candidate"}
        rows = group["rows"]
        datasets.append({"route_family": group["route_family"], "dataset": group["dataset"], "company_scope": group["company_scope"],
                         "file_observations": len(group["files"]), "row_observations": rows, "non_object_rows": group["non_objects"],
                         "distinct_row_fingerprints": len(group["hashes"]), "repeated_row_observations": sum(c - 1 for c in group["hashes"].values()),
                         "native_document_count": "not_proven", "evidence_state": "rows_observed_completeness_unknown" if rows else "empty_observed_scope_only",
                         "role": "embedded_master" if group["dataset"] in MASTER_DATASETS else "summary_not_transaction" if group["dataset"] in SUMMARY_DATASETS else "original_header_candidate" if group["dataset"] in OBJECT_DATASETS else "detail_candidate_unverified_semantics",
                         "fields": {field: {"types": dict(types), "nonempty": group["nonnull"][field], "missing": rows - sum(types.values())} for field, types in sorted(group["fields"].items())},
                         "dates": dates, "identity_candidates": candidates, "company_conflict_rows": group["company_mismatches"],
                         "observed_fiscal_and_book_values": {k: sorted(v) for k, v in group["fiscal_values"].items()}, "referenced_godown_ids": sorted(group["godowns"], key=int)})
    datasets.sort(key=lambda d: (d["route_family"], d["company_scope"], d["dataset"]))
    domains = {}
    for domain, names in DOMAINS.items():
        found = [d for d in datasets if d["dataset"] in names and d["row_observations"]]
        if domain == "source_audit_and_cancellations":
            found = [d for d in datasets if any(field in d["fields"] for field in ("created_time", "updated_time", "cancelled"))]
        if domain == "attachments":
            found = [d for d in datasets if any(ATTACHMENT_FIELD.search(field) and stats["nonempty"] for field, stats in d["fields"].items())]
        if domain == "opening_and_closing_controls":
            found += [d for d in datasets if any(field in d["fields"] for field in ("opbal", "clbal", "closing_amount", "opening_balance", "closing_balance"))]
        domains[domain] = {"status": "partial_evidence_observed_requirements_still_open" if found else "no_classified_row_evidence_observed",
                           "company_scopes_with_rows": sorted({d["company_scope"] for d in found}),
                           "datasets": sorted({d["dataset"] for d in found}), "complete": False}
    bindings = []
    for godown, values in sorted(warehouse.items(), key=lambda pair: int(pair[0])):
        claims = values["master"] | values["transaction"]
        status = ("conflicting_company_evidence" if values["master"] and len(claims) > 1 else "explicit_master_binding_observed" if len(values["master"]) == 1
                  else "multiple_company_transaction_context_unbound" if len(values["transaction"]) > 1
                  else "transaction_context_only" if values["transaction"] else "report_context_only")
        bindings.append({"source_godown_id": godown, "binding_status": status, "master_company_ids": sorted(values["master"]),
                         "master_records_observed": values["master_records"],
                         "transaction_company_ids": sorted(values["transaction"]), "report_context_company_ids": sorted(values["context"]),
                         "row_reference_observations": values["references"], "usable_master_binding": status == "explicit_master_binding_observed"})
    return {"version": 1, "captured_at_utc": datetime.now(timezone.utc).isoformat(), "import_allowed": False, "completeness": "unknown",
            "source_manifest": {"sha256": hashlib.sha256(source_manifest).hexdigest(), "entries": len(source_manifest.splitlines())},
            "report_manifest": {"sha256": hashlib.sha256(report_manifest).hexdigest(), "entries": len(report_manifest.splitlines())},
            "integrity": {"valid": not issues, "issues": issues}, "identity_issues": dict(identity_issues), "report_responses": dict(response_counts),
            "history_coverage": {company: {"indexed_jobs": len(indexed[company]), "requested_indexed_jobs": len(history_requests[company]),
                "valid_history_jobs": len(history_jobs[company]), "indexed_jobs_without_valid_history": len(indexed[company] - history_jobs[company]),
                "indexed_jobs_without_valid_history_ids": sorted(indexed[company] - history_jobs[company], key=int),
                "proven_empty_company": False, "coverage_basis": "captured historical job index only; not all business records"} for company in sorted(companies, key=int)},
            "job_ledger_coverage": {company: {"valid_original_job_headers": len(ledger_jobs[company]),
                "indexed_jobs_without_ledger_header": len(indexed[company] - ledger_jobs[company]),
                "history_gaps_with_ledger_header_ids": sorted((indexed[company] - history_jobs[company]) & ledger_jobs[company], key=int)} for company in sorted(companies, key=int)},
            "original_job_date_comparisons": {**{k: date_comparisons[k] for k in ("matched", "different", "unknown")}, "differences": date_findings},
            "datasets": datasets, "report_files": report_files, "warehouse_company_evidence": bindings,
            "attachments": {"metadata_field_observations": dict(attachments), "complete_inventory": False, "file_bytes_verified": 0},
            "production_and_rolls": {**{key: production[key] for key in ("production_rows", "production_with_roll_no_rows", "prodreports_rows", "detail_rows_with_id", "history_rows_with_qc_roll_no")},
                "roll_entry_value_shapes": {k.removeprefix("roll_entry_"): v for k, v in production.items() if k.startswith("roll_entry_")},
                "individual_roll_identity_and_weight": "not_established", "consumed_lot_lines": "not_established",
                "overlap": "production and production_with_roll_no are overlapping views; prodreports must not be added to their totals"},
            "missing_domain_updates": domains, "limitations": [
                "Captured manifests are fixed inputs; acquisition can continue. This is not an atomic source snapshot or completeness certificate.",
                "Exact row fingerprints and repeated candidate IDs diagnose report joins/repeated exports; neither proves source transaction identity or chooses a version.",
                "Dates are original ISO observations; invalid/ambiguous values are not repaired. Report date filters do not establish row coverage.",
                "Fiscal/book values, company filters and embedded masters are observations, not certified complete scope or ownership.",
                "Warehouse transaction context is not a verified godown master. Conflicting or unbound IDs remain unresolved.",
                "No invoice/voucher arithmetic or financial/inventory reconciliation is performed. Every missing-domain requirement remains open.",
                "Template metadata, currentUserinfo and session fields are excluded. Attachment references do not verify file bytes."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("reports", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    output = args.report.resolve()
    if output.suffix != ".json" or any(output.is_relative_to(folder.resolve()) for folder in (args.source, args.reports)):
        parser.error("Write the private JSON inventory outside both read-only archives.")
    captured = [(folder / "manifest.jsonl").read_bytes() for folder in (args.source, args.reports)]
    for label, raw in zip(("source", "reports"), captured):
        write_private(output.with_name(output.stem + "." + label + ".manifest.jsonl"), raw.decode("utf-8"))
    report = inventory(args.source, args.reports, source_manifest=captured[0], report_manifest=captured[1])
    write_private(output, json.dumps(report, indent=2) + "\n")
    print(json.dumps({"manifest_files": report["report_manifest"]["entries"], "datasets": len(report["datasets"]),
                      "integrity_issue_count": len(report["integrity"]["issues"]), "identity_issue_count": sum(report["identity_issues"].values()),
                      "import_allowed": False, "completeness": "unknown"}))
    return 0 if report["integrity"]["valid"] and not report["identity_issues"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
