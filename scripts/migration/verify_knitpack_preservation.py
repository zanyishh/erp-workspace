#!/usr/bin/env python3
"""Recheck the frozen Knitpack capture, provenance and saved MariaDB dump offline."""
import argparse
import base64
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re

from check_knitpack_snapshot import response_failed
from import_knitpack_history import apply_overlay, contracts, preflight


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(path.read_bytes())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def archives(base, scope, coverage):
    evidence = {}
    totals = {}
    histories, history_requests, ledgers = set(), set(), set()
    for kind, expected in (("source", coverage["original_manifest_sha256"]), ("report", scope["manifest_sha256"])):
        folder = base / (kind + "-snapshot")
        manifest = (folder / "manifest.jsonl").read_bytes()
        frozen = base / "verification" / (folder.name + "-final.manifest.jsonl")
        require(manifest == frozen.read_bytes() and digest(manifest) == expected, "Frozen manifest differs.")
        names = {p.name for p in folder.iterdir()} - {"manifest.jsonl"}
        total_bytes = 0
        indexed = set()
        for line in manifest.splitlines():
            entry = json.loads(line)
            name = entry["file"]
            require(name in names, "Missing, duplicate or unexpected manifest path.")
            names.remove(name)
            path = folder / name
            require(path.is_file() and not path.is_symlink(), "Unexpected response file type.")
            require(not path.stat().st_mode & 0o077, "Response permissions differ from private capture.")
            raw = path.read_bytes()
            require(len(raw) == entry["bytes"] and digest(raw) == entry["sha256"], "Response size or digest differs.")
            evidence[(name, entry["sha256"])] = {"path": path, "bytes": len(raw)}
            total_bytes += len(raw)
            route, envelope = entry["path"], json.loads(raw)
            if "JobTransHistory/" in route:
                history_requests.add(str(entry["filters"]["jobmas_id"]))
            if not isinstance(envelope, dict) or response_failed(envelope):
                continue
            root = envelope.get("root")
            if route.endswith("/getInwardListForProgChart") and isinstance(envelope.get("result"), dict):
                indexed.update(str(row["id"]) for row in envelope["result"]["items"])
            elif "JobTransHistory/" in route and isinstance(root, dict):
                job = str(entry["filters"]["jobmas_id"])
                if any(str(row.get("id")) == job for row in root.get("order_inward", [])):
                    histories.add(job)
            elif "ViewJobLedgerreport/" in route and isinstance(root, dict) and isinstance(root.get("job"), dict):
                job = str(entry["filters"]["id"])
                if str(root["job"].get("id")) == job:
                    ledgers.add(job)
        require(not names, "Unmanifested response entries.")
        totals[kind] = {"files": len(manifest.splitlines()), "bytes": total_bytes,
                        "manifest_sha256": expected, "distinct_indexed_jobs": len(indexed)}
    return evidence, totals, {"matched_histories": len(histories), "missing_histories": len(history_requests - histories),
                             "matched_ledger_headers": len(ledgers)}


def verify_assets(base, evidence):
    sizes = []
    folder = base / "original-assets"
    for item in read_json(folder / "manifest.json"):
        value = read_json(evidence[(item["source_file"], item["source_sha256"])]["path"])
        for field in item["source_field"].split("."):
            value = value[field]
        require(Path(item["file"]).name == item["file"], "Unexpected asset path.")
        raw = (folder / item["file"]).read_bytes()
        require(raw == base64.b64decode(value.split(",")[-1], validate=True)
                and digest(raw) == item["sha256"] and len(raw) == item["bytes"], "Decoded asset differs.")
        sizes.append(len(raw))
    return sizes


_DUMP_CELL = re.compile(r"(?:'([^'\\]*(?:(?:\\.|'')[^'\\]*)*)'|(NULL|-?\d+(?:\.\d+)?))(?=,|$)")
_ESCAPE = re.compile(r"\\(.)|''")
_ESCAPED = {"0": "\0", "b": "\b", "n": "\n", "r": "\r", "t": "\t", "Z": "\x1a"}


def dump_cells(source):
    """Decode the dump's SQL literals, keeping NULL distinct from the text 'NULL'."""
    offset = 0
    while True:
        match = _DUMP_CELL.match(source, offset)
        require(match is not None, "Unexpected dump literal.")
        string, bare = match.groups()
        if string is None:
            yield None if bare == "NULL" else bare
        else:
            yield _ESCAPE.sub(lambda m: _ESCAPED.get(m[1], m[1]) if m[1] else "'", string)
        if match.end() == len(source):
            return
        offset = match.end() + 1


