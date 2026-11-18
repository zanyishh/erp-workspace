#!/usr/bin/env python3
"""Offline native yarn-return controls; original IDs and quantities stay unchanged."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_reports import compare, exact_sum, response_failed, selected_records
from check_knitpack_snapshot import identifier, write_private
from reconcile_knitpack_balances import number

ROUTE = "knitpack/Yarnreturn/getNewYarnreturn/"
FIELDS = {"net_kgs": "total_net_kgs", "gross_kgs": "total_gross_kgs", "bags": "total_bags", "cons": "total_cones"}


def validate_native_return(payload, source_id, company):
    out = {"source_key": [company, source_id], "identity_status": "unknown", "children": [], "quantity_controls": {},
           "child_id_namespace": "persisted_return_line_id_from_native_edit_save_contract", "candidate_id_duplicates": [],
           "empty_unpersisted_context_rows": []}
    data = payload.get("result") if isinstance(payload, dict) and not response_failed(payload) else None
    if (not isinstance(data, dict) or identifier(data.get("id")) != source_id
            or identifier(data.get("companymas_id")) != company or not source_id or not company
            or not iso_date(data.get("dc_date")) or not isinstance(data.get("yarn_details"), list)):
        return out
    out.update(original_date=data["dc_date"], original_cancelled=data.get("cancelled"),
               original_created_time=data.get("created_time"), original_updated_time=data.get("updated_time"),
               original_job_no=data.get("job_no"))
    rows, ids = data["yarn_details"], Counter()
    valid = True
    for row in rows:
        if not isinstance(row, dict):
            valid = False
            continue
        yarn = identifier(row.get("yarnmas_id"))
        valid = valid and yarn is not None
        candidate_id = identifier(row.get("id"))
        if (row.get("id") in (None, "", 0, "0") and row.get("yarn_dc_id") in (None, "", 0, "0")
                and yarn and identifier(row.get("item_id")) and all(number(row.get(f)) == 0 for f in FIELDS)):
            out["empty_unpersisted_context_rows"].append({"original_id": row.get("id"), "original_item_id": row.get("item_id"),
                "source_yarn_id": yarn, "original_quantities": {f: row.get(f) for f in FIELDS}})
            continue
        valid = valid and candidate_id is not None and ids[candidate_id] == 0
        if "yarn_dc_id" in row and row["yarn_dc_id"] not in (None, ""):
            valid = valid and identifier(row["yarn_dc_id"]) == source_id
        if candidate_id:
            ids[candidate_id] += 1
        out["children"].append({"original_id": row.get("id"), "original_item_id": row.get("item_id"),
                                "source_yarn_id": yarn, "original_quantities": {f: row.get(f) for f in FIELDS}})
    out["candidate_id_duplicates"] = sorted(k for k, n in ids.items() if n > 1)
    out["identity_status"] = "passed" if valid else "unknown"
    out["quantity_controls"] = {field: compare([r.get(field) if isinstance(r, dict) else None for r in rows], data.get(control))
                                 for field, control in FIELDS.items()}
    return out


def audit(folder, manifest=None):
    manifest = (folder / "manifest.jsonl").read_bytes() if manifest is None else manifest
    out = {"version": 1, "import_allowed": False, "selected_evidence_integrity": {"issues": []},
           "identity_issues": [], "native_returns": [], "register_observations": [], "coverage": {},
           "native_header_controls_semantics": "diagnostic_source_header_vs_children; backend_total_field_contract_unproved",
           "limitations": [
               "The saved public return editor creates new lines with blank id, loads saved getter lines unchanged in edit mode and forwards their id to UpdateYarnReturn. Positive unique row.id is the persisted return-line ID; item_id is job-yarn context and never substitutes for it.",
               "The native getter establishes parent containment when the response omits a child yarn_dc_id foreign key; no missing FK value is fabricated.",
               "Blank new-line id and parent fields with explicit zero quantities and valid context IDs are retained as unpersisted editor choices, not additional return events.",
               "Header job_no is retained verbatim, never parsed or assumed to be the native job ID. Register jobmas_id remains an independent observed reference.",
               "Native quantities are compared with each report scope independently; repeated observations do not create additional source events.",
               "The public editor sums child net_kgs into grd_total but does not assign the supplied total_* header fields. Header-versus-child comparisons are diagnostic observations, not proven backend invariants or authorized corrections.",
               "Exact totals and original date/cancellation agreement do not establish stock conservation, cancellation posting semantics, or complete source balances.",
               "Failed responses, conflicting versions, missing fields and unavailable current records remain unknown; no missing value becomes zero."]}
    digest, records = selected_records(folder.resolve(), lambda e: e["path"].startswith(ROUTE) or "/getYarnReturnRegPrint/" in e["path"],
                                       out["selected_evidence_integrity"]["issues"], manifest)
    out["selected_evidence_integrity"].update(captured_manifest_sha256=digest, verified_files=len(records))
    native = defaultdict(list)
    for entry, payload, path in records:
        if not entry["path"].startswith(ROUTE):
            continue
        source_id = identifier(entry["path"].removeprefix(ROUTE))
        filters = entry.get("filters", {})
        company = identifier(filters.get("companymas_id"))
        observation = validate_native_return(payload, source_id, company)
        observation["evidence"] = {"file": entry["file"], "sha256": entry["sha256"], "retrieved_at_utc": entry.get("retrieved_at_utc")}
        if identifier(filters.get("id")) != source_id:
            observation["identity_status"] = "unknown"
        out["native_returns"].append(observation)
        if observation["identity_status"] == "passed":
            native[(company, source_id)].append((payload["result"], observation))
        else:
            out["identity_issues"].append({"kind": "native_return_identity_or_original_date_unknown", "file": entry["file"]})
    expected, usable = set(), set()
    for entry, payload, path in records:
        if "/getYarnReturnRegPrint/" not in entry["path"]:
            continue
        company = identifier(entry.get("filters", {}).get("companymas_id"))
        rows = payload.get("root", {}).get("yarnreturns") if not response_failed(payload) else None
        if not company or not isinstance(rows, list):
            out["identity_issues"].append({"kind": "register_scope_or_response_unknown", "file": entry["file"]})
            continue
        groups = defaultdict(list)
        for row in rows:
            key = (company, identifier(row.get("yarn_dc_id")), identifier(row.get("yarnmas_id"))) if isinstance(row, dict) else (None,) * 3
            if not all(key) or identifier(row.get("dc_id")) != key[1] or identifier(row.get("companymas_id")) != company:
                out["identity_issues"].append({"kind": "register_native_parent_alias_unknown", "file": entry["file"]})
                continue
            groups[key].append(row)
            expected.add(key[:2])
        for key, grouped in groups.items():
            versions = native.get(key[:2], [])
            obs = {"source_company_parent_yarn": list(key), "file": entry["file"], "sha256": entry["sha256"],
                   "status": "unknown", "quantity_controls": {}}
            out["register_observations"].append(obs)
            if not versions or len({json.dumps(v, sort_keys=True, default=str) for v, _ in versions}) != 1:
                continue
            data, native_observation = versions[0]
            native_rows = [r for r in data["yarn_details"] if identifier(r.get("yarnmas_id")) == key[2]]
            obs["native_evidence"] = native_observation["evidence"]
            obs["original_date_agreement"] = all(iso_date(r.get("dc_date")) and r["dc_date"] == data["dc_date"] for r in grouped)
            obs["original_cancelled_agreement"] = (None if data.get("cancelled") is None or any(r.get("cancelled") is None for r in grouped)
                else all(str(r["cancelled"]) == str(data["cancelled"]) for r in grouped))
            obs["source_register_job_ids"] = sorted({identifier(r.get("jobmas_id")) for r in grouped} - {None})
            if not native_rows:
                continue
            obs["quantity_controls"] = {f: compare([r.get(f) for r in grouped], exact_sum([number(r.get(f)) for r in native_rows])) for f in FIELDS}
            obs["status"] = ("passed" if obs["original_date_agreement"] and obs["original_cancelled_agreement"] is True
                and all(c["status"] == "passed" for c in obs["quantity_controls"].values()) else "different_or_unknown")
            usable.add(key[:2])
    for company in sorted({k[0] for k in expected | native.keys()}):
        ex = {k for k in expected if k[0] == company}
        na = {k for k in native if k[0] == company}
        out["coverage"][company] = {"register_native_parents": len(ex), "captured_native_parents": len(na),
            "register_parents_without_usable_native": [list(k) for k in sorted(ex - usable)],
            "native_parents_not_in_register": [list(k) for k in sorted(na - ex)]}
    out["summary"] = {"native_responses": len(out["native_returns"]), "native_parent_keys": len(native),
        "native_child_context_rows": sum(len(x["children"]) for x in out["native_returns"]),
        "empty_unpersisted_context_rows": sum(len(x["empty_unpersisted_context_rows"]) for x in out["native_returns"]),
        "native_header_controls": dict(Counter(c["status"] for x in out["native_returns"] for c in x["quantity_controls"].values())),
        "register_overlap_controls": dict(Counter(c["status"] for x in out["register_observations"] for c in x["quantity_controls"].values())),
        "register_overlap_statuses": dict(Counter(x["status"] for x in out["register_observations"]))}
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = (args.manifest or args.reports / "manifest.jsonl").read_bytes()
    report = audit(args.reports, manifest)
    write_private(args.output, json.dumps(report, indent=2, sort_keys=True, default=str) + "\n")
    write_private(args.output.with_suffix(".manifest.jsonl"), manifest.decode("utf-8"))
    print(json.dumps({"summary": report["summary"], "integrity_issues": len(report["selected_evidence_integrity"]["issues"]),
                      "identity_issues": len(report["identity_issues"]), "import_allowed": False}))


if __name__ == "__main__":
    main()
