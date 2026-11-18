#!/usr/bin/env python3
"""Require original X11 exports, except seven reviewed libXi linker markers."""
import argparse
import hashlib
import json
from pathlib import Path

MARKERS={'__bss_end__','__bss_start','__bss_start__','__end__','_bss_end__','_edata','_end'}


def check(soname, baseline, candidate, contract):
    before=set(baseline.decode().splitlines())
    after=set(candidate.decode().splitlines())
    allowed=set()
    if soname == 'libXi.so.6':
        if (contract['library'] != soname or set(contract['allowed_removed_symbols']) != MARKERS
                or hashlib.sha256(baseline).hexdigest() != contract['baseline_export_sha256']
                or set(contract['preserved_symbols']) != before-MARKERS
                or len(contract['preserved_symbols']) != 88):
            raise ValueError('libXi baseline/public ABI contract changed')
        allowed=MARKERS
    removed=before-after
    if removed-allowed:
        raise ValueError('Original API exports removed: '+', '.join(sorted(removed-allowed)))
    return {'status':'original-api-exports-preserved','library':soname,
            'required_original_exports':len(before-allowed),
            'removed_reviewed_linker_markers':sorted(removed),
            'all_other_original_exports_preserved':True}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('baseline','candidate','original-library','contract'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--soname',required=True)
    args=parser.parse_args()
    contract=json.loads(args.contract.read_text())
    if args.soname=='libXi.so.6' and hashlib.sha256(args.original_library.read_bytes()).hexdigest()!=contract['original_library_sha256']:
        raise ValueError('Original libXi bytes differ from the audited pinned image')
    result=check(args.soname,args.baseline.read_bytes(),args.candidate.read_bytes(),contract)
    result['contract_sha256']=hashlib.sha256(args.contract.read_bytes()).hexdigest()
    print(json.dumps(result,indent=2))