def verify_dump(path, expected, scope_name):
    """Read this dump's extended-insert format as text. Never execute a SQL statement."""
    table = "`tabHistorical Business Record`"
    columns = []
    schema = inserting = False
    remaining = expected.copy()
    mismatched_fields = Counter()
    mismatched_families = Counter()
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("CREATE TABLE " + table + " ("):
                schema = True
            elif schema:
                if line.startswith(")"):
                    schema = False
                elif line.lstrip().startswith("`"):
                    columns.append(line.split("`", 2)[1])
            elif line.startswith("INSERT INTO " + table + " VALUES"):
                require(not inserting and line.strip() == "INSERT INTO " + table + " VALUES",
                        "Unexpected dump insert format.")
                inserting = True
            elif inserting:
                line = line.rstrip()
                require(line.startswith("(") and line[-2:] in ("),", ");"), "Unexpected dump row format.")
                inserting = line.endswith(",")
                cells = list(dump_cells(line[1:-2]))
                require(len(cells) == len(columns), "Dump columns and values differ.")
                row = dict(zip(columns, cells))
                record = json.loads(row["record_data"])
                stored_hash = record.pop("data_sha256")
                require(contracts.sha(record) == stored_hash == row["data_sha256"]
                        and record["source_key"] == row["source_key"]
                        and remaining.pop(row["source_key"], None) == stored_hash, "Backup record differs.")
                projected = {field: record[field] for field in contracts.REGISTER_COLUMNS if field != "data_sha256"}
                projected.update(name="history-" + record["source_key"], source_scope=scope_name)
                differences = [field for field, value in projected.items()
                               if row[field] != (str(int(value)) if isinstance(value, bool) else value)]
                if differences:
                    mismatched_fields.update(differences)
                    mismatched_families[record["family"]] += 1
    require(columns and not inserting and not remaining, "Backup history is incomplete.")
    return {"matching_payloads": len(expected), "rows_with_projection_mismatches": sum(mismatched_families.values()),
            "mismatches_by_field": dict(mismatched_fields), "mismatched_rows_by_family": dict(mismatched_families)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("workspace", type=Path, help="Directory of offline migration receipts")
    parser.add_argument("backup", type=Path, help="Saved database.sql.gz")
    args = parser.parse_args()
    package = args.archive / "destination"
    scope = contracts.normalize_scope(read_json(args.workspace / "migration-scope.json"))
    coverage = read_json(package / "history-records-coverage.json")
    evidence, totals, jobs = archives(args.archive, scope, coverage)
    assets = verify_assets(args.archive, evidence)
    correction = read_json(package / "history-provenance-correction-plan.json")
    repairs = {r["source_key"]: r for r in correction["repairs"]}
    inputs = []
    for name in ("history-records", "history-master-supplement"):
        receipt = read_json(package / (name + "-validation.json"))
        inputs.append({"path": package / (name + ".jsonl"), "sha256": receipt["sha256"],
                       "supplement": name == "history-master-supplement"})
    require(inputs[0]["sha256"] == correction["frozen_history_sha256"], "Correction belongs to a different input.")
    checked = preflight(scope, inputs, evidence, repairs)
    prior = read_json(args.workspace / "history-import-preflight.json")
    require(all(prior.get(k) == v for k, v in checked.items()), "Historical preflight receipt differs.")
    expected = {}
    for item in inputs:
        with item["path"].open() as stream:
            for line in stream:
                _, row = apply_overlay(scope, json.loads(line), repairs)
                expected[row["source_key"]] = row["data_sha256"]
    backup = verify_dump(args.backup, expected, "scope-" + contracts.sha(scope["source_instance"])[:40])
    print(json.dumps({"archives": totals, "jobs": jobs, "history": checked,
                      "verified_asset_sizes": assets, "matching_backup_records": backup["matching_payloads"],
                      "backup_register": backup}, indent=2))
    if backup["rows_with_projection_mismatches"]:
        raise SystemExit("Backup register columns differ from the authenticated import. See the counts above.")


if __name__ == "__main__":
    main()
