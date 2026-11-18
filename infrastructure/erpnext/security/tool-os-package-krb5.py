#!/usr/bin/env python3
"""Preserve the installed four-library Kerberos contract during a source rebuild."""
import ctypes
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

PACKAGES = {
    'libkrb5support0': 'libkrb5support.so.0',
    'libk5crypto3': 'libk5crypto.so.3',
    'libkrb5-3': 'libkrb5.so.3',
    'libgssapi-krb5-2': 'libgssapi_krb5.so.2',
}
WORK = Path('/security-work')
OUTPUT = Path('/security-output')
LIBDIR = Path('usr/lib/aarch64-linux-gnu')
VERSION = '1.22.3-0+erp1'
ABI_CONTRACT = 'tool-os-krb5-abi-exception.json'
# These exact non-runtime files are excluded by the pinned Debian slim image; copyright remains required.
IMAGE_EXCLUDED_PATHS = {
    'libkrb5support0': {'/usr/share/doc/libkrb5support0/changelog.Debian.gz', '/usr/share/lintian/overrides/libkrb5support0'},
    'libk5crypto3': {'/usr/share/doc/libk5crypto3/changelog.Debian.gz'},
    'libkrb5-3': {'/usr/share/doc/libkrb5-3/README.Debian', '/usr/share/doc/libkrb5-3/README.gz',
                 '/usr/share/doc/libkrb5-3/changelog.Debian.gz', '/usr/share/lintian/overrides/libkrb5-3'},
    'libgssapi-krb5-2': {'/usr/share/doc/libgssapi-krb5-2/changelog.Debian.gz', '/usr/share/lintian/overrides/libgssapi-krb5-2'},
}


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True).stdout


def capture():
    """Snapshot before installing build prerequisites can upgrade dependencies."""
    baseline = WORK / 'baseline'
    baseline.mkdir()
    rows = {}
    for package in PACKAGES:
        control = run('dpkg-query', '-s', package)
        assert 'Version: 1.21.3-5+deb13u1\n' in control, package
        paths = run('dpkg-query', '-L', package).splitlines()
        preserved, excluded = [], []
        for name in paths:
            source = Path(name)
            target = baseline / source.relative_to('/')
            if source.is_symlink():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(source.readlink())
            elif source.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif source.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            else:
                if name not in IMAGE_EXCLUDED_PATHS[package]:
                    raise ValueError('Missing baseline package path: ' + name)
                excluded.append(name)
                continue
            preserved.append(name)
        rows[package] = {'control': control, 'paths': preserved,
                         'declared_paths': paths, 'image_excluded_paths': excluded}
    (OUTPUT / 'original-package-contracts.json').write_text(json.dumps(rows, indent=2) + '\n')


def symbols(path):
    lines = run('nm', '-D', '--defined-only', str(path)).splitlines()
    return {line.split()[-1] for line in lines if line.split()}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_abi_contract(directory=None):
    directory = directory or Path(__file__).resolve().parent
    source = json.loads((directory/'tool-os-krb5.lock.json').read_text())
    path = directory/ABI_CONTRACT
    if (source['abi_exception']['file'] != ABI_CONTRACT or path.is_symlink()
            or digest(path) != source['abi_exception']['sha256']):
        raise ValueError('Reviewed image-specific ABI contract changed')
    contract = json.loads(path.read_text())
    return contract, source


def reviewed_removal(missing, context, contract):
    expected = {'base_image': contract['base_image'],
        'baseline_version': contract['baseline_package_version'],
        'candidate_version': contract['candidate_package_version'],
        'upstream_version': contract['upstream_version'], 'source_sha256': contract['source_sha256'],
        'provider_path': contract['baseline_provider']['path'],
        'provider_sha256': contract['baseline_provider']['sha256'], 'soname': contract['soname']}
    if context != expected or missing != {contract['removed_symbol']}:
        raise ValueError('Removed exported symbols differ from exact reviewed ERP image contract')
    return {'missing_symbols': sorted(missing), 'full_export_parity': False,
            'scope': contract['scope'], 'reviewed_context': context,
            'review_evidence_sha256': {k: v['sha256'] for k, v in contract['review_evidence'].items()}}


