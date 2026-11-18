#!/usr/bin/env python3
"""Corroborate supplied native stock counters offline; never invent their formula."""
import argparse
from collections import defaultdict
from datetime import datetime
import json
from pathlib import Path

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_physical import audit as physical_audit, ARRAYS, LEDGER_ROUTE
from audit_knitpack_reports import compare, exact_sum, selected_records, response_failed
from check_knitpack_snapshot import check, identifier, write_private
from reconcile_knitpack_balances import number

FABRIC_ROUTE = "knitpack/Subcontract/getJobInfos/"
YARN_ROUTE = "knitpack/inward/getjoborderwithyarnmas/"


def provenance(record):
    entry, _, path = record
    return {"file": entry["file"], "path": path, "sha256": entry["sha256"], "bytes": entry["bytes"],
            "retrieved_at_utc": entry.get("retrieved_at_utc")}


def capture_order(original_times, native_time):
    result = {"comparison": "unknown", "cause_established": False}
    try:
        original = [datetime.fromisoformat(value) for value in original_times]
        native = datetime.fromisoformat(native_time)
        if not original or any(value.tzinfo is None for value in [*original, native]):
            return result
    except (TypeError, ValueError):
        return result
    result["comparison"] = ("after_all_originals" if native > max(original) else
                            "before_all_originals" if native < min(original) else "within_original_capture_interval")
    result["seconds_after_latest_original"] = str((native - max(original)).total_seconds())
    return result


def validate_delivery(data, source_id, company, expected_job, contexts):
    """Bind an actual DC header/detail to native job dimensions, never its display number."""
    result = {"status": "unknown", "source_key": [company, source_id], "expected_job_id": expected_job, "children": []}
    if (not isinstance(data, dict) or identifier(data.get("id")) != source_id or identifier(data.get("companymas_id")) != company
            or not iso_date(data.get("dc_date")) or not isinstance(data.get("fabric_dia_details"), list)):
        return result
    result["original_date"] = data["dc_date"]
    result["original_updated_time"] = data.get("updated_time")
    seen, valid, persisted = set(), True, []
    result["empty_unpersisted_context_rows"] = 0
    for row in data["fabric_dia_details"]:
        row = row if isinstance(row, dict) else {}
        child_id, dimkey = identifier(row.get("id")), (identifier(row.get("fabric_id")), identifier(row.get("jobdia_id")))
        owners = {key for key, versions in contexts.items() if any(dimkey in version["dims"] for version in versions)}
        if (row.get("id") in (None, "", 0, "0") and row.get("dc_id") in (None, "", 0, "0")
                and all(number(row.get(field)) == 0 for field in ("dlvry_kgs", "dlvry_rolls")) and owners == {(company, expected_job)}):
            result["empty_unpersisted_context_rows"] += 1
            continue
        good = bool(child_id and child_id not in seen and identifier(row.get("dc_id")) == source_id and owners == {(company, expected_job)})
        valid = valid and good
        seen.add(child_id)
        persisted.append(row)
        result["children"].append({"source_detail_id": child_id, "source_fabric_id": dimkey[0], "source_dia_id": dimkey[1], "identity_valid": good})
    result["status"] = "passed" if valid and result["children"] else "unknown"
    result["quantity_controls"] = {field: compare([row.get(field) for row in persisted], data.get(control))
        for field, control in (("dlvry_kgs", "total_dlvry_kgs"), ("dlvry_rolls", "total_dlvry_rolls"))}
    return result


def selector(value):
    # diaorsize is not the native primary key. Explicit zero/blank selectors are
    # retained; a unique matching native child must independently prove identity.
    return str(value) if isinstance(value, (str, int)) and not isinstance(value, bool) else None


