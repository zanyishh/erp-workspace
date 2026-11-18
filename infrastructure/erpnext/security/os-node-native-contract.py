#!/usr/bin/env python3
"""Bind a narrow native-addon applicability review to candidate file bytes.

This does not repair Node's statically bundled zlib or exclude dynamic lookup.
Run only in a disposable pinned-base/candidate container with no application data.
"""
import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

BASE_IMAGE = 'frappe/erpnext@sha256:32145acc7f699dc598ca141018a95ebf8e56f516d4a0e76beb7287ae68b303b8'
ROOTS = ['/usr', '/opt', '/home']
TARGETS = {'gzwrite', 'gzfwrite', 'gzprintf', 'gzvprintf', 'gzputs', 'gzputc',
           'gzopen', 'gzopen64', 'gzdopen', 'gzclearerr', 'gzflush', 'gzseek',
           'gzseek64', 'inflateGetDictionary', 'inflateSync'}


def require_dynamic_metadata(sections):
    if not {6, 11} <= {section[1] for section in sections}:
        raise ValueError('Unsupported or missing ELF dynamic metadata; review required')
    for section in sections:
        if section[1] not in (6, 11):
            continue
        entry_size = 16 if section[1] == 6 else 24
        if (section[9] != entry_size or section[5] < entry_size
                or section[5] % entry_size or section[6] >= len(sections)
                or sections[section[6]][1] != 3):
            raise ValueError('Unsupported ELF dynamic metadata layout; review required')


def inspect_file(path, hash_bytes=True):
    stat = path.stat()
    result = {'bytes': stat.st_size, 'mode': stat.st_mode & 0o7777,
              'symlink': os.readlink(path) if path.is_symlink() else None,
              'needed': [], 'search_paths': [], 'target_imports': []}
    with path.open('rb') as stream:
        if hash_bytes:
            result['sha256'] = hashlib.file_digest(stream, 'sha256').hexdigest()
            stream.seek(0)
        magic = stream.read(6)
        if magic != b'\x7fELF\x02\x01':
            result['kind'] = 'other-native-format'
            return result
        result['kind'] = 'elf64-le'
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            result['elf_machine'] = struct.unpack_from('<H', data, 18)[0]
            offset = struct.unpack_from('<Q', data, 40)[0]
            size, count = struct.unpack_from('<HH', data, 58)
            if not offset or not count or size != 64:
                raise ValueError('Unsupported ELF section metadata; review required')
            sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * size)
                        for i in range(count)]
            require_dynamic_metadata(sections)
            for section in sections:
                if section[1] not in (6, 11):
                    continue
                strings_section = sections[section[6]]
                strings = data[strings_section[4]:strings_section[4] + strings_section[5]]
                def string(index):
                    return strings[index:strings.index(b'\0', index)].decode('ascii')
                for position in range(section[4], section[4] + section[5], section[9]):
                    if section[1] == 6:
                        tag, value = struct.unpack_from('<qQ', data, position)
                        if tag == 1:
                            result['needed'].append(string(value))
                        elif tag in (15, 29):
                            result['search_paths'].append(string(value))
                    else:
                        name, _, _, index, _, _ = struct.unpack_from('<IBBHQQ', data, position)
                        if index == 0 and string(name) in TARGETS:
                            result['target_imports'].append(string(name))
    result['target_imports'] = sorted(set(result['target_imports']))
    return result


