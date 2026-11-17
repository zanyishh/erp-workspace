#!/usr/bin/env python3
"""Recover only the pinned install tree whose upstream tests already completed."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import tarfile


def verify(directory, recovery, source):
    for name, entry in recovery['files'].items():
        if Path(name).name != name: raise ValueError('Recovery input must be a basename')
        path = directory / name
        if (path.is_symlink() or not path.is_file() or path.stat().st_size != entry['bytes']
                or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']):
            raise ValueError('Recovery input checksum/size mismatch: ' + name)
    prior = json.loads((directory / 'receipt.json').read_text())
    phase = json.loads((directory / 'validated-build-inputs.json').read_text())
    if (prior.get('status') != recovery['prior_outer_status'] or prior.get('exit_code') != 1
            or prior.get('error') != recovery['prior_outer_error']
            or prior.get('cleanup_errors') or prior.get('container_retained')
            or prior.get('application_mounts') != [] or prior.get('source') != source
            or phase.get('status') != recovery['retained_phase'] or phase.get('source_lock') != source
            or phase.get('files') != {name: recovery['files'][name] for name in
                                    ('validated-build-inputs.tar.gz', 'upstream-tests.log', 'source-applicability.json')}):
        raise ValueError('Recovery source/test phase or prior build identity mismatch')
    if 'All 340 tests PASSED' not in (directory / 'upstream-tests.log').read_text():
        raise ValueError('Retained upstream completion summary missing')
    with tarfile.open(directory / 'validated-build-inputs.tar.gz') as archive:
        members = archive.getmembers()
        if len(members) > 10000 or sum(member.size for member in members) > 100 * 1024**2:
            raise ValueError('Recovery extraction budget exceeded')
        names = set()
        for member in members:
            relative = PurePosixPath(member.name)
            allowed = (relative.parts and relative.parts[0] in ('installed', 'original-packages')) or (
                str(relative) == 'util-linux-2.41.6/COPYING' or relative.parts[:2] == ('util-linux-2.41.6', 'debian'))
            if (not allowed or relative.is_absolute() or '..' in relative.parts or str(relative) in names
                    or not (member.isfile() or member.isdir() or member.issym() or member.islnk())):
                raise ValueError('Unexpected recovery archive member')
            names.add(str(relative))
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                resolved = PurePosixPath(posixpath.normpath(str(relative.parent / target) if member.issym() else str(target)))
                if target.is_absolute() or not resolved.parts or resolved.parts[0] not in ('installed', 'util-linux-2.41.6'):
                    raise ValueError('Recovery link escapes its retained source tree')
        return {'archive_sha256': recovery['files']['validated-build-inputs.tar.gz']['sha256'],
                'entries': len(members), 'expanded_bytes': sum(member.size for member in members),
                'upstream_suite_reused': True, 'upstream_skips_retained': True, 'recompiled': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    recovery = json.loads((args.input / 'util-linux-recovery.lock.json').read_text())
    source_path = args.input / 'util-linux-artifacts.lock.json'
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != recovery['source_lock_sha256']:
        raise ValueError('Reviewed util-linux source lock changed')
    result = verify(args.input, recovery, json.loads(source_path.read_text()))
    if args.destination.exists(): raise ValueError('Recovery destination must be new')
    args.destination.mkdir()
    with tarfile.open(args.input / 'validated-build-inputs.tar.gz') as archive:
        archive.extractall(args.destination, filter='data')
    for name in ('validated-build-inputs.json', 'upstream-tests.log', 'source-applicability.json'):
        shutil.copyfile(args.input / name, args.output / name)
    shutil.copyfile(args.input / 'receipt.json', args.output / 'prior-build-failed-receipt.json')
    (args.output / 'recovery-receipt.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__': main()
