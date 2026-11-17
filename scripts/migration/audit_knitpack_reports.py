#!/usr/bin/env python3
"""Audit selected, already acquired report JSON offline. This never opens import.

The report archive may still be growing: only selected manifested files are
checked. Neither snapshot completeness nor financial balances are established.
"""
import argparse
from collections import defaultdict
from datetime import date
from decimal import Decimal, localcontext
import hashlib
import json
from pathlib import Path

from check_knitpack_snapshot import check, identifier, response_failed, write_private
from reconcile_knitpack_balances import number


FIELDS = {"order_qty": "programqty", "prod_qty": "prod_qty",
          "dlvry_kgs": "dlvry_kgs", "stock_kgs": "stock_kgs"}
DATE_FIELDS = {"order_inward": ("jobdate",), "yarninward": ("grndate", "partydcdate"),
               "fabricdc": ("dc_date",), "production": ("date",), "production_with_roll_no": ("date",)}


def exact_sum(values):
    if any(value is None for value in values):
        return None
    if not values:
        return Decimal(0)
    with localcontext() as context:
        context.prec = max(28, max(v.adjusted() for v in values)
                           - min(v.as_tuple().exponent for v in values) + len(str(len(values))) + 3)
        return sum(values, Decimal(0))


def compare(values, control):
    parsed, control = [number(value) for value in values], number(control)
    total = exact_sum(parsed)
    if total is None or control is None:
        return {"status": "unknown", "missing_or_invalid_row_values": sum(v is None for v in parsed),
                "control_missing_or_invalid": control is None}
    delta = exact_sum([control, total.copy_negate()])
    scales = [max(0, -value.as_tuple().exponent) for value in parsed]
    control_scale = max(0, -control.as_tuple().exponent)
    max_scale = max(scales, default=0)
    tail = delta != 0 and control_scale > max_scale and delta.copy_abs() < Decimal(1).scaleb(-max_scale)
    return {"status": "passed" if delta == 0 else "different", "row_sum": format(total, "f"),
            "source_control": format(control, "f"), "control_minus_row_sum": format(delta, "f"),
            "absolute_difference": format(delta.copy_abs(), "f"), "control_decimal_scale": control_scale,
            "row_decimal_scale_min": min(scales, default=None), "row_decimal_scale_max": max(scales, default=None),
            "interpretation": "possible_floating_point_tail_inference_only" if tail else "exact_comparison"}


def job_sizes(document):
    sizes, keys = [], set()
    for fabric in document["job_fabrics"]:
        if (not isinstance(fabric, dict) or not identifier(fabric.get("id"))
                or identifier(fabric.get("jobmas_id")) != identifier(document.get("id"))
                or not isinstance(fabric.get("dias"), list) or not fabric["dias"]):
            return None
        for row in fabric["dias"]:
            if (not isinstance(row, dict) or not identifier(row.get("id"))
                    or identifier(row.get("jobfabric_id")) != identifier(fabric["id"])):
                return None
            key = (identifier(fabric["id"]), identifier(row["id"]))
            if key in keys:
                return None
            keys.add(key)
            sizes.append(row)
    return sizes or None


def selected_records(folder, select, issues, manifest_bytes=None):
    """Hash the captured manifest and selected bytes; do not claim a sealed archive."""
    try:
        manifest = folder / "manifest.jsonl"
        if manifest.is_symlink():
            raise ValueError()
        raw_manifest = manifest.read_bytes() if manifest_bytes is None else manifest_bytes
        entries = [json.loads(line) for line in raw_manifest.decode("utf-8").splitlines()]
    except (OSError, UnicodeError, ValueError):
        issues.append("invalid_manifest")
        return None, []
    records = []
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            issues.append("invalid_manifest_entry")
            continue
        if not select(entry):
            continue
        try:
            relative = Path(entry["file"])
            path = folder / relative
            if (relative.is_absolute() or ".." in relative.parts or not path.resolve().is_relative_to(folder)
                    or any(p.is_symlink() for p in [path, *path.parents] if p.is_relative_to(folder))):
                raise ValueError()
            raw = path.read_bytes()
            if type(entry.get("bytes")) is not int or len(raw) != entry["bytes"] or hashlib.sha256(raw).hexdigest() != entry.get("sha256"):
                issues.append("selected_file_hash_or_size_mismatch")
                continue
            payload = json.loads(raw, parse_float=Decimal)
            if not isinstance(payload, dict):
                raise ValueError()
        except (KeyError, OSError, TypeError, ValueError):
            issues.append("invalid_selected_file")
            continue
        records.append((entry, payload, str(path)))
    return hashlib.sha256(raw_manifest).hexdigest(), records


