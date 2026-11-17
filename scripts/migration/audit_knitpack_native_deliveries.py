#!/usr/bin/env python3
"""Offline delivery evidence with one payload in memory at a time; never import."""
from collections import Counter, defaultdict
import argparse
import hashlib
import json
from pathlib import Path

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_reports import compare, exact_sum, response_failed, selected_records
from check_knitpack_snapshot import identifier, write_private
from reconcile_knitpack_balances import number


def validate_dc(payload, expected, owners):
    out = {"identity_status": "unknown", "persisted_children": [], "empty_availability_choices": [],
           "header_quantity_diagnostics": {}}
    d = payload.get("result") if isinstance(payload, dict) and not response_failed(payload) else None
    sid, company, job = (identifier(expected.get(k)) for k in ("id", "companymas_id", "job_no"))
    out["source_key"] = [company, sid]
    out["expected_job_id"] = job
    if (not all((sid, company, job)) or not isinstance(d, dict) or identifier(d.get("id")) != sid
            or identifier(d.get("companymas_id")) != company or identifier(d.get("job_no")) != job
            or not iso_date(d.get("dc_date")) or not isinstance(d.get("fabric_dia_details"), list)):
        return out
    out.update(original_date=d["dc_date"], original_number=d.get("dc_no"), original_cancelled=d.get("cancelled"),
               original_invoice_id=d.get("invoice_id"), original_eway_id=d.get("eway_id"),
               original_created_time=d.get("created_time"), original_updated_time=d.get("updated_time"))
    for values, value, name in ((expected.get("dates", []), d["dc_date"], "date"),
                                (expected.get("numbers", []), str(d.get("dc_no")), "number")):
        out[name + "_observation_agreement"] = "unknown_no_independent_value" if not values else "passed" if set(values) == {value} else "different"
    eway = d.get("eway_id")
    out["eway_id_status"] = ("positive_native_id" if identifier(eway) else "explicit_zero" if number(eway) == 0
                              else "missing" if eway in (None, "") else "invalid_or_unproved")
    seen, valid = set(), True
    for row in d["fabric_dia_details"]:
        if not isinstance(row, dict):
            valid = False
            continue
        cid, parent = identifier(row.get("id")), identifier(row.get("dc_id"))
        dimensions = (identifier(row.get("fabric_id")), identifier(row.get("jobdia_id")))
        matched = owners.get(dimensions, set()) == {(company, job)}
        value = {"original_id": row.get("id"), "original_dc_id": row.get("dc_id"), "fabric_id": dimensions[0],
                 "jobdia_id": dimensions[1], "dlvry_kgs": row.get("dlvry_kgs"), "dlvry_rolls": row.get("dlvry_rolls")}
        value["original_diatype"] = row.get("diatype")
        if (row.get("id") in (None, "", 0, "0") and row.get("dc_id") in (None, "", 0, "0") and matched
                and all(number(row.get(f)) == 0 for f in ("dlvry_kgs", "dlvry_rolls"))):
            out["empty_availability_choices"].append(value)
            continue
        good = bool(cid and cid not in seen and parent == sid and matched)
        seen.add(cid)
        valid = valid and good
        value["identity_valid"] = good
        out["persisted_children"].append(value)
    out["identity_status"] = "passed" if valid else "unknown"
    for field, control in (("dlvry_kgs", "total_dlvry_kgs"), ("dlvry_rolls", "total_dlvry_rolls")):
        out["header_quantity_diagnostics"][field] = compare([r[field] for r in out["persisted_children"]], d.get(control))
    return out


