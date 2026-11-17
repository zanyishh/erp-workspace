#!/usr/bin/env python3
"""Ordinary synthetic compatibility checks; no application data is opened."""
import argparse
import ctypes
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import zlib


def sqlite_check(abi_contract=None):
    assert sqlite3.sqlite_version == '3.54.1', sqlite3.sqlite_version
    abi = {}
    if abi_contract is not None:
        data = Path(abi_contract).read_bytes()
        contract = json.loads(data)
        library = ctypes.CDLL('libsqlite3.so.0')
        library.sqlite3_libversion.restype = ctypes.c_char_p
        assert library.sqlite3_libversion().decode() == sqlite3.sqlite_version
        for name in contract['public_exports']:
            getattr(library, name)
        abi = {'public_exports_resolved': len(contract['public_exports']),
               'abi_contract_sha256': hashlib.sha256(data).hexdigest()}
    with tempfile.TemporaryDirectory(prefix='erp-sqlite-check-') as directory:
        db = sqlite3.connect(str(Path(directory) / 'fixture.db'))
        options = {row[0] for row in db.execute('PRAGMA compile_options')}
        required = {'ENABLE_COLUMN_METADATA', 'ENABLE_FTS3', 'ENABLE_FTS4', 'ENABLE_FTS5',
                    'ENABLE_RTREE', 'ENABLE_SESSION', 'ENABLE_PREUPDATE_HOOK', 'ENABLE_UNLOCK_NOTIFY',
                    'ENABLE_UPDATE_DELETE_LIMIT', 'ENABLE_LOAD_EXTENSION', 'ENABLE_MATH_FUNCTIONS',
                    'ENABLE_DBSTAT_VTAB', 'ENABLE_DBPAGE_VTAB', 'ENABLE_STMTVTAB', 'SECURE_DELETE',
                    'SOUNDEX', 'THREADSAFE=1', 'USE_URI', 'MAX_VARIABLE_NUMBER=250000'}
        assert not (required - options), required - options
        assert db.execute('PRAGMA journal_mode=WAL').fetchone()[0] == 'wal'
        db.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, amount INTEGER NOT NULL)')
        db.executemany('INSERT INTO orders VALUES (?,?)', [(1, 100), (2, 250)])
        db.commit()
        db.execute('UPDATE orders SET amount=999 WHERE id=1')
        db.rollback()
        assert db.execute('SELECT sum(amount) FROM orders').fetchone()[0] == 350
        db.execute('CREATE VIRTUAL TABLE search USING fts5(description)')
        db.execute("INSERT INTO search VALUES ('synthetic knitting order')")
        assert db.execute("SELECT count(*) FROM search WHERE search MATCH 'knitting'").fetchone()[0] == 1
        assert db.execute("SELECT json_extract('{\"quantity\":4}', '$.quantity')").fetchone()[0] == 4
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        copy = sqlite3.connect(':memory:')
        db.commit()
        db.backup(copy)
        assert copy.execute('SELECT sum(amount) FROM orders').fetchone()[0] == 350
        copy.close()
        db.close()
    return {'component': 'sqlite', 'version': sqlite3.sqlite_version, 'compile_options': sorted(options),
            'checks': ['WAL', 'transactions', 'rollback', 'FTS5', 'JSON', 'integrity', 'backup'], **abi}