def notice(contract):
    return ('MIT Kerberos 1.22.3, locally rebuilt with four pinned Debian compatibility patches '
        'and a local test-error reporting correction. Full corresponding source, signatures and '
        'build recipes are retained with the build receipt. Only the previously installed runtime '
        'libraries and plugin are packaged.\nImage-specific ABI difference: '+contract['removed_symbol']+
        ' is absent following upstream private-parser replacement. All other baseline exports '
        'remain required. This is not a generic full ABI parity claim. Reviewed ERP consumer '
        'inventory and final installed consumer/GSS checks are required.\n')


def require_consumer_scope(inventory, contract, documentation):
    target = contract['removed_symbol'].split('@')[0]
    if (inventory.get('status') != 'completed' or inventory.get('errors')
            or inventory.get('roots') != ['/usr', '/opt', '/home', '/etc']
            or inventory.get('target') != target):
        raise ValueError('Installed consumer inventory is incomplete or changed scope')
    bundled = contract['unmodified_bundled_provider']; found = False
    for item in inventory['matches']:
        elf = item['elf']
        if elf and target in elf['imports']:
            raise ValueError('Installed ELF imports removed internal symbol: '+item['path'])
        if item['path'] == bundled['path']:
            if (item['sha256'] != bundled['sha256'] or not elf
                    or target not in elf['definitions']):
                raise ValueError('Untouched bundled GSS provider changed')
            found = True
        elif item['target_literal']:
            if elf or documentation.get(item['path']) != item['sha256']:
                raise ValueError('New literal lookup consumer of removed internal symbol: '+item['path'])
    if not found:
        raise ValueError('Reviewed untouched bundled GSS provider missing')


def check_abi(original, candidate, soname):
    dynamic = run('readelf', '-d', str(candidate))
    if soname and re.search(r'\(SONAME\).*\[' + re.escape(soname) + r'\]', dynamic) is None:
        raise ValueError('Changed SONAME: ' + str(candidate))
    old, new = symbols(original), symbols(candidate)
    missing = old - new
    evidence = {'missing_symbols': [], 'full_export_parity': True}
    if missing:
        if soname != PACKAGES['libgssapi-krb5-2']:
            raise ValueError('Removed exported symbols: ' + ', '.join(sorted(missing)))
        contract, source = load_abi_contract()
        controls = json.loads((OUTPUT/'original-package-contracts.json').read_text())
        baseline_version = re.search(r'^Version: (.+)$', controls['libgssapi-krb5-2']['control'], re.M).group(1)
        context = {'base_image': source['base_image'], 'baseline_version': baseline_version,
            'candidate_version': VERSION, 'upstream_version': source['upstream_version'],
            'source_sha256': source['sources'][contract['source_archive']]['sha256'],
            'provider_path': '/'+str(original.relative_to(WORK/'baseline')),
            'provider_sha256': digest(original), 'soname': soname}
        evidence = reviewed_removal(missing, context, contract)
        evidence['contract_sha256'] = digest(Path(__file__).resolve().parent/ABI_CONTRACT)
    return dict(evidence, soname=soname, old_symbols=len(old), new_symbols=len(new), dynamic_section=dynamic)