def audit(folder, source, manifest, plan_path, invoice_audit_path, details_path):
    """Keep only identifiers and narrow witness projections, never all raw payloads."""
    entries = {e["file"]: e for line in manifest.splitlines() if (e := json.loads(line))}
    plan_bytes = plan_path.read_bytes()
    plan = json.loads(plan_bytes)
    issues, verified, unusable = [], set(), []
    owners, owner_basis = defaultdict(set), defaultdict(set)
    out = {"version": 1, "import_allowed": False, "manifest_sha256": hashlib.sha256(manifest).hexdigest(),
           "plan_sha256": hashlib.sha256(plan_bytes).hexdigest(), "finite_expected_parents": plan["known_parent_count"],
           "integrity_issues": issues, "identity_findings": [], "companies": {}, "checks": {}, "historical_job_1857": [],
           "limits": ["Only the finite delivery plan and its selected source witnesses are read; this is not an archive-wide rehash.",
               "Original dates, numbers, cancellation fields, Eway references and source IDs remain unchanged. Unavailable current job1857 is not inferred cancelled.",
               "Persisted detail IDs/FKs are distinct from explicit-zero empty-ID availability choices.",
               "Source header total_dlvry_rolls is assigned from row counts by the public editor. Its kilogram callback depends on source fabric type; alternate total_kgs/total_rolls have no established universal equality contract. Header comparisons remain diagnostic.",
               "An invoice saved-selection association is corroborated separately from the native DC invoice_id field. A disagreement does not authorize reassignment or duplicate posting.",
               "No external Eway document is inferred from a zero or missing reference; positive references require their own authoritative document evidence."]}

    def load(entry, base=folder):
        if not entry:
            return None
        local = []
        _, found = selected_records(base.resolve(), lambda e: True, local, (json.dumps(entry) + "\n").encode())
        issues.extend({"file": entry["file"], "issue": x} for x in local)
        if not found:
            return None
        verified.add((str(base), entry["file"]))
        payload = found[0][1]
        if response_failed(payload):
            unusable.append(entry["file"])
            return None
        return payload

    def context(job, fabrics, basis):
        key = (identifier(job.get("companymas_id")), identifier(job.get("id"))) if isinstance(job, dict) else (None, None)
        if not all(key) or not iso_date(job.get("jobdate")) or not isinstance(fabrics, list):
            return False
        dims, seen = [], set()
        for fabric in fabrics:
            if not isinstance(fabric, dict) or identifier(fabric.get("jobmas_id")) != key[1] or not isinstance(fabric.get("dias"), list):
                return False
            fid = identifier(fabric.get("id"))
            for dia in fabric["dias"]:
                pair = (fid, identifier(dia.get("id"))) if isinstance(dia, dict) else (None, None)
                if not all(pair) or pair in seen or identifier(dia.get("jobfabric_id")) != fid:
                    return False
                seen.add(pair)
                dims.append(pair)
        for pair in dims:
            owners[pair].add(key)
            owner_basis[(key, pair)].add(basis)
        return True

    for entry in entries.values():
        if not entry["path"].startswith("knitpack/Subcontract/getJobInfos/"):
            continue
        payload = load(entry)
        data = payload.get("result") if payload else None
        job = data.get("job") if isinstance(data, dict) else None
        if (isinstance(job, dict) and identifier(job.get("id")) == identifier(entry["path"].split("/")[-1])
                and context(job, data.get("fabs"), "current_native_job_context")):
            continue
        if payload:
            unusable.append(entry["file"])
    original_manifest = (source / "manifest.jsonl").read_bytes()
    for line in original_manifest.splitlines():
        entry = json.loads(line)
        if entry["path"] != "knitpack/inward/getInward/1857":
            continue
        payload = load(entry, source)
        data = payload.get("result") if payload else None
        if isinstance(data, dict) and identifier(data.get("id")) == "1857" and context(data, data.get("job_fabrics"), "original_archived_job_1857"):
            out["original_1857_job_evidence"] = {"file": entry["file"], "sha256": entry["sha256"], "original_date": data["jobdate"],
                                                  "current_status_inferred": False}

    expected, witness_files = {}, defaultdict(set)
    for read in plan["reads"]:
        exp = read["expected"].copy()
        exp.update(dates=read.get("observed_original_dates", []), numbers=read.get("observed_numbers", []))
        expected[identifier(exp["id"])] = exp
        for ref in read.get("id_sources", []):
            filename = Path(ref["file"]).name
            entry = entries.get(filename)
            if not entry or entry["sha256"] != ref["sha256"]:
                issues.append({"file": filename, "issue": "planned_witness_not_in_checkpoint_or_hash_differs"})
            else:
                witness_files[filename].add(ref["kind"])
    for old in plan["already_captured"]:
        filename = Path(old["file"]).name
        entry = entries.get(filename)
        if not entry or entry["sha256"] != old["sha256"]:
            issues.append({"file": filename, "issue": "previous_capture_not_in_checkpoint_or_hash_differs"})
            continue
        exp = entry.get("filters", {}).copy()
        # The earlier finite gap plan named its native job scope source_job_id.
        # This normalizes acquisition metadata only; native response fields stay intact.
        if "job_no" not in exp and "source_job_id" in exp:
            exp["job_no"] = exp["source_job_id"]
        expected[identifier(exp.get("id"))] = exp
    already_jobs = {identifier(x.get("job_no")) for x in expected.values() if not x.get("dates")}
    for entry in entries.values():
        filters = entry.get("filters") or {}
        if "/ViewJobLedgerreport/" in entry["path"] and identifier(filters.get("id")) in already_jobs:
            witness_files[entry["file"]].add("validated_job_ledger")
        if "/JobTransHistory/" in entry["path"] and identifier(filters.get("jobmas_id")) in already_jobs:
            witness_files[entry["file"]].add("history")

    invoice_proof_bytes = invoice_audit_path.read_bytes()
    invoices = json.loads(invoice_proof_bytes)
    invoice_companies = defaultdict(set)
    for invoice in invoices["invoices"]:
        key, evidence = invoice["source_key"], invoice["evidence"]
        filename = Path(evidence["file"]).name
        if key[0] == "regular" and entries.get(filename, {}).get("sha256") == evidence["sha256"]:
            invoice_companies[key[2]].add(key[1])
    out["prior_native_invoice_proof_sha256"] = hashlib.sha256(invoice_proof_bytes).hexdigest()
    del invoices, invoice_proof_bytes, plan

    witnesses = defaultdict(list)
    for filename, kinds in witness_files.items():
        entry = entries[filename]
        payload = load(entry)
        if not payload:
            continue
        for kind in kinds:
            root = payload.get("root", {})
            invoice = identifier(entry["path"].split("/")[-1]) if kind == "validated_invoice_dc" else None
            rows = (root.get("fabricdc") if kind == "history" and isinstance(root, dict) else
                    root.get("deliveries") if kind == "validated_job_ledger" and isinstance(root, dict) else
                    payload.get("result", {}).get("dcinfo") if kind == "validated_invoice_dc" and isinstance(payload.get("result"), dict) else None)
            if not isinstance(rows, list):
                continue
            groups = defaultdict(list)
            for row in rows:
                if not isinstance(row, dict):
                    continue
                sid = identifier(row.get("id" if kind == "validated_job_ledger" else "dc_id"))
                if sid in expected:
                    groups[sid].append(row)
            for sid, rows in groups.items():
                exp = expected[sid]
                if kind == "validated_job_ledger":
                    job = root.get("job", {})
                    identity = identifier(job.get("companymas_id")) == identifier(exp.get("companymas_id")) and identifier(job.get("id")) == identifier(exp.get("job_no"))
                elif kind == "history":
                    identity = all(identifier(row.get("companymas_id")) == identifier(exp.get("companymas_id")) and identifier(row.get("jobmas_id")) == identifier(exp.get("job_no")) for row in rows)
                else:
                    identity = invoice_companies.get(invoice) == {identifier(exp.get("companymas_id"))} and all(identifier(row.get("invoice_id")) == invoice and identifier(row.get("jobmas_id")) == identifier(exp.get("job_no")) for row in rows)
                narrow = [{f: row.get(f) for f in ("fabric_id", "jobdia_id", "dc_date", "dc_no", "dlvry_kgs", "dlvry_rolls", "eway_id", "cancelled")} for row in rows]
                witnesses[sid].append({"kind": kind, "file": filename, "sha256": entry["sha256"], "identity_valid": identity,
                                        "invoice_id": invoice, "rows": narrow})

    counts, checks = Counter(), defaultdict(Counter)
    observed, child_keys = set(), set()
    write_private(details_path, "")
    with details_path.open("a") as stream:
        for entry in entries.values():
            if not entry["path"].startswith("knitpack/fabricdelivery/getFabricdelivery/"):
                continue
            sid = identifier(entry["path"].split("/")[-1])
            exp = expected.get(sid)
            if not exp:
                out["identity_findings"].append({"file": entry["file"], "kind": "native_parent_outside_finite_plan"})
                continue
            observed.add(sid)
            payload = load(entry)
            record = validate_dc(payload or {}, exp, owners)
            record["evidence"] = {"file": entry["file"], "sha256": entry["sha256"], "retrieved_at_utc": entry.get("retrieved_at_utc")}
            record["witnesses"] = []
            company = identifier(exp.get("companymas_id"))
            stat = out["companies"].setdefault(company, Counter())
            stat["native_parents"] += 1
            stat["identity_" + record["identity_status"]] += 1
            for child in record["persisted_children"]:
                key = (company, identifier(child["original_id"]))
                if key in child_keys:
                    out["identity_findings"].append({"source_key": record["source_key"], "kind": "repeated_persisted_child_id_in_company"})
                child_keys.add(key)
            stat["persisted_children"] += len(record["persisted_children"])
            stat["empty_availability_choices"] += len(record["empty_availability_choices"])
            counts["native_parents"] += 1
            counts["persisted_children"] += len(record["persisted_children"])
            counts["empty_availability_choices"] += len(record["empty_availability_choices"])
            checks["identity"][record["identity_status"]] += 1
            for name in ("date_observation_agreement", "number_observation_agreement", "eway_id_status"):
                checks[name][record.get(name, "unknown")] += 1
            for control in record["header_quantity_diagnostics"].values():
                checks["header_quantity_diagnostics"][control["status"]] += 1
            for witness in witnesses.get(sid, []):
                rows = witness.pop("rows")
                witness["original_date_comparisons"] = ["passed" if row["dc_date"] == record.get("original_date") else "different" if iso_date(row["dc_date"]) else "unknown_non_iso_source_representation" for row in rows]
                witness["original_number_comparisons"] = ["unknown" if row["dc_no"] is None else "passed" if str(row["dc_no"]) == str(record.get("original_number")) else "different" for row in rows]
                witness["quantities"] = {f: compare([row[f] for row in rows], exact_sum([number(c[f]) for c in record["persisted_children"]])) for f in ("dlvry_kgs", "dlvry_rolls")}
                if witness["kind"] in ("history", "validated_job_ledger"):
                    native_dims, witness_dims = defaultdict(list), defaultdict(list)
                    for child in record["persisted_children"]:
                        native_dims[(child["fabric_id"], child["jobdia_id"])].append(child)
                    for row in rows:
                        witness_dims[(identifier(row["fabric_id"]), identifier(row["jobdia_id"]))].append(row)
                    witness["dimension_keys_agree"] = set(native_dims) == set(witness_dims) and all(all(k) for k in witness_dims)
                    checks[witness["kind"] + "_dimension_identity"]["passed" if witness["dimension_keys_agree"] else "unknown_or_different"] += 1
                    witness["dimension_quantity_checks"] = []
                    for dim in sorted(set(native_dims) & set(witness_dims)):
                        values = {f: compare([row[f] for row in witness_dims[dim]], exact_sum([number(c[f]) for c in native_dims[dim]])) for f in ("dlvry_kgs", "dlvry_rolls")}
                        witness["dimension_quantity_checks"].append({"native_fabric_dia": list(dim), "checks": values})
                        for value in values.values():
                            checks[witness["kind"] + "_dimension_quantities"][value["status"]] += 1
                if witness["kind"] == "validated_invoice_dc":
                    witness["native_dc_invoice_reference_agreement"] = identifier(record.get("original_invoice_id")) == witness["invoice_id"]
                    checks["native_invoice_reference"]["passed" if witness["native_dc_invoice_reference_agreement"] else "different"] += 1
                for f in ("eway_id", "cancelled"):
                    supplied = [row[f] for row in rows if row[f] is not None]
                    witness[f + "_agreement"] = "unknown_not_supplied" if not supplied else "passed" if all(str(v) == str(record.get("original_" + ("eway_id" if f == "eway_id" else "cancelled"))) for v in supplied) else "different"
                    checks[witness["kind"] + "_" + f][witness[f + "_agreement"]] += 1
                checks[witness["kind"] + "_identity"]["passed" if witness["identity_valid"] else "unknown"] += 1
                for c in witness["quantities"].values():
                    checks[witness["kind"] + "_quantities"][c["status"]] += 1
                for name in ("original_date_comparisons", "original_number_comparisons"):
                    checks[witness["kind"] + "_" + name].update(witness[name])
                record["witnesses"].append(witness)
            if identifier(exp.get("job_no")) == "1857":
                out["historical_job_1857"].append({"source_key": record["source_key"], "identity_status": record["identity_status"],
                    "original_date": record.get("original_date"), "original_number": record.get("original_number"), "original_cancelled": record.get("original_cancelled"),
                    "persisted_children": len(record["persisted_children"]), "basis": "original_archived_job_dimensions; current_job_state_unknown"})
            stream.write(json.dumps(record, sort_keys=True, default=str) + "\n")
    out.update(counts=dict(counts), checks={k: dict(v) for k, v in checks.items()}, selected_files_verified=len(verified),
               failed_source_response_files=unusable, missing_native_parent_ids=sorted(set(expected) - observed),
               observed_expected_parent_keys=len(observed), distinct_persisted_child_keys=len(child_keys),
               details_file=str(details_path), dimensions_with_conflicting_native_owners=sum(len(v) != 1 for v in owners.values()))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--invoice-audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.suffix != ".json" or any(args.output.resolve().is_relative_to(p.resolve()) for p in (args.source, args.reports)):
        parser.error("Write private audit output outside both read-only source archives.")
    result = audit(args.reports, args.source, args.manifest.read_bytes(), args.plan, args.invoice_audit, args.output.with_suffix(".details.jsonl"))
    write_private(args.output, json.dumps(result, indent=2, sort_keys=True, default=str) + "\n")
    print(json.dumps({"counts": result["counts"], "checks": result["checks"], "integrity_issues": len(result["integrity_issues"]),
                      "identity_findings": len(result["identity_findings"]), "missing_native_parents": len(result["missing_native_parent_ids"])}))


if __name__ == "__main__":
    main()
