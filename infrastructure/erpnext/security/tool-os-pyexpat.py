#!/usr/bin/env python3
"""Build and validate the pinned CPython XML extension pair without replacing Python."""
import argparse
import ctypes
import hashlib
import importlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import sysconfig
import tarfile

HERE = Path(__file__).resolve().parent
MODULES = ('pyexpat', '_elementtree')


def validate_upstream_log(log, suites):
    """Require CPython's complete good-module summary, not a successful exit alone."""
    plain = re.sub(r'\x1b\[[0-9;]*m', '', log)
    count = len(suites)
    lines = plain.splitlines()
    if (f'All {count} tests OK.' not in lines
            or f'Total test files: run={count}/{count}' not in lines
            or any(name not in plain for name in suites)):
        raise ValueError('Incomplete or unsuccessful upstream XML module results')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(*args, **kwargs):
    result = subprocess.run(list(args), text=True, capture_output=True, timeout=120, **kwargs)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args!r}\n{result.stdout}\n{result.stderr}')
    return result.stdout


def require_runtime(lock):
    if (platform.system() != 'Linux' or platform.machine() != 'aarch64'
            or platform.python_version() != lock['python_version']):
        raise ValueError('Require the exact pinned Linux ARM64 CPython runtime')
    variables = dict(lock['baseline']['variables'], **lock['standard_extension_flags'])
    for key, value in variables.items():
        if sysconfig.get_config_var(key) != value:
            raise ValueError('Interpreter configuration changed: ' + key)
    if sys.base_prefix != '/usr/local':
        raise ValueError('Unexpected Python base prefix')


