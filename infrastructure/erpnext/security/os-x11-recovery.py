#!/usr/bin/env python3
"""Verify the completed X11 checkpoint before a manuals-only recovery."""
from email.parser import Parser
import hashlib
import json
from pathlib import Path
import re


def metadata(path):
    if path.is_symlink() or not path.is_file(): raise ValueError('Require regular saved checkpoint files')
    return {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def verify_checkpoint(directory, lock, scope, families=('libx11', 'libxi', 'libxrender', 'libxtst')):
    directory = Path(directory).absolute()
    if any(p.is_symlink() for p in [directory, *directory.parents]): raise ValueError('Linked checkpoint path')
    read = lambda name: json.loads((directory/name).read_text())
    receipt = read('receipt.json'); snapshot = read('os-artifacts.lock.json')
    if (receipt.get('status') != 'failed' or receipt.get('exit_code') != 2
            or receipt.get('source') != lock['x11'] or snapshot['x11'] != lock['x11']
            or receipt.get('base_image') != lock['base_image'] or snapshot['base_image'] != lock['base_image']
            or receipt.get('application_mounts') != []
            or any(receipt.get(k) for k in ('cleanup_errors', 'evidence_copy_errors', 'container_retained'))
            or '/usr/local/bin/python3: No module named asciidoc' not in (directory/'git-manual-build.log').read_text()
            or (directory/'dpkg-audit.txt').read_bytes()):
        raise ValueError('Require the exact completed-X11/manual-Python failure checkpoint')
    compatibility = read('compatibility.json')
    if (compatibility.get('component') != 'x11' or compatibility.get('libxi_public_exports_resolved') != 88
            or compatibility.get('versions') != {n: v['version'] for n, v in scope.items()}):
        raise ValueError('The ordinary X11/88-export checks did not complete')
    source_hash = metadata(directory/'os-artifacts.lock.json')['sha256']
    for family in families:
        proof = read(family+'.compiled-tree.json')
        if any(Path(proof[key]).name != proof[key] for key in ('archive', 'build_log')):
            raise ValueError('Checkpoint evidence must use local basenames')
        archive = metadata(directory/proof['archive'])
        if (proof.get('status') != 'debian-build-target-completed-binary-packaging-and-abi-pending'
                or proof.get('package') != family or proof.get('build_target_completed') is not True
                or proof.get('source_lock_sha256') != source_hash
                or archive != {'bytes': proof['archive_bytes'], 'sha256': proof['archive_sha256']}
                or metadata(directory/proof['build_log'])['sha256'] != proof['build_log_sha256']):
            raise ValueError('An ordinary completed source build checkpoint differs: '+family)
    checksums = {}
    for changes in directory.glob('*.changes'):
        message = Parser().parsestr(changes.read_text())
        for line in message.get('Checksums-Sha256', '').splitlines():
            if not line.strip(): continue
            sha, count, name = line.split()
            if Path(name).name != name or not re.fullmatch('[0-9a-f]{64}', sha): raise ValueError('Invalid packaging checksum')
            item = {'sha256': sha, 'bytes': int(count)}
            if name in checksums and checksums[name] != item: raise ValueError('Conflicting packaging checksum')
            checksums[name] = item
    packages = {}
    for name in scope:
        matches = list(directory.glob(name+'_*.deb'))
        if len(matches) != 1 or metadata(matches[0]) != checksums.get(matches[0].name):
            raise ValueError('Saved runtime package differs from its packaging checksum: '+name)
        packages[name] = matches[0].name
    files = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink(): raise ValueError('Linked checkpoint entry')
        if path.is_file(): files[str(path.relative_to(directory))] = metadata(path)
        elif not path.is_dir(): raise ValueError('Special checkpoint entry')
    if sum(item['bytes'] for item in files.values()) > 160*1024**2:
        raise ValueError('Checkpoint exceeds the finish-only recovery size bound')
    return {'status': 'verified-x11-checkpoint-manuals-only-pending', 'origin': str(directory),
            'files': files, 'packages': packages, 'prior_failed_receipt_sha256': files['receipt.json']['sha256']}
