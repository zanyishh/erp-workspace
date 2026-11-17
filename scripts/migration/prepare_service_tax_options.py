"""Prepare explicit optional service tax templates from the verified native masters."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import sys

from check_knitpack_snapshot import response_failed

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps/erp_extensions"))
from erp_extensions.migration.tax_templates import compile_options


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-root", type=Path, default=Path(".local/knitpack-migration"))
    parser.add_argument("--targets", type=Path, default=Path(".local/customer-workspace/target-bindings.json"))
    args = parser.parse_args()
    root, targets = args.private_root, json.loads(args.targets.read_text())
    manifest = root / "verification/report-snapshot-final.manifest.jsonl"
    selected = {"master-accv2-masters-listhsn.json"} | {f"master-detail-company-{i}.json" for i in range(1, 5)}
    expected = {}
    with manifest.open() as handle:
        for line in handle:
            row = json.loads(line)
            if row.get("file") in selected:
                if row["file"] in expected:
                    raise ValueError("Duplicate master evidence in the fixed manifest.")
                expected[row["file"]] = row["sha256"]
    if set(expected) != selected:
        raise ValueError("The fixed manifest does not cover all tax/company masters.")
    evidence, companies, hsns = [], {}, None
    for filename in sorted(selected):
        raw = (root / "report-snapshot" / filename).read_bytes()
        digest = sha256(raw).hexdigest()
        if digest != expected[filename]:
            raise ValueError("A native tax/company master failed its hash check.")
        payload = json.loads(raw)
        if response_failed(payload):
            raise ValueError("A native tax/company master is not a business response.")
        if filename == "master-accv2-masters-listhsn.json":
            hsns = payload["result"]
        else:
            value = payload["result"]
            native_id = str(value.get("id"))
            if filename != f"master-detail-company-{native_id}.json":
                raise ValueError("A native company identity differs from its read plan.")
            companies[native_id] = value
        evidence.append({"file": filename, "sha256": digest, "pointer": "/result"})
    code = root / "preflight/2730.b612af7d6ee88ba3.js"
    source = code.read_text()
    excerpts = []
    for start, end in (("onInvoiceTypeChange(){", "updateSalesHSN(){"),
                       ("addtaxList(t,i,n,a,r){", "onJobnoChange(){"),
                       ("calculateTaxValue(){", "CalculateFinalValue(){")):
        position = source.index(start)
        ending = source.index(end, position)
        excerpts.append({"offset": position, "text": source[position:ending]})
    evidence.append({"file": str(code), "sha256": sha256(code.read_bytes()).hexdigest(), "kind": "published_invoice_editor",
        "excerpts": excerpts, "meaning": "New service invoices select service HSN definitions; India/non-book-1 tax code splits percentage for SGST mode or uses IGST. Applicability remains an explicit future invoice choice."})
    result = compile_options(scope=targets["scope"], manifest_sha256=sha256(manifest.read_bytes()).hexdigest(),
        hsns=hsns, companies=companies, company_bindings={key: value["company"] for key, value in targets["companies"].items()}, evidence=evidence)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    path = root / "destination/service-tax-options.json"
    if path.exists():
        if path.read_text() != encoded:
            raise ValueError("Existing immutable service tax options differ; preserve and review both versions.")
    else:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(encoded)
    print(json.dumps({"source_master_hashes_verified": len(selected), "companies": len(result["companies"]),
        "optional_templates": sum(len(row["templates"]) for row in result["companies"]), "defaults_assigned": 0,
        "proof_hash": result["proof_hash"]}))


if __name__ == "__main__":
    main()
