#!/usr/bin/env python3
"""Find explicit saved movement/counter arithmetic supporting physical differences."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

from audit_knitpack_native_stock import FABRIC_ROUTE, YARN_ROUTE, provenance, selector
from audit_knitpack_reports import response_failed, compare, exact_sum, selected_records
from check_knitpack_snapshot import identifier, write_private
from reconcile_knitpack_balances import number

MOVEMENTS = {
    "yarninward": {"kgs": ("grnnetkgs",), "bags": ("grnbags",), "cones": ("grncones",)},
    "yarnreturns": {"kgs": ("net_kgs", "mistake_kgs"), "bags": ("bags",), "cones": ("cons",)},
    "fabricdc": {"kgs": ("dlvry_kgs", "mistake_kgs"), "rolls": ("dlvry_rolls",)},
    "production": {"kgs": ("prodkgs",), "rolls": ("prodrolls",)},
    "prodreports": {"kgs": ("prodkgs",), "rolls": ("prodrolls",)},
    "reciepts": {"kgs": ("grnnetkgs",), "bags": ("grnbags",), "cones": ("grncones",)},
    "returns": {"kgs": ("net_kgs",), "bags": ("bags",), "cones": ("cons",)},
    "deliveries": {"kgs": ("dlvry_kgs",), "rolls": ("dlvry_rolls",)},
}
OTHER_MOVEMENTS = ("trans_in", "trans_out", "job_trans_in", "job_trans_out", "yarndelivery", "yarnstocksdj",
                   "sc_stock_adj", "fabric_trans", "dia_trans", "fabricreceipt", "fabricstockadj", "sc_order_inward",
                   "own_transin", "own_transout", "transin", "transout", "jobTransIn", "jobTransOut", "subcontract")
NATIVE_YARN_FIELDS = {"kgs": ("prog_kgs", "grn_kgs", "transin_kgs", "transout_kgs", "consumed_kgs", "sc_dc_kgs",
                              "sc_rtn_kgs", "return_kgs", "adjust_kgs", "stock_kgs"),
                      "bags": ("grn_bags", "return_bags", "stock_bags"), "cones": ()}
NATIVE_DIA_FIELDS = {"kgs": ("programqty", "prod_qty", "sc_grn", "adjust_qty", "transin_kgs", "transout_kgs",
                             "stock_kgs", "dlvry_kgs", "canc_kgs", "sc_canc_kgs"), "bags": (), "cones": ()}
ID_FIELDS = ("jobyarngrn_id", "deatid", "yarn_dc_id", "dc_id", "fabric_id", "jobdia_id", "yarnmas_id", "det_id")
DATE_FIELDS = ("date", "real_date", "grndate", "partydcdate", "dc_date", "adj_date", "created_time", "updated_time")


def candidate(values, delta, original_rows, original_control):
    total = exact_sum([number(v) for v in values])
    return {"sum": None if total is None else format(total, "f"), "values_count": len(values),
            "delta_equals_sum": compare([total], delta),
            "delta_equals_negative_sum": compare([total.copy_negate() if total is not None else None], delta),
            "original_rows_equal_sum": compare([total], original_rows),
            "original_control_equal_sum": compare([total], original_control),
            "explanation_proved": False}


def movement_candidates(rows, dataset, unit, delta, original_rows, original_control):
    if not isinstance(rows, list):
        return []
    fields = MOVEMENTS.get(dataset, {}).get(unit, ())
    result = []
    for field in fields:
        if rows and not any(isinstance(r, dict) and field in r for r in rows):
            continue
        groups = [({}, rows)]
        if rows and all(isinstance(r, dict) and "cancelled" in r for r in rows):
            groups.extend(({"cancelled": str(flag)}, [r for r in rows if str(r["cancelled"]) == str(flag)])
                          for flag in sorted({str(r["cancelled"]) for r in rows}))
        for group, selected in groups:
            result.append({"dataset": dataset, "field": field, "group": group,
                           "scope_completeness": "unknown", **candidate([r.get(field) if isinstance(r, dict) else None for r in selected],
                                                                        delta, original_rows, original_control)})
        # Individual native movement observations are numerical candidates only;
        # displayed IDs/flattened joined IDs are not invented as primary keys.
        for index, row in enumerate(rows):
            if isinstance(row, dict):
                ids = {key: identifier(row[key]) for key in ID_FIELDS if identifier(row.get(key))}
                if ids:
                    result.append({"dataset": dataset, "field": field, "group": {"observed_id_fields": ids},
                                   "source_array_index": index,
                                   "original_dates": {key: row[key] for key in DATE_FIELDS if key in row},
                                   "source_flags": {key: row[key] for key in ("cancelled", "status", "dc_type", "grntype", "etype") if key in row},
                                   "scope_completeness": "unknown", **candidate([row.get(field)], delta, original_rows, original_control)})
    return result


def audit(report_source, native_report):
    raw = native_report.read_bytes()
    native = json.loads(raw)
    findings = [t for t in native["prior_findings_traced"] if t["original_finding"]["status"] == "different"]
    jobs = {t["original_finding"]["source_key"][1] for t in findings}
    issues = []
    captured_path = native_report.with_suffix(".manifest.jsonl")
    captured = captured_path.read_bytes() if captured_path.is_file() else None
    if captured is not None and hashlib.sha256(captured).hexdigest() != native["selected_evidence_integrity"]["captured_manifest_sha256"]:
        raise ValueError("Native report manifest capture does not match its recorded digest")
    def selected(entry):
        path, filters = entry["path"], entry.get("filters")
        return (path.startswith((FABRIC_ROUTE, YARN_ROUTE)) and path.rsplit("/", 1)[-1] in jobs
                or "/JobTransHistory/" in path and isinstance(filters, dict) and identifier(filters.get("jobmas_id")) in jobs
                or "/ViewJobLedgerreport/" in path and isinstance(filters, dict) and identifier(filters.get("id")) in jobs
                or "/getProductionReg/" in path)
    manifest, records = selected_records(report_source.resolve(), selected, issues, captured)
    hashes = {e["file"]: e["sha256"] for e, _, _ in records}
    earlier = {e["file"]: e["sha256"] for e in native["evidence_manifest"]}
    validated_yarn = {(tuple(context["source_key"]), e["file"], e["sha256"])
                      for context in native.get("validated_native_contexts", []) for e in context["yarn_evidence"]}
    validated_fabric = {(tuple(context["source_key"]), context["fabric_evidence"]["file"], context["fabric_evidence"]["sha256"])
                        for context in native.get("validated_native_contexts", [])}
    if any(file in earlier and earlier[file] != digest for file, digest in hashes.items()):
        issues.append("native_trace_original_evidence_changed")
    result = {"version": 1, "import_allowed": False, "physical_balances_reconciled": False,
              "input_trace_sha256": hashlib.sha256(raw).hexdigest(), "findings": [],
              "selected_evidence_integrity": {"captured_manifest_sha256": manifest, "issues": issues, "verified_files": len(records)},
              "evidence_manifest": [provenance(r) for r in records],
              "limitations": ["An equal numerical delta is an arithmetic candidate, not a proven causal or accounting explanation.",
                  "No arbitrary subsets or combinations are searched. Candidates are whole named datasets, explicit raw cancellation groups, individual native movement observations, or named native counters.",
                  "An empty saved movement dataset is reported as empty scope evidence, never proof that no such source transaction exists.",
                  "Sample/order production labels are requested report scopes; they cannot override native returned identities or prove every production row has that type.",
                  "No corrections, tolerances, inferred dates, invented consumption or quantity adjustments are applied.",
                  "Native stock and programme templates directly display supplied stock_kgs; no publicly established transformation explains their difference."]}
    for traced in findings:
        finding = traced["original_finding"]
        company, job = finding["source_key"][:2]
        unit = "bags" if finding["field"].endswith("bags") else "cones" if finding["field"].endswith("cones") else "kgs"
        delta, old_rows, old_control = (finding.get(f) for f in ("control_minus_row_sum", "row_sum", "source_control"))
        detail = {"original_finding": finding, "native_counter_corroboration": traced["versions"], "unit": unit,
                  "movement_dataset_coverage": [], "candidates": [], "explanation_proved": False}
        result["findings"].append(detail)
        for record in records:
            entry, payload, path = record
            if response_failed(payload):
                continue
            route, filters = entry["path"], entry.get("filters")
            root = payload.get("root")
            data = payload.get("result")
            if isinstance(root, dict):
                history = "/JobTransHistory/" in route and identifier(filters.get("jobmas_id")) == job
                ledger = "/ViewJobLedgerreport/" in route and identifier(filters.get("id")) == job
                prod = "/getProductionReg/" in route and identifier(filters.get("companymas_id")) == company
                if not (history or ledger or prod):
                    continue
                if history and (not root.get("order_inward") or any(identifier(r.get("id")) != job for r in root["order_inward"])):
                    issues.append("history_native_job_identity_unknown")
                    continue
                if ledger and (identifier(root.get("job", {}).get("id")) != job or identifier(root.get("job", {}).get("companymas_id")) != company):
                    issues.append("ledger_native_job_identity_unknown")
                    continue
                arrays = ("prodreports",) if prod else (*MOVEMENTS, *OTHER_MOVEMENTS)
                for dataset in arrays:
                    rows = root.get(dataset)
                    if prod and isinstance(rows, list):
                        rows = [r for r in rows if identifier(r.get("jobmas_id")) == job]
                    if isinstance(rows, list) and any(isinstance(r, dict) and
                        ("companymas_id" in r and identifier(r["companymas_id"]) != company or
                         "jobmas_id" in r and identifier(r["jobmas_id"]) != job) for r in rows):
                        issues.append("movement_company_or_job_identity_conflict")
                        continue
                    detail["movement_dataset_coverage"].append({"dataset": dataset, "rows": len(rows) if isinstance(rows, list) else None,
                         "status": "observed" if isinstance(rows, list) else "unknown", "evidence": provenance(record),
                         "requested_job_type": filters.get("job_type") if prod else None})
                    for value in movement_candidates(rows, dataset, unit, delta, old_rows, old_control):
                        detail["candidates"].append({"kind": "movement_observation", "evidence": provenance(record),
                            "requested_job_type": filters.get("job_type") if prod else None, **value})
            if not isinstance(data, dict) or route.rsplit("/", 1)[-1] != job:
                continue
            native_rows, fields = None, ()
            if route.startswith(YARN_ROUTE) and identifier(data.get("id")) == job:
                # Company binding was independently required by the input native audit.
                if ((company, job), entry["file"], entry["sha256"]) not in validated_yarn:
                    continue
                native_rows, fields = data.get("yarn_mas"), NATIVE_YARN_FIELDS[unit]
            elif route.startswith(FABRIC_ROUTE) and isinstance(data.get("job"), dict) and identifier(data["job"].get("companymas_id")) == company and identifier(data["job"].get("id")) == job:
                if ((company, job), entry["file"], entry["sha256"]) not in validated_fabric:
                    continue
                native_rows = [dia for fabric in data.get("fabs", []) for dia in fabric.get("dias", [])
                    if finding["check"] != "fabric_stock_programme_overlap" or identifier(fabric.get("id")) == finding["source_key"][2]
                    and selector(dia.get("diaorsize")) == finding["source_key"][3]]
                fields = NATIVE_DIA_FIELDS[unit]
            if isinstance(native_rows, list):
                for field in fields:
                    detail["candidates"].append({"kind": "native_cumulative_counter", "field": field, "evidence": provenance(record),
                        **candidate([r.get(field) for r in native_rows], delta, old_rows, old_control)})
        detail["arithmetic_delta_matches"] = [index for index, c in enumerate(detail["candidates"])
            if c["delta_equals_sum"]["status"] == "passed" or c["delta_equals_negative_sum"]["status"] == "passed"]
    paired = defaultdict(list)
    for f_index, detail in enumerate(result["findings"]):
        for c_index in detail["arithmetic_delta_matches"]:
            c = detail["candidates"][c_index]
            if "source_array_index" in c:
                paired[(tuple(detail["original_finding"]["source_key"][:2]), c["evidence"]["sha256"],
                        c["dataset"], c["source_array_index"])].append({"finding_index": f_index, "candidate_index": c_index})
    result["same_source_row_matching_multiple_field_deltas"] = [
        {"source_key": list(key[0]), "source_sha256": key[1], "dataset": key[2], "source_array_index": key[3],
         "matches": matches, "explanation_proved": False} for key, matches in paired.items()
        if len({m["finding_index"] for m in matches}) > 1]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("native_report", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if destination.suffix != ".json" or destination.is_relative_to(args.report_source.resolve()) or destination == args.native_report.resolve():
        parser.error("Write the private JSON trace outside the read-only archive and input trace.")
    result = audit(args.report_source, args.native_report)
    write_private(destination, json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"import_allowed": False, "findings": len(result["findings"]), "verified_files": result["selected_evidence_integrity"]["verified_files"]}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