def context_index(records, companies, issues):
    contexts = defaultdict(list)
    for record in records:
        entry, payload, path = record
        if not entry["path"].startswith(FABRIC_ROUTE):
            continue
        if response_failed(payload):
            issues.append({"kind": "failed_native_context_response", "path": path})
            continue
        data = payload.get("result")
        job = data.get("job") if isinstance(data, dict) else None
        expected = identifier(entry["path"].removeprefix(FABRIC_ROUTE))
        key = (identifier(job.get("companymas_id")), identifier(job.get("id"))) if isinstance(job, dict) else (None, None)
        dims, valid = {}, isinstance(job, dict) and key[0] in companies and key[1] == expected and expected is not None and iso_date(job.get("jobdate")) is not None
        fabrics = data.get("fabs") if isinstance(data, dict) else None
        valid = valid and isinstance(fabrics, list)
        seen_fabrics = set()
        for fabric in fabrics if isinstance(fabrics, list) else []:
            fid = identifier(fabric.get("id")) if isinstance(fabric, dict) else None
            if (not fid or fid in seen_fabrics or identifier(fabric.get("jobmas_id")) != key[1]
                    or not isinstance(fabric.get("dias"), list)):
                valid = False
                continue
            seen_fabrics.add(fid)
            for dia in fabric["dias"]:
                did = identifier(dia.get("id")) if isinstance(dia, dict) else None
                if not did or identifier(dia.get("jobfabric_id")) != fid or (fid, did) in dims:
                    valid = False
                    continue
                dims[(fid, did)] = dia
        if not valid:
            issues.append({"kind": "invalid_native_fabric_context_identity_or_date", "path": path})
            continue
        contexts[key].append({"job": job, "dims": dims, "record": record, "yarn_versions": []})
    for record in records:
        entry, payload, path = record
        if not entry["path"].startswith(YARN_ROUTE):
            continue
        if response_failed(payload):
            issues.append({"kind": "failed_native_context_response", "path": path})
            continue
        data = payload.get("result")
        expected = identifier(entry["path"].removeprefix(YARN_ROUTE))
        if not isinstance(data, dict) or not expected or identifier(data.get("id")) != expected or not isinstance(data.get("yarn_mas"), list):
            issues.append({"kind": "invalid_native_yarn_context", "path": path})
            continue
        candidates = [version for key, versions in contexts.items() if key[1] == expected for version in versions]
        owners = {identifier(v["job"]["companymas_id"]) for v in candidates}
        rows, ids = data["yarn_mas"], set()
        valid = len(owners) == 1
        for row in rows:
            rid = identifier(row.get("id")) if isinstance(row, dict) else None
            if not rid or rid in ids or identifier(row.get("jobmas_id")) != expected or not identifier(row.get("yarnmas_id")):
                valid = False
            ids.add(rid)
        matched = False
        for version in candidates if valid else []:
            if all(data.get(f) is not None and str(data[f]) == str(version["job"].get(f)) for f in ("id", "jobdate", "partymas_id", "sec_acc", "jobtype")):
                version["yarn_versions"].append({"rows": rows, "record": record})
                matched = True
        if not matched:
            issues.append({"kind": "yarn_job_context_conflict_or_unknown", "path": path})
    return contexts


