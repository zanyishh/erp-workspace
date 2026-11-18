#!/usr/bin/env python3
"""Offline evidence gate, never an importer. Exit 2 while any balance is unknown.

Only same-field quantities in overlapping full jobs and job-status exports can
currently be corroborated. They do not establish transaction or ledger balances.
"""
import argparse
from collections import defaultdict
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path

from check_knitpack_snapshot import check, identifier, response_failed, write_private


QUANTITY_FIELDS = (
    "programqty", "programpcs", "programrolls", "prod_planned", "prod_plannedpcs",
    "sc_ord_qty", "sc_ord_pcs", "sc_grn", "sc_grnpcs", "prod_qty", "prod_pcs",
    "adjust_qty", "adjust_pcs", "transin_pcs", "transin_kgs", "transout_pcs",
    "transout_kgs", "stock_rolls", "stock_kgs", "dlvry_rolls", "dlvry_kgs",
    "can_rolls", "canc_kgs", "sc_can_rolls", "sc_canc_kgs", "planned_kgs",
)

REQUIRED_EVIDENCE = {
    "general_ledger": "Native accounts, vouchers, posting status and source-supported debit/credit leg semantics, company/book/currency ownership, and opening/movement/closing controls. Equivalent authoritative native records may establish the legs; a separate double-entry export is not mandatory if the source does not provide it. Apply each account category only where the source maintains that balance.",
    "stock": "Opening, signed source movements/counters and independent closing quantities at supported company/owner/location/job/item/UOM granularity, retaining lot/roll identities where maintained. Establish ownership and native balance formulas first; monetary valuation and inventory-to-GL controls apply only where the source maintains those balances, not unvalued customer custody.",
    "work_in_progress": "Opening WIP, source-recorded material consumption/returns, operation/subcontract movements, completions and loss controls with independent closing quantities at supported native granularity. If source consumption exists only as cumulative counters, preserve them and disclose unavailable dated detail rather than inventing events. Costs/valuations apply only when maintained in the source contract.",
    "receivables": "Every sales invoice, tax/discount/rounding line, credit/debit note, receipt, allocation, unallocated credit and reversal; dated opening/closing debtor controls and invoice-level outstanding by party/currency tied to the GL.",
    "payables": "Every purchase/subcontract invoice, tax/discount/rounding line, credit/debit note, payment, allocation, advance and reversal; dated opening/closing creditor controls and invoice-level outstanding by party/currency tied to the GL.",
    "cash_bank": "Every source cash/bank movement, original account/currency, native company/shared ownership, debit/credit, dates and opening/closing controls. Preserve bank reconciliation and uncleared-entry state where maintained; do not invent a bank reconciliation feature absent from the source.",
    "openings": "Source-certified opening trial balance, stock/WIP quantities (and values only where source valuation applies), party invoice balances, advances and cash/bank balances at the earliest included date, with preceding-year closing-to-next-year-opening controls for each fiscal boundary.",
    "transfers": "Both linked legs of every stock, job, warehouse, cash/bank and inter-company transfer, original company/account/job/item/lot/UOM/currency IDs, dates, quantities/values and in-transit/open-leg controls; no cross-company netting.",
    "reversals": "Cancelled/deleted/amended/reversed documents and audit trail, links to originals and replacements, status, effective dates and signed quantity/value effects; do not net away original history.",
    "attachments": "Complete document-to-file inventory with company, source document ID/type, original filename/type, byte size and digest, plus all file bytes and explicit missing-file exceptions; an absent inventory is unknown, not zero attachments.",
}


def number(value):
    if isinstance(value, bool) or not isinstance(value, (str, int, Decimal)):
        return None
    try:
        parsed = Decimal(value)
        return parsed if parsed.is_finite() else None
    except (InvalidOperation, ValueError):
        return None


