#!/usr/bin/env python3
"""Replace only upstream latest-directory discovery with reviewed pinned URLs."""
import json
from pathlib import Path
import runpy
import sys

sys.path.insert(0, str(Path.cwd()))
import buildlibxml

lock = json.loads(Path('/security-input/lxml-artifacts.lock.json').read_text())
sources = {entry['name']: entry for entry in lock['sources']}


def pinned_directory(url, version=None):
    for name in ('libxml2', 'libxslt'):
        entry = sources[name]
        expected = 'https://download.gnome.org/sources/'+name+'/'
        if url == expected and version == entry['version']:
            return entry['url'].rsplit('/', 1)[0]+'/'
    raise ValueError('Unexpected dependency discovery request')


def refuse_download(*args, **kwargs):
    raise RuntimeError('All build sources must already exist and match the offline lock')


buildlibxml.http_find_latest_version_directory = pinned_directory
buildlibxml.urlretrieve = refuse_download
buildlibxml.ARCHIVE_HASHES.update({entry['filename']: entry['sha256'] for entry in lock['sources']})
sys.argv[0] = 'setup.py'
runpy.run_path('setup.py', run_name='__main__')
