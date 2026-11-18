#!/usr/bin/env python3
"""Use the upstream build and complete ordinary tests with locked offline inputs."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import zipfile
import lxml_recovery

INPUT, WORK, OUTPUT = Path('/security-input'), Path('/security-work'), Path('/security-output')
APP_PYTHON = Path('/home/frappe/frappe-bench/env/bin/python')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    lock = json.loads((INPUT/'lxml-artifacts.lock.json').read_text())
    for entry in lock['sources'] + lock['build_test_wheels']:
        path = INPUT/entry['filename']
        if path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
            raise ValueError('Changed locked input: '+path.name)
    recovery = None
    if (INPUT/'recovery').exists():
        recovery_lock = json.loads((INPUT/'lxml-recovery.lock.json').read_text())
        recovery = lxml_recovery.restore(INPUT/'recovery', WORK, OUTPUT, recovery_lock,
                                        digest(INPUT/'lxml-artifacts.lock.json'))
        if (OUTPUT/'build-package-versions.txt').read_bytes() != (INPUT/'recovery/build-package-versions.txt').read_bytes():
            raise ValueError('Recovery compiler/base package versions differ from the compiled checkpoint')
    else:
        with tarfile.open(INPUT/'lxml-6.1.3.tar.gz') as archive:
            archive.extractall(WORK, filter='data')
    source = WORK/'lxml-6.1.3'
    env = dict(os.environ, HOME=str(WORK), CFLAGS='-O1 -g0 -fPIC',
        CXXFLAGS='-O1 -g0 -fPIC', LDFLAGS='-Wl,-Bsymbolic-functions',
        MAKEFLAGS='-j1', STATIC_DEPS='true', LIBXML2_VERSION='2.15.4',
        LIBXSLT_VERSION='1.1.45', LIBICONV_VERSION='1.19', ZLIB_VERSION='1.4',
        MULTICORE='1', DOWNLOAD_DIR=str(INPUT), UV_OFFLINE='1', UV_NO_CACHE='1',
        PIP_NO_INDEX='1', PIP_DISABLE_PIP_VERSION_CHECK='1')
    steps = []
    def run(args, name, cwd=source, build_env=env):
        path = OUTPUT/name
        with path.open('w') as stream:
            result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=build_env,
                stdout=stream, stderr=subprocess.STDOUT, timeout=2400)
        steps.append({'log': name, 'exit_code': result.returncode, 'sha256': digest(path)})
        (OUTPUT/'steps.json').write_text(json.dumps(steps, indent=2)+'\n')
        if result.returncode: raise RuntimeError('Ordinary build/check failed: '+name)
    run([APP_PYTHON, '-m', 'venv', WORK/'venv'], 'venv.log')
    python = WORK/'venv/bin/python'
    requirements = WORK/'build-requirements.txt'
    requirements.write_text(''.join(f"{item['name']}=={item['version']} --hash=sha256:{item['sha256']}\n"
        for item in lock['build_test_wheels']))
    run(['uv', 'pip', 'install', '--python', python, '--no-index', '--no-deps', '--require-hashes',
         '--find-links', INPUT, '-r', requirements], 'build-dependencies.log')
    run(['uv', 'pip', 'check', '--python', python], 'build-dependency-check.log')
    if not recovery:
        run([python, INPUT/'lxml-offline-setup.py', '--without-cython', 'build_ext', '--inplace', '-j1'], 'compile.log')
    prefix = source/'build/tmp/libxml2'
    dependency_paths = {key: str(prefix/value) for key, value in
        [('CPATH', 'include'), ('LIBRARY_PATH', 'lib'), ('LD_LIBRARY_PATH', 'lib')]}
    # Upstream's separate test targets also need the dependencies installed in its private prefix.
    dependency_env = dict(env, **dependency_paths)
    prefix_files = [prefix/name for name in ('include/zlib.h', 'include/zconf.h',
        'lib/libz.a', 'lib/libiconv.a', 'lib/libxml2.a', 'lib/libxslt.a')]
    (OUTPUT/'dependency-test-environment.json').write_text(json.dumps({
        'environment': dependency_paths,
        'installed_inputs': {str(path.relative_to(prefix)): digest(path) for path in prefix_files},
        'generated_makefile_flags_preserved': True}, indent=2)+'\n')
    # Preserve this exact compiled tree so a later test-setup failure need not trigger recompilation.
    compiled = {str(path.relative_to(source)): digest(path) for path in (source/'src/lxml').rglob('*.so')}
    if len(compiled) != 7: raise ValueError('Expected seven compiled lxml extensions before checkpoint')
    if not recovery:
        checkpoint = OUTPUT/'compiled-source.tar.gz'
        with tarfile.open(checkpoint, 'w:gz', compresslevel=1) as archive:
            archive.add(source, arcname=source.name)
        (OUTPUT/'compiled-source.json').write_text(json.dumps({
            'status': 'compiled-before-ordinary-tests-not-validated',
            'archive': checkpoint.name, 'sha256': digest(checkpoint), 'bytes': checkpoint.stat().st_size,
            'base_image': lock['base_image'], 'source_lock_sha256': digest(INPUT/'lxml-artifacts.lock.json'),
            'compiled_extensions': compiled, 'completed_steps': steps,
            'recipes': {name: digest(INPUT/name) for name in ('build-lxml-inside.py', 'lxml-offline-setup.py')}}, indent=2)+'\n')
    production = dict(compiled, **{str(path.relative_to(source)): digest(path)
                                  for path in (source/'build').rglob('*.a')})
    for name, version in [('zlib', '1.4'), ('libiconv', '1.19'), ('libxml2', '2.15.4'), ('libxslt', '1.1.45')]:
        candidates = list((source/'build/tmp').rglob(name+'-'+version))
        if len(candidates) != 1: raise ValueError('Cannot identify compiled dependency '+name)
        dependency = candidates[0]
        if name == 'libxml2':
            fixture = lxml_recovery.fixture_source(dependency, INPUT, lock)
            # Static-only libtool omits the shared fixture required by the unchanged module-loader test.
            run(['make', '-j1', 'testdso.la'], 'libxml2-module-fixture-target.log', cwd=dependency, build_env=dependency_env)
            run(['cc', '-shared', '-fPIC', '-O1', '-g0', '-Iinclude', 'testdso.c', '-o', '.libs/testdso.so'],
                'libxml2-module-fixture-compile.log', cwd=dependency, build_env=dependency_env)
            if fixture != lxml_recovery.fixture_source(dependency, INPUT, lock):
                raise ValueError('Module fixture preparation changed upstream source/configuration')
            fixture['shared_fixture_sha256'] = digest(dependency/'.libs/testdso.so')
            (OUTPUT/'libxml2-module-fixture.json').write_text(json.dumps(fixture, indent=2)+'\n')
        run(['make', '-j1', 'check'], name+'-ordinary-tests.log', cwd=dependency, build_env=dependency_env)
        lxml_recovery.verify_binaries(source, production)
        for notice in dependency.rglob('*'):
            if notice.is_file() and any(word in notice.name.lower() for word in ('copying', 'copyright', 'license', 'notice')):
                relative = notice.relative_to(dependency)
                target = source/('LICENSE.'+name+'.'+str(relative).replace('/', '.'))
                shutil.copy2(notice, target)
    # No regular-expression selection or exclusion: all upstream unit/functional levels.
    run([python, 'test.py', '-u', '-f', '--all-levels', '-v'], 'lxml-ordinary-tests.log')
    test_log = (OUTPUT/'lxml-ordinary-tests.log').read_text()
    counts = re.findall(r'Ran (\d+) tests?', test_log)
    if not counts or int(counts[-1]) == 0: raise ValueError('Upstream suite did not report executed tests')
    run([python, INPUT/'lxml-offline-setup.py', '--without-cython', 'bdist_wheel', '--dist-dir', OUTPUT], 'wheel.log')
    lxml_recovery.verify_binaries(source, production)
    wheels = list(OUTPUT.glob('lxml-6.1.3-*.whl'))
    if len(wheels) != 1: raise ValueError('Expected one Linux lxml wheel')
    wheel = wheels[0]
    with zipfile.ZipFile(wheel) as archive:
        names = archive.namelist()
        for dependency in ('zlib', 'libiconv', 'libxml2', 'libxslt'):
            if not any('/LICENSE.'+dependency+'.' in name for name in names):
                raise ValueError('Bundled dependency legal notices absent: '+dependency)
        extensions = {'lxml/'+str(path.relative_to(source/'src/lxml')): path
                      for path in (source/'src/lxml').rglob('*.so')}
        expected = {'lxml/etree', 'lxml/objectify', 'lxml/builder', 'lxml/_elementpath',
                    'lxml/html/diff', 'lxml/html/_difflib', 'lxml/sax'}
        if ({name.split('.', 1)[0] for name in extensions} != expected
                or len(extensions) != len(expected)
                or set(extensions) != {name for name in names if name.endswith('.so')}):
            raise ValueError('Expected the complete seven-extension upstream-tested wheel')
        for name, extension in extensions.items():
            if archive.read(name) != extension.read_bytes():
                raise ValueError('Wheel differs from the upstream-tested extension')
    run(['uv', 'pip', 'install', '--python', APP_PYTHON, '--no-index', '--no-deps', '--reinstall-package', 'lxml', wheel], 'wheel-install.log')
    run([APP_PYTHON, INPUT/'lxml-ordinary-compatibility.py'], 'ordinary-compatibility.json', cwd=WORK)
    # Retain object/static-library material and the exact sources/recipe for relinking.
    with tarfile.open(OUTPUT/'relink-objects.tar.gz', 'w:gz') as archive:
        for path in sorted((source/'build').rglob('*')):
            if path.is_file() and path.suffix in ('.o', '.a'):
                archive.add(path, arcname=str(path.relative_to(source)))
    receipt = {'status': 'passed', 'base_image': lock['base_image'], 'source_lock_sha256': digest(INPUT/'lxml-artifacts.lock.json'),
        'ordinary_tests_exit_code': 0, 'ordinary_tests_run': int(counts[-1]),
        'ordinary_test_summary': test_log[-2000:], 'steps': steps,
        'wheel': wheel.name, 'wheel_sha256': digest(wheel), 'wheel_bytes': wheel.stat().st_size,
        'relink_objects_sha256': digest(OUTPUT/'relink-objects.tar.gz'),
        'sources': lock['sources'], 'application_mounts': [], 'compile_test_network': 'disabled',
        'production_binary_hashes': production, 'production_binaries_unchanged': True,
        'compiled_checkpoint_recovery': recovery, 'module_fixture': fixture,
        'limits': ['Linux arm64 and the pinned ERP Python interpreter only; full app/renderer compatibility is a later image gate.']}
    (OUTPUT/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')


if __name__ == '__main__':
    main()