def stock_overlap(contexts, records, issues):
    result = {"checks": {f: {s: 0 for s in ("passed", "different", "unknown")} for f in
              ("fabric_stock_kgs", "fabric_stock_rolls", "yarn_stock_kgs")}, "findings": [], "coverage": {}, "company_checks": {}}
    def compare_field(name, values, control, key, evidence):
        check = compare(values, control)
        result["checks"][name][check["status"]] += 1
        company_checks = result["company_checks"].setdefault(key[0], {})
        company_checks.setdefault(name, {s: 0 for s in ("passed", "different", "unknown")})[check["status"]] += 1
        if check["status"] != "passed":
            result["findings"].append({"check": name, "source_key": list(key), "evidence": evidence, **check})
    for record in records:
        entry, payload, path = record
        kind = next((k for k in ("getjobfabricstock", "getjobyarnstock") if "/" + k + "/" in entry["path"]), None)
        if not kind:
            continue
        if response_failed(payload):
            issues.append({"kind": "failed_stock_report_response", "path": path})
            continue
        filters, root = entry.get("filters"), payload.get("root")
        company = identifier(filters.get("companymas_id")) if isinstance(filters, dict) else None
        rows = root.get(ARRAYS[kind]) if isinstance(root, dict) else None
        if not isinstance(rows, list):
            issues.append({"kind": "invalid_stock_report_rows", "path": path})
            continue
        count = {"observed_rows": len(rows), "rows_with_native_context": 0, "rows_without_native_context": 0,
                 "source_company_id": company, "requested_type": filters.get("type"), "evidence": provenance(record)}
        result["coverage"][path] = count
        for row in rows:
            key = (company, identifier(row.get("jobmas_id"))) if isinstance(row, dict) else (None, None)
            if not all(key) or identifier(row.get("companymas_id")) != company or not iso_date(row.get("jobdate")):
                issues.append({"kind": "invalid_stock_row_identity_or_date", "path": path})
                continue
            versions = [v for v in contexts.get(key, []) if v["job"]["jobdate"] == row["jobdate"]]
            linked = False
            for version in versions:
                evidence = [provenance(record), provenance(version["record"])]
                if kind == "getjobfabricstock":
                    dimkey = (identifier(row.get("jobfabric_id")), identifier(row.get("jobdiaid")))
                    native = version["dims"].get(dimkey)
                    if native is None or identifier(row.get("fab_id")) != dimkey[0] or selector(row.get("diaorsize")) != selector(native.get("diaorsize")):
                        continue
                    linked = True
                    for field in ("stock_kgs", "stock_rolls"):
                        compare_field("fabric_" + field, [row.get(field)], native.get(field), (*key, *dimkey), evidence)
                else:
                    yarn = identifier(row.get("yarnmas_id"))
                    if not yarn:
                        continue
                    for yversion in version["yarn_versions"]:
                        native_rows = [r for r in yversion["rows"] if identifier(r.get("yarnmas_id")) == yarn]
                        if not native_rows:
                            continue
                        linked = True
                        compare_field("yarn_stock_kgs", [row.get("stock_kgs")], exact_sum([number(r.get("stock_kgs")) for r in native_rows]),
                                      (*key, yarn), [*evidence, provenance(yversion["record"])])
            count["rows_with_native_context" if linked else "rows_without_native_context"] += 1
    return result


