#!/usr/bin/env python3
"""Prepare deterministic source identity references offline; never import masters."""
from collections import Counter, defaultdict
import hashlib
import json
import re

from check_knitpack_snapshot import identifier


COMPANIES = frozenset({"1", "2", "3", "4"})
DATE_FIELDS = frozenset({"date", "jobdate", "duedate", "grndate", "partydcdate", "created_t", "updated_t"})


def original_date_field(field):
    name = field.lower()
    return name in DATE_FIELDS or name.endswith(("_date", "_time")) or name in {"created_at", "updated_at", "modified_at"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def source_key(instance, row):
    return {"instance": instance, "namespace": row["namespace"],
            "scope": [str(v) for v in row.get("scope", [])], "native_id": str(row["native_id"])}


def target_key(key):
    return "KP-" + digest(key)


def unique_sorted(rows):
    return [json.loads(value) for value in sorted({canonical(row) for row in rows})]


def evidence_valid(value):
    return (isinstance(value, dict) and isinstance(value.get("file"), str) and bool(value["file"])
        and isinstance(value.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", value["sha256"]) is not None
        and isinstance(value.get("pointer"), str) and value["pointer"].startswith("/"))


def build(instance, observations, uses):
    """Input contains only explicitly identified native entities and evidence locators.

    Fields are represented by typed value hashes and pointers, not copied master
    values. Complementary observations extend evidence; conflicting values are
    quarantined. Company use never supplies account/material ownership.
    """
    grouped, entities, issues = defaultdict(list), [], []
    for row in observations:
        if (not instance or not isinstance(row.get("namespace"), str) or not row["namespace"]
                or not identifier(row.get("native_id")) or not isinstance(row.get("scope", []), (list, tuple))
                or any(not identifier(value) for value in row.get("scope", []))):
            issues.append({"code": "source_identity_invalid"})
            continue
        if not evidence_valid(row.get("evidence")):
            issues.append({"code": "source_evidence_invalid"})
            continue
        grouped[canonical(source_key(instance, row))].append(row)
    for serialized, rows in sorted(grouped.items()):
        key = json.loads(serialized)
        claims, dates, refs, reasons, supplements = defaultdict(list), [], [], set(), []
        kinds = {r["kind"] for r in rows}
        for row in rows:
            ref = row["evidence"]
            refs.append(ref)
            reasons.update(row.get("quarantine_reasons", []))
            supplements.extend(row.get("supplementary_evidence", []))
            for field, value in row.get("fields", {}).items():
                if field in {"session_id", "rc_session", "password", "token"}:
                    continue
                pointer = ref["pointer"] + "/" + field.replace("~", "~0").replace("/", "~1")
                claim = {**ref, "pointer": pointer, "value_sha256": digest(value), "original_type": type(value).__name__}
                claims[field].append(claim)
                if original_date_field(field):
                    dates.append({"field": field, **claim})
        if len(kinds) != 1:
            reasons.add("conflicting_source_kinds")
        if any(len({(c["original_type"], c["value_sha256"]) for c in values}) > 1 for values in claims.values()):
            reasons.add("conflicting_source_field_versions")
        references = unique_sorted(refs)
        reference_index = {canonical(r): i for i, r in enumerate(references)}

        def index_for(claim):
            return reference_index[canonical({"file": claim["file"], "sha256": claim["sha256"],
                "pointer": claim["pointer"].rsplit("/", 1)[0]})]

        compact_claims = {}
        for field, values in sorted(claims.items()):
            versions = defaultdict(set)
            for claim in values:
                versions[(claim["value_sha256"], claim["original_type"])].add(index_for(claim))
            compact_claims[field] = [{"value_sha256": value_hash, "original_type": original_type,
                "evidence_indices": sorted(indices)} for (value_hash, original_type), indices in sorted(versions.items())]
        compact_dates = unique_sorted({"field": r["field"], "pointer": r["pointer"],
            "value_sha256": r["value_sha256"], "original_type": r["original_type"],
            "evidence_index": index_for(r)} for r in dates)
        entities.append({"source_key": key, "proposed_registry_key": target_key(key),
            "kind": sorted(kinds)[0], "evidence": references,
            "field_evidence": compact_claims,
            "original_date_evidence": compact_dates, "supplementary_evidence": unique_sorted(supplements),
            "ownership": "not_inferred_from_use", "target_item_equivalence": None,
            "quarantine_reasons": sorted(reasons), "status": "quarantined" if reasons else "prepared_identity_only"})
    targets = defaultdict(list)
    for row in entities:
        targets[row["proposed_registry_key"]].append(row)
    for rows in targets.values():
        if len(rows) > 1:
            for row in rows:
                row["quarantine_reasons"] = sorted(set(row["quarantine_reasons"]) | {"target_key_collision"})
                row["status"] = "quarantined"
    known = {canonical(r["source_key"]) for r in entities}
    company_use = []
    for row in uses:
        key = source_key(instance, row)
        if str(row.get("company")) not in COMPANIES:
            issues.append({"code": "use_company_unknown", "source_key": key, "evidence": row["evidence"]})
        elif canonical(key) not in known:
            issues.append({"code": "use_master_missing", "source_key": key, "evidence": row["evidence"]})
        else:
            company_use.append({"source_key": key, "company_id": str(row["company"]),
                "source_book": row.get("book"), "role": row["role"], "evidence": row["evidence"],
                "company_evidence": row.get("company_evidence"), "book_evidence": row.get("book_evidence"),
                "ownership_inferred": False})
    return {"version": 1, "source_instance": instance, "import_allowed": False,
        "operational_migration_complete": False, "entities": entities,
        "company_use": unique_sorted(company_use), "issues": unique_sorted(issues),
        "counts": {"entities": len(entities), "kinds": dict(sorted(Counter(r["kind"] for r in entities).items())),
                   "quarantined": sum(r["status"] == "quarantined" for r in entities)},
        "limits": ["Proposed registry keys are deterministic preparation identifiers, not created destination documents.",
                   "Job-associated yarn, fabric and size identities are contextual; no global ERPNext Item equivalence is inferred.",
                   "Original field values and dates remain in the hash-bound source files; no target posting/audit dates are assigned.",
                   "Company use is evidence of a reference, never ownership or a party alias."]}