def git_check(https=False):
    def run(*args, cwd=None):
        return subprocess.check_output(['git', *args], cwd=cwd, text=True, stderr=subprocess.STDOUT, timeout=120).strip()
    assert run('--version') == 'git version 2.50.2'
    with tempfile.TemporaryDirectory(prefix='erp-git-check-') as directory:
        root = Path(directory)
        repo, clone = root / 'source', root / 'clone'
        run('init', '--initial-branch=main', str(repo))
        run('config', 'user.name', 'Synthetic fixture', cwd=repo)
        run('config', 'user.email', 'fixture@localhost', cwd=repo)
        (repo / 'order.txt').write_text('synthetic order\n')
        run('add', 'order.txt', cwd=repo)
        run('commit', '-m', 'Synthetic fixture', cwd=repo)
        run('clone', '--no-local', str(repo), str(clone))
        assert run('rev-parse', 'HEAD', cwd=repo) == run('rev-parse', 'HEAD', cwd=clone)
        run('fsck', '--full', cwd=clone)
        assert (clone / 'order.txt').read_text() == 'synthetic order\n'
        run('bundle', 'create', str(root / 'fixture.bundle'), '--all', cwd=repo)
        run('bundle', 'verify', str(root / 'fixture.bundle'), cwd=clone)
        run('subtree', 'add', '--prefix=vendor', str(clone), 'main', '--squash', cwd=repo)
        assert (repo / 'vendor' / 'order.txt').read_text() == 'synthetic order\n'
        split = run('subtree', 'split', '--quiet', '--prefix=vendor', cwd=repo)
        assert run('show', split + ':order.txt', cwd=repo) == 'synthetic order'
    subprocess.run(['perl', '-MGit', '-e', 'print $Git::VERSION'], check=True, capture_output=True)
    linked = subprocess.check_output(['ldd', '/usr/lib/git-core/git-remote-http'], text=True)
    assert 'libcurl-gnutls.so.4' in linked and 'not found' not in linked, linked
    checks = ['init', 'commit', 'clone', 'fsck', 'bundle', 'subtree add/split', 'Perl module', 'GnuTLS curl linkage']
    if https:
        ref = run('-c', 'http.sslVerify=true', 'ls-remote', 'https://github.com/git/git.git', 'refs/tags/v2.50.2')
        assert ref.endswith('refs/tags/v2.50.2'), ref
        checks.append('verified TLS official Git remote')
    return {'component': 'git', 'version': run('--version'), 'checks': checks}


def x11_check(abi_contract=None):
    versions = {'libx11-6': '2:1.8.14-1+erp1', 'libx11-data': '2:1.8.14-1+erp1',
                'libx11-xcb1': '2:1.8.14-1+erp1', 'libxi6': '2:1.8.4-1+erp1',
                'libxrender1': '1:0.9.13-1+erp1', 'libxtst6': '2:1.2.6-1+erp1'}
    for package, expected in versions.items():
        actual = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', package], text=True)
        assert actual == expected, (package, actual, expected)
    names = ['libX11.so.6', 'libX11-xcb.so.1', 'libXi.so.6', 'libXrender.so.1', 'libXtst.so.6']
    loaded = [ctypes.CDLL(name) for name in names]
    if abi_contract is None:
        raise ValueError('Require the reviewed libXi public ABI contract')
    contract=json.loads(abi_contract.read_text())
    symbols=contract['preserved_symbols']
    if contract['library']!='libXi.so.6' or len(symbols)!=88 or len(set(symbols))!=88:
        raise ValueError('Incomplete libXi public ABI contract')
    for symbol in symbols:getattr(loaded[2],symbol)
    loaded[0].XInitThreads.restype = ctypes.c_int
    assert loaded[0].XInitThreads() != 0
    loaded[0].XSupportsLocale.restype = ctypes.c_int
    assert loaded[0].XSupportsLocale() != 0
    return {'component': 'x11', 'versions': versions, 'loaded': names,
            'checks': ['shared library loading', 'all 88 libXi public exports', 'XInitThreads', 'XSupportsLocale'],
            'libxi_public_exports_resolved':len(symbols),
            'dependent_browser_and_display_test': 'pending in final candidate image'}


def zlib_check():
    assert zlib.ZLIB_RUNTIME_VERSION == '1.4', zlib.ZLIB_RUNTIME_VERSION
    original = b'Synthetic ERP compression fixture\n' * 4096
    assert zlib.decompress(zlib.compress(original)) == original
    compressor = zlib.compressobj(wbits=-15)
    compressed = compressor.compress(original) + compressor.flush()
    assert zlib.decompress(compressed, wbits=-15) == original
    assert gzip.decompress(gzip.compress(original)) == original
    dictionary = b'Synthetic ERP compression fixture'
    compressor = zlib.compressobj(zdict=dictionary)
    compressed = compressor.compress(original) + compressor.flush()
    decompressor = zlib.decompressobj(zdict=dictionary)
    assert decompressor.decompress(compressed) + decompressor.flush() == original
    return {'component': 'zlib', 'version': zlib.ZLIB_RUNTIME_VERSION,
            'checks': ['zlib round trip', 'raw deflate', 'gzip', 'preset dictionary']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('component', choices=('git', 'sqlite', 'x11', 'zlib'))
    parser.add_argument('--https', action='store_true')
    parser.add_argument('--sqlite-abi-contract', type=Path)
    parser.add_argument('--x11-abi-contract', type=Path)
    args = parser.parse_args()
    result = {'sqlite': lambda: sqlite_check(args.sqlite_abi_contract), 'git': lambda: git_check(args.https),
              'x11': lambda: x11_check(args.x11_abi_contract), 'zlib': zlib_check}[args.component]()
    print(json.dumps(result, indent=2))