def package():
    baseline, installed = WORK / 'baseline', WORK / 'installed'
    contracts = json.loads((OUTPUT / 'original-package-contracts.json').read_text())
    source = WORK / 'krb5-1.22.3'
    metadata = source / 'debian'
    metadata.mkdir(exist_ok=True)
    contract, _ = load_abi_contract()
    (metadata / 'control').write_text('Source: krb5\nSection: libs\nPriority: optional\nMaintainer: ERP local security build <security@localhost>\n\n' +
        '\n'.join(f'Package: {p}\nArchitecture: any\nDescription: MIT Kerberos runtime library\n' for p in PACKAGES))
    shlibs = source / 'local-shlibs'
    shlibs.write_text(''.join(f'{soname.split(".so.")[0]} {soname.split(".so.")[1]} {pkg} (= {VERSION})\n'
                             for pkg, soname in PACKAGES.items()))
    evidence = {}
    for pkg, soname in PACKAGES.items():
        target = WORK / ('package-' + pkg)
        target.mkdir()
        elf = []
        for name in contracts[pkg]['paths']:
            relative = Path(name).relative_to('/')
            old = baseline / relative
            dest = target / relative
            # Keep notices and package-owned directories; replace every binary with the new build.
            candidate = installed / relative if relative.is_relative_to(LIBDIR) else old
            if old.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
            elif old.is_symlink():
                assert candidate.is_symlink(), str(candidate)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.symlink_to(candidate.readlink())
            else:
                assert candidate.is_file(), str(candidate)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(candidate, dest)
                if dest.read_bytes()[:4] == b'\x7fELF':
                    expected = soname if dest.parent == target / LIBDIR else None
                    evidence[str(relative)] = check_abi(old, dest, expected)
                    run('strip', '--strip-unneeded', str(dest))
                    evidence[str(relative)]['candidate_sha256'] = digest(dest)
                    elf.extend(['-e', str(dest)])
        assert elf, pkg
        doc = target / 'usr/share/doc' / pkg
        doc.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / 'NOTICE', doc / 'NOTICE.upstream')
        (doc / 'README.erp-security').write_text(notice(contract))
        dependencies = run('dpkg-shlibdeps', '-O', '-L' + str(shlibs), '-l' + str(installed / LIBDIR), *elf, cwd=source)
        matches = re.findall(r'^shlibs:Depends=(.+)$', dependencies, re.M)
        assert len(matches) == 1, dependencies
        admin = target / 'DEBIAN'
        admin.mkdir()
        (admin / 'control').write_text(f'Package: {pkg}\nVersion: {VERSION}\nArchitecture: arm64\nMulti-Arch: same\nSource: krb5\nSection: libs\nPriority: optional\nMaintainer: ERP local security build <security@localhost>\nDepends: {matches[0]}\nDescription: MIT Kerberos runtime library, local security rebuild\n Official MIT Kerberos 1.22.3 with preserved Debian runtime compatibility.\n')
        (admin / 'shlibs').write_text(next(x for x in shlibs.read_text().splitlines() if f' {pkg} ' in x) + '\n')
        (admin / 'triggers').write_text('activate-noawait ldconfig\n')
        run('dpkg-deb', '--root-owner-group', '--build', str(target), str(OUTPUT / f'{pkg}_{VERSION}_arm64.deb'))
    (OUTPUT / 'abi-comparison.json').write_text(json.dumps(evidence, indent=2) + '\n')
    original = contract['baseline_provider']['path'].lstrip('/')
    (OUTPUT/'abi-exception-evidence.json').write_text(json.dumps(evidence[original], indent=2)+'\n')


def require_name_roundtrip(expected, displayed, expected_oid, returned_oid):
    class OID(ctypes.Structure):
        _fields_ = [('length', ctypes.c_uint32), ('elements', ctypes.c_void_p)]
    if expected != displayed or not expected_oid or not returned_oid:
        raise ValueError('GSS displayed name or name type differs')
    left = ctypes.cast(expected_oid, ctypes.POINTER(OID)).contents
    right = ctypes.cast(returned_oid, ctypes.POINTER(OID)).contents
    if (left.length != right.length
            or ctypes.string_at(left.elements, left.length) != ctypes.string_at(right.elements, right.length)):
        raise ValueError('GSS name-type OID value differs')