def verify_baseline(lock):
    require_runtime(lock)
    root = Path(sysconfig.get_config_var('INCLUDEPY'))
    actual = {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*.h'))}
    if actual != lock['baseline']['headers']:
        raise ValueError('Installed Python headers differ from the audited interpreter')
    for name, expected in lock['baseline']['files'].items():
        path = Path(name)
        if path.is_symlink() or not path.is_file() or digest(path) != expected['sha256']:
            raise ValueError('Pinned Python module/configuration preimage changed: ' + name)
        st = path.stat()
        if (st.st_uid, st.st_gid, oct(st.st_mode & 0o777)) != (expected['uid'], expected['gid'], expected['mode']):
            raise ValueError('Pinned Python file metadata changed: ' + name)


def require_expat(lock):
    library = Path('/usr/lib/aarch64-linux-gnu/libexpat.so.1').resolve(strict=True)
    value = ctypes.CDLL(str(library))
    value.XML_ExpatVersion.restype = ctypes.c_char_p
    if value.XML_ExpatVersion().decode() != 'expat_' + lock['expat_version']:
        raise ValueError('Require the verified system Expat security update first')
    return {'path': str(library), 'sha256': digest(library), 'version': value.XML_ExpatVersion().decode()}


def extract_source(path, destination, prefix):
    with tarfile.open(path) as archive:
        for member in archive:
            parts = Path(member.name).parts
            if (not parts or parts[0] != prefix or Path(member.name).is_absolute()
                    or '..' in parts or not (member.isfile() or member.isdir())):
                raise ValueError('Unexpected source archive path or special member')
        archive.extractall(destination, filter='data')


def build(lock, inputs, output):
    verify_baseline(lock)
    expat = require_expat(lock)
    work = Path('/security-work')
    for name, entry in lock['sources'].items():
        path = inputs / name
        if path.is_symlink() or path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
            raise ValueError('Source identity mismatch: ' + name)
    extract_source(inputs / 'Python-3.14.10.tar.xz', work, 'Python-3.14.10')
    extract_source(inputs / 'expat-2.10.0.tar.xz', work, 'expat-2.10.0')
    source = work / 'Python-3.14.10'
    for name, expected in lock['source_members'].items():
        if digest(source / name) != expected:
            raise ValueError('CPython source member changed: ' + name)
    configuration = work / 'extension-config'; configuration.mkdir()
    shutil.copyfile(source / 'Modules/expat/expat_config.h', configuration / 'expat_config.h')
    modules = output / 'modules'; modules.mkdir()
    include = Path(sysconfig.get_config_var('INCLUDEPY'))
    # The original, installed pyconfig.h and core headers describe this exact
    # interpreter. Expat's new public headers are used; bundled old headers are
    # deliberately never placed on the compiler search path.
    includes = [include, include / 'internal', include / 'internal/mimalloc',
                work / 'expat-2.10.0/lib', configuration]
    if not all(p.is_dir() for p in includes):
        raise ValueError('Required installed core or Expat headers are missing')
    standard = lock['standard_extension_flags']
    flags = shlex.split(standard['PY_CFLAGS']) + shlex.split(sysconfig.get_config_var('CCSHARED'))
    for flag in shlex.split(standard['PY_CFLAGS_NODIST']):
        if flag in lock['compiler_adjustments']['removed_flags']:
            continue
        if flag in ('-I./Include/internal', '-I./Include/internal/mimalloc'):
            continue  # The corresponding audited installed paths follow.
        flags.append(flag)
    flags += ['-I' + str(p) for p in includes]
    link = work / 'extension-link'; link.mkdir()
    (link / 'libexpat.so').symlink_to(expat['path'])
    commands = []
    for name in MODULES:
        target = modules / (name + sysconfig.get_config_var('EXT_SUFFIX'))
        command = shlex.split(standard['BLDSHARED']) + shlex.split(standard['PY_LDFLAGS_NODIST']) + flags
        command += [str(source / ('Modules/' + name + '.c')), '-o', str(target)]
        if name == 'pyexpat':
            command += ['-L' + str(link), '-lexpat']
        commands.append(command)
        result = subprocess.run(command, text=True, capture_output=True, timeout=300)
        (output / (name + '-compile.log')).write_text(result.stdout + result.stderr)
        result.check_returncode()
        target.chmod(0o755)
        dynamic = run('readelf', '-d', str(target))
        if 'RPATH' in dynamic or 'RUNPATH' in dynamic:
            raise ValueError('Temporary library search paths must not enter the module')
        if name == 'pyexpat' and 'Shared library: [libexpat.so.1]' not in dynamic:
            raise ValueError('pyexpat must link to system libexpat.so.1')
        (output / (name + '-elf.txt')).write_text(dynamic)
    notices = output / 'notices'; notices.mkdir()
    shutil.copyfile(source / 'LICENSE', notices / 'CPython-LICENSE')
    shutil.copyfile(work / 'expat-2.10.0/COPYING', notices / 'Expat-COPYING')
    testlib = work / 'extension-tests'; testlib.mkdir()
    (testlib / 'test').symlink_to(source / 'Lib/test', target_is_directory=True)
    receipt = {'status': 'compiled-not-tested', 'python': sys.version, 'source_lock_sha256': digest(inputs / 'tool-os-pyexpat.lock.json'),
               'system_expat': expat, 'commands': commands, 'module_directory': str(modules),
               'test_library': str(testlib), 'modules': {p.name: digest(p) for p in modules.iterdir()},
               'notices': {p.name: digest(p) for p in notices.iterdir()},
               'compiler_adjustments': lock['compiler_adjustments'], 'compiler': run('gcc', '--version'),
               'source_modifications': False, 'interpreter_replaced': False}
    (output / 'build-identity.json').write_text(json.dumps(receipt, indent=2) + '\n')


def smoke(lock, expected_modules):
    require_runtime(lock)
    expat = require_expat(lock)
    import pyexpat
    import _elementtree
    import xml.etree.ElementTree as ET
    import xml.dom.minidom as minidom
    import xml.sax
    values = {}
    for name in MODULES:
        module = importlib.import_module(name)
        path = Path(module.__file__).resolve()
        if path.parent != expected_modules.resolve():
            raise ValueError('Wrong XML extension was imported: ' + str(path))
        values[name] = {'path': str(path), 'sha256': digest(path)}
    if pyexpat.version_info != (2, 10, 0) or pyexpat.EXPAT_VERSION != expat['version']:
        raise ValueError('Python is not using the fixed Expat library')
    names = {'pyexpat': dir(pyexpat), 'parser': dir(pyexpat.ParserCreate()), '_elementtree': dir(_elementtree)}
    for name, expected in lock['baseline']['public_names'].items():
        if set(expected) - set(names[name]):
            raise ValueError('A baseline XML public API is missing: ' + name)
    assert ET.Element is _elementtree.Element
    for text in ('<invoice><amount>125</amount></invoice>', '<invoice>தமிழ்</invoice>'):
        for encoding in ('utf-8', 'utf-16'):
            raw = text.encode(encoding)
            parser = pyexpat.ParserCreate(); parser.Parse(raw, True)
            element = ET.fromstring(raw); assert element.tag == 'invoice'
            assert minidom.parseString(raw).documentElement.tagName == 'invoice'
            xml.sax.parseString(raw, xml.sax.handler.ContentHandler())
    try:
        pyexpat.ParserCreate().Parse(b'<invoice><amount></invoice>', True)
    except pyexpat.ExpatError:
        pass
    else:
        raise ValueError('Malformed ordinary XML was not rejected')
    loaded = sorted({row.split(maxsplit=5)[5] for row in Path('/proc/self/maps').read_text().splitlines() if '/libexpat.so.' in row})
    if loaded != [expat['path']]:
        raise ValueError('Unexpected Expat library loaded: ' + repr(loaded))
    return {'status': 'passed', 'python': sys.version, 'modules': values, 'system_expat': expat,
            'public_api_preserved': True, 'normal_xml_roundtrips': True, 'malformed_xml_rejected': True,
            'elementtree_c_accelerator': True, 'loaded_expat': loaded}


def prepare_pair(lock, artifacts, output):
    if os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1' or os.geteuid() != 0:
        raise ValueError('Install only inside the isolated candidate builder')
    verify_baseline(lock)
    identity = json.loads((artifacts / 'build-identity.json').read_text())
    if identity['source_lock_sha256'] != digest(HERE / 'tool-os-pyexpat.lock.json'):
        raise ValueError('Build and installer source locks differ')
    if require_expat(lock) != identity['system_expat']:
        raise ValueError('Candidate Expat bytes differ from the tested build')
    suffix = lock['baseline']['variables']['EXT_SUFFIX']
    expected = {name + suffix for name in MODULES}
    if set(identity['modules']) != expected:
        raise ValueError('Require exactly the coupled XML extension pair')
    if {p.name for p in (artifacts / 'modules').iterdir()} != expected:
        raise ValueError('Unexpected or missing extension artifact')
    notices = {'CPython-LICENSE', 'Expat-COPYING'}
    if set(identity['notices']) != notices or {p.name for p in (artifacts / 'notices').iterdir()} != notices:
        raise ValueError('Require exactly the original source license notices')
    for name in notices:
        path = artifacts / 'notices' / name
        if path.is_symlink() or not path.is_file() or not path.stat().st_size or digest(path) != identity['notices'][name]:
            raise ValueError('Original source notice artifact changed')
    for name in expected:
        path = artifacts / 'modules' / name
        if path.is_symlink() or not path.is_file() or digest(path) != identity['modules'][name]:
            raise ValueError('Tested module artifact changed')
    target = Path('/usr/local/lib/python3.14/lib-dynload')
    output.mkdir(parents=True)
    (output / 'original-module-metadata.json').write_text(json.dumps({
        name: lock['baseline']['files'][str(target / name)] for name in expected}, indent=2) + '\n')
    for name in expected:
        temporary = target / (name + '.erp-new')
        with temporary.open('xb') as stream:
            stream.write((artifacts / 'modules' / name).read_bytes())
        temporary.chmod(0o755)
    # Both verified files are prepared before either replacement. No application
    # process runs here. Original bytes remain in the preserved baseline image,
    # never in final-image evidence where they could retain vulnerable code.
    for name in expected:
        (target / (name + '.erp-new')).replace(target / name)
    return identity, target


def install(lock, artifacts, output):
    tested = json.loads((artifacts / 'upstream-result.json').read_text())
    if tested.get('status') != 'passed' or tested.get('suites') != lock['upstream_tests']:
        raise ValueError('Require successful complete selected upstream parser suites')
    identity = json.loads((artifacts / 'build-identity.json').read_text())
    if (identity.get('status') != 'compiled-and-upstream-tests-passed'
            or tested.get('module_hashes_before') != identity['modules']
            or tested.get('module_hashes_after') != identity['modules']):
        raise ValueError('Require the exact module pair verified before and after upstream tests')
    identity, target = prepare_pair(lock, artifacts, output)
    results = {}
    for python in ('/usr/local/bin/python3', '/home/frappe/frappe-bench/env/bin/python'):
        results[python] = json.loads(run(python, '-B', str(HERE / 'tool-os-pyexpat.py'), 'smoke', '--modules', str(target)))
    shutil.copytree(artifacts / 'notices', output / 'notices')
    (output / 'installed.json').write_text(json.dumps({'status': 'passed', 'checks': results,
        'source_lock_sha256': digest(HERE / 'tool-os-pyexpat.lock.json'), 'build_identity': identity}, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('baseline', 'build', 'smoke', 'install'))
    parser.add_argument('--inputs', type=Path, default=Path('/security-input'))
    parser.add_argument('--output', type=Path, default=Path('/security-output'))
    parser.add_argument('--modules', type=Path)
    parser.add_argument('--artifacts', type=Path)
    args = parser.parse_args()
    lock = json.loads((HERE / 'tool-os-pyexpat.lock.json').read_text())
    if args.action == 'baseline': verify_baseline(lock)
    elif args.action == 'build': build(lock, args.inputs, args.output)
    elif args.action == 'smoke':
        if args.modules is None: parser.error('--modules is required for smoke')
        print(json.dumps(smoke(lock, args.modules)))
    elif args.action == 'install':
        if args.artifacts is None: parser.error('--artifacts is required for install')
        install(lock, args.artifacts, args.output)


if __name__ == '__main__':
    main()
