#!/usr/bin/env python3
"""Describe five preserved baseline transport exports in local Debian metadata.

No library source, symbol, test or strict dpkg-gensymbols check is changed.
"""
import argparse
import hashlib
import json
from pathlib import Path

SYMBOLS = (
    '_XimXTransSocketINET6Funcs',
    '_XimXTransSocketINETFuncs',
    '_XimXTransSocketLocalFuncs',
    '_XimXTransSocketTCPFuncs',
    '_XimXTransSocketUNIXFuncs',
)
VERSION = '2:1.8.14-1+erp1'


def adapt(baseline, original):
    missing = set(SYMBOLS) - set(baseline.splitlines())
    if missing:
        raise ValueError('Expected original-library exports are absent: ' + ', '.join(sorted(missing)))
    if original.splitlines()[0] != 'libX11.so.6 libx11-6 #MINVER#':
        raise ValueError('Require the libX11 runtime symbols manifest')
    if any(symbol + '@' in original for symbol in SYMBOLS):
        raise ValueError('Transport metadata already exists; review the source version')
    # One library section only; append exactly the local exported-symbol entries.
    headers = [line for line in original.splitlines()
               if line and not line[0].isspace() and not line.startswith(('#', '|', '*'))]
    if headers != ['libX11.so.6 libx11-6 #MINVER#']:
        raise ValueError('Unexpected extra library section in symbols metadata')
    if not original.endswith('\n'):
        raise ValueError('Require the unmodified newline-terminated source manifest')
    return original + ''.join(f' {symbol}@Base {VERSION}\n' for symbol in SYMBOLS)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--symbols', type=Path, required=True)
    args = parser.parse_args()
    baseline = args.baseline.read_bytes()
    before = args.symbols.read_bytes()
    after = adapt(baseline.decode(), before.decode()).encode()
    args.symbols.write_bytes(after)
    print(json.dumps({'status': 'exact-additive-local-package-metadata',
                      'added_exports': list(SYMBOLS), 'minimum_local_version': VERSION,
                      'baseline_symbols_sha256': hashlib.sha256(baseline).hexdigest(),
                      'original_metadata_sha256': hashlib.sha256(before).hexdigest(),
                      'adjusted_metadata_sha256': hashlib.sha256(after).hexdigest(),
                      'strict_dpkg_gensymbols': '-c4 unchanged',
                      'library_source_or_abi_changed': False}, indent=2))
