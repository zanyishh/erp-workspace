#!/usr/bin/env python3
"""Install only the tested Archive::Tar component onto a matching candidate base."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile

TARGET_ROOT = Path('/')
LOCK = Path(__file__).with_name('archive-tar-artifacts.lock.json')

def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    if os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1':
        raise RuntimeError('Only the explicitly isolated candidate build may install this payload')
    lock = json.loads(LOCK.read_text())
    expected = lock['archive-tar']['preimages']
    with tarfile.open(args.payload) as archive:
        members = archive.getmembers()
        allowed = set(expected) | {'manifest.json', 'Archive-Tar-META.json', 'Archive-Tar-README'}
        if (len(members) != len(allowed) or {member.name for member in members} != allowed
                or any(not member.isfile() for member in members)
                or sum(member.size for member in members) > 1024**2):
            raise ValueError('Unexpected Archive::Tar payload paths or size')
        data = {member.name: archive.extractfile(member).read() for member in members}
    manifest = json.loads(data['manifest.json'])
    if manifest['version'] != '3.14' or manifest['source_sha256'] != lock['archive-tar']['sources']['Archive-Tar-3.14.tar.gz']['sha256']:
        raise ValueError('Payload provenance differs from the reviewed source')
    if set(manifest['files']) != set(expected): raise ValueError('Payload file inventory differs')
    # Preflight all existing and incoming bytes before replacing any module/tool.
    for name, before in expected.items():
        target = TARGET_ROOT/name
        if (target.is_symlink() or not target.is_file() or digest(target.read_bytes()) != before
                or digest(data[name]) != manifest['files'][name]):
            raise ValueError('Archive::Tar source/target checksum mismatch: '+name)
    for name in expected:
        target = TARGET_ROOT/name
        mode = target.stat().st_mode & 0o777
        target.write_bytes(data[name]); target.chmod(mode)
    version = subprocess.check_output(['perl', '-MArchive::Tar', '-e', 'print $Archive::Tar::VERSION'], text=True)
    if version != '3.14': raise RuntimeError('A different module shadows the installed Archive::Tar')
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    for name in ('Archive-Tar-META.json', 'Archive-Tar-README'):
        (args.receipt.parent/name).write_bytes(data[name])
    args.receipt.write_text(json.dumps({'status': 'installed', 'version': version,
        'payload_sha256': digest(args.payload.read_bytes()), 'source_sha256': manifest['source_sha256'],
        'files': manifest['files'], 'preimages': expected,
        'perl_interpreter_version': 'unchanged; only Archive::Tar modules and ptar tools replaced'}, indent=2)+'\n')


if __name__ == '__main__':
    main()
