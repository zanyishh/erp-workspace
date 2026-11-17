"""Build private native address/tax enrichment from the fixed read-only archive."""
import argparse
from collections import Counter
from hashlib import sha256
import importlib.util
import json
import os
from pathlib import Path

from check_knitpack_snapshot import response_failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-root", type=Path, default=Path(".local/knitpack-migration"))
    parser.add_argument("--targets", type=Path, default=Path(".local/customer-workspace/target-bindings.json"))
    args = parser.parse_args()
    root = args.private_root
    targets = json.loads(args.targets.read_text())
    module_path = Path(__file__).resolve().parents[2] / "apps/erp_extensions/erp_extensions/migration/master_details.py"
    spec = importlib.util.spec_from_file_location("master_details", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    countries = set(json.loads((Path(__file__).resolve().parents[2] / "upstream/frappe/frappe/geo/country_info.json").read_text()))
    supplier_ids = set(json.loads((root / "destination/financial-posting-mapping-plan.json").read_text())["required_supplier_ids"])
    package = json.loads((root / "destination/master-mapping-package.json").read_text())
    party_ids = sorted((e["source_key"]["native_id"] for e in package["entities"] if e["kind"] == "party"), key=int)
    selected = {f"master-detail-party-{i}.json" for i in party_ids} | {f"master-detail-company-{i}.json" for i in range(1, 5)}
    manifest = root / "verification/report-snapshot-final.manifest.jsonl"
    expected = {}
    with manifest.open() as handle:
        for line in handle:
            row = json.loads(line)
            if row.get("file") in selected:
                if row["file"] in expected:
                    raise ValueError("A selected master has duplicate manifest records.")
                expected[row["file"]] = row["sha256"]
    if set(expected) != selected:
        raise ValueError("The fixed manifest does not cover every selected native master.")
    entities, evidence, counts = [], [], Counter()
    for filename in sorted(selected):
        raw = (root / "report-snapshot" / filename).read_bytes()
        digest = sha256(raw).hexdigest()
        if digest != expected[filename]:
            raise ValueError("An original native master failed its hash check.")
        payload = json.loads(raw)
        if response_failed(payload) or not isinstance(payload.get("result"), dict):
            raise ValueError("A selected native master is not a successful business response.")
        source = payload["result"]
        native_id = str(source.get("id"))
        company = filename.startswith("master-detail-company-")
        if filename != f"master-detail-{'company' if company else 'party'}-{native_id}.json":
            raise ValueError("The native master identity differs from its finite read plan.")
        entity = module.company_details(source, targets["scope"], targets["companies"][native_id]["company"], countries=countries) if company else module.party_details(
            source, targets["scope"], supplier=native_id in supplier_ids, countries=countries)
        entities.append(entity)
        evidence.append({"file": filename, "sha256": digest, "pointer": "/result"})
        counts[entity["source_kind"] + "_masters"] += 1
        counts["native_address_records"] += len(entity["addresses"])
        counts["native_business_contact_records"] += len(entity.get("contacts", []))
        counts["tax_id_updates_with_source_value"] += sum(bool(u.get("tax_id")) for u in entity["updates"])
        for kind, observed in entity["address_coverage"].items():
            counts[f"{entity['source_kind']}_{kind}_" + ("complete" if observed["complete"] else "preserved_only_in_history")] += 1
            counts["identical_billing_shipping_shared_once"] += bool(observed.get("shares_exact_billing_address"))
            counts["address_phone_omitted_without_primary"] += bool(observed.get("phone_preserved_only_in_history"))
    result = {"scope": targets["scope"], "manifest_sha256": sha256(manifest.read_bytes()).hexdigest(), "counts": dict(counts),
        "evidence": evidence, "entities": entities, "missing_address_components_invented": False, "person_contacts_invented": False,
        "tax_id_basis": "Only the original gstin field; PAN is never substituted. Original identifiers remain in immutable history.",
        "address_basis": "Require original street, city and a supported source country; preserve other supplied postal lines without truncation. Exact billing/shipping duplicates share one linked native Address."}
    path = root / "destination/master-detail-enrichment.json"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    os.chmod(path, 0o600)
    print(json.dumps({"source_hashes_verified": len(evidence), **dict(counts)}))


if __name__ == "__main__":
    main()
