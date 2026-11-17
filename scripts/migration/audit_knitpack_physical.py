#!/usr/bin/env python3
"""Offline physical-quantity observations; missing movements never imply zero."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_reports import compare, exact_sum, selected_records, response_failed
from check_knitpack_snapshot import check, identifier, write_private
from reconcile_knitpack_balances import number


ARRAYS = {"getProductionReg": "prodreports", "programChart": "prgm_chart", "getjobyarnstock": "jobyarnstocks",
          "getjobfabricstock": "jobfabricstocks", "getYarnGRNRegPrint": "yarnreceipts", "getYarnReturnRegPrint": "yarnreturns",
          "getFabricDcReport": "fab_dc", "StockAdjRegPrint": "stockadjreg", "getRollStockReg": "roll_stock"}
LEDGER_ROUTE = "ViewJobLedgerreport"
RECEIPT_FIELDS = ("grnnetkgs", "grnbags", "grncones", "grndate", "partydcdate")


def audit(source, report_source, report_manifest=None):
    baseline = check(source.resolve())
    result = {"version": 1, "import_allowed": False, "physical_balances_reconciled": False, "report_archive_completeness": "unknown",
              "selected_evidence_integrity": {"issues": [], "verified_files": 0}, "evidence_manifest": [], "companies": {},
              "identity_issues": [], "unusable_report_files": [], "findings": [], "job_ledger_observations": [], "date_observations": [],
              "checks": {name: {"passed": 0, "different": 0, "unknown": 0} for name in (
                  "production_summary_controls", "production_programme_overlap", "fabric_stock_programme_overlap",
                  "grn_ledger_overlap", "yarn_return_ledger_overlap", "job_ledger_report_rollups", "job_ledger_header_rollups")},
              "required_before_physical_balance_reconciliation": [
                  "Independent dated opening and closing quantities at supported source company/owner/godown/job/item/UOM granularity across fiscal boundaries; retain lot/roll identity where maintained.",
                  "Source-supported material consumption/issue/return movements or cumulative counters with original identities and dates where maintained. Recipes are not actual consumption, and cumulative counters do not create dated lot/roll events.",
                  "Both sides and original identities of transfers, subcontract issues/receipts, losses, scrap, adjustments, cancellations and reversals; documented quantity signs.",
                  "A consistent cutoff and explicit source completeness controls. Job/programme snapshots and an empty report are not proof of complete physical balances.",
                  "First establish the source ownership and valuation contract. Require monetary stock/WIP controls only if the source records owned-inventory values or valuation balances; custodial customer-owned material must not acquire invented monetary balances.",
                  "Equivalent authoritative registers/native children may cover a failed report screen. Identify missing native records or controls rather than requiring the broken screen itself to work.",
              ],
              "limitations": [
                  "Checks corroborate source rollups and overlapping quantities. No complete physical conservation or valuation equation is asserted.",
                  "Production summaries are controls, not events. Only native prodreports IDs count as production events; roll_entry and aggregate rolls/kgs do not establish individual rolls or weights.",
                  "Stock snapshots supply balances without their derivation. No zero stock, opening or consumption is inferred for missing rows.",
                  "GRN matching uses company/job/header/detail/yarn IDs. Fabric DC printed numbers and return-register overwritten IDs are not invented as unique line keys.",
                  "Yarn-return comparisons aggregate by explicit company/job/return-parent/yarn IDs. They do not claim matching individual return lines when a validated line ID is absent.",
                  "Programme/stock comparisons use a unique company/job/fabric/source-size-selector tuple and retain native stock jobdiaid; ambiguous tuples are excluded.",
                  "Job-ledger balance is preserved with its original sign even when its template displays Abs(balance). It is not assumed to be yarn or fabric stock.",
                  "Source exports were acquired at different times. Exact differences remain evidence; no dates, quantities or source records are corrected.",
                  "Non-ISO ledger date strings are retained as an unresolved source representation, not parsed heuristically. Native-ID quantity overlap does not assert date equivalence; differing canonical ISO dates block corroboration.",
              ]}
    if not baseline["integrity"]["valid"] or not baseline["identity"]["valid"]:
        result["selected_evidence_integrity"]["issues"].append("baseline_integrity_or_identity_failed")
        return result
    for company in baseline["companies"]:
        result["companies"][company] = {"physical_balance_status": "unknown", "observed_rows_by_report": {},
            "production_native_rows": 0, "production_native_distinct_ids": 0, "job_ledgers": 0, "grn_detail_overlap": 0,
            "yarn_return_parent_yarn_overlap": 0,
            "grn_register_without_job_ledger_detail": [], "job_ledger_detail_without_grn_register": [],
            "historical_job_ids_without_usable_ledger": [], "fabric_stock_programme_overlap": 0}
    issues = result["selected_evidence_integrity"]["issues"]
    manifest, records = selected_records(report_source.resolve(), lambda e: any("/" + route + "/" in e["path"] for route in (*ARRAYS, LEDGER_ROUTE)), issues, report_manifest)
    result["selected_evidence_integrity"].update(captured_manifest_sha256=manifest, verified_files=len(records))
    indexed = defaultdict(set)
    _, indexes = selected_records(source.resolve(), lambda e: e["path"] == "knitpack/inward/getInwardListForProgChart", issues)
    for entry, payload, _ in indexes:
        if response_failed(payload):
            continue
        params = entry["filters"]["getParams"]
        params = json.loads(params) if isinstance(params, str) else params
        indexed[identifier(params["companymas_id"])].update(identifier(row.get("id")) for row in payload["result"]["items"])
    production, programmes, stocks, grn, receipts, ledgers = (defaultdict(list) for _ in range(6))
    production_by_job = defaultdict(list)
    return_register, return_ledger = defaultdict(list), defaultdict(list)
    incomplete_programme_jobs = set()

    def identity(kind, path, key=None):
        result["identity_issues"].append({"kind": kind, "path": path, "source_key": list(key) if key else None})

    def numeric(name, values, control, field, paths, key=None):
        value = compare(values, control)
        result["checks"][name][value["status"]] += 1
        if value["status"] != "passed":
            result["findings"].append({"check": name, "field": field, "paths": sorted(set(paths)),
                                       "source_key": list(key) if key else None, **value})

    def unique(observations, fields, key):
        signatures = {json.dumps({field: row.get(field) for field in fields}, sort_keys=True, default=str) for row, _ in observations}
        if len(signatures) != 1:
            identity("conflicting_source_observations", observations[0][1], key)
            return None
        return observations[0][0]

    for entry, payload, path in records:
        result["evidence_manifest"].append({"file": entry["file"], "bytes": entry["bytes"], "sha256": entry["sha256"]})
        if response_failed(payload):
            result["unusable_report_files"].append(path)
            continue
        route = next(route for route in (*ARRAYS, LEDGER_ROUTE) if "/" + route + "/" in entry["path"])
        root, filters = payload.get("root"), entry.get("filters")
        if not isinstance(root, dict) or not isinstance(filters, dict):
            result["unusable_report_files"].append(path)
            continue
        if route == LEDGER_ROUTE:
            job = root.get("job")
            if (not isinstance(job, dict) or not identifier(job.get("id")) or identifier(job.get("id")) != identifier(filters.get("id"))
                    or identifier(job.get("companymas_id")) not in result["companies"] or not iso_date(job.get("jobdate"))):
                identity("invalid_job_ledger_identity_or_original_date", path)
                continue
            ledgers[(identifier(job["companymas_id"]), identifier(job["id"]))].append((root, path))
            continue
        company, rows = identifier(filters.get("companymas_id")), root.get(ARRAYS[route])
        if company not in result["companies"] or not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            identity("invalid_report_company_or_rows", path)
            continue
        if any("companymas_id" in row and identifier(row["companymas_id"]) != company for row in rows):
            identity("row_company_mismatch", path)
            continue
        stats = result["companies"][company]
        stats["observed_rows_by_report"][route] = stats["observed_rows_by_report"].get(route, 0) + len(rows)
        if route == "getProductionReg":
            # Explicitly filtered exports are not combined with the full initial-form scope.
            if filters.get("job_type") not in (None, "") or filters.get("order_type") not in (None, ""):
                continue
            if any(not identifier(row.get("id")) or not iso_date(row.get("date")) for row in rows):
                identity("invalid_production_native_id_or_original_date", path)
                continue
            stats["production_native_rows"] += len(rows)
            for row in rows:
                production[(company, identifier(row["id"]))].append((row, path))
            for summary in ("mc_wise", "dia_wise", "fab_var_wise"):
                controls = root.get(summary)
                for field, control_field in (("prodkgs", "sum_prodkgs"), ("prodrolls", "sum_prodrolls")):
                    total = exact_sum([number(row.get(control_field)) if isinstance(row, dict) else None for row in controls]) if isinstance(controls, list) else None
                    numeric("production_summary_controls", [row.get(field) for row in rows], total, summary + "." + field, [path], (company,))
        elif route == "programChart":
            for row in rows:
                key = (company, *(identifier(row.get(f)) for f in ("job_id", "fabric_id", "diaorsize")))
                if all(key):
                    programmes[key].append((row, path))
                else:
                    identity("invalid_programme_source_dimension_ids", path, key)
                    if key[1]:
                        incomplete_programme_jobs.add(key[:2])
        elif route == "getjobfabricstock":
            for row in rows:
                key = (company, *(identifier(row.get(f)) for f in ("jobmas_id", "jobfabric_id", "diaorsize")))
                if (all(key) and identifier(row.get("fab_id")) == key[2] and identifier(row.get("jobdiaid"))
                        and iso_date(row.get("jobdate"))):
                    stocks[key].append((row, path))
                else:
                    identity("invalid_stock_source_dimension_ids_or_date", path)
        elif route == "getYarnGRNRegPrint":
            if any(identifier(row.get("godown_id")) != identifier(filters.get("godown_id")) for row in rows):
                identity("receipt_godown_mismatch", path)
                continue
            for row in rows:
                key = (company, *(identifier(row.get(f)) for f in ("jobmas_id", "jobyarngrn_id", "deatid", "yarnmas_id")))
                if all(key):
                    grn[key].append((row, path))
                else:
                    identity("invalid_grn_native_parent_or_detail_ids", path)
        elif route == "getYarnReturnRegPrint":
            for row in rows:
                key = (company, *(identifier(row.get(f)) for f in ("jobmas_id", "yarn_dc_id", "yarnmas_id")))
                if all(key) and identifier(row.get("dc_id")) == key[2]:
                    return_register[key].append((row, path))
                else:
                    identity("invalid_yarn_return_parent_alias", path, key)

    usable_ledger_jobs = set()
    for key, observations in ledgers.items():
        if len({json.dumps(root, sort_keys=True, default=str) for root, _ in observations}) != 1:
            identity("conflicting_job_ledger_versions", observations[0][1], key)
            continue
        root, path = observations[0]
        usable_ledger_jobs.add(key)
        job, company = root["job"], key[0]
        result["companies"][company]["job_ledgers"] += 1
        result["job_ledger_observations"].append({"source_key": list(key), "path": path, "original_job_date": job["jobdate"],
            "original_signed_balance": str(root["balance"]) if number(root.get("balance")) is not None else None,
            "physical_balance_meaning": "unknown_not_assumed_stock"})
        for array, field, root_control in (("reciepts", "grnnetkgs", "yarn_grn_total"), ("deliveries", "dlvry_kgs", "fabdc_total"), ("returns", "net_kgs", "yarn_return_total")):
            rows = root.get(array)
            values = [row.get(field) if isinstance(row, dict) else None for row in rows] if isinstance(rows, list) else [None]
            numeric("job_ledger_report_rollups", values, root.get(root_control), root_control, [path], key)
        for array, field, header in (("reciepts", "grnnetkgs", "total_grn_net_kgs"), ("reciepts", "grnbags", "total_grn_bags"),
                ("reciepts", "grncones", "total_grn_cones"), ("deliveries", "dlvry_kgs", "total_dlvry_kgs"),
                ("deliveries", "dlvry_rolls", "total_dlvry_rolls"), ("returns", "net_kgs", "total_ret_net_kgs"),
                ("returns", "bags", "total_ret_bags"), ("returns", "cons", "total_ret_cones")):
            rows = root.get(array)
            values = [row.get(field) if isinstance(row, dict) else None for row in rows] if isinstance(rows, list) else [None]
            numeric("job_ledger_header_rollups", values, job.get(header), header, [path], key)
        for row in root.get("reciepts", []):
            if not isinstance(row, dict):
                identity("invalid_job_ledger_receipt", path, key)
                continue
            receipt_key = (*key, *(identifier(row.get(f)) for f in ("id", "det_id", "yarnmas_id")))
            if all(receipt_key):
                receipts[receipt_key].append((row, path))
            else:
                identity("invalid_job_ledger_receipt_ids", path, key)
        for row in root.get("returns", []):
            if isinstance(row, dict):
                return_key = (*key, identifier(row.get("id")), identifier(row.get("yarnmas_id")))
                if all(return_key):
                    return_ledger[return_key].append((row, path))
    for key, observations in production.items():
        row = unique(observations, ("jobmas_id", "fabric_id", "dia_id", "date", "real_date", "prodkgs", "prodrolls"), key)
        if row is not None and identifier(row.get("jobmas_id")):
            production_by_job[(key[0], identifier(row["jobmas_id"]))].append((row, observations[0][1]))
            result["companies"][key[0]]["production_native_distinct_ids"] += 1
    programme_by_job = defaultdict(list)
    for key, observations in programmes.items():
        row = unique(observations, ("stock_kgs", "prod_qty"), key)
        if row is not None:
            programme_by_job[key[:2]].append((row, observations[0][1]))
    for key in production_by_job.keys() & programme_by_job.keys():
        rows, controls = production_by_job[key], programme_by_job[key]
        numeric("production_programme_overlap", [row.get("prodkgs") for row, _ in rows],
                None if key in incomplete_programme_jobs else exact_sum([number(row.get("prod_qty")) for row, _ in controls]),
                "prodkgs_vs_prod_qty", [p for _, p in rows + controls], key)
    for key in stocks.keys() & programmes.keys():
        stock = unique(stocks[key], ("jobdiaid", "stock_kgs", "stock_rolls", "jobdate"), key)
        programme = unique(programmes[key], ("stock_kgs", "prod_qty"), key)
        if stock is not None and programme is not None:
            result["companies"][key[0]]["fabric_stock_programme_overlap"] += 1
            numeric("fabric_stock_programme_overlap", [stock.get("stock_kgs")], programme.get("stock_kgs"), "stock_kgs", [p for _, p in stocks[key] + programmes[key]], key)
    for key in grn.keys() & receipts.keys():
        row, ledger = unique(grn[key], RECEIPT_FIELDS, key), unique(receipts[key], RECEIPT_FIELDS, key)
        if row is None or ledger is None:
            continue
        dates = ("grndate", "partydcdate")
        if not iso_date(row.get("grndate")) or any(iso_date(row.get(field)) and iso_date(ledger.get(field))
                                                  and row[field] != ledger[field] for field in dates):
            identity("original_receipt_date_conflict", grn[key][0][1], key)
            continue
        if any(row.get(field) != ledger.get(field) for field in dates):
            result["date_observations"].append({"source_key": list(key), "status": "unknown_source_date_encoding",
                "register_grndate": row.get("grndate"), "ledger_grndate": ledger.get("grndate"),
                "register_partydcdate": row.get("partydcdate"), "ledger_partydcdate": ledger.get("partydcdate"),
                "paths": [p for _, p in grn[key] + receipts[key]]})
        result["companies"][key[0]]["grn_detail_overlap"] += 1
        for field in RECEIPT_FIELDS[:3]:
            numeric("grn_ledger_overlap", [row.get(field)], ledger.get(field), field, [p for _, p in grn[key] + receipts[key]], key)
    for key in return_register.keys() & return_ledger.keys():
        registered, observed = return_register[key], return_ledger[key]
        if len({path for _, path in registered}) != 1 or len({path for _, path in observed}) != 1:
            identity("return_scope_overlap_without_validated_line_ids", registered[0][1], key)
            continue
        register_dates = {row.get("dc_date") for row, _ in registered}
        ledger_dates = {row.get("dc_date") for row, _ in observed}
        if len(register_dates) != 1 or len(ledger_dates) != 1:
            identity("conflicting_return_document_dates", registered[0][1], key)
            continue
        original_date, ledger_date = next(iter(register_dates)), next(iter(ledger_dates))
        if not iso_date(original_date) or iso_date(ledger_date) and original_date != ledger_date:
            identity("original_return_date_conflict", registered[0][1], key)
            continue
        if original_date != ledger_date:
            result["date_observations"].append({"source_key": list(key), "status": "unknown_source_date_encoding",
                "register_dc_date": original_date, "ledger_dc_date": ledger_date,
                "paths": sorted({path for _, path in registered + observed})})
        result["companies"][key[0]]["yarn_return_parent_yarn_overlap"] += 1
        for field in ("net_kgs", "bags", "cons"):
            numeric("yarn_return_ledger_overlap", [row.get(field) for row, _ in registered],
                exact_sum([number(row.get(field)) for row, _ in observed]), field, [path for _, path in registered + observed], key)
    for company, stats in result["companies"].items():
        stats["grn_register_without_job_ledger_detail"] = [list(key) for key in sorted(grn.keys() - receipts.keys()) if key[0] == company]
        stats["job_ledger_detail_without_grn_register"] = [list(key) for key in sorted(receipts.keys() - grn.keys()) if key[0] == company]
        observed_jobs = {key[1] for key in usable_ledger_jobs if key[0] == company}
        stats["historical_job_ids_without_usable_ledger"] = sorted(indexed[company] - observed_jobs, key=int)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if destination.suffix != ".json" or any(destination.is_relative_to(folder.resolve()) for folder in (args.source, args.report_source)):
        parser.error("Write the private JSON audit outside both read-only archives.")
    report = audit(args.source, args.report_source)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    print(json.dumps({"import_allowed": False, "physical_balances_reconciled": False, "checks": report["checks"],
                      "identity_issue_count": len(report["identity_issues"]), "report": str(destination)}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