def trace_finding(finding, contexts, records):
    key = tuple(finding["source_key"][:2])
    originals = [r for r in records if r[2] in finding["paths"] and not response_failed(r[1])]
    result = {"original_finding": finding, "cause_established": False,
              "original_evidence": [provenance(r) for r in originals], "versions": []}
    for version in contexts.get(key, []):
        out = {"native_evidence": provenance(version["record"]), "original_job_date": version["job"]["jobdate"],
               "native_job_updated_time": version["job"].get("updated_time"), "same_job_updated_time": [],
               "capture_order": capture_order([r[0].get("retrieved_at_utc") for r in originals], version["record"][0].get("retrieved_at_utc"))}
        result["versions"].append(out)
        for record in originals:
            job = record[1].get("root", {}).get("job")
            if isinstance(job, dict) and identifier(job.get("id")) == key[1] and identifier(job.get("companymas_id")) == key[0]:
                old, new = job.get("updated_time"), version["job"].get("updated_time")
                out["same_job_updated_time"].append({"original": old, "native": new,
                    "comparison": "unknown" if old is None or new is None else "equal" if old == new else "different",
                    "original_job_date": job.get("jobdate"), "original_date_agrees": job.get("jobdate") == version["job"]["jobdate"]})
        if finding["check"] == "job_ledger_header_rollups":
            native = version["job"].get(finding["field"])
            out["native_vs_original_rows"] = compare([finding.get("row_sum")], native)
            out["native_vs_original_header"] = compare([finding.get("source_control")], native)
        elif finding["check"] == "fabric_stock_programme_overlap":
            matches = [r for (fid, _), r in version["dims"].items() if fid == finding["source_key"][2]
                       and selector(r.get("diaorsize")) == finding["source_key"][3]]
            native = matches[0].get("stock_kgs") if len(matches) == 1 else None
            out["native_dimension_identity"] = "unique" if len(matches) == 1 else "unknown"
            out["native_vs_original_stock"] = compare([finding.get("row_sum")], native)
            out["native_vs_original_programme"] = compare([finding.get("source_control")], native)
        elif finding["check"] == "production_programme_overlap":
            programme, production, native_keys = [], {}, []
            map_valid = True
            for entry, payload, _ in originals:
                root, filters = payload.get("root", {}), entry.get("filters", {})
                if identifier(filters.get("companymas_id")) != key[0]:
                    continue
                for row in root.get("prgm_chart", []):
                    if identifier(row.get("job_id")) != key[1]:
                        continue
                    programme.append(row)
                    matches = [dimkey for dimkey, dim in version["dims"].items() if dimkey[0] == identifier(row.get("fabric_id"))
                               and selector(dim.get("diaorsize")) == selector(row.get("diaorsize")) and selector(row.get("diaorsize")) is not None]
                    map_valid = map_valid and len(matches) == 1
                    native_keys.extend(matches)
                if filters.get("job_type") not in (None, "") or filters.get("order_type") not in (None, ""):
                    continue
                for row in root.get("prodreports", []):
                    if identifier(row.get("jobmas_id")) == key[1] and identifier(row.get("companymas_id")) == key[0]:
                        rid = identifier(row.get("id"))
                        if not rid or (rid in production and production[rid] != row):
                            map_valid = False
                        production[rid] = row
            mapped = map_valid and bool(programme) and len(native_keys) == len(set(native_keys)) and set(native_keys) == version["dims"].keys()
            out["programme_native_dimension_mapping"] = "unique_complete" if mapped else "unknown"
            programme_total = exact_sum([number(r.get("prod_qty")) for r in programme]) if mapped else None
            out["production_vs_complete_programme"] = compare([r.get("prodkgs") for r in production.values()] if production else [None], programme_total)
            native_total = exact_sum([number(r.get("prod_qty")) for r in version["dims"].values()]) if version["dims"] else None
            out["native_vs_programme"] = compare([programme_total], native_total)
            out["native_vs_production"] = compare([r.get("prodkgs") for r in production.values()] if production else [None], native_total)
    return result


def refresh_plan(records, findings, missing_jobs):
    affected = {tuple(f["source_key"][:2]) for f in findings} | set(missing_jobs)
    header_paths = {path for f in findings if f["check"] == "job_ledger_header_rollups" for path in f["paths"]}
    requests = {}
    for record in records:
        entry, _, path = record
        route, filters = entry["path"], entry.get("filters")
        reason = None
        if route.startswith((FABRIC_ROUTE, YARN_ROUTE)) and any(k[1] == route.rsplit("/", 1)[-1] for k in affected):
            reason = "affected_job_native_counters"
        elif path in header_paths:
            reason = "affected_job_header_detail_controls"
        elif any("/" + name + "/" in route for name in ("programChart", "getjobfabricstock", "getjobyarnstock")):
            reason = "all_company_final_stock_programme_controls"
        elif "/getProductionReg/" in route and isinstance(filters, dict) and all(filters.get(f) in (None, "") for f in ("job_type", "order_type")):
            reason = "all_company_final_production_controls"
        if reason:
            signature = json.dumps([entry.get("method"), route, filters], sort_keys=True)
            requests[signature] = {"method": entry.get("method"), "path": route, "filters": filters, "purpose": reason,
                                   "observed_request_evidence": provenance(record)}
    return {"executed": False, "requests": list(requests.values()),
            "conditions": ["Execute after bulk copying with the source quiet or a documented source cutoff; retrieval order alone cannot establish why quantities differ.",
                           "Keep each refreshed response as a new immutable manifested original; do not overwrite prior evidence.",
                           "Compare final controls to existing native-ID movements. If changed, refresh only affected job or register scopes before claiming reconciliation.",
                           "Recovering a missing job header through its native context does not prove its missing transaction list is complete."]}