def smoke():
    contract, _ = load_abi_contract()
    proof_path = OUTPUT/'abi-exception-evidence.json'
    proof = json.loads(proof_path.read_text())
    if (proof.get('contract_sha256') != digest(Path(__file__).resolve().parent/ABI_CONTRACT)
            or proof.get('missing_symbols') != [contract['removed_symbol']]
            or proof.get('full_export_parity') is not False
            or digest(Path(contract['baseline_provider']['path'])) != proof.get('candidate_sha256')):
        raise ValueError('Installed GSS bytes differ from reviewed build ABI evidence')
    loaded = [ctypes.CDLL(soname) for soname in PACKAGES.values()]
    krb = ctypes.CDLL('libkrb5.so.3')
    ctx = ctypes.c_void_p()
    krb.krb5_init_context.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    krb.krb5_init_context.restype = ctypes.c_int32
    krb.krb5_free_context.argtypes = [ctypes.c_void_p]
    assert krb.krb5_init_context(ctypes.byref(ctx)) == 0 and ctx.value
    krb.krb5_free_context(ctx)
    gss = ctypes.CDLL('libgssapi_krb5.so.2')
    minor, mechs = ctypes.c_uint32(), ctypes.c_void_p()
    gss.gss_indicate_mechs.argtypes = [ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_void_p)]
    gss.gss_indicate_mechs.restype = ctypes.c_uint32
    gss.gss_release_oid_set.argtypes = gss.gss_indicate_mechs.argtypes
    gss.gss_release_oid_set.restype = ctypes.c_uint32
    assert gss.gss_indicate_mechs(ctypes.byref(minor), ctypes.byref(mechs)) == 0 and mechs.value
    assert gss.gss_release_oid_set(ctypes.byref(minor), ctypes.byref(mechs)) == 0
    class Buffer(ctypes.Structure):
        _fields_ = [('length', ctypes.c_size_t), ('value', ctypes.c_void_p)]
    name, displayed, kind = ctypes.c_void_p(), Buffer(), ctypes.c_void_p()
    text = b'erp-security-synthetic-user'
    data = ctypes.create_string_buffer(text)
    input_name = Buffer(len(text), ctypes.cast(data, ctypes.c_void_p))
    user_name = ctypes.c_void_p.in_dll(gss, 'GSS_C_NT_USER_NAME')
    gss.gss_import_name.argtypes = [ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(Buffer), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    gss.gss_display_name.argtypes = [ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p, ctypes.POINTER(Buffer), ctypes.POINTER(ctypes.c_void_p)]
    gss.gss_release_name.argtypes = [ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_void_p)]
    gss.gss_release_buffer.argtypes = [ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(Buffer)]
    assert gss.gss_import_name(ctypes.byref(minor), ctypes.byref(input_name), user_name, ctypes.byref(name)) == 0 and name.value
    try:
        assert gss.gss_display_name(ctypes.byref(minor), name, ctypes.byref(displayed), ctypes.byref(kind)) == 0
        require_name_roundtrip(text, ctypes.string_at(displayed.value, displayed.length), user_name, kind)
    finally:
        assert gss.gss_release_buffer(ctypes.byref(minor), ctypes.byref(displayed)) == 0
        assert gss.gss_release_name(ctypes.byref(minor), ctypes.byref(name)) == 0
    versions = {p: run('dpkg-query', '-W', '-f=${Version}', p) for p in PACKAGES}
    assert set(versions.values()) == {VERSION}, versions
    loaded.append(ctypes.CDLL('/usr/lib/aarch64-linux-gnu/krb5/plugins/preauth/spake.so'))
    maps = {line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines() if '/' in line}
    paths = [Path('/usr/lib/aarch64-linux-gnu')/soname for soname in PACKAGES.values()]
    paths.append(Path('/usr/lib/aarch64-linux-gnu/krb5/plugins/preauth/spake.so'))
    if any(str(path.resolve()) not in maps for path in paths):
        raise ValueError('Canonical GSS/Kerberos runtime library or plugin was not loaded')
    helper = Path(__file__).with_name('tool-os-krb5-consumers.py')
    if digest(helper) != contract['consumer_inventory_sha256']:
        raise ValueError('Reviewed installed-consumer verifier changed')
    raw = subprocess.run([sys.executable, str(helper), contract['removed_symbol'].split('@')[0]],
                         check=True, capture_output=True, text=True, timeout=150).stdout
    inventory = json.loads(raw)
    documents = {str(Path(__file__).with_name(ABI_CONTRACT)): digest(Path(__file__).with_name(ABI_CONTRACT)),
                 str(proof_path): digest(proof_path)}
    notice_hash = hashlib.sha256(notice(contract).encode()).hexdigest()
    documents.update({str(Path('/usr/share/doc')/pkg/'README.erp-security'): notice_hash for pkg in PACKAGES})
    require_consumer_scope(inventory, contract, documents)
    (OUTPUT/'installed-consumer-inventory.json').write_text(raw)
    print(json.dumps({'versions': versions, 'context_round_trip': True, 'gss_mechanisms': True,
        'gss_name_roundtrip': True, 'spake_load': True, 'canonical_native_libraries_loaded': True,
        'installed_consumer_recheck': True, 'consumer_inventory_sha256': hashlib.sha256(raw.encode()).hexdigest(),
        'loaded_library_sha256': {str(path.resolve()): digest(path.resolve()) for path in paths},
        'missing_internal_symbol': contract['removed_symbol'], 'full_export_parity': False,
        'bundled_psycopg2_kerberos_source_fixed': False,
        'scope': contract['scope'], 'dynamic_lookup_limits': inventory['limits']}))


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1:3] == ['smoke', '--consumer-output']:
        OUTPUT = Path(sys.argv[3])
    elif len(sys.argv) != 2:
        raise SystemExit('Expected capture, package or smoke [--consumer-output PATH]')
    if sys.argv[1] not in ('capture', 'package', 'smoke'):
        raise SystemExit('Expected capture, package or smoke')
    globals()[sys.argv[1]]()