def audit(source, report_source, history_job=None, report_manifest=None):
    source, report_source = source.resolve(), report_source.resolve()
    baseline = check(source)
    result = {"version": 1, "import_allowed": False, "financial_and_inventory_balances": "unknown",
              "report_archive_completeness": "unknown", "programme_reports": [], "history_reports": [],
              "baseline_archive_checks": {"integrity_valid": baseline["integrity"]["valid"],
                                          "identity_valid": baseline["identity"]["valid"]},
              "selected_evidence_integrity": {"issues": [], "verified_files": 0},
              "limitations": [
                  "Only selected manifested report files are checked; a growing report archive is not sealed or certified complete.",
                  "Programme root controls are totals from the same report, not independent inventory or accounting balances.",
                  "An exact nonzero delta remains a discrepancy, including a possible floating-point tail. No tolerance, rounding, adjustment or date correction is applied.",
                  "Exports were captured at different times; overlapping job differences need original transaction evidence before a cause can be established.",
                  "An empty programme report proves only an empty selected report scope, not an empty company or zero balances.",
                  "Programme rows have no fiscal-year or transaction-date field; the request date range cannot establish per-year coverage.",
                  "Date observations below preserve original ISO strings. They do not establish that every original transaction or posting date has been acquired.",
              ]}
    if not baseline["integrity"]["valid"] or not baseline["identity"]["valid"]:
        return result
    issues = result["selected_evidence_integrity"]["issues"]
    source_hash, originals = selected_records(source, lambda e: True, issues)
    if source_hash != baseline["manifest_sha256"] or issues:
        issues.append("baseline_changed_or_unreadable")
        return result
    indexes, full = defaultdict(set), defaultdict(list)
    for entry, payload, path in originals:
        if response_failed(payload):
            continue
        data, route = payload.get("result"), entry["path"]
        if route == "knitpack/inward/getInwardListForProgChart" and isinstance(data, dict):
            params = entry["filters"]["getParams"]
            params = json.loads(params) if isinstance(params, str) else params
            company = identifier(params.get("companymas_id"))
            indexes[company].update(identifier(row.get("id")) for row in data["items"])
        elif route.startswith("knitpack/inward/getInward/") and isinstance(data, dict):
            full[(identifier(data.get("companymas_id")), identifier(data.get("id")))].append(data)
    history_job = identifier(history_job) if history_job is not None else None
    manifest_hash, records = selected_records(report_source, lambda e:
        "/programChart/" in e["path"] or (history_job and "/JobTransHistory/" in e["path"]
            and isinstance(e.get("filters"), dict) and identifier(e["filters"].get("jobmas_id")) == history_job), issues, report_manifest)
    result["selected_evidence_integrity"].update({"captured_manifest_sha256": manifest_hash, "verified_files": len(records)})
    for entry, payload, path in records:
        if response_failed(payload):
            continue
        root, filters = payload.get("root"), entry.get("filters")
        if not isinstance(root, dict) or not isinstance(filters, dict):
            issues.append("invalid_report_root_or_context")
            continue
        if "/programChart/" in entry["path"]:
            company, rows = identifier(filters.get("companymas_id")), root.get("prgm_chart")
            if not company or company not in baseline["companies"] or not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
                issues.append("invalid_programme_identity_or_rows")
                continue
            grouped = defaultdict(list)
            for row in rows:
                job = identifier(row.get("job_id"))
                if job:
                    grouped[job].append(row)
                else:
                    issues.append("invalid_programme_job_id")
            counts = {"matched_jobs": 0, "passed": 0, "different": 0, "unknown": 0}
            programme = {"source_company_id": company, "path": path, "rows": len(rows), "distinct_jobs": len(grouped),
                         "requested_scope": {field: filters.get(field) for field in ("from_date", "to_date", "type", "stock_type")},
                         "root_dates_match_request": all(root.get(f) == filters.get(f) for f in ("from_date", "to_date")),
                         "controls": {field: compare([row.get(field) for row in rows], root.get(field)) for field in (*FIELDS, "blns_qty")},
                         "historical_index_without_programme_ids": sorted(indexes[company] - grouped.keys(), key=int),
                         "programme_without_historical_index_ids": sorted(grouped.keys() - indexes[company], key=int),
                         "archived_job_comparisons": counts, "archived_job_discrepancies": []}
            for job, job_rows in grouped.items():
                documents = full.get((company, job), [])
                if not documents:
                    continue
                if len({json.dumps(doc, sort_keys=True, default=str) for doc in documents}) != 1:
                    counts["unknown"] += len(FIELDS)
                    continue
                document = documents[0]
                sizes = job_sizes(document)
                counts["matched_jobs"] += 1
                for programme_field, full_field in FIELDS.items():
                    total = exact_sum([number(row.get(full_field)) for row in sizes]) if sizes else None
                    comparison = compare([row.get(programme_field) for row in job_rows], total)
                    counts[comparison["status"]] += 1
                    if comparison["status"] != "passed":
                        programme["archived_job_discrepancies"].append({"source_key": ["knitpack", company, "job", job],
                            "field": programme_field, "comparison_direction": "archived_full_job_minus_programme", **comparison})
            result["programme_reports"].append(programme)
        else:
            order_rows = root.get("order_inward")
            if not isinstance(order_rows, list) or not order_rows or any(not isinstance(row, dict) or identifier(row.get("id")) != history_job for row in order_rows):
                issues.append("invalid_history_job_identity")
                continue
            matching = [(company, doc) for (company, job), docs in full.items() if job == history_job for doc in docs]
            baseline_dates = {doc.get("jobdate") for company, doc in matching}
            company_ids = {company for company, doc in matching}
            observed, invalid_dates, identity_issues = {}, 0, 0
            for section, fields in DATE_FIELDS.items():
                if not isinstance(root.get(section, []), list):
                    identity_issues += 1
                    continue
                for field in fields:
                    dates = []
                    for row in root.get(section, []):
                        if (not isinstance(row, dict) or (section != "order_inward" and identifier(row.get("jobmas_id")) != history_job)
                                or ("companymas_id" in row and (len(company_ids) != 1 or identifier(row["companymas_id"]) not in company_ids))):
                            identity_issues += 1
                            continue
                        value = row.get(field)
                        try:
                            if not isinstance(value, str) or date.fromisoformat(value).isoformat() != value:
                                raise ValueError()
                        except (ValueError, TypeError):
                            invalid_dates += 1
                            continue
                        dates.append(value)
                    observed[section + "." + field] = sorted(set(dates))
            agreement = "unknown"
            if len(company_ids) == 1 and len(baseline_dates) == 1 and observed.get("order_inward.jobdate") and not identity_issues:
                agreement = "passed" if set(observed["order_inward.jobdate"]) == baseline_dates else "different"
            result["history_reports"].append({"source_job_id": history_job, "path": path, "original_dates": observed,
                "invalid_date_values": invalid_dates, "identity_issues": identity_issues,
                "archived_job_date_agreement": agreement})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("--history-job")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if (destination.suffix != ".json" or destination.is_relative_to(args.source.resolve())
            or destination.is_relative_to(args.report_source.resolve())):
        parser.error("Write the private JSON audit outside both read-only source archives.")
    report = audit(args.source, args.report_source, args.history_job)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    print(json.dumps({"import_allowed": False, "programme_scopes": len(report["programme_reports"]),
                      "selected_file_issues": len(report["selected_evidence_integrity"]["issues"]), "report": str(destination)}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
