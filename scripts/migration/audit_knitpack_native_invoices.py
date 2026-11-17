#!/usr/bin/env python3
"""Audit native invoice identities, saved children and explicit voucher references."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re

from audit_knitpack_financial_reports import iso_date
from audit_knitpack_native_stock import provenance
from audit_knitpack_reports import compare, exact_sum, selected_records, response_failed
from check_knitpack_snapshot import identifier, write_private
from reconcile_knitpack_balances import number

HEADER = re.compile(r"^knitpack/(inv|general_invoice)/getinvoice/(\d+)$")
DC = re.compile(r"^knitpack/inv/getUpdateDcJobinfoByJobNo/(\d+)$")
FABRIC = re.compile(r"^knitpack/inv/getFabDetail/([^/]*)/(\d+)$")
VOUCHER = re.compile(r"^accv2/accounts/getvoucher/(\d+)$")
TAX_FIELDS = ("sgst_value", "cgst_value", "igst_value")
ORIGINAL_FIELDS = ("invoice_date", "inv_date", "trans_doc_date", "finyear", "created_time", "updated_time", "cancelled")
TOTAL_FIELDS = ("total_kgs", "total_rolls_pcs", "total_value", "total_item_val", "nettotal_value", "tax_total_value",
                "grandtotal_value", "invoice_value", "r_invoice_value", "sgst_value", "cgst_value", "igst_value", "tcs_value")
PARTY_ROUTE = "masters/masters/getParty/"


def compare_party_business(left, right):
    excluded = {"id", "session_id", "created_by", "created_time", "updated_by", "updated_time", "created_t", "updated_t"}
    def business(value, root_id, nested=False):
        if isinstance(value, dict):
            return {key: business(item, root_id, True) for key, item in value.items()
                    if key not in excluded and not (nested and key == "party_id" and identifier(item) == root_id)}
        if isinstance(value, list):
            return [business(item, root_id, True) for item in value]
        return value
    def canonical(value):
        return json.dumps(value, sort_keys=True, default=lambda item: {"decimal_value": str(item)})
    a, b = business(left, identifier(left.get("id"))), business(right, identifier(right.get("id")))
    def saved_equal(field):
        values = left.get(field), right.get(field)
        return values[0] == values[1] if all(isinstance(v, str) and v.strip() for v in values) else None
    def address_equal(prefix):
        present = all(any(isinstance(row.get(prefix + f), str) and row[prefix + f].strip() for f in ("address1", "address2")) for row in (left, right))
        fields = ("address1", "address2", "city", "state", "state_id", "zip_code", "country", "country_id")
        return all(left.get(prefix + f) == right.get(prefix + f) for f in fields) if present else None
    return {"exact_business_record_duplicate": canonical(a) == canonical(b),
            "differing_business_field_names": sorted(key for key in a.keys() | b.keys() if canonical(a.get(key)) != canonical(b.get(key))),
            "saved_gstin_equal": saved_equal("gstin"), "saved_party_name_equal": saved_equal("party_name"),
            "saved_display_name_equal": saved_equal("cust_display_name"), "saved_billing_address_equal": address_equal("bill_"),
            "saved_shipping_address_equal": address_equal("shipp_"), "merge_authorized": False,
            "interpretation": "Exact saved-field observations only; no alias, ownership reassignment or merge is inferred"}


def identity(row):
    company, source_id, book = identifier(row.get("companymas_id")), identifier(row.get("id")), str(row.get("sec_acc"))
    return (company, source_id, book) if company and source_id and book in ("0", "1", "2") else None


def compact(values, control):
    result = compare(values, control)
    return {"status": "passed"} if result["status"] == "passed" else result


def child_list(rows, parent, parent_field, dataset, evidence, issues):
    if not isinstance(rows, list):
        return {"status": "unknown", "rows": None, "children": []}
    children, seen, good = [], set(), True
    for index, row in enumerate(rows):
        source_id = identifier(row.get("id")) if isinstance(row, dict) else None
        source_parent = identifier(row.get(parent_field)) if isinstance(row, dict) else None
        valid = bool(source_id and source_parent == parent and source_id not in seen)
        good = good and valid
        if not valid:
            issues.append({"kind": "child_parent_or_id_conflict", "dataset": dataset, "evidence": evidence, "source_row": index})
        seen.add(source_id)
        children.append({"source_id": source_id, "source_parent_id": source_parent, "identity_valid": valid,
                         "original_created_time": row.get("created_time") if isinstance(row, dict) else None,
                         "original_updated_time": row.get("updated_time") if isinstance(row, dict) else None})
    return {"status": "passed" if good else "different", "rows": len(rows), "children": children}


def audit(folder, manifest=None):
    folder = folder.resolve()
    manifest = (folder / "manifest.jsonl").read_bytes() if manifest is None else manifest
    issues = []
    digest, records = selected_records(folder, lambda e: e["path"].startswith(PARTY_ROUTE) or any(pattern.fullmatch(e["path"]) for pattern in (HEADER, DC, FABRIC, VOUCHER)), issues, manifest)
    result = {"version": 1, "import_allowed": False, "archive_completeness": "unknown",
              "selected_evidence_integrity": {"captured_manifest_sha256": digest, "verified_files": len(records), "issues": issues},
              "evidence_manifest": [provenance(r) for r in records], "identity_issues": [], "invoices": [], "voucher_links": [],
              "coverage": {}, "limitations": [
                  "Regular and general invoices have separate native namespaces. Book identity comes from returned sec_acc, never the request or a printed invoice number.",
                  "getFabDetail samplerates.invoice_id is not established as the current invoice parent. Returned native DC references must bind through saved dcinfo.invoice_id; original invoice_id/sample_inv_id are retained without reassignment.",
                  "Quantity and monetary comparisons are exact source diagnostics. UI recalculation with Number/toFixed and conditional tax/sample logic does not establish every historical stored invariant or authorize rounding corrections.",
                  "Explicit kpinvoice/kpgeninvoice voucher references establish candidate identity. Date, party, cancellation and both original invoice amount fields are compared separately; no heuristic invoice-number join is used.",
                  "The r_invoice_value field is not universally a whole-unit or two-place rounding of invoice_value. Its historical posting meaning is unproved; legacy output keys containing rounded are only field-comparison labels, not a rounding assertion.",
                  "No return/credit application, settlement, tax-mode applicability or posting approval is inferred from invoice header totals."]}
    identities = result["identity_issues"]
    headers, dc_records, fabric_records, vouchers = defaultdict(list), defaultdict(list), defaultdict(list), []
    party_masters = defaultdict(list)
    for record in records:
        entry, payload, path = record
        if response_failed(payload):
            identities.append({"kind": "failed_native_response", "evidence": provenance(record)})
            continue
        route, data = entry["path"], payload.get("result")
        if route.startswith(PARTY_ROUTE):
            party_id = identifier(route.removeprefix(PARTY_ROUTE))
            if isinstance(data, dict) and party_id and identifier(data.get("id")) == party_id:
                party_masters[party_id].append((data, record))
            continue
        h, dc, fabric, voucher = (pattern.fullmatch(route) for pattern in (HEADER, DC, FABRIC, VOUCHER))
        if h:
            key = identity(data) if isinstance(data, dict) else None
            if not key or key[1] != identifier(h[2]) or not iso_date(data.get("invoice_date")):
                identities.append({"kind": "invalid_native_invoice_identity_or_date", "evidence": provenance(record)})
                continue
            family = "regular" if h[1] == "inv" else "general"
            if family == "general" and (not iso_date(data.get("inv_date")) or data["inv_date"] != data["invoice_date"]):
                identities.append({"kind": "general_original_date_fields_disagree_or_unknown", "source_key": [family, *key], "evidence": provenance(record)})
            headers[(family, *key)].append((data, record))
        elif dc:
            dc_records[identifier(dc[1])].append(record)
        elif fabric:
            fabric_records[identifier(fabric[2])].append(record)
        elif voucher:
            key = identity(data) if isinstance(data, dict) else None
            if key and key[1] == identifier(voucher[1]) and data.get("acc_ref_type") in ("kpinvoice", "kpgeninvoice"):
                vouchers.append((key, data, record))
    native, by_regular_id = {}, defaultdict(list)
    for key, versions in headers.items():
        if len({json.dumps(data, sort_keys=True, default=str) for data, _ in versions}) != 1:
            identities.append({"kind": "conflicting_native_invoice_versions", "source_key": list(key), "evidence": [provenance(r) for _, r in versions]})
            continue
        native[key] = versions[0]
        if key[0] == "regular":
            by_regular_id[key[2]].append(key)
    for key, (data, record) in native.items():
        family, company, source_id, book = key
        evidence = provenance(record)
        out = {"source_key": list(key), "evidence": evidence, "original_fields": {field: data.get(field) for field in ORIGINAL_FIELDS},
               "original_totals": {field: str(data[field]) if number(data.get(field)) is not None else None for field in TOTAL_FIELDS},
               "original_header_dc_details_rows": len(data["dc_details"]) if isinstance(data.get("dc_details"), list) else None,
               "source_party_id": identifier(data.get("party_id")), "children": {}, "diagnostics": {},
               "diagnostics_are_import_gate_controls": False,
               "saved_dc_children": {"status": "unknown"}, "saved_fabric_children": {"status": "unknown"}}
        result["invoices"].append(out)
        datasets = (("tax_lists", "invoice_id"), ("invoice_add_less", "invoice_id")) if family == "regular" else (("item_details", "inv_id"), ("tax_value", "inv_id"), ("invoice_add_less", "inv_id"))
        for dataset, parent_field in datasets:
            out["children"][dataset] = child_list(data.get(dataset), source_id, parent_field, dataset, evidence, identities)
        taxes = data.get("tax_lists" if family == "regular" else "tax_value")
        tax_dataset = "tax_lists" if family == "regular" else "tax_value"
        if isinstance(taxes, list) and taxes and out["children"][tax_dataset]["status"] == "passed":
            for field in TAX_FIELDS:
                out["diagnostics"]["tax_children_vs_header_" + field] = compact([r.get(field) for r in taxes], data.get(field))
        if family == "general":
            items = data.get("item_details")
            if isinstance(items, list) and out["children"]["item_details"]["status"] == "passed":
                out["diagnostics"]["item_total_vs_total_item_val"] = compact([r.get("total") for r in items], data.get("total_item_val"))
            ingredients = data.get("invoice_add_less")
            signed_amounts = []
            for row in ingredients if isinstance(ingredients, list) else [None]:
                value = number(row.get("amount")) if isinstance(row, dict) else None
                flag = str(row.get("add_less_flag")) if isinstance(row, dict) else None
                signed_amounts.append(value if flag == "1" else value.copy_negate() if flag == "0" and value is not None else None)
            out["diagnostics"]["item_total_plus_signed_add_less_vs_nettotal"] = compact([data.get("total_item_val"), *signed_amounts], data.get("nettotal_value"))
            out["diagnostics"]["net_plus_tax_vs_grandtotal"] = compact([data.get("nettotal_value"), data.get("tax_total_value")], data.get("grandtotal_value"))
            out["diagnostics"]["grandtotal_plus_tcs_vs_invoice_value"] = compact([data.get("grandtotal_value"), data.get("tcs_value")], data.get("invoice_value"))
            continue
        if len(by_regular_id[source_id]) != 1:
            identities.append({"kind": "ambiguous_company_or_book_for_child_request", "source_key": list(key)})
            continue
        # Each capture remains separate. Do not merge child versions from different times.
        dc_versions = dc_records.get(source_id, [])
        if len(dc_versions) != 1:
            out["saved_dc_children"] = {"status": "unknown", "capture_count": len(dc_versions)}
            continue
        dc_record = dc_versions[0]
        root = dc_record[1].get("result")
        dc_rows = root.get("dcinfo") if isinstance(root, dict) else None
        ids, good, dc_details = set(), isinstance(dc_rows, list), []
        for row in dc_rows if isinstance(dc_rows, list) else []:
            row = row if isinstance(row, dict) else {}
            source_dc = identifier(row.get("dc_id")) if isinstance(row, dict) else None
            valid = bool(source_dc and source_dc not in ids and identifier(row.get("invoice_id")) == source_id
                         and identifier(row.get("jobmas_id")) and iso_date(row.get("dc_date")))
            good = good and valid
            ids.add(source_dc)
            dc_details.append({"source_dc_id": source_dc, "source_job_id": identifier(row.get("jobmas_id")),
                               "original_date": row.get("dc_date"), "identity_valid": valid})
        out["saved_dc_children"] = {"status": "passed" if good else "unknown", "rows": len(dc_rows) if isinstance(dc_rows, list) else None,
                                    "evidence": provenance(dc_record), "children": dc_details}
        if not good:
            continue
        out["diagnostics"]["saved_dc_kgs_vs_header"] = compact([r.get("dlvry_kgs") for r in dc_rows], data.get("total_kgs"))
        out["diagnostics"]["saved_dc_rolls_vs_header"] = compact([r.get("dlvry_rolls") for r in dc_rows], data.get("total_rolls_pcs"))
        fabric_versions = fabric_records.get(source_id, [])
        if len(fabric_versions) != 1:
            out["saved_fabric_children"] = {"status": "unknown", "capture_count": len(fabric_versions)}
            continue
        fab_record = fabric_versions[0]
        requested = FABRIC.fullmatch(fab_record[0]["path"])[1].split(",")
        requested_ids = {identifier(value) for value in requested}
        root = fab_record[1].get("result")
        rows = root.get("samplerates") if isinstance(root, dict) else None
        good = isinstance(rows, list) and requested_ids == ids and None not in requested_ids
        seen_details, observations = set(), []
        for row in rows if isinstance(rows, list) else []:
            row = row if isinstance(row, dict) else {}
            valid = isinstance(row, dict) and identifier(row.get("jobmas_id")) and identifier(row.get("jobfabric_id"))
            refs = row.get("dc_list") if isinstance(row, dict) else None
            valid = valid and isinstance(refs, list) and bool(refs)
            reference_ids = []
            for ref in refs if isinstance(refs, list) else []:
                dc_id = identifier(ref.get("dc_id")) if isinstance(ref, dict) else None
                det_id = identifier(ref.get("dc_det_id")) if isinstance(ref, dict) else None
                correct_job = any(identifier(dc_row.get("dc_id")) == dc_id and identifier(dc_row.get("jobmas_id")) == identifier(row.get("jobmas_id")) for dc_row in dc_rows)
                valid = valid and bool(dc_id in ids and det_id and (dc_id, det_id) not in seen_details and correct_job)
                seen_details.add((dc_id, det_id))
                reference_ids.append([dc_id, det_id])
            good = good and bool(valid)
            observations.append({"source_job_id": identifier(row.get("jobmas_id")), "source_jobfabric_id": identifier(row.get("jobfabric_id")),
                                 "original_invoice_id_field": row.get("invoice_id"), "original_sample_inv_id_field": row.get("sample_inv_id"),
                                 "dc_detail_references": reference_ids, "identity_valid": bool(valid)})
        out["saved_fabric_children"] = {"status": "passed" if good else "unknown", "rows": len(rows) if isinstance(rows, list) else None,
                                        "evidence": provenance(fab_record), "children": observations,
                                        "semantic_role": "DC-linked fabric helper context; not a proven native historical invoice-line entity"}
        if good:
            out["diagnostics"]["fabric_value_vs_header_total_value"] = compact([r.get("fabric_value") for r in rows], data.get("total_value"))
            out["diagnostics"]["fabric_value_vs_header_total_value"]["meaning"] = "UI sums fabric_value into totaldc_value; its alias to persisted total_value is unproved"
            out["diagnostics"]["fabric_dc_detail_kgs_vs_header"] = compact([ref.get("dlvry_kgs") for row in rows for ref in row["dc_list"]], data.get("total_kgs"))
    expected = defaultdict(list)
    for voucher_key, voucher, record in vouchers:
        family = "regular" if voucher["acc_ref_type"] == "kpinvoice" else "general"
        key = (family, voucher_key[0], identifier(voucher.get("acc_ref_code")), voucher_key[2])
        expected[key].append(voucher_key)
        link = {"invoice_key": list(key), "voucher_key": list(voucher_key), "evidence": provenance(record),
                "reference_field": voucher["acc_ref_type"], "status": "unknown_missing_native_invoice"}
        result["voucher_links"].append(link)
        if key not in native:
            continue
        invoice, inv_record = native[key]
        amount = compact([invoice.get("invoice_value")], voucher.get("amt"))
        date_equal = bool(iso_date(voucher.get("v_date")) and voucher.get("v_date") == invoice.get("invoice_date"))
        party_equal = bool(identifier(voucher.get("party_id")) and identifier(voucher.get("party_id")) == identifier(invoice.get("party_id")))
        cancelled_equal = None if "cancelled" not in voucher or "cancelled" not in invoice else str(voucher["cancelled"]) == str(invoice["cancelled"])
        link.update({"native_invoice_evidence": provenance(inv_record), "original_date_agrees": date_equal,
                     "source_party_agrees": party_equal, "amount": amount,
                     "original_invoice_party_id": identifier(invoice.get("party_id")), "original_voucher_party_id": identifier(voucher.get("party_id")),
                     "original_invoice_value": str(invoice["invoice_value"]) if number(invoice.get("invoice_value")) is not None else None,
                     "original_rounded_invoice_value": str(invoice["r_invoice_value"]) if number(invoice.get("r_invoice_value")) is not None else None,
                     "original_r_invoice_value": str(invoice["r_invoice_value"]) if number(invoice.get("r_invoice_value")) is not None else None,
                     "r_invoice_value_semantics": "unproven_source_field_not_assumed_rounded",
                     "original_voucher_amount": str(voucher["amt"]) if number(voucher.get("amt")) is not None else None,
                     "original_invoice_updated_time": invoice.get("updated_time"), "original_voucher_updated_time": voucher.get("updated_time"),
                     "rounded_source_invoice_amount_diagnostic": compact([invoice.get("r_invoice_value")], voucher.get("amt")),
                     "source_cancelled_agrees": cancelled_equal,
                     "status": "passed" if date_equal and party_equal and cancelled_equal is not False and amount["status"] == "passed" else "identity_or_original_field_difference"})
    result["reference_collisions"] = [{"invoice_key": list(key), "voucher_keys": [list(v) for v in values]} for key, values in expected.items() if len(set(values)) > 1]
    result["party_relationship_observations"] = []
    for link in result["voucher_links"]:
        if link.get("source_party_agrees") is not False:
            continue
        left, right = (party_masters.get(link[field], []) for field in ("original_invoice_party_id", "original_voucher_party_id"))
        item = {"invoice_key": link["invoice_key"], "voucher_key": link["voucher_key"],
                "invoice_party_id": link["original_invoice_party_id"], "voucher_party_id": link["original_voucher_party_id"],
                "status": "unknown", "invoice_master_evidence": [provenance(r) for _, r in left],
                "voucher_master_evidence": [provenance(r) for _, r in right]}
        if left and right:
            comparisons = [compare_party_business(a, b) for a, _ in left for b, _ in right]
            if len({json.dumps(c, sort_keys=True) for c in comparisons}) == 1:
                item.update(status="observed", **comparisons[0])
        result["party_relationship_observations"].append(item)
    for family in ("regular", "general"):
        for company in ("1", "2", "3", "4"):
            for book in ("0", "1"):
                expected_keys = {key for key in expected if key[0] == family and key[1] == company and key[3] == book}
                native_keys = {key for key in native if key[0] == family and key[1] == company and key[3] == book}
                result["coverage"]["/".join((family, company, book))] = {"native_headers": len(native_keys), "explicit_voucher_reference_keys": len(expected_keys),
                    "referenced_native_headers_acquired": len(expected_keys & native_keys), "referenced_headers_missing": [list(k) for k in sorted(expected_keys - native_keys)],
                    "native_headers_without_reference": [list(k) for k in sorted(native_keys - expected_keys)], "scope_completeness": "unknown"}
    result["summary"] = {"native_invoices": len(native), "voucher_references": len(vouchers),
                         "voucher_link_statuses": dict(Counter(link["status"] for link in result["voucher_links"])),
                         "diagnostic_statuses": dict(Counter(check["status"] for invoice in result["invoices"] for check in invoice["diagnostics"].values()))}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report_source", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if destination.suffix != ".json" or destination.is_relative_to(args.report_source.resolve()):
        parser.error("Write the private audit outside the read-only archive.")
    captured = (args.report_source / "manifest.jsonl").read_bytes()
    result = audit(args.report_source, captured)
    write_private(destination.with_suffix(".manifest.jsonl"), captured.decode("utf-8"))
    write_private(destination, json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"import_allowed": False, **result["summary"]}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
