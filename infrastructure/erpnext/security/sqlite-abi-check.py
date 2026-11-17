#!/usr/bin/env python3
"""Check public SQLite ABI and the exact reviewed internal-symbol transition."""
import argparse
import hashlib
import json
from pathlib import Path


def verified_json(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('ABI evidence checksum mismatch: ' + path.name)
    return json.loads(data)


def compare_exports(original, candidate, public, internal):
    if not public or not public <= original or public & internal:
        raise ValueError('Invalid public ABI classification')
    removed = original - candidate
    if public - candidate:
        raise ValueError('Public SQLite exports removed: ' + ', '.join(sorted(public - candidate)))
    if removed - internal:
        raise ValueError('Unreviewed SQLite exports removed: ' + ', '.join(sorted(removed - internal)))
    return {'public_exports_preserved': len(public), 'audited_internal_removals': sorted(removed),
            'unexpected_removals': []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('original', 'candidate', 'contract', 'imports', 'classification'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text())
    original = args.original.read_bytes()
    if hashlib.sha256(original).hexdigest() != contract['baseline_exports_sha256']:
        raise ValueError('Baseline SQLite export inventory differs from the reviewed image')
    imports = verified_json(args.imports, contract['import_audit_sha256'])
    classification = verified_json(args.classification, contract['classification_sha256'])
    if (imports['base_image'] != contract['baseline_image'] or imports['imports']
            or imports['elf_files_inspected'] <= 0 or imports['network'] != 'none'
            or imports['application_mounts']):
        raise ValueError('Internal-symbol baseline importer audit does not pass')
    internal = set(contract['audited_internal_removals'])
    if {row['symbol'] for row in classification} != internal:
        raise ValueError('Internal-symbol classification differs from its contract')
    for row in classification:
        if any(row['public_header_occurrences'].values()) or not any(row['internal_header_declarations'].values()):
            raise ValueError('Removed symbol is not classified as internal: ' + row['symbol'])
    result = compare_exports(set(original.decode().splitlines()), set(args.candidate.read_text().splitlines()),
                             set(contract['public_exports']), internal)
    result.update(status='passed', baseline_elf_files_audited=imports['elf_files_inspected'],
                  baseline_importers_of_removed_symbols=0,
                  contract_sha256=hashlib.sha256(args.contract.read_bytes()).hexdigest(),
                  import_audit_sha256=contract['import_audit_sha256'],
                  classification_sha256=contract['classification_sha256'])
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