def capture():
    if any(os.environ.get(key) for key in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'LD_AUDIT')):
        raise ValueError('Loader environment overrides require a fresh applicability review')
    files = {}
    for root in ROOTS:
        for parent, directories, names in os.walk(root, followlinks=False):
            directories[:] = sorted(x for x in directories if x not in ('.git', '__pycache__'))
            for name in sorted(names):
                if name.endswith('.node'):
                    path = Path(parent) / name
                    if not path.is_file():
                        raise ValueError('Non-regular native addon: ' + str(path))
                    files[str(path)] = inspect_file(path)
    node = shutil.which('node')
    if not node:
        raise ValueError('Node executable missing from the candidate PATH')
    node_info = inspect_file(Path(node), hash_bytes=False)
    if node_info.get('elf_machine') != 183:
        raise ValueError('Require the ARM64 Linux Node runtime')
    if node_info['search_paths']:
        raise ValueError('Node library search paths require a fresh applicability review')
    requested = set(node_info['needed'])
    foreign = []
    for path, entry in files.items():
        if entry.get('elf_machine') != 183 or any('musl' in name or name == 'libc.so' for name in entry['needed']):
            foreign.append(path)
            continue
        if entry['search_paths']:
            raise ValueError('Addon library search paths require review: ' + path)
        requested.update(entry['needed'])
    cache = subprocess.check_output(['/sbin/ldconfig', '-p'], text=True)
    providers = {}
    for line in cache.splitlines():
        match = re.match(r'\s*(\S+)\s+\([^)]*AArch64[^)]*\)\s+=>\s+(\S+)', line)
        if match:
            name, path = match.groups()
            providers.setdefault(name, set()).add(str(Path(path).resolve(strict=True)))
    libraries = {}
    while requested:
        name = requested.pop()
        paths = providers.get(name, set())
        if len(paths) != 1:
            raise ValueError('Ambiguous or missing loader provider: ' + name)
        path = next(iter(paths))
        if path in libraries:
            continue
        entry = inspect_file(Path(path))
        if entry['search_paths']:
            raise ValueError('Runtime library search paths require review: ' + path)
        libraries[path] = entry
        requested.update(entry['needed'])
    return {'schema': 1, 'base_image': BASE_IMAGE, 'roots': ROOTS, 'files': files,
            'node_needed': node_info['needed'], 'runtime_libraries': libraries,
            'foreign_platform_addons': sorted(foreign),
            'scope': 'Physical .node files under the listed roots; symlink file targets are hashed; directory symlinks are not traversed',
            'limitation': 'Static imports/dependencies do not exclude dlsym, dlopen, future addons or other native consumers'}


def verify(expected, candidate):
    for key, required in [('schema', 1), ('base_image', BASE_IMAGE), ('roots', ROOTS)]:
        if expected.get(key) != required or candidate.get(key) != required:
            raise ValueError('Native contract scope mismatch: ' + key)
    if not expected.get('files'):
        raise ValueError('An empty baseline is not an accepted native contract')
    if not expected.get('node_needed') or not expected.get('runtime_libraries'):
        raise ValueError('Missing baseline dependency capture')
    for entry in [*expected['files'].values(), *expected.get('runtime_libraries', {}).values()]:
        if entry.get('target_imports'):
            raise ValueError('Baseline target imports require a fresh review')
    if set(expected['files']) != set(candidate['files']):
        raise ValueError('Native addon file set changed; applicability review required')
    changed = [path for path in expected['files'] if expected['files'][path] != candidate['files'][path]]
    if changed:
        raise ValueError('Native addon bytes/metadata changed: ' + ', '.join(changed))
    for key in ('node_needed', 'runtime_libraries', 'foreign_platform_addons'):
        if expected.get(key) != candidate.get(key):
            raise ValueError('Native dependency inventory changed: ' + key)
    return {'status': 'unchanged-native-addon-inventory', 'addon_files': len(expected['files']),
            'runtime_libraries': len(expected.get('runtime_libraries', {})),
            'bundled_zlib_source_fixed': False,
            'limitation': 'This binds the reviewed deployment inventory only; dynamic lookup and the exported unpatched Node zlib functions remain outside a global source-fix claim'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected', type=Path, help='Omit only when capturing the pinned-base inventory')
    args = parser.parse_args()
    current = capture()
    if args.expected:
        data = args.expected.read_bytes()
        result = verify(json.loads(data), current)
        result['contract_sha256'] = hashlib.sha256(data).hexdigest()
    else:
        result = current
    print(json.dumps(result, indent=2, sort_keys=True))
