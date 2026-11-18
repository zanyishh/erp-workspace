#!/usr/bin/env python3
"""Normal utility/library checks on synthetic files; never mount or alter devices."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import tempfile

VERSION = '2.41.6-0+erp1'
PACKAGES = {name: VERSION for name in
    'util-linux mount libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2'.split()}
PACKAGES.update(bsdutils='1:'+VERSION, login='1:4.16.0-2+really'+VERSION)


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=30).strip()


def main():
    if os.geteuid() == 0: raise RuntimeError('Run ordinary utility checks as the unprivileged frappe account')
    actual = {name: run('dpkg-query', '-W', '-f=${Version}', name) for name in PACKAGES}
    assert actual == PACKAGES, actual
    versions = {name: run(name, '--version') for name in ('mount', 'umount', 'findmnt', 'lsblk', 'blkid', 'mkswap', 'flock')}
    assert all('2.41.6' in value for value in versions.values()), versions
    mounted = json.loads(run('findmnt', '--json', '--target', '/', '--output', 'TARGET,FSTYPE,OPTIONS'))
    assert mounted['filesystems'] and mounted['filesystems'][0]['target'] == '/'
    devices = json.loads(run('lsblk', '--json', '--output', 'NAME,TYPE'))
    assert isinstance(devices['blockdevices'], list)
    libraries = ['libblkid.so.1', 'libmount.so.1', 'libsmartcols.so.1', 'libuuid.so.1', 'liblastlog2.so.2']
    for name in libraries: ctypes.CDLL(name)
    uuid = ctypes.CDLL('libuuid.so.1')
    value = (ctypes.c_ubyte*16)(); text = ctypes.create_string_buffer(37)
    uuid.uuid_generate.argtypes = [ctypes.c_void_p]
    uuid.uuid_unparse_lower.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    uuid.uuid_parse.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
    uuid.uuid_generate(value); uuid.uuid_unparse_lower(value, text)
    restored = (ctypes.c_ubyte*16)()
    assert uuid.uuid_parse(text.value, restored) == 0 and bytes(value) == bytes(restored)
    with tempfile.TemporaryDirectory(prefix='erp-util-linux-') as directory:
        swap = Path(directory)/'synthetic.swap'
        # A normal, unmounted swap-format file exercises libblkid parsing.
        with swap.open('wb') as stream: stream.write(b'\0'*(4*1024**2))
        swap.chmod(0o600)
        run('mkswap', '--uuid', text.value.decode(), str(swap))
        fields = dict(line.split('=', 1) for line in run('blkid', '-p', '-o', 'export', str(swap)).splitlines())
        assert fields['TYPE'] == 'swap' and fields['UUID'] == text.value.decode(), fields
        run('flock', '--nonblock', str(Path(directory)/'normal.lock'), '/bin/true')
    print(json.dumps({'status': 'passed', 'versions': actual, 'utility_versions': versions,
        'libraries_loaded': libraries, 'checks': ['read-only mount table', 'read-only block-device inventory',
        'UUID generate/parse', 'synthetic swap format/probe', 'file lock'],
        'mount_operations': False, 'uid': os.geteuid()}, indent=2))


if __name__ == '__main__': main()
