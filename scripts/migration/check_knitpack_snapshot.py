#!/usr/bin/env python3
"""Check an existing Knitpack archive offline; never imports or changes source data.

Usage: python3 scripts/migration/check_knitpack_snapshot.py SOURCE --report PRIVATE_REPORT.json
Exit 0 means the files/identities checked are valid, not that the source export is complete.
Exit 2 means damaged evidence, an identity discrepancy, or malformed input was found.
Only counts and private file references are emitted. Customer rows and API messages are not.
"""
import argparse
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urlsplit


INDEX_ROUTE = "knitpack/inward/getInwardListForProgChart"
DETAIL_ROUTE = "knitpack/inward/getInward/"


def response_failed(payload):
    """Keep explicit failure envelopes as archive evidence, including stale-shaped results."""
    return ("rc_error" in payload or payload.get("isLogin") is False
            or str(payload.get("mode", "")).lower() in ("error", "failed", "failure"))


def identifier(value):
    if isinstance(value, bool):
        return None
    text = str(value)
    return str(int(text)) if re.fullmatch(r"[0-9]{1,18}", text) and int(text) > 0 else None


def check(source):
    source = source.resolve()
    issues = {group: defaultdict(list) for group in ("integrity", "identity")}
    manifest = source / "manifest.jsonl"
    records, verified_files, referenced = [], set(), set()
    def issue(group, kind, path):
        issues[group][kind].append(str(path))

    try:
        if manifest.is_symlink():
            raise ValueError()
        manifest_bytes = manifest.read_bytes()
        lines = manifest_bytes.decode("utf-8").splitlines()
    except (OSError, UnicodeError, ValueError):
        lines, manifest_bytes = [], b""
        issue("integrity", "invalid_manifest", manifest)
    for number, line in enumerate(lines, 1):
        ref = f"{manifest}#line={number}"
        try:
            entry = json.loads(line)
            if not isinstance(entry, dict) or not isinstance(entry.get("path"), str) or not entry["path"]:
                issue("integrity", "invalid_manifest_entry", ref)
                continue
            relative = Path(entry["file"])
            if relative.is_absolute() or not relative.parts or ".." in relative.parts:
                raise ValueError()
            path = source / relative
            if any(parent.is_symlink() for parent in [path, *path.parents] if parent != source.parent):
                raise ValueError()
            if not path.resolve().is_relative_to(source):
                raise ValueError()
        except (ValueError, KeyError, TypeError):
            issue("integrity", "unsafe_paths", ref)
            continue
        referenced.add(path)
        try:
            data = path.read_bytes()
        except OSError:
            issue("integrity", "missing_files", path)
            continue
        size_ok = type(entry.get("bytes")) is int and entry["bytes"] == len(data)
        hash_ok = entry.get("sha256") == hashlib.sha256(data).hexdigest()
        if not size_ok:
            issue("integrity", "size_mismatch", path)
        if not hash_ok:
            issue("integrity", "hash_mismatch", path)
        if not size_ok or not hash_ok:
            continue
        try:
            response = json.loads(data)
            if not isinstance(response, dict):
                raise ValueError()
        except (ValueError, UnicodeError):
            issue("integrity", "invalid_json", path)
            continue
        if path in verified_files:
            issue("integrity", "duplicate_manifest_paths", path)
            continue
        verified_files.add(path)
        records.append((entry, path, response))
    for path in source.rglob("*"):
        if (path.is_file() or path.is_symlink()) and path != manifest and path not in referenced:
            issue("integrity", "unmanifested_files", path)

    successful, failures = [], []
    for entry, path, response in records:
        if "result" not in response or response_failed(response):
            failures.append(str(path))
        else:
            successful.append((entry, path, response["result"]))

    years, known_companies = {}, set()
    for entry, path, result in successful:
        route = urlsplit(entry.get("path", "")).path
        if route == "masters/masters/listCompany" and isinstance(result, list):
            known_companies.update(identifier(row.get("id")) for row in result if isinstance(row, dict))
        if route == "knitpack/masters/getFinYearSB" and isinstance(result, list):
            for row in result:
                if not isinstance(row, dict):
                    continue
                match = re.fullmatch(r"(\d{2}|\d{4})-(\d{2}|\d{4})", str(row.get("name", "")))
                year_id = identifier(row.get("value"))
                if not match or not year_id:
                    issue("identity", "invalid_fiscal_year_catalogue", path)
                    continue
                begin, end = (int(v) + (2000 if len(v) == 2 else 0) for v in match.groups())
                if end != begin + 1:
                    issue("identity", "invalid_fiscal_year_catalogue", path)
                    continue
                years[year_id] = (date(begin, 4, 1), date(end, 3, 31))
    known_companies.discard(None)
    indexed, index_paths, index_owners = defaultdict(set), defaultdict(set), defaultdict(set)
    series, headers = defaultdict(dict), defaultdict(list)
    index_observations = 0
    full, all_full, full_paths, full_identities = defaultdict(set), defaultdict(set), defaultdict(list), defaultdict(set)
    for entry, path, result in successful:
        route = urlsplit(entry.get("path", "")).path
        if route == INDEX_ROUTE:
            try:
                filters = entry["filters"]
                params = filters["getParams"]
                params = json.loads(params) if isinstance(params, str) else params
                company = identifier(params["companymas_id"])
                rows = result["items"]
                if not company or not isinstance(rows, list):
                    raise ValueError()
                if filters.get("searchKeyword") or params.get("type") != "all" or params.get("partymas_id") not in (None, "", "null"):
                    issue("identity", "restricted_index_filter", path)
                    continue
                start, limit = int(filters["limit_from"]), int(filters["limit_to"])
                if start < 0 or limit <= 0 or len(rows) > limit:
                    raise ValueError()
            except (KeyError, TypeError, ValueError):
                issue("identity", "invalid_index", path)
                continue
            index_paths[company].add(str(path))
            indexed[company]  # An empty company index is still evidence.
            key = (company, str(params.get("from_date", "")), str(params.get("to_date", "")), limit)
            series[key][start] = len(rows)
            for row in rows:
                source_id = identifier(row.get("id")) if isinstance(row, dict) else None
                if not source_id:
                    issue("identity", "invalid_index_id", path)
                    continue
                index_observations += 1
                indexed[company].add(source_id)
                index_owners[source_id].add(company)
        elif route == "knitpack/inward/getJobOrderList" and isinstance(result, dict):
            for row in result.get("data", []):
                if isinstance(row, dict) and identifier(row.get("id")):
                    headers[identifier(row["id"])].append((row, str(path)))

    full_records = []
    for entry, path, result in successful:
        route = urlsplit(entry.get("path", "")).path
        if not route.startswith(DETAIL_ROUTE):
            continue
        source_id = identifier(result.get("id")) if isinstance(result, dict) else None
        company = identifier(result.get("companymas_id")) if isinstance(result, dict) else None
        year = identifier(result.get("finyear")) if isinstance(result, dict) else None
        if not source_id or not company or not isinstance(result.get("job_fabrics"), list):
            issue("identity", "invalid_full_document", path)
            continue
        all_full[company].add(source_id)
        full_paths[source_id].append(str(path))
        full_identities[source_id].add((company, year))
        valid = True
        def invalid(kind):
            nonlocal valid
            valid = False
            issue("identity", kind, path)
        if source_id != identifier(route[len(DETAIL_ROUTE):]):
            invalid("requested_id_mismatch")
        if (known_companies and company not in known_companies) or (index_owners[source_id] and index_owners[source_id] != {company}):
            invalid("company_mismatch")
        try:
            job_date = date.fromisoformat(str(result.get("jobdate", ""))[:10])
        except ValueError:
            job_date = None
            invalid("invalid_job_date")
        if year not in years:
            invalid("unknown_fiscal_year")
        elif job_date and not years[year][0] <= job_date <= years[year][1]:
            invalid("fiscal_year_date_mismatch")
        for header, header_path in headers[source_id]:
            if identifier(header.get("companymas_id")) != company or identifier(header.get("finyear")) != year:
                invalid("indexed_header_identity_mismatch")
            if str(header.get("jobdate", ""))[:10] != str(result.get("jobdate", ""))[:10]:
                invalid("indexed_header_date_mismatch")
        full_records.append((company, source_id, year, str(path), valid))
    for source_id, owners in index_owners.items():
        if len(owners) > 1:
            for company in owners:
                for path in index_paths[company]:
                    issue("identity", "cross_company_index_id", path)
    for source_id, identities in full_identities.items():
        if len(identities) > 1:
            for path in full_paths[source_id]:
                issue("identity", "conflicting_full_identity", path)
    by_year = defaultdict(Counter)
    for company, source_id, year, path, valid in full_records:
        if valid and len(full_identities[source_id]) == 1 and source_id not in full[company]:
            full[company].add(source_id)
            by_year[company][year] += 1
    company_report = {}
    for company in sorted(set(indexed) | set(all_full) | known_companies, key=int):
        terminated = False
        for key, pages in series.items():
            if key[0] != company:
                continue
            cursor = 0
            while cursor in pages and pages[cursor] == key[3]:
                cursor += key[3]
            terminated |= cursor in pages and pages[cursor] < key[3]
        company_report[company] = {
            "indexed_distinct_jobs": len(indexed[company]),
            "archived_structural_full_distinct_jobs": len(all_full[company]),
            "verified_full_distinct_jobs": len(full[company]),
            "indexed_without_verified_full": len(indexed[company] - full[company]),
            "verified_full_not_in_historical_index": len(full[company] - indexed[company]),
            "verified_full_by_fiscal_year_id": dict(sorted(by_year[company].items())),
            "observed_index_enumeration_terminated": terminated,
            "index_evidence_paths": sorted(index_paths[company]),
        }
    integrity_keys = ("unsafe_paths", "missing_files", "size_mismatch", "hash_mismatch", "invalid_json",
                      "duplicate_manifest_paths", "unmanifested_files", "invalid_manifest")
    identity_keys = ("requested_id_mismatch", "company_mismatch", "fiscal_year_date_mismatch")
    grouped = {}
    for group, required in (("integrity", integrity_keys), ("identity", identity_keys)):
        grouped[group] = {key: {"count": len(paths), "paths": sorted(set(paths))}
                          for key in sorted(set(required) | set(issues[group]))
                          for paths in [issues[group][key]]}
    valid = not any(issues["integrity"].values())
    identity_valid = not any(issues["identity"].values())
    duplicate_ids = [source_id for source_id, paths in full_paths.items() if len(paths) > 1]
    return {"version": 1, "checked_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_directory": str(source), "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
            "manifest_entries": len(lines), "verified_response_files": len(verified_files),
            "integrity": {"valid": valid, **grouped["integrity"]},
            "identity": {"valid": identity_valid, **grouped["identity"]},
            "failed_api_responses": {"count": len(failures), "paths": sorted(failures)},
            "companies": company_report,
            "duplicates": {"index_observations": index_observations - sum(map(len, indexed.values())),
                           "full_source_ids": {"count": len(duplicate_ids),
                               "paths": sorted(path for source_id in duplicate_ids for path in full_paths[source_id])}},
            "all_source_data_complete": False,
            "limitations": ["Only manifested historical job indices and full getInward job records are reconciled.",
                            "A terminal selector page proves only the observed query ended, not that the source includes every job.",
                            "Zero indexed records is not proof that a company is empty.",
                            "Full job responses do not prove receipt, production, invoice, payment, stock, attachment or audit-history completeness.",
                            "Fiscal labels are interpreted as Indian April-to-March financial years; independent source export remains necessary.",
                            "Hashes verify the archive against its manifest, not authenticity of the original service or a point-in-time database backup."]}