def audit(source, report_source, report_manifest=None):
    if report_manifest is None:
        report_manifest = (report_source / "manifest.jsonl").read_bytes()
    baseline = check(source.resolve())
    previous = physical_audit(source, report_source, report_manifest)
    issues = []
    manifest, records = selected_records(report_source.resolve(), lambda e: e["path"].startswith((FABRIC_ROUTE, YARN_ROUTE))
        or any("/" + route + "/" in e["path"] for route in (*ARRAYS, LEDGER_ROUTE)), issues, report_manifest)
    current_hashes = {entry["file"]: entry["sha256"] for entry, _, _ in records}
    previous_unchanged = all(current_hashes.get(entry["file"]) == entry["sha256"] for entry in previous["evidence_manifest"])
    if not previous_unchanged:
        issues.append("physical_audit_evidence_changed_between_captures")
    identity_issues = []
    contexts = context_index(records, baseline["companies"], identity_issues)
    missing = [(company, job) for company, stats in previous["companies"].items() for job in stats["historical_job_ids_without_usable_ledger"]]
    result = {"version": 1, "import_allowed": False, "physical_balances_reconciled": False,
              "selected_evidence_integrity": {"captured_manifest_sha256": manifest, "verified_files": len(records), "issues": issues},
              "physical_audit_capture": previous["selected_evidence_integrity"],
              "evidence_manifest": [provenance(r) for r in records], "identity_issues": identity_issues,
              "validated_native_contexts": [{"source_key": list(key), "fabric_evidence": provenance(version["record"]),
                  "yarn_evidence": [provenance(y["record"]) for y in version["yarn_versions"]]}
                  for key, versions in contexts.items() for version in versions],
              "companies": {company: {"native_job_contexts": sum(k[0] == company for k in contexts),
                  "native_yarn_contexts": sum(k[0] == company and any(v["yarn_versions"] for v in versions) for k, versions in contexts.items())}
                  for company in baseline["companies"]},
              "stock_snapshot_overlap": stock_overlap(contexts, records, identity_issues),
              "prior_findings_traced": [trace_finding(f, contexts, records) for f in previous["findings"]] if previous_unchanged else [],
              "missing_ledger_native_header_recovery": [{"source_key": list(key), "native_header_recovered": key in contexts,
                  "transaction_list_complete": "unknown", "evidence": [provenance(v["record"]) for v in contexts.get(key, [])]} for key in missing],
              "refresh_plan": refresh_plan(records, previous["findings"], missing),
              "limitations": ["Same-field native counters corroborate snapshots; no unproved conservation equation or aggregate adjustment sign is used.",
                  "All capture versions remain separate. Acquisition times and same-native-record updated_time changes are observations, never an assumed cause or date correction.",
                  "Native consumed_kgs is a supplied cumulative counter, not dated lot consumption history or proof of a known stock formula.",
                  "Yarn company identity requires exact job ID/date/party/book/type agreement with an unambiguous native fabric job header.",
                  "Unknown company ownership, cutoff, annual physical openings and missing movement semantics keep the import gate closed.",
                  "Party Stock and Own Stock categories are source-supported; monetary valuation requirements remain conditional on the source ownership/valuation contract."]}
    if not baseline["integrity"]["valid"] or not baseline["identity"]["valid"]:
        issues.append("baseline_integrity_or_identity_failed")
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
    captured = (args.report_source / "manifest.jsonl").read_bytes()
    result = audit(args.source, args.report_source, captured)
    write_private(destination.with_suffix(".manifest.jsonl"), captured.decode("utf-8"))
    write_private(destination, json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"import_allowed": False, "verified_files": result["selected_evidence_integrity"]["verified_files"],
                      "native_context_companies": len(result["companies"]), "trace_count": len(result["prior_findings_traced"])}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
