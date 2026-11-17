#!/usr/bin/env python3
"""Preserve and inspect captured Tally text offline; no source access or import.

Unnamed semicolon columns are compared to an explicit candidate mapping. Even
an exact unique tuple is corroboration, not a source document ID or a GL export.
"""
import argparse
from collections import Counter, defaultdict
from datetime import date
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from check_knitpack_snapshot import identifier, response_failed, write_private
from inventory_knitpack_reports import records
from reconcile_knitpack_balances import number


AMOUNTS = ("amt", "taxable_value", "cgst_value", "sgst_value", "igst_value")
HEADER_FIELDS = ("id", "companymas_id", "sec_acc", "ref_no", "v_date", "party_id", *AMOUNTS, "finyear", "acc_type", "cancelled")


def iso_date(value):
    try:
        return value if isinstance(value, str) and date.fromisoformat(value).isoformat() == value else None
    except ValueError:
        return None


def audit(folder, manifest=None):
    folder = folder.resolve()
    manifest = (folder / "manifest.jsonl").read_bytes() if manifest is None else manifest
    issues, exports, texts = [], [], {}
    versions, parties, register_names = defaultdict(dict), defaultdict(set), defaultdict(set)
    for line, entry, payload in records(folder, manifest, issues, "reports"):
        if response_failed(payload):
            continue
        value = payload.get("result")
        if isinstance(value, dict) and isinstance(value.get("tally_txt"), str):
            company = identifier((entry.get("filters") or {}).get("companymas_id"))
            text = value["tally_txt"]
            raw = text.encode("utf-8")
            digest = hashlib.sha256(raw).hexdigest()
            filename = "company-" + (company or "unresolved") + "-" + digest[:12] + ".txt"
            texts[filename] = raw
            exports.append({"source_manifest_line": line, "source_file": entry["file"], "source_response_sha256": entry["sha256"],
                            "source_json_pointer": "/result/tally_txt", "request_company_id": company,
                            "request_date_range": {k: (entry.get("filters") or {}).get(k) for k in ("from_date", "to_date")},
                            "derived_file": filename, "derived_sha256": digest, "derived_utf8_bytes": len(raw),
                            "source_string_codepoints": len(text), "complete": False, "book_scope": "not_declared_in_export",
                            "company_scope": "request_context_only; export has no explicit company ID",
                            "exact_text_preserved": True, "explicit_ledger_leg_records": 0, "parsed": False})
        roots = payload.get("root")
        roots = roots if isinstance(roots, list) else [roots] if isinstance(roots, dict) else []
        for root in roots:
            if not isinstance(root, dict):
                continue
            company_info = root.get("company_info")
            context = identifier(company_info.get("id")) if isinstance(company_info, dict) else identifier((entry.get("filters") or {}).get("companymas_id"))
            for name in ("party", "party_info"):
                rows = root.get(name)
                rows = [rows] if isinstance(rows, dict) else rows if isinstance(rows, list) else []
                for row in rows:
                    if isinstance(row, dict) and identifier(row.get("id")) and isinstance(row.get("party_name"), str):
                        parties[(context, identifier(row["id"]))].add(row["party_name"])
            for row in root.get("statement", []) if isinstance(root.get("statement"), list) else []:
                if isinstance(row, dict) and identifier(row.get("id")) and isinstance(row.get("party_name"), str):
                    register_names[(context, identifier(row["id"]), str(row.get("ref_no")), str(row.get("v_date")), identifier(row.get("party_id")))].add(row["party_name"])
            native = root.get("ledg_list") if isinstance(root.get("ledg_list"), list) else []
            if isinstance(root.get("voucher"), dict):
                native = [*native, root["voucher"]]
            for row in native:
                if not isinstance(row, dict):
                    continue
                company, voucher, book = identifier(row.get("companymas_id")), identifier(row.get("id")), str(row.get("sec_acc"))
                if not company or not voucher or book not in ("0", "1", "2"):
                    continue
                header = {k: row.get(k) for k in HEADER_FIELDS}
                signature = tuple(number(header[k]) if k in AMOUNTS else str(header[k]) for k in HEADER_FIELDS)
                versions[(company, voucher, book)][signature] = header
                if isinstance(root.get("party"), dict) and identifier(root["party"].get("id")) == identifier(row.get("party_id")):
                    label = root["party"].get("party_name")
                    if isinstance(label, str):
                        parties[(company, identifier(row["party_id"]))].add(label)
    headers = {key: next(iter(rows.values())) for key, rows in versions.items() if len(rows) == 1}
    candidates = defaultdict(set)
    for key, header in headers.items():
        company, voucher, _ = key
        values = tuple(number(header[field]) for field in AMOUNTS)
        source_date = iso_date(header.get("v_date"))
        if any(value is None for value in values) or not source_date or not isinstance(header.get("ref_no"), str):
            continue
        party = identifier(header.get("party_id"))
        labels = parties.get((company, party), set()) | parties.get((None, party), set()) | register_names.get((company, voucher, header["ref_no"], source_date, party), set())
        for label in labels:
            candidates[(company, label, header["ref_no"], source_date, *values)].add(key)

    for export in exports:
        text = texts[export["derived_file"]].decode("utf-8")
        if not text:
            export.update({"format": "empty_text", "nonblank_records": 0})
            continue
        if text.lstrip().startswith("<"):
            if re.search(r"<!\s*(DOCTYPE|ENTITY)\b", text, re.I):
                export["format"] = "xml_rejected_declaration"
                continue
            try:
                tree = ET.fromstring(text)
            except ET.ParseError:
                export["format"] = "xml_invalid"
                continue
            tags = Counter(node.tag.rsplit("}", 1)[-1].upper() for node in tree.iter())
            export.update({"format": "xml", "parsed": True, "xml_voucher_elements": tags["VOUCHER"],
                           "explicit_ledger_leg_records": tags["ALLLEDGERENTRIES.LIST"] + tags["LEDGERENTRIES.LIST"],
                           "xml_element_names": sorted(tags)})
            continue
        lines = text.splitlines()
        rows = [(index, line.split(";")) for index, line in enumerate(lines, 1) if line]
        stats, dates, matches, unmatched, fingerprints = Counter(), [], set(), [], Counter()
        field_counts = Counter(len(row) for _, row in rows)
        company = export["request_company_id"]
        for index, row in rows:
            if len(row) != 9 or row[-1] != "" or not row[0] or not row[1] or not iso_date(row[2]):
                stats["invalid_record_rows"] += 1
                continue
            amounts = tuple(number(value) for value in row[3:8])
            if any(value is None for value in amounts):
                stats["invalid_record_rows"] += 1
                continue
            dates.append(row[2])
            fingerprints[hashlib.sha256(";".join(row).encode()).hexdigest()] += 1
            keys = candidates.get((company, row[0], row[1], row[2], *amounts), set())
            if len(keys) == 1:
                stats["unique_native_key_rows"] += 1
                matches.update(keys)
            else:
                kind = "ambiguous_native_key_rows" if keys else "unmatched_rows"
                stats[kind] += 1
                unmatched.append({"line": index, "kind": kind, "exact_candidate_count": len(keys)})
        company_keys = {key for key in headers if key[0] == company}
        dates.sort()
        export.update({"format": "semicolon_text_nine_fields", "parsed": True, "nonblank_records": len(rows),
                       "blank_lines": len(lines) - len(rows), "field_count_observations": dict(field_counts),
                       "invalid_record_rows": stats["invalid_record_rows"], "distinct_exact_records": len(fingerprints),
                       "repeated_exact_record_observations": sum(count - 1 for count in fingerprints.values()),
                       "original_dates": {"min": dates[0] if dates else None, "max": dates[-1] if dates else None,
                                          "calendar_year_observations": dict(sorted(Counter(value[:4] for value in dates).items()))},
                       "exact_corroboration": {**{k: stats[k] for k in ("unique_native_key_rows", "ambiguous_native_key_rows", "unmatched_rows")},
                           "distinct_native_keys_matched": len(matches), "matched_books": sorted({key[2] for key in matches}),
                           "matched_native_fiscal_ids": sorted({str(headers[key].get("finyear")) for key in matches}),
                           "matched_native_account_types": dict(Counter(str(headers[key].get("acc_type")) for key in matches)),
                           "native_keys_without_unique_export_match_by_book": dict(Counter(key[2] for key in company_keys - matches)),
                           "exceptions": unmatched}})
    return {"version": 1, "import_allowed": False, "manifest_sha256": hashlib.sha256(manifest).hexdigest(),
            "manifest_entries": len(manifest.splitlines()), "integrity": {"valid": not issues, "issues": issues},
            "native_header_keys": len(versions), "native_keys_with_conflicting_comparison_fields": sum(len(v) > 1 for v in versions.values()),
            "exports": exports, "candidate_column_mapping": {"1": "party display name", "2": "ref_no", "3": "v_date", **{str(i + 4): name for i, name in enumerate(AMOUNTS)}, "9": "empty trailing field"},
            "limitations": [
                "The semicolon columns have no header/schema declaration. Candidate mapping is tested by exact equality only; it is not asserted as an official export contract.",
                "Source company is request context; the text contains no explicit company, book, native voucher ID, account IDs, debit/credit legs or allocation links.",
                "An exact tuple may corroborate one native key but does not create a stable export identity. Ambiguous matches are not guessed or deduplicated.",
                "Matched native books and fiscal IDs describe corroborated rows only; they do not certify the scope of every export row or source completeness.",
                "Unmatched native keys can reflect an intentionally narrower export; no omission cause or source correction is inferred.",
                "No opening/closing balance, GL equality, settlement allocation completeness, attachment coverage or operational import is established.",
                "Text is preserved exactly after JSON decoding and UTF-8 encoding. No text is executed; XML DTD/entity declarations are rejected and no external resolution is used."]}, texts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(args.reports.resolve()):
        parser.error("Write derived evidence outside the read-only report archive.")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    output.chmod(0o700)
    manifest = (args.manifest or args.reports / "manifest.jsonl").read_bytes()
    report, texts = audit(args.reports, manifest)
    for filename, raw in texts.items():
        write_private(output / filename, raw.decode("utf-8"))
        if (output / filename).read_bytes() != raw:
            raise ValueError("Derived text bytes changed.")
    write_private(output / "tally-audit.manifest.jsonl", manifest.decode("utf-8"))
    write_private(output / "tally-audit.json", json.dumps(report, indent=2) + "\n")
    print(json.dumps({"exports": len(report["exports"]), "native_header_keys": report["native_header_keys"],
                      "integrity_issue_count": len(report["integrity"]["issues"]), "import_allowed": False}))
    return 0 if report["integrity"]["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