def readable(report):
    lines = ["# Private offline archive audit", "", "The customer migration is incomplete.", "",
             f"Checked: {report['checked_at_utc']}",
             f"Manifested responses: {report['manifest_entries']}. Verified files: {report['verified_response_files']}.",
             f"File integrity: {'passed' if report['integrity']['valid'] else 'failed'}.",
             f"Job identity checks: {'passed' if report['identity']['valid'] else 'failed'}.",
             f"Failed API responses excluded: {report['failed_api_responses']['count']}.", "",
             "| Source company ID | Historical indexed jobs | Verified full jobs | Indexed jobs missing verified full records |",
             "| --- | ---: | ---: | ---: |"]
    for company, values in report["companies"].items():
        lines.append(f"| {company} | {values['indexed_distinct_jobs']} | {values['verified_full_distinct_jobs']} | {values['indexed_without_verified_full']} |")
    lines.extend(["", f"Repeated index observations: {report['duplicates']['index_observations']} (overlapping exports are deduplicated).",
                  f"Duplicated full source IDs: {report['duplicates']['full_source_ids']['count']}.", "", "## Scope and limits", ""])
    lines.extend("- " + text for text in report["limitations"])
    lines.extend(["", "## Discrepancy evidence", ""])
    for group in ("integrity", "identity"):
        for key, finding in report[group].items():
            if isinstance(finding, dict) and finding["count"]:
                lines.append(f"- {group}: {key}: {finding['count']}.")
                lines.extend("  - " + path for path in finding["paths"])
    if report["failed_api_responses"]["count"]:
        lines.append(f"- Failed API responses: {report['failed_api_responses']['count']}.")
        lines.extend("  - " + path for path in report["failed_api_responses"]["paths"])
    for company, values in report["companies"].items():
        if values["indexed_without_verified_full"]:
            lines.append(f"- Company {company}: {values['indexed_without_verified_full']} indexed jobs lack verified full records; index evidence:")
            lines.extend("  - " + path for path in values["index_evidence_paths"])
    lines.extend(["", "No source files were edited. No network calls or import operations were performed.", ""])
    return "\n".join(lines)


def write_private(destination, content):
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=".snapshot-check-", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    destination = args.report.resolve()
    if not args.source.is_dir() or destination.is_relative_to(args.source.resolve()) or destination.suffix != ".json":
        parser.error("Use an existing archive and a report path outside that read-only archive.")
    report = check(args.source)
    write_private(destination, json.dumps(report, indent=2) + "\n")
    write_private(destination.with_suffix(".md"), readable(report))
    print(json.dumps({"integrity_valid": report["integrity"]["valid"],
                      "identity_valid": report["identity"]["valid"],
                      "manifest_entries": report["manifest_entries"],
                      "failed_api_responses": report["failed_api_responses"]["count"],
                      "all_source_data_complete": False, "report": str(destination)}))
    return 0 if report["integrity"]["valid"] and report["identity"]["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