def reconcile(source):
    source = source.resolve()
    archive = check(source)
    comparison = {"status": "not_checked", "matched_distinct_size_records": 0,
                  "full_without_status": 0, "status_without_full": 0,
                  "ambiguous_size_records": 0, "invalid_identity_rows": 0,
                  "date_or_fiscal_year_disagreements": 0,
                  "numeric_checks": {"passed": 0, "mismatched": 0, "unknown": 0}, "findings": []}
    report = {"version": 1, "checked_at_utc": archive["checked_at_utc"],
              "source_directory": str(source), "manifest_sha256": archive["manifest_sha256"],
              "import_allowed": False, "gate_status": "blocked_missing_balance_evidence",
              "archive_checks": {"integrity_valid": archive["integrity"]["valid"],
                                 "identity_valid": archive["identity"]["valid"],
                                 "failed_api_responses": archive["failed_api_responses"]["count"]},
              "cross_export": comparison, "company_fiscal_year_coverage": [],
              "required_evidence_for_each_company_and_fiscal_year": REQUIRED_EVIDENCE,
              "shared_requirements": [
                  "Complete exports for every company and fiscal year, including explicitly certified empty scopes, with source counts/control totals, source fiscal boundaries and one consistent cutoff or documented change history.",
                  "A failed report screen is not itself missing business data when equivalent authoritative records cover its actual native IDs, fields and controls. Preserve the error and quantify only remaining data gaps.",
                  "Preserve original document, posting, due, creation and amendment dates as separate source fields; resolve discrepancies from original records without replacing or heuristically correcting dates.",
                  "Stable keys are source system + source company ID + document type + source document ID, then original child IDs; retain source references and immutable hashes. Names and printed document numbers are not keys.",
                  "For each account/currency and inventory unit, reconcile opening plus signed movements to independently exported closing; preserve all currencies, units, precision and source rounding rules. Missing values and missing movements never equal zero.",
              ],
              "limitations": [
                  "Matching repeated summary fields corroborates only overlapping exports; it is not stock, WIP, transaction, ledger, valuation or attachment reconciliation.",
                  "Captured API responses are not proven to represent one atomic snapshot. Differences require original source evidence; they do not authorize adjustments.",
                  "The archive checker interprets fiscal labels as April-to-March; this gate neither infers fiscal boundaries nor repairs source dates.",
                  "No financial amount, customer row, credential or session value is copied into this report. Findings identify source IDs, field names and evidence paths only.",
              ]}
    if not archive["integrity"]["valid"]:
        report["gate_status"] = "blocked_archive_integrity"
        return report
    if not archive["identity"]["valid"]:
        report["gate_status"] = "blocked_archive_identity"
        return report

    full, status = defaultdict(list), defaultdict(list)
    companies, years = set(), set()

    def remember(target, key, parent, row, path):
        if not all(key):
            comparison["invalid_identity_rows"] += 1
            return
        values = {field: row.get(field) for field in QUANTITY_FIELDS}
        values.update({field: parent.get(field) for field in ("jobdate", "finyear")})
        # Only comparison fields participate; session tokens are never retained.
        signature = json.dumps(values, sort_keys=True, default=str)
        target[key].append((signature, values, str(path)))

    manifest_bytes = (source / "manifest.jsonl").read_bytes()
    if hashlib.sha256(manifest_bytes).hexdigest() != archive["manifest_sha256"]:
        report["gate_status"] = "blocked_archive_changed"
        report["archive_checks"]["integrity_valid"] = False
        return report
    entries = [json.loads(line) for line in manifest_bytes.decode("utf-8").splitlines()]
    for entry in entries:
        path = source / entry["file"]
        raw = path.read_bytes()
        # The archive may have changed since the checker ran; fail closed.
        if len(raw) != entry["bytes"] or hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            report["gate_status"] = "blocked_archive_changed"
            report["archive_checks"]["integrity_valid"] = False
            return report
        response = json.loads(raw, parse_float=Decimal)
        if "result" not in response or response_failed(response):
            continue
        result, route = response["result"], entry["path"].split("?", 1)[0]
        if route == "masters/masters/listCompany" and isinstance(result, list):
            companies.update(identifier(row.get("id")) for row in result if isinstance(row, dict))
        elif route == "knitpack/masters/getFinYearSB" and isinstance(result, list):
            years.update(identifier(row.get("value")) for row in result if isinstance(row, dict))
        elif route.startswith("knitpack/inward/getInward/") and isinstance(result, dict):
            company, job = identifier(result.get("companymas_id")), identifier(result.get("id"))
            if job != identifier(route.rsplit("/", 1)[-1]) or not isinstance(result.get("job_fabrics"), list):
                comparison["invalid_identity_rows"] += 1
                continue
            for fabric in result["job_fabrics"]:
                if not isinstance(fabric, dict) or identifier(fabric.get("jobmas_id")) != job or not isinstance(fabric.get("dias"), list):
                    comparison["invalid_identity_rows"] += 1
                    continue
                for row in fabric["dias"]:
                    if not isinstance(row, dict) or identifier(row.get("jobfabric_id")) != identifier(fabric.get("id")):
                        comparison["invalid_identity_rows"] += 1
                        continue
                    remember(full, (company, job, identifier(fabric.get("id")), identifier(row.get("id"))), result, row, path)
        elif route == "knitpack/reports/getJobOrderStatus" and isinstance(result, list):
            for row in result:
                if not isinstance(row, dict):
                    comparison["invalid_identity_rows"] += 1
                    continue
                key = tuple(identifier(row.get(field)) for field in ("companymas_id", "jobmasid", "jobdfabricid", "jobdiaid"))
                filters = entry.get("filters")
                if (identifier(row.get("jobmas_id")) != key[1] or identifier(row.get("jobfabric_id")) != key[2]
                        or (isinstance(filters, dict) and "companymas_id" in filters and identifier(filters["companymas_id"]) != key[0])):
                    comparison["invalid_identity_rows"] += 1
                    continue
                remember(status, key, row, row, path)

    companies.discard(None)
    years.discard(None)
    report["company_fiscal_year_coverage"] = [
        {"source_company_id": company, "source_fiscal_year_id": year,
         "balances": {domain: "unknown" for domain in REQUIRED_EVIDENCE}}
        for company in sorted(companies, key=int) for year in sorted(years, key=int)]
    comparison["status"] = "checked_overlap_only"
    comparison["full_without_status"] = len(full.keys() - status.keys())
    comparison["status_without_full"] = len(status.keys() - full.keys())
    for key in sorted(full.keys() | status.keys()):
        records = full.get(key, []) + status.get(key, [])
        finding = {"source_key": ["knitpack", *key], "paths": sorted({r[2] for r in records})}
        if any(len({r[0] for r in group}) > 1 for group in (full.get(key, []), status.get(key, []))):
            comparison["ambiguous_size_records"] += 1
            comparison["findings"].append({**finding, "reason": "conflicting_export_versions"})
            continue
        if key not in full or key not in status:
            continue
        left, right = full[key][0][1], status[key][0][1]
        if any(not isinstance(left[field], str) or not left[field] or left[field] != right[field]
               for field in ("jobdate", "finyear")):
            comparison["date_or_fiscal_year_disagreements"] += 1
            comparison["findings"].append({**finding, "reason": "original_date_or_fiscal_year_unresolved"})
            continue
        comparison["matched_distinct_size_records"] += 1
        mismatches = []
        for field in QUANTITY_FIELDS:
            first, second = number(left[field]), number(right[field])
            outcome = "unknown" if first is None or second is None else "passed" if first == second else "mismatched"
            comparison["numeric_checks"][outcome] += 1
            if outcome == "mismatched":
                mismatches.append(field)
        if mismatches:
            comparison["findings"].append({**finding, "reason": "different_export_quantities", "fields": mismatches})
    return report


