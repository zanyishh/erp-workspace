#!/usr/bin/env python3
"""Hash-check curated offline artifacts and build only an isolated candidate image.

Input JSON contains base_image, artifacts {context_name: {source,sha256,bytes}},
debian_packages [{artifact,name,version,architecture}], python_packages
[{artifact,name,version}]. Required test evidence is checked before building.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parents[2]
BASE = 'frappe/erpnext@sha256:32145acc7f699dc598ca141018a95ebf8e56f516d4a0e76beb7287ae68b303b8'
DOCKER = ['docker', '--context', 'colima-erp']
MIB = 1024**2
SCRIPTS = {name: DIRECTORY/name for name in ('assemble-runtime.py', 'runtime-python-pins.py',
    'runtime-node-critical.py', 'validate-runtime.py', 'build-assets.py', 'os-runtime-compatibility.py',
    'install-runtime-perl.py', 'archive-tar-ordinary-compatibility.pl', 'runtime-component-evidence.py',
    'install-runtime-pip.py', 'check-runtime-os.py', 'util-linux-ordinary-compatibility.py',
    'tool-os-package-krb5.py', 'tool-os-krb5-consumers.py', 'tool-os-check-curl.py', 'ncurses-compatibility.py',
    'tool-os-check-libsndfile.py', 'tool-os-pyexpat.py', 'install-runtime-node.py', 'node-runtime-ordinary.cjs',
    'os-node-native-contract.py', 'install-runtime-debs.py')}
SCRIPTS.update({name: ROOT/'scripts/quality'/name for name in ('install_runtime_node.py',
    'check_runtime_node.cjs', 'check_runtime_vite.mjs', 'check_runtime_vue.cjs',
    'check_runtime_decoder.cjs', 'check_runtime_node_legacy.cjs', 'check_runtime_postcss.cjs')})
CONTRACTS = {'runtime-artifacts.lock.json': DIRECTORY/'runtime-artifacts.lock.json',
    'runtime-python-postgres.lock.json': DIRECTORY/'runtime-python-postgres.lock.json',
    'archive-tar-artifacts.lock.json': DIRECTORY/'archive-tar-artifacts.lock.json',
    'lxml-artifacts.lock.json': DIRECTORY/'lxml-artifacts.lock.json',
    'pip-artifacts.lock.json': DIRECTORY/'pip-artifacts.lock.json',
    'tool-os-pyexpat.lock.json': DIRECTORY/'tool-os-pyexpat.lock.json',
    'node-runtime.lock.json': DIRECTORY/'node-runtime.lock.json',
    'runtime-node-native-contract.lock.json': DIRECTORY/'runtime-node-native-contract.lock.json',
    'runtime-node-manifest.json': ROOT/'infrastructure/erpnext/quality/runtime-node-manifest.json',
    'runtime-node-legacy-baseline.json': ROOT/'infrastructure/erpnext/quality/runtime-node-legacy-baseline.json'}
CONTRACTS.update({name: DIRECTORY/name for name in ('runtime-os-closure.lock.json', 'os-artifacts.lock.json',
    'util-linux-artifacts.lock.json', 'tool-os-krb5.lock.json', 'tool-os-curl.lock.json',
    'ncurses-artifacts.lock.json', 'tool-os-libsndfile.lock.json', 'sqlite-abi-contract.json',
    'os-x11-abi-contract.json', 'tool-os-krb5-abi-exception.json')})
VITE_ROOT = '/home/frappe/frappe-bench/apps/erpnext/banking/node_modules/vite'
NATIVE_CANDIDATE_ADDITIONS = {VITE_ROOT+'/node_modules/'+name for name in (
    'lightningcss/node_modules/lightningcss-linux-arm64-gnu/lightningcss.linux-arm64-gnu.node',
    'lightningcss/node_modules/lightningcss-linux-arm64-musl/lightningcss.linux-arm64-musl.node',
    'rolldown/node_modules/@rolldown/binding-linux-arm64-gnu/rolldown-binding.linux-arm64-gnu.node',
    'rolldown/node_modules/@rolldown/binding-linux-arm64-musl/rolldown-binding.linux-arm64-musl.node')}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(MIB), b''): value.update(block)
    return value.hexdigest()


def ordinary(path):
    path = Path(path).absolute()
    if any(item.is_symlink() for item in [path, *path.parents]):
        raise ValueError('Linked artifact/state paths are not accepted')
    return path


def metadata(path):
    return {'sha256': digest(path), 'bytes': path.stat().st_size}


def check_manifest(manifest, tool_home):
    if manifest.get('base_image') != BASE:
        raise ValueError('Only the reviewed immutable ERP base is accepted')
    allowed = [ROOT/'.local/quality/security-remediation', tool_home/'security-remediation']
    files = {}
    for name, entry in manifest['artifacts'].items():
        relative = PurePosixPath(name)
        if (relative.is_absolute() or '..' in relative.parts or not relative.parts
                or relative.parts[0] not in {'chrome.zip', 'node-critical.tar.gz', 'artifacts', 'debs', 'wheels', 'node', 'perl', 'evidence'}):
            raise ValueError('Unexpected build-context artifact name: '+name)
        path = ordinary(entry['source'])
        if not any(path.is_relative_to(folder) for folder in allowed) or not path.is_file():
            raise ValueError('Artifact source must be inside owned security staging')
        if not re.fullmatch('[0-9a-f]{64}', entry.get('sha256', '')) or not 0 <= entry.get('bytes', -1) <= 600*MIB:
            raise ValueError('Artifact needs an exact hash and bounded byte count')
        if metadata(path) != {'sha256': entry['sha256'], 'bytes': entry['bytes']}:
            raise ValueError('Artifact checksum/size mismatch: '+name)
        files[name] = path
    if sum(path.stat().st_size for path in files.values()) > 1500*MIB:
        raise ValueError('Curated build context exceeds its storage budget')
    debs = manifest['debian_packages']
    required = {'libxml2', 'libexpat1', 'libmariadb3', 'mariadb-client', 'mariadb-client-core',
                'mariadb-common', 'libpq5', 'libpq-dev', 'postgresql-client-17'}
    if not required <= {item['name'] for item in debs}:
        raise ValueError('Required Debian replacements are missing')
    if len({item['name'] for item in debs}) != len(debs): raise ValueError('Duplicate Debian package')
    for item in debs:
        if (not item['artifact'].startswith('debs/') or not item['artifact'].endswith('.deb')
                or item['artifact'] not in files or item['architecture'] not in {'arm64', 'all'}):
            raise ValueError('Invalid Debian artifact contract')
    python = manifest['python_packages']
    versions = {item['name'].lower().replace('_', '-'): item['version'] for item in python}
    if versions.get('gitpython') != '3.2.1' or versions.get('pypdf') != '6.21.4' or versions.get('lxml') != '6.1.3':
        raise ValueError('Fixed Python dependency contracts are missing')
    if set(versions) != {'gitpython', 'pypdf', 'flit-core', 'lxml'} or len(python) != 4:
        raise ValueError('Provide the three runtime wheels and offline Flit backend')
    for item in python:
        if not item['artifact'].startswith('wheels/') or not item['artifact'].endswith('.whl') or item['artifact'] not in files:
            raise ValueError('Python dependencies require local hashed wheels')
    return files


def check_pyexpat_gates(manifest, files):
    prefix = 'artifacts/pyexpat/'
    data = lambda name: json.loads(files[prefix+name].read_text())
    receipt, identity, tested = (data(name) for name in ('receipt.json', 'build-identity.json', 'upstream-result.json'))
    source = json.loads(CONTRACTS['tool-os-pyexpat.lock.json'].read_text())
    source_hash = digest(CONTRACTS['tool-os-pyexpat.lock.json'])
    expected = {name+source['baseline']['variables']['EXT_SUFFIX'] for name in ('pyexpat', '_elementtree')}
    if (receipt.get('status') != 'built-upstream-tests-and-isolated-compatibility-passed-runtime-validation-pending'
            or receipt.get('exit_code') != 0 or receipt.get('cleanup_errors') or receipt.get('container_retained')
            or receipt.get('base_image') != BASE or receipt.get('source') != source
            or receipt.get('source_lock_sha256') != source_hash or receipt.get('application_mounts') != []
            or identity.get('status') != 'compiled-and-upstream-tests-passed'
            or identity.get('source_lock_sha256') != source_hash
            or tested.get('status') != 'passed' or tested.get('exit_code') != 0
            or tested.get('suites') != source['upstream_tests']
            or set(identity.get('modules', {})) != expected
            or receipt.get('modules') != identity['modules']
            or tested.get('module_hashes_before') != identity['modules']
            or tested.get('module_hashes_after') != identity['modules']
            or tested.get('junit', {}).get('tests', 0) <= 0
            or tested['junit'].get('failures') != 0 or tested['junit'].get('errors') != 0):
        raise ValueError('Require the exact paired Python XML modules and complete upstream test evidence')
    if set(identity.get('notices', {})) != {'CPython-LICENSE', 'Expat-COPYING'}:
        raise ValueError('Require both original XML source notices')
    source_root = files[prefix+'receipt.json'].parent
    for name in ('build-identity.json', 'upstream-result.json', 'upstream-tests.log', 'upstream-tests.xml',
                 *('modules/'+name for name in expected), *('notices/'+name for name in identity['notices'])):
        key = prefix+name
        if (files[key] != source_root/name
                or manifest['artifacts'][key]['sha256'] != receipt['artifacts'].get(name)):
            raise ValueError('Python XML artifact differs from its completed build receipt')
    for kind in ('modules', 'notices'):
        for name, value in identity[kind].items():
            if manifest['artifacts'][prefix+kind+'/'+name]['sha256'] != value:
                raise ValueError('Python XML tested payload identity changed')
    # A successful interpreter exit can include skipped whole modules. Bind the
    # actual retained log to the same strict module-summary check as the builder.
    spec = importlib.util.spec_from_file_location('xml_pair_check', DIRECTORY/'tool-os-pyexpat.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    helper.validate_upstream_log(files[prefix+'upstream-tests.log'].read_text(), source['upstream_tests'])


def check_node_runtime_inputs(manifest, files):
    lock = json.loads(CONTRACTS['node-runtime.lock.json'].read_text())
    archive = 'artifacts/node-v24.22.3-linux-arm64.tar.xz'
    staging = 'evidence/node-runtime/staging-receipt.json'
    baseline = 'evidence/node-runtime/preimage.json'
    receipt = json.loads(files[staging].read_text())
    if (lock.get('status') != 'verified-inputs-runtime-validation-pending' or lock.get('base_image') != BASE
            or lock.get('before', {}).get('node') != '24.22.2' or lock.get('after', {}).get('node') != '24.22.3'
            or lock['after'].get('modules') != '137' or lock['after'].get('sqlite') != '3.54.1'
            or manifest['artifacts'][archive]['sha256'] != lock['archive']['sha256']
            or manifest['artifacts'][archive]['bytes'] != lock['archive']['bytes']
            or manifest['artifacts'][staging]['sha256'] != lock['staging_receipt_sha256']
            or manifest['artifacts'][baseline]['sha256'] != lock['baseline_receipt_sha256']
            or receipt.get('status') != lock['source_verification']
            or receipt.get('files', {}).get(lock['archive']['filename'], {}).get('sha256') != lock['archive']['sha256']):
        raise ValueError('Require the exact official Node runtime archive and verified baseline/staging evidence')


def check_node_runtime_gates(manifest, files):
    check_node_runtime_inputs(manifest, files)
    prefix = 'evidence/node-runtime/validation/'
    if prefix+'receipt.json' not in files:
        raise ValueError('Actual isolated Node installation and ordinary runtime validation must finish first')
    receipt = json.loads(files[prefix+'receipt.json'].read_text())
    if (receipt.get('status') != 'installed-and-ordinary-tests-passed-candidate-image-validation-pending'
            or receipt.get('exit_code') != 0 or receipt.get('cleanup_errors') or receipt.get('container_retained')
            or receipt.get('base_image') != BASE or receipt.get('network') != 'none'
            or receipt.get('application_mounts') != []
            or receipt.get('source_lock_sha256') != digest(CONTRACTS['node-runtime.lock.json'])
            or receipt.get('sources', {}).get('install-runtime-node.py') != digest(SCRIPTS['install-runtime-node.py'])
            or receipt.get('sources', {}).get('node-runtime-ordinary.cjs') != digest(SCRIPTS['node-runtime-ordinary.cjs'])):
        raise ValueError('Node ordinary validation source/runtime receipt does not match current inputs')
    for name, field in [('install/receipt.json', 'installed_receipt_sha256'),
                        ('ordinary.json', 'ordinary_receipt_sha256'), ('validation.log', 'validation_log_sha256')]:
        if (manifest['artifacts'][prefix+name]['sha256'] != receipt[field]
                or files[prefix+name] != files[prefix+'receipt.json'].parent/name):
            raise ValueError('Node validation evidence changed after ordinary checks')


def verify_native_candidate_inventory(baseline, candidate, additions):
    if set(additions) != NATIVE_CANDIDATE_ADDITIONS or set(baseline['files']) & set(additions):
        raise ValueError('Require exactly the four reviewed nested Vite native addons')
    providers = set(baseline['node_needed'])
    for entry in [*baseline['files'].values(), *baseline['runtime_libraries'].values()]:
        providers.update(entry.get('needed', []))
    for path, entry in additions.items():
        if (entry.get('elf_machine') != 183 or entry.get('target_imports') or entry.get('search_paths')
                or '-gnu/' in path and set(entry['needed'])-providers):
            raise ValueError('Added native addon imports/providers require a fresh review: '+path)
    expected = json.loads(json.dumps(baseline))
    expected['files'].update(additions)
    expected['foreign_platform_addons'] = sorted([*baseline['foreign_platform_addons'],
        *(path for path in additions if '-musl/' in path)])
    if candidate != expected:
        raise ValueError('Native candidate differs from the unchanged baseline and four exact reviewed additions')


def native_candidate_additions(manifest, files):
    node = json.loads(CONTRACTS['runtime-node-manifest.json'].read_text())
    targets = [item for item in node['replacements'] if item['package']=='vite']
    if (len(targets)!=1 or targets[0]['target_path']!=VITE_ROOT or targets[0]['replacement_version']!='8.2.4'
            or targets[0]['archive']!='vite-8.2.4.tgz'):
        raise ValueError('Unexpected reviewed Vite native-addon source')
    key='node/'+targets[0]['archive']; archive=files[key]
    if digest(archive)!=targets[0]['tar_sha256'] or manifest['artifacts'][key]['sha256']!=targets[0]['tar_sha256']:
        raise ValueError('Vite native-addon archive differs from the reviewed manifest')
    spec=importlib.util.spec_from_file_location('native_metadata', SCRIPTS['os-node-native-contract.py'])
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    additions={}
    with tempfile.TemporaryDirectory(prefix='erp-native-metadata-') as temporary, tarfile.open(archive) as package:
        for member in package:
            if not member.name.endswith('.node'): continue
            relative=PurePosixPath(member.name)
            path=VITE_ROOT+'/'+str(relative).removeprefix('package/')
            if (not member.isfile() or relative.parts[0]!='package' or '..' in relative.parts
                    or path not in NATIVE_CANDIDATE_ADDITIONS or path in additions):
                raise ValueError('Unexpected native addon archive path/type')
            target=Path(temporary)/Path(member.name).name
            filtered=tarfile.data_filter(member,temporary)
            with package.extractfile(member) as source, target.open('wb') as output: shutil.copyfileobj(source,output)
            target.chmod(filtered.mode)
            additions[path]=helper.inspect_file(target)
    return additions


def check_node_native_gates(manifest, files):
    lock = json.loads(CONTRACTS['runtime-node-native-contract.lock.json'].read_text())
    if (lock.get('base_image') != BASE or lock.get('bundled_zlib_source_fixed') is not False
            or lock.get('verifier_sha256') != digest(SCRIPTS['os-node-native-contract.py'])):
        raise ValueError('Native-addon applicability verifier or its explicit scope changed')
    for name in ('baseline', 'assessment', 'verification', 'candidate'):
        key = lock[name+'_artifact']
        if (key not in files or manifest['artifacts'][key]['sha256'] != lock[name+'_sha256']):
            raise ValueError('Preserve the exact native-addon baseline and source assessment')
    verified = json.loads(files[lock['verification_artifact']].read_text())
    if (verified.get('status') != 'passed' or verified.get('exit_code') != 0
            or verified.get('helper_sha256') != lock['verifier_sha256']
            or verified.get('contract_sha256') != lock['baseline_sha256']
            or verified.get('verification', {}).get('bundled_zlib_source_fixed') is not False):
        raise ValueError('Native baseline verification must retain its exact limited applicability scope')
    verify_native_candidate_inventory(json.loads(files[lock['baseline_artifact']].read_text()),
        json.loads(files[lock['candidate_artifact']].read_text()), native_candidate_additions(manifest, files))


def check_local_apt_gates(manifest, files):
    prefix = 'evidence/offline-apt/'
    receipt = json.loads(files[prefix+'receipt.json'].read_text())
    if (receipt.get('status') != 'passed-offline-local-apt-and-ordinary-util-tests'
            or receipt.get('exit_code') != 0 or receipt.get('cleanup_errors') or receipt.get('container_retained')
            or receipt.get('base_image') != BASE or receipt.get('network') != 'none'
            or receipt.get('application_mounts') != []
            or receipt.get('sources', {}).get('install-runtime-debs.py') != digest(SCRIPTS['install-runtime-debs.py'])):
        raise ValueError('Offline local APT validation must match the current installer')
    current = {item['name']: item for item in manifest['debian_packages']}
    scope = json.loads(CONTRACTS['runtime-os-closure.lock.json'].read_text())['components']['util-linux']['packages']
    if set(item['name'] for item in receipt['inputs']['debian_packages']) != set(scope):
        raise ValueError('Offline APT replay must cover all nine dependency-ordered util packages')
    for item in receipt['inputs']['debian_packages']:
        if (current.get(item['name']) != item
                or receipt['inputs']['files'][item['artifact']] != {
                    key: manifest['artifacts'][item['artifact']][key] for key in ('bytes', 'sha256')}):
            raise ValueError('Offline APT replay package inputs differ from the candidate')
    for name, field in [('debian/receipt.json', 'installer_receipt_sha256'),
                        ('compatibility.json', 'ordinary_receipt_sha256')]:
        if (manifest['artifacts'][prefix+name]['sha256'] != receipt[field]
                or files[prefix+name] != files[prefix+'receipt.json'].parent/name):
            raise ValueError('Offline APT replay evidence changed')
    installed = json.loads(files[prefix+'debian/receipt.json'].read_text())
    ordinary = json.loads(files[prefix+'compatibility.json'].read_text())
    versions = {name: value['version'] for name, value in scope.items()}
    if (installed.get('status') != 'passed' or installed.get('repositories') != []
            or installed.get('unlisted_package_changes') != [] or installed.get('selected') != versions
            or installed.get('network') != 'loopback-only' or ordinary.get('status') != 'passed'
            or ordinary.get('uid') == 0 or ordinary.get('mount_operations') is not False
            or ordinary.get('versions') != versions):
        raise ValueError('Offline APT replay did not preserve its package boundary')
    for name, sha in installed['evidence'].items():
        if Path(name).name != name or manifest['artifacts'][prefix+'debian/'+name]['sha256'] != sha:
            raise ValueError('Preserve exact offline package transaction and audit evidence')


def check_gates(manifest, files):
    spec = importlib.util.spec_from_file_location('runtime_os_closure', DIRECTORY/'check-runtime-os-closure.py')
    closure = importlib.util.module_from_spec(spec); spec.loader.exec_module(closure)
    closure.verify(manifest, files, DIRECTORY)
    check_pyexpat_gates(manifest, files)
    check_node_runtime_gates(manifest, files)
    check_node_native_gates(manifest, files)
    check_local_apt_gates(manifest, files)
    def data(name): return json.loads(files[name].read_text())
    lock = json.loads(CONTRACTS['runtime-artifacts.lock.json'].read_text())
    packages = {item['name']: item for item in manifest['debian_packages']}
    browser = data('evidence/browser.json')
    if (browser['status'] != 'verified-staged-not-runtime-validated'
            or browser['archive_sha256'] != manifest['artifacts']['chrome.zip']['sha256']
            or browser['version'] != '157.0.8103.78'):
        raise ValueError('Verified browser staging evidence is required')
    if manifest['artifacts']['artifacts/esbuild-linux-arm64']['sha256'] != lock['go_build']['artifacts']['esbuild-linux-arm64']['sha256']:
        raise ValueError('Go-built esbuild differs from its verified build receipt')
    if not lock['go_build']['steps'] or any(step['exit_code'] for step in lock['go_build']['steps']):
        raise ValueError('Go build/module verification did not pass')
    if manifest['artifacts']['node-critical.tar.gz']['sha256'] != lock['node_critical_overlay']['sha256']:
        raise ValueError('Critical Node archive differs from the reviewed lock')
    node = json.loads(CONTRACTS['runtime-node-manifest.json'].read_text())
    expected = {'node/'+entry['archive']: entry['tar_sha256'] for entry in node['packages']}
    actual = {name: manifest['artifacts'][name]['sha256'] for name in files if name.startswith('node/')}
    if actual != expected: raise ValueError('Provide exactly the reviewed Node archive set')
    xml = data('evidence/libxml2/resource-receipt.json')
    if (xml['exit_code'] != 0 or xml['base_image'] != BASE
            or files['evidence/libxml2/status.txt'].read_text().strip() != 'package-build-and-tests-passed'
            or files['evidence/libxml2/upstream-check.exit'].read_text().strip() != '0'):
        raise ValueError('XML packaging, ordinary checks and regressions must finish first')
    if files[packages['libxml2']['artifact']].parent != files['evidence/libxml2/status.txt'].parent:
        raise ValueError('XML package and its validation must originate in the same build')
    if packages['libxml2']['version'] != lock['libxml2']['local_version']:
        raise ValueError('Unexpected XML backport package version')
    if manifest['artifacts'][packages['libxml2']['artifact']]['sha256'] != lock['libxml2']['built_package_sha256']:
        raise ValueError('XML package differs from the completed ordinary-tested build')
    expat = data('evidence/expat/receipt.json')
    expat_name = packages['libexpat1']['artifact']
    if (expat['status'] != 'built-upstream-tests-passed-runtime-validation-pending'
            or expat['exit_code'] != 0 or expat.get('cleanup_errors')
            or expat['source']['base_image'] != BASE
            or expat['package_sha256'] != manifest['artifacts'][expat_name]['sha256']
            or files[expat_name].parent != files['evidence/expat/receipt.json'].parent):
        raise ValueError('Expat ordinary build/test evidence does not match its package')
    lxml = data('evidence/lxml/receipt.json')
    lxml_build = data('evidence/lxml/resource-receipt.json')
    wheel = next(item['artifact'] for item in manifest['python_packages'] if item['name'].lower() == 'lxml')
    if (lxml.get('status') != 'passed' or lxml.get('ordinary_tests_exit_code') != 0
            or lxml.get('wheel_sha256') != manifest['artifacts'][wheel]['sha256']
            or lxml.get('source_lock_sha256') != digest(CONTRACTS['lxml-artifacts.lock.json'])
            or lxml_build.get('exit_code') != 0 or lxml_build.get('cleanup_errors')
            or lxml_build.get('status') != 'built-upstream-and-ordinary-tests-passed-not-deployed'
            or files[wheel].parent != files['evidence/lxml/receipt.json'].parent):
        raise ValueError('The replacement lxml wheel and ordinary suite are not verified')
    for item in lock['mariadb_client']['packages']:
        target = packages[item['name']]
        if target['version'] != item['version'] or manifest['artifacts'][target['artifact']]['sha256'] != item['sha256']:
            raise ValueError('MariaDB client package differs from official staged bytes')
    official = json.loads(CONTRACTS['runtime-python-postgres.lock.json'].read_text())
    for item in official['postgresql']['packages']:
        target = packages[item['Package']]
        if (target['version'] != item['Version'] or target['architecture'] != item['Architecture']
                or manifest['artifacts'][target['artifact']]['sha256'] != item['SHA256']):
            raise ValueError('PostgreSQL package differs from authenticated Debian metadata')
    python = {item['name'].lower().replace('_', '-'): item for item in manifest['python_packages']}
    for item in official['python_wheels']:
        target = python[item['name'].lower().replace('_', '-')]
        if (target['version'] != item['version']
                or manifest['artifacts'][target['artifact']]['sha256'] != item['artifacts'][0]['sha256']):
            raise ValueError('Python wheel differs from the official artifact lock')
    pip = json.loads(CONTRACTS['pip-artifacts.lock.json'].read_text())
    for name, entry in pip['artifacts'].items():
        if manifest['artifacts']['wheels/'+name]['sha256'] != entry['sha256']:
            raise ValueError('Pip/bootstrap ordinary-check wheel differs from the official lock')
    perl = data('evidence/archive-tar/archive-tar-receipt.json')
    perl_build = data('evidence/archive-tar/receipt.json')
    perl_source = json.loads(CONTRACTS['archive-tar-artifacts.lock.json'].read_text())
    payload_hash = manifest['artifacts']['perl/archive-tar-runtime.tar.gz']['sha256']
    if (perl.get('status') != 'passed' or perl.get('upstream_tests_exit_code') != 0
            or perl.get('version') != '3.14' or perl.get('upstream_tests', 0) <= 0
            or perl.get('files', {}).get('archive-tar-runtime.tar.gz') != payload_hash
            or perl_build.get('exit_code') != 0 or perl_build.get('cleanup_errors')
            or perl_build.get('base_image') != BASE or perl_build.get('source') != perl_source['archive-tar']
            or perl_build.get('container_retained')
            or files['perl/archive-tar-runtime.tar.gz'].parent != files['evidence/archive-tar/receipt.json'].parent
            or perl_build.get('artifacts', {}).get('archive-tar-runtime.tar.gz') != payload_hash):
        raise ValueError('Archive::Tar payload must match a completed ordinary-tested build')


def command(args, env):
    return subprocess.check_output(args, cwd=ROOT, env=env, text=True, stderr=subprocess.STDOUT, timeout=60)


def prepare_context(manifest, files, destination):
    destination.mkdir(mode=0o700)
    sources = {**files, **CONTRACTS, **{'scripts/'+name: path for name, path in SCRIPTS.items()}}
    inventory = {}
    for name, source in sources.items():
        source = ordinary(source)
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        before = metadata(source)
        if name in manifest['artifacts']:
            expected = {key: manifest['artifacts'][name][key] for key in ('sha256', 'bytes')}
            if before != expected: raise ValueError('Artifact changed after verification: '+name)
        # Copied bytes freeze inputs even if another preparation task updates its source.
        shutil.copy2(source, target)
        if metadata(target) != before: raise ValueError('Input changed while staging: '+name)
        inventory[name] = before
    prepared = {'base_image': BASE, 'files': inventory, 'debian_packages': manifest['debian_packages'],
                'python_packages': manifest['python_packages']}
    (destination/'runtime-image-inputs.json').write_text(json.dumps(prepared, indent=2, sort_keys=True)+'\n')
    return prepared


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    if not args.execute:
        print('Plan only: verify locked artifacts and completed tests; freeze curated inputs; stage them in uniquely owned ERP VM root scratch; assemble offline with fresh scratch sites/logs; verify complete image-internal assets; commit with the exact pinned base configuration; retain evidence and remove only owned scratch/containers. No service activation. --inputs MANIFEST --execute requires all inputs and resources ready.')
        return 0
    if not args.inputs: parser.error('--inputs is required for execution')
    sys.path.insert(0, str(ROOT/'scripts/quality'))
    import quality
    quality.require_space(3)
    tool_home = ordinary(quality.TOOL_HOME)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('DOCKER_', 'COMPOSE_', 'ERP_', 'FRAPPE_')) and not key.upper().endswith('_PROXY')}
    env.update(PATH='/opt/homebrew/bin:/usr/local/bin:'+env.get('PATH', ''))
    base = json.loads(command(DOCKER+['image', 'inspect', '--format', '{{json .}}', BASE], env))
    if base['Architecture'] != 'arm64' or base['Os'] != 'linux': raise ValueError('Unexpected pinned base architecture')
    manifest = json.loads(ordinary(args.inputs).read_text())
    files = check_manifest(manifest, tool_home)
    check_gates(manifest, files)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    output = tool_home/'security-remediation'/('image-build-'+stamp)
    output.mkdir(mode=0o700)
    receipt = {'status': 'preparing', 'base_id': base['Id'], 'base_image': BASE,
               'network': 'none', 'application_mounts': [], 'output': str(output)}
    try:
        context = output/'context'
        prepared = prepare_context(manifest, files, context)
        receipt['input_manifest_sha256'] = digest(context/'runtime-image-inputs.json')
        receipt['files'] = prepared['files']
        receipt['tag'] = 'erp-secure-native/runtime:'+stamp.lower()
        spec = importlib.util.spec_from_file_location('runtime_image_controller', DIRECTORY/'runtime-image-controller.py')
        controller = importlib.util.module_from_spec(spec); spec.loader.exec_module(controller)
        controller.assemble(context, output, base, BASE, stamp.lower(), env, receipt)
        if receipt.get('cleanup_errors') or receipt.get('evidence_copy_errors'):
            raise RuntimeError('Owned assembly evidence export/cleanup requires inspection; retained identities are recorded')
        for name, expected in prepared['files'].items():
            if metadata(context/name) != expected: raise ValueError('Build input changed during execution: '+name)
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
