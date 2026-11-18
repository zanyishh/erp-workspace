#!/usr/bin/env python3
"""Package the ordinary-tested pure-Perl component without renumbering Perl."""
import hashlib
import io
import json
from pathlib import Path
import tarfile

SOURCE = Path('/security-work/Archive-Tar-3.14')
OUTPUT = Path('/security-output')
lock = json.loads(Path('/security-input/archive-tar-artifacts.lock.json').read_text())['archive-tar']
data = {}
for name in lock['preimages']:
    relative = name.removeprefix('usr/share/perl/5.40.1/')
    path = SOURCE/'blib/lib'/relative if relative != name else SOURCE/'blib/script'/Path(name).name
    data[name] = path.read_bytes()
data['manifest.json'] = (json.dumps({'version': '3.14',
    'source_sha256': lock['sources']['Archive-Tar-3.14.tar.gz']['sha256'],
    'files': {name: hashlib.sha256(value).hexdigest() for name, value in data.items()}}, indent=2)+'\n').encode()
data['Archive-Tar-META.json'] = (SOURCE/'META.json').read_bytes()
data['Archive-Tar-README'] = (SOURCE/'README').read_bytes()
with tarfile.open(OUTPUT/'archive-tar-runtime.tar.gz', 'w:gz') as archive:
    for name, value in sorted(data.items()):
        info = tarfile.TarInfo(name); info.size = len(value); info.mode = 0o644
        archive.addfile(info, io.BytesIO(value))