def readable(report):
    cross = report["cross_export"]
    lines = ["# Private pre-import balance gate", "", "Import is blocked. Every financial and inventory balance remains unverified.", "",
             f"Gate: {report['gate_status']}.", f"Matched source size records: {cross['matched_distinct_size_records']}.",
             f"Exact quantity comparisons: {cross['numeric_checks']}.", "",
             "These comparisons only corroborate overlapping job summaries. They cannot establish balances.", "",
             "| Source company ID | Source fiscal year ID | Required balance domains |", "| --- | --- | --- |"]
    lines.extend(f"| {cell['source_company_id']} | {cell['source_fiscal_year_id']} | All unknown |"
                 for cell in report["company_fiscal_year_coverage"])
    lines.extend(["", "## Required evidence in every company and fiscal year", ""])
    lines.extend(f"- **{domain.replace('_', ' ')}:** {requirement}" for domain, requirement in REQUIRED_EVIDENCE.items())
    lines.extend(["", *["- " + value for value in report["shared_requirements"]], "", "## Limits", ""])
    lines.extend("- " + value for value in report["limitations"])
    lines.extend(["", "No source changes, network calls, ERPNext operations or imports were performed.", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if not args.source.is_dir() or destination.is_relative_to(args.source.resolve()) or destination.suffix != ".json":
        parser.error("Use an existing archive and a private JSON report path outside the read-only archive.")
    report = reconcile(args.source)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    write_private(destination.with_suffix(".md"), readable(report))
    print(json.dumps({"import_allowed": False, "gate_status": report["gate_status"],
                      "numeric_checks": report["cross_export"]["numeric_checks"], "report": str(destination)}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
