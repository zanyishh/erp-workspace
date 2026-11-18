#!/usr/bin/env python3
"""Preserve Debian curl's ABI and protocol contract through a maintained upgrade."""
import argparse
import ctypes
import email.utils
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import resource
import shlex
import signal
import shutil
import ssl
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import threading

WORK, OUTPUT = Path('/security-work'), Path('/security-output')
LIBDIR = Path('/usr/lib/aarch64-linux-gnu')
LIBRARIES = ('libcurl.so.4', 'libcurl-gnutls.so.4')
VERSION = '8.23.0-2+erp1'
REMOVED_PROTOCOLS = {'smb', 'smbs', 'rtmp'}
REMOVED_FEATURES = {'TLS-SRP'}


def fixture_contract(entry):
    expected = {
        'file':'tool-os-curl-https-mtls-dependency.patch','bytes':252,
        'sha256':'b38b954c46507b9c2c035ef283358131ff376acaa406b6ee12bcdf218935e5b7',
        'target':'tests/servers.pm',
        'original_sha256':'8d07bf529d7fd3423bfe0ccd52f169e07ab98657fa085aebace835ffab0d033b',
        'patched_sha256':'019af30846df55a410b9c5ef39ce359aaeefd71b6fde386c8e14b8567b10659d',
        'scope':'test-fixture dependency lifecycle only; restart mTLS proxy when shared HTTP backend changes; no TLS/auth/assertion/production changes',
        'causal_review_sha256':'a6696f2e46adcb658b3b4bdb2aaeca3b59702ff30f90a0d203e00cf7309c1916'}
    if entry != expected:
        raise ValueError('Test fixture patch differs from exact reviewed source/dependency fix')
    return entry


def patched_fixture(original, entry, patch):
    fixture_contract(entry)
    if (hashlib.sha256(original).hexdigest()!=entry['original_sha256']
            or len(patch)!=entry['bytes'] or hashlib.sha256(patch).hexdigest()!=entry['sha256']):
        raise ValueError('Original fixture or reviewed patch bytes differ')
    anchor=b'        push @killservers, "http/3";\n'
    if original.count(anchor)!=1:raise ValueError('Original fixture dependency anchor changed')
    changed=original.replace(anchor,anchor+b'        push @killservers, "https-mtls";\n',1)
    if hashlib.sha256(changed).hexdigest()!=entry['patched_sha256']:
        raise ValueError('Unexpected fixture change outside the one reviewed dependency')
    return changed


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                          check=True).stdout


def failure_files(build, limit=128*1024**2):
    """A fixed diagnostic checkpoint for 2088/2089/2095, never a build cache."""
    files = set()
    for directory in ('tests/log', 'tests/certs'):
        files.update(p for p in (build/directory).rglob('*') if not p.is_dir() or p.is_symlink())
    def server_binary(path):
        if not path.resolve().is_relative_to(build.resolve()):
            raise ValueError('Server runtime link leaves the owned curl build')
        if path.suffix in ('.o', '.lo', '.a', '.la') or not path.stat().st_mode & 0o111:
            return False
        with path.open('rb') as stream:
            return stream.read(4) == b'\x7fELF'
    for pattern in ('tests/**/*.pl', 'tests/**/*.pm', 'tests/server/*', 'tests/server/.libs/*',
                    'lib/.libs/libcurl.so*'):
        files.update(p for p in build.glob(pattern) if p.is_file() and
                     (p.suffix in ('.pl', '.pm') or p.name.startswith('libcurl.so') or
                      server_binary(p)))
    for name in ('tests/data/DISABLED', 'tests/data/test2088', 'tests/data/test2089',
                 'tests/data/test2095', 'tests/runtests.pl', 'tests/libtest/libtests',
                 'tests/libtest/.libs/libtests', 'src/curl', 'src/.libs/curl', 'libtool'):
        if (build/name).is_file(): files.add(build/name)
    required = ('tests/runtests.pl', 'tests/data/DISABLED', 'tests/data/test2088', 'tests/data/test2089', 'tests/data/test2095',
                'tests/certs/test-ca.crt', 'tests/certs/test-localhost.crt',
                'tests/certs/test-client-cert.crt', 'tests/certs/test-client-cert.key',
                'tests/certs/test-client-eku-only.crt', 'tests/certs/test-client-eku-only.key',
                'tests/libtest/libtests', 'tests/libtest/.libs/libtests', 'src/curl',
                'src/.libs/curl', 'tests/server/servers', 'lib/.libs/libcurl.so.4', 'libtool')
    if any(build/name not in files for name in required):
        raise ValueError('Focused curl runtime is incomplete; no reusable checkpoint')
    regular_targets = {p.resolve() for p in files if not p.is_symlink()}
    if (len(files) > 20000 or sum(p.stat().st_size for p in files if not p.is_symlink()) > limit or
            any(not p.is_file() and not p.is_symlink() for p in files) or
            any(not p.resolve().is_relative_to(build.resolve()) for p in files) or
            any(p.is_symlink() and p.resolve() not in regular_targets
                for p in files)):
        raise ValueError('Curl failure capture exceeds its bound or has an escaping/incomplete link')
    return sorted(files)


def failurecapture():
    """Retain evidence before the original failed lifecycle cleans its own work."""
    build = WORK/'curl-8.23.0/debian/build-openssl'
    report = {'status': 'capture-incomplete', 'failed_exit': args.failed_exit,
              'ordinary_suite_pass': False, 'limit_bytes': 128*1024**2}
    archive = OUTPUT/'failed-openssl-runtime.tar.gz'
    def digest(path):
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, 'sha256').hexdigest()
    try:
        files = failure_files(build)
        report['files'] = {str(p.relative_to(build)): {
            'bytes': p.stat().st_size, 'sha256': digest(p),
            'symlink': os.readlink(p) if p.is_symlink() else None} for p in files}
        report['bindings'] = {str(p): digest(p) for p in [
            *Path('/security-input').glob('*'), *OUTPUT.glob('test-compiler-flags-*.json'),
            *OUTPUT.glob('dependencies/*.deb'), *OUTPUT.glob('mtls-*'), OUTPUT/'build.log',
            OUTPUT/'build-package-versions.txt', OUTPUT/'local-packaging-changes.json'] if p.is_file()}
        report['commands'] = []
        commands = mtls_certificate_commands(build)
        # ldd records resolution for the retained ELF; it is not a retrospective
        # claim about the already-exited client's process maps.
        commands += [['ldd',str(build/name)] for name in
                     ('tests/libtest/.libs/libtests','src/.libs/curl','tests/server/servers')]
        commands += [['ldd', '/usr/bin/stunnel4']]
        providers = set()
        env = dict(os.environ, LD_LIBRARY_PATH=str(build/'lib/.libs'))
        for command in commands:
            result = subprocess.run(command,env=env,capture_output=True,text=True,timeout=5)
            output = result.stdout + result.stderr
            report['commands'].append({'argv':command,'exit_code':result.returncode,'output':output})
            if command[0]=='ldd': providers.update(re.findall(r'(/[^\s()]+)',output))
        report['surviving_process_maps'] = {}
        for process in Path('/proc').glob('[0-9]*'):
            try:
                executable = (process/'exe').resolve(strict=True)
                if executable.is_relative_to(build) or executable.name in ('stunnel','stunnel4'):
                    maps = (process/'maps').read_text()
                    report['surviving_process_maps'][process.name] = {'exe':str(executable),'maps':maps}
                    providers.update(re.findall(r'(/[^\n]+)',maps))
            except (OSError, ValueError): pass  # Original test processes may already have exited.
        report['resolved_or_observed_providers'] = {p:digest(Path(p)) for p in sorted(providers) if Path(p).is_file()}
        with tarfile.open(archive,'w:gz',compresslevel=1) as stream:
            for path in files: stream.add(path,arcname=str(path.relative_to(WORK)),recursive=False)
        if archive.stat().st_size > report['limit_bytes']:
            raise ValueError('Compressed diagnostic checkpoint exceeds its bound')
        report.update(status='failed-run-diagnostic-checkpoint-only',archive_sha256=digest(archive),
                      archive_bytes=archive.stat().st_size)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report['capture_error'] = str(error)
        archive.unlink(missing_ok=True)
    (OUTPUT/'failed-openssl-runtime.json').write_text(json.dumps(report,indent=2)+'\n')


def mtls_commands():
    directory = str(WORK/'curl-8.23.0/debian/build-openssl')
    return [(tag,['make','-C',directory,'-j1','test','TFLAGS=-n -j1 '+selection])
            for tag,selection in [('mtls-isolated','2095'),('mtls-sequence','2088 2089 2095')]]


def mtls_certificate_commands(build):
    commands = [['openssl','version','-a'],['stunnel4','-version']]
    certs = build/'tests/certs'
    for name in ('test-ca','test-localhost','test-client-cert','test-client-eku-only'):
        commands.append(['openssl','x509','-in',str(certs/(name+'.crt')),'-noout',
                         '-sha256','-fingerprint','-subject','-issuer','-dates','-purpose'])
        if name!='test-ca':
            commands.append(['openssl','verify','-CAfile',str(certs/'test-ca.crt'),'-purpose',
                             'sslserver' if name=='test-localhost' else 'sslclient',str(certs/(name+'.crt'))])
    return commands


def mtls_loaded_driver(text, directory):
    return bool(re.search(r'initialize program: .*libtests\s*$',text,re.M)
                and re.search(r'calling init: '+re.escape(str(directory/'lib/.libs/libcurl.so.4'))+r'(?:\.\d+)*\s*$',text,re.M)
                and re.search(r'calling init: /[^\n]+/libssl\.so\.3\s*$',text,re.M))


def mtls_log_files(directory, tag):
    logs = sorted(p for p in (directory/'tests/log').rglob('*') if not p.is_dir() or p.is_symlink())
    traces = sorted(OUTPUT.glob(tag+'.loader.*'))
    files = [OUTPUT/(tag+'.log'),*logs,*traces]
    size = 0
    for path in files:
        try:
            info=path.lstat()
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('Focused diagnostic log has a special/link path')
            size += info.st_size
        except FileNotFoundError: pass  # The live maintained runner rotates its own logs.
    if len(files)>4096 or size>16*1024**2:
        raise ValueError('Focused aggregate main/server/loader log bound exceeded16MiB')
    return logs,traces


def mtls_input_hashes(directory):
    paths = [directory/name for name in ('tests/libtest/.libs/libtests','src/.libs/curl','tests/server/servers')]
    paths += list((directory/'lib/.libs').glob('libcurl.so*'))
    paths += [p for p in (directory/'tests/certs').glob('*') if p.suffix in ('.crt','.key')]
    result = {}
    for path in paths:
        if path.is_file():
            with path.open('rb') as stream:
                result[str(path.relative_to(directory))]=hashlib.file_digest(stream,'sha256').hexdigest()
    return result


def mtlsdiagnose():
    """Two unchanged maintained selections; this is separate from full suites."""
    report = {'status':'diagnostic-incomplete','ordinary_suite_pass':False,'runs':[]}
    directory = WORK/'curl-8.23.0/debian/build-openssl'
    try:
        for tag,command in mtls_commands():
            logfile = OUTPUT/(tag+'.log')
            before_inputs = mtls_input_hashes(directory)
            # glibc records actual loader decisions in separate per-process
            # files, leaving the original driver's stdout/stderr intact.
            env = dict(os.environ,LD_DEBUG='libs',LD_DEBUG_OUTPUT=str(OUTPUT/(tag+'.loader')))
            with logfile.open('w') as stream:
                process = subprocess.Popen(command,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
                deadline=time.monotonic()+180;guard=None
                code=process.poll()
                while code is None:
                    try: mtls_log_files(directory,tag)
                    except ValueError as error: guard=str(error)
                    if time.monotonic()>deadline:guard='Focused diagnostic180second timeout'
                    if guard:
                        try: os.killpg(process.pid,signal.SIGTERM)
                        except ProcessLookupError: pass
                        try: code=process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid,signal.SIGKILL);code=process.wait(timeout=5)
                        break
                    time.sleep(0.05)
                    code=process.poll()
            try: os.killpg(process.pid,0); descendants=True
            except ProcessLookupError: descendants=False
            if guard and descendants:
                try: os.killpg(process.pid,signal.SIGKILL)
                except ProcessLookupError: pass
            entry = {'tag':tag,'command':command,'exit_code':code,'descendants_after_wait':descendants,
                     'guard_failure':guard,'inputs_before_sha256':before_inputs}
            report['runs'].append(entry)
            # Check again after the owned producer closes, before any read/hash.
            try: logs,traces=mtls_log_files(directory,tag)
            except ValueError as error:
                entry['guard_failure']=guard or str(error)
                raise
            if guard or descendants:
                raise ValueError('Focused diagnostic guard/descendants prevented continuation')
            entry['log_sha256']=hashlib.sha256(logfile.read_bytes()).hexdigest()
            entry['inputs_after_sha256']=mtls_input_hashes(directory)
            archive = OUTPUT/(tag+'-complete-test-log.tar.gz')
            with tarfile.open(archive,'w:gz',compresslevel=1) as stream:
                for path in logs: stream.add(path,arcname=str(path.relative_to(directory)),recursive=False)
            entry['test_log_archive_sha256']=hashlib.sha256(archive.read_bytes()).hexdigest()
            entry['loader_trace_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in traces}
            entry['original_driver_candidate_openssl_loader_observed']=any(
                mtls_loaded_driver(p.read_text(),directory) for p in traces)
            providers={name for p in traces for name in re.findall(r'calling init: (/[^\s]+)',p.read_text())}
            entry['observed_provider_sha256']={name:hashlib.sha256(Path(name).read_bytes()).hexdigest()
                                               for name in sorted(providers) if Path(name).is_file()}
            count=1 if tag=='mtls-isolated' else 3
            entry['all_selected_cases_passed']=bool(re.search(
                rf'TESTDONE:\s+{count} tests out of {count} reported OK: 100%',logfile.read_text()))
        if report['runs'][0]['inputs_after_sha256'] != report['runs'][1]['inputs_before_sha256'] or \
                report['runs'][0]['inputs_after_sha256'] != report['runs'][1]['inputs_after_sha256']:
            raise ValueError('Focused selections changed certificate/runtime bytes; identity comparison needs review')
        report['certificate_and_version_commands']=[]
        for command in mtls_certificate_commands(directory):
            result=subprocess.run(command,capture_output=True,text=True,timeout=5)
            report['certificate_and_version_commands'].append({'argv':command,'exit_code':result.returncode,
                                                               'output':result.stdout+result.stderr})
        report['runtime_sha256']={str(p.relative_to(directory)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [directory/'tests/libtest/.libs/libtests',directory/'src/.libs/curl',
                      directory/'tests/server/servers',*(directory/'lib/.libs').glob('libcurl.so*')] if p.is_file()}
        if any(r['exit_code'] or not r['all_selected_cases_passed']
               or not r['original_driver_candidate_openssl_loader_observed'] for r in report['runs']):
            raise ValueError('Original focused mTLS cases failed or were skipped; full suites not claimed')
        if any(c['exit_code'] for c in report['certificate_and_version_commands']):
            raise ValueError('Focused mTLS certificate/version diagnostics did not complete cleanly')
        report['status']='both-focused-selections-passed-full-suites-still-required'
    finally:
        (OUTPUT/'mtls-diagnostic.json').write_text(json.dumps(report,indent=2)+'\n')


def cli_contract(text):
    return {kind.lower(): set(re.search(r'^' + kind + r': (.+)$', text, re.M)[1].split())
            for kind in ('Protocols', 'Features')}


def configured_contract(protocols, features):
    # curl-config reports uppercase protocol identifiers; URL schemes and the
    # curl CLI baseline use their canonical lowercase spelling.
    return {'protocols': {name.lower() for name in protocols.split()},
            'features': set(features.split())}


def protocol_removals(lock=None):
    lock = lock or json.loads(Path(__file__).with_name('tool-os-curl.lock.json').read_text())
    policy = lock['protocol_contract']
    if (lock['upstream_version'] != '8.23.0'
            or lock['sources']['tool-os-curl-8.23.0.tar.xz']['sha256'] != '8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5'
            or set(policy['upstream_removed_protocols']) != REMOVED_PROTOCOLS
            or set(policy['upstream_removed_features']) != REMOVED_FEATURES
            or policy['rtmp_removal_review']['sha256'] != '8ac236cb4f5d93be72bf16547e6ce8482cc90eb91087fd864c73b4c76ccbb495'):
        raise ValueError('Protocol removal differs from exact reviewed source/version/ERP scope')
    return REMOVED_PROTOCOLS


def check_features(old, new):
    for kind, removed in [('protocols', protocol_removals()), ('features', REMOVED_FEATURES)]:
        missing = set(old[kind]) - set(new[kind]) - removed
        if missing:
            raise ValueError('Unapproved missing ' + kind + ': ' + ', '.join(sorted(missing)))


def capture():
    dest = WORK / 'curl-baseline'
    dest.mkdir()
    for name in LIBRARIES:
        shutil.copy2(LIBDIR / name, dest / name)
    # The old compatibility symlink is retained by the new library package.
    assert (LIBDIR / 'libcurl-gnutls.so.3').resolve() == (LIBDIR / 'libcurl-gnutls.so.4').resolve()
    old = run('curl', '--version')
    (OUTPUT / 'original-curl-version.txt').write_text(old)
    controls = {p: run('dpkg-query', '-s', p)
                for p in ['curl', 'libcurl4t64', 'libcurl3t64-gnutls']}
    assert all('Version: 8.14.1-2+deb13u7\n' in c for c in controls.values())
    (OUTPUT / 'original-package-contracts.json').write_text(json.dumps(controls, indent=2) + '\n')


def bounded_test_rules(text):
    tail = '  $(2)\nendef\n'
    build_boundary = '\n# Invoke dh_auto_build for a specific curl flavour.\n'
    if (text.count('$(NUMJOBS) * 4') != 1 or text.count(tail) != 1
            or text.count(build_boundary) != 1
            or text.count('define test-curl\n') != 1
            or text.count('--enable-threaded-resolver') != 1 or '--enable-ntlm' in text
            or 'override CFLAGS' in text or 'ERP_CURL_TEST_BACKEND' in text):
        raise ValueError('Original Debian test/compiler rules changed')
    # GNU Make target-specific append: global CFLAGS remain first, including
    # hardening/typechecks, while only this giant test object ends in -O0 -g0.
    extra = ("  $(2)\nprintf '%s\\n' 'libtests.$$(OBJEXT): override CFLAGS += -O0 -g0 -ftrack-macro-expansion=0' "
             ">> debian/build-$(1)/tests/libtest/Makefile\n"
             "ERP_CURL_TEST_BACKEND=$(1) python3 /security-input/tool-os-check-curl.py testflags\nendef\n")
    gate = '\nifeq ($(ERP_CURL_COMPILER_PROBE),1)\n\tpython3 /security-input/tool-os-check-curl.py compilerprobe\nendif\n'
    diagnostic = ('define test-curl\nif [ "$(1)" = openssl ] && [ "$(ERP_CURL_MTLS_DIAGNOSE)" = 1 ]; '
                  'then python3 /security-input/tool-os-check-curl.py mtlsdiagnose; fi\n')
    return text.replace('$(NUMJOBS) * 4', '$(NUMJOBS)').replace(tail, extra).replace(build_boundary, gate+build_boundary).replace('--enable-threaded-resolver', '--enable-threaded-resolver --enable-ntlm').replace('define test-curl\n',diagnostic)


def require_test_compile_flags(command):
    tokens = shlex.split(command)
    optimize = [token for token in tokens if token.startswith('-O')]
    debug = [token for token in tokens if token.startswith('-g')]
    tracking = [token for token in tokens if token.startswith('-ftrack-macro-expansion')]
    if (not optimize or optimize[-1] != '-O0' or not debug or debug[-1] != '-g0'
            or '-fstack-protector-strong' not in tokens or '-D_FORTIFY_SOURCE=2' not in tokens
            or any(token.startswith('-DCURL_DISABLE_TYPECHECK') for token in tokens)
            or tracking[-1:] != ['-ftrack-macro-expansion=0']
            or not {'-c', '-o', 'libtests.o'} <= set(tokens)):
        raise ValueError('Test-only compiler flags missing, reordered or safety checks disabled')


def testflags():
    backend = os.environ.get('ERP_CURL_TEST_BACKEND')
    if backend not in ('openssl', 'gnutls'):
        raise ValueError('Require an exact Debian curl backend')
    directory = WORK/'curl-8.23.0/debian'/('build-'+backend)
    entries=json.loads(Path(__file__).with_name('tool-os-curl.lock.json').read_text())['patches']
    if len(entries)!=1:raise ValueError('Require the one reviewed test fixture patch')
    fixture=fixture_contract(entries[0])
    fixture_sha=hashlib.sha256((directory/fixture['target']).read_bytes()).hexdigest()
    if fixture_sha!=fixture['patched_sha256']:
        raise ValueError('Configured backend lacks the reviewed fixture dependency lifecycle fix')
    test = run('make', '-n', '-W', 'libtests.c', '-C', str(directory/'tests/libtest'), 'libtests.o')
    commands = [line for line in test.splitlines() if '-c -o libtests.o ' in line]
    if len(commands) != 1:
        raise ValueError('Exact test object compiler command not found')
    require_test_compile_flags(commands[0])
    production = run('make', '-n', '-W', 'altsvc.c', '-C', str(directory/'lib'), 'libcurl_la-altsvc.lo')
    commands = [line for line in production.splitlines() if ' -c ' in line and 'libcurl_la-altsvc.lo' in line]
    if len(commands) != 1:
        raise ValueError('Exact production compiler command not found')
    tokens = shlex.split(commands[0])
    if ([x for x in tokens if x.startswith('-O')][-1:] != ['-O2']
            or '-fstack-protector-strong' not in tokens or '-D_FORTIFY_SOURCE=2' not in tokens
            or any(x.startswith('-DCURL_DISABLE_TYPECHECK') for x in tokens)):
        raise ValueError('Production optimization, hardening or typechecks changed')
    if any(x.startswith('-ftrack-macro-expansion') for x in tokens):
        raise ValueError('Test-only diagnostic flag leaked into production')
    baseline = cli_contract((OUTPUT/'original-curl-version.txt').read_text())
    configured_raw = {kind: run('sh', str(directory/'curl-config'), '--'+kind)
                      for kind in ('protocols', 'features')}
    configured = configured_contract(configured_raw['protocols'], configured_raw['features'])
    check_features(baseline, configured)
    (OUTPUT/('test-compiler-flags-'+backend+'.json')).write_text(json.dumps({
        'status': 'verified-test-object-only', 'backend': backend,
        'actual_test_make_dry_run': test, 'actual_production_make_dry_run': production,
        'last_test_optimization': '-O0', 'last_test_debug': '-g0',
        'production_optimization': '-O2', 'typechecks_disabled': False,
        'test_selection_changed': False, 'configured_contract': {k: sorted(v) for k,v in configured.items()},
        'configured_raw_output': configured_raw,
        'actual_baseline_difference': {k: sorted(baseline[k]-configured[k]) for k in baseline},
        'full_protocol_parity': False, 'NTLM_preserved': 'NTLM' in configured['features'],
        'test_fixture_sha256':fixture_sha,'test_fixture_causal_review_sha256':fixture['causal_review_sha256']}, indent=2)+'\n')


def compiler_fit(exit_code, before, after):
    return (exit_code == 0 and before['memory_max_bytes'] == after['memory_max_bytes'] == 640*1024**2
            and all(after['memory_events'].get(k, 0) == before['memory_events'].get(k, 0)
                    for k in ('oom', 'oom_kill', 'oom_group_kill')))


def cgroup_memory():
    root = Path('/sys/fs/cgroup')
    return {'memory_max_bytes': int((root/'memory.max').read_text()),
            'memory_peak_bytes': int((root/'memory.peak').read_text()),
            'memory_current_bytes': int((root/'memory.current').read_text()),
            'memory_events': {k: int(v) for k, v in (line.split() for line in (root/'memory.events').read_text().splitlines())}}


def compilerprobe():
    """One exact object fit measurement; never an ordinary-suite result."""
    command = ['make', '-C', str(WORK/'curl-8.23.0/debian/build-openssl/tests/libtest'), 'libtests.o']
    before = cgroup_memory()
    if before['memory_max_bytes'] != 640*1024**2:
        raise ValueError('Compiler probe resource cap differs')
    started = time.monotonic(); timed_out = False
    with (OUTPUT/'compiler-probe-build.log').open('w') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try: code = process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            timed_out = True; os.killpg(process.pid, signal.SIGTERM)
            try: code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); code = process.wait(timeout=5)
    try: os.killpg(process.pid, 0); descendants = True
    except ProcessLookupError: descendants = False
    if descendants:
        os.killpg(process.pid, signal.SIGKILL)
    after = cgroup_memory()
    result = {'status': 'compiler-object-fits' if compiler_fit(code, before, after) and not timed_out and not descendants else 'compiler-object-did-not-fit',
        'command': command, 'exit_code': code, 'timed_out': timed_out,
        'descendants_remaining_after_wait': descendants, 'before': before, 'after': after,
        'maximum_descendant_RSS_KiB': resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
        'elapsed_seconds': time.monotonic()-started, 'ordinary_suite_result': False,
        'typechecks_disabled': False, 'test_selection_changed': False,
        'build_log_sha256': hashlib.sha256((OUTPUT/'compiler-probe-build.log').read_bytes()).hexdigest()}
    (OUTPUT/'compiler-probe.json').write_text(json.dumps(result, indent=2)+'\n')
    (OUTPUT/'compiler-probe-finished').touch()
    deadline = time.monotonic()+600
    while not Path('/security-input/compiler-probe-continue.json').exists():
        if time.monotonic()>deadline:
            raise RuntimeError('Bounded compiler-fit review window expired; full production build held')
        time.sleep(1)
    resumeprobe()


def resumeprobe():
    path = OUTPUT/'compiler-probe.json'
    decision = json.loads(Path('/security-input/compiler-probe-continue.json').read_text())
    if (decision != {'probe_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'continue': True}
            or json.loads(path.read_text())['status'] != 'compiler-object-fits'):
        raise ValueError('No full build without reviewed exact successful compiler probe')


def prepare():
    source = WORK / 'curl-8.23.0'
    entries=json.loads(Path(__file__).with_name('tool-os-curl.lock.json').read_text())['patches']
    if len(entries)!=1:raise ValueError('Require the one reviewed test fixture patch')
    fixture=fixture_contract(entries[0]);target=source/fixture['target']
    if target.is_symlink():raise ValueError('Fixture target must be an original regular source file')
    target.write_bytes(patched_fixture(target.read_bytes(),fixture,Path(__file__).with_name(fixture['file']).read_bytes()))
    (OUTPUT/'test-fixture-patch.json').write_text(json.dumps({'status':'applied-reviewed-test-dependency-fix','contract':fixture,'production_source_changed':False,'TLS_or_assertions_changed':False},indent=2)+'\n')
    changelog = source / 'debian/changelog'
    assert changelog.read_text().startswith('curl (8.23.0-2) ')
    entry = f'curl ({VERSION}) trixie; urgency=medium\n\n  * Local rebuild of maintained upstream and Debian packaging on the ERP base.\n  * Retain the previous libcurl-gnutls.so.3 compatibility symlink and NTLM capability.\n  * Upstream removed SMB/SMBS/RTMP and TLS-SRP; exact ERP consumer review retained.\n    This is not a generic protocol-parity claim.\n  * Serialize ordinary tests for the resource-limited builder.\n  * Restart the dependent mTLS test proxy when its shared HTTP fixture changes.\n\n -- ERP local security build <security@localhost>  {email.utils.formatdate(localtime=False)}\n\n'
    changelog.write_text(entry + changelog.read_text())
    rules = source / 'debian/rules'
    old = rules.read_text()
    rules.write_text(bounded_test_rules(old))
    links = source / 'debian/libcurl4-gnutls.links'
    assert not links.exists()
    links.write_text('usr/lib/${DEB_HOST_MULTIARCH}/libcurl-gnutls.so.4 usr/lib/${DEB_HOST_MULTIARCH}/libcurl-gnutls.so.3\n')
    (OUTPUT / 'local-packaging-changes.json').write_text(json.dumps({
        'version': VERSION, 'upstream_source_changes': [fixture], 'upstream_production_source_changes': [],
        'packaging': ['truthful local changelog', 'retain old GnuTLS compatibility symlink', 'test concurrency4->1',
                      'test libtests.o only: append -O0 -g0 -ftrack-macro-expansion=0; production O2/hardening/typechecks unchanged'],
        'maintained_debian_patches': (source / 'debian/patches/series').read_text().splitlines(),
        'upstream_removed_protocols': sorted(REMOVED_PROTOCOLS),
        'upstream_removed_features': sorted(REMOVED_FEATURES)}, indent=2) + '\n')


def exports(path):
    # Old default GNUTLS_3 exports become maintained non-default compatibility
    # aliases; @ versus @@ differs, but the symbol+version contract is retained.
    return {line.split()[-1].replace('@@', '@')
            for line in run('nm', '-D', '--defined-only', str(path)).splitlines() if line.split()}


def packages():
    names = ['curl', 'libcurl4t64', 'libcurl4-gnutls', 'libcurl3t64-gnutls']
    paths = {}
    extract = WORK / 'curl-packages'
    extract.mkdir()
    for name in names:
        found = list(WORK.glob(f'{name}_{VERSION}_arm64.deb'))
        assert len(found) == 1, (name, found)
        target = OUTPUT / found[0].name
        shutil.copy2(found[0], target)
        run('dpkg-deb', '--extract', str(target), str(extract))
        paths[name] = {'filename': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}
    evidence = {}
    for name in LIBRARIES:
        old = WORK / 'curl-baseline' / name
        new = extract / str(LIBDIR).lstrip('/') / name
        dynamic = run('readelf', '-d', str(new))
        assert re.search(r'\(SONAME\).*\[' + re.escape(name) + r'\]', dynamic), dynamic
        missing = exports(old) - exports(new)
        assert not missing, (name, sorted(missing))
        evidence[name] = {'old_exports': len(exports(old)), 'new_exports': len(exports(new)),
                          'missing_exports': [], 'dynamic_section': dynamic}
    old_features = cli_contract((OUTPUT / 'original-curl-version.txt').read_text())
    source = WORK / 'curl-8.23.0'
    for flavor in ('openssl', 'gnutls'):
        new_version = run(str(source / f'debian/build-{flavor}/src/curl'), '--version')
        check_features(old_features, cli_contract(new_version))
        (OUTPUT / f'candidate-{flavor}-version.txt').write_text(new_version)
    (OUTPUT / 'abi-comparison.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (OUTPUT / 'runtime-packages.json').write_text(json.dumps(paths, indent=2) + '\n')


def native_request_diagnostic(name, code, error_buffer, library):
    # Failure context only: no retries, changed TLS policy or changed request.
    report={'library':name,'curlcode':code,'error_buffer':error_buffer.value[:255].decode('utf-8','replace'),'providers':{}}
    try:
        library.curl_easy_strerror.argtypes=[ctypes.c_int]
        library.curl_easy_strerror.restype=ctypes.c_char_p
        library.curl_version.restype=ctypes.c_char_p
        report['strerror']=library.curl_easy_strerror(code)[:256].decode('utf-8','replace')
        report['curl_version']=library.curl_version()[:2048].decode('utf-8','replace')
        with Path('/proc/self/maps').open('rb') as stream: raw=stream.read(1024**2+1)
        if len(raw)>1024**2:raise ValueError('Native provider map exceeds 1MiB bound')
        providers=set()
        for line in raw.decode().splitlines():
            fields=line.split(None,5)
            if len(fields)!=6 or not fields[5].startswith('/'):continue
            path=Path(fields[5])
            if path.name.startswith(('libcurl','libssl','libcrypto','libgnutls','libnghttp','libngtcp')) and '.so' in path.name:
                providers.add(path)
        if len(providers)>16:raise ValueError('Native provider count exceeds 16 bound')
        total=0
        for path in sorted(providers):
            size=path.stat().st_size;total+=size
            if size>32*1024**2 or total>128*1024**2:raise ValueError('Native provider bytes exceed bound')
            with path.open('rb') as stream:sha=hashlib.file_digest(stream,'sha256').hexdigest()
            report['providers'][str(path)]={'bytes':size,'sha256':sha}
    except Exception as error:
        report['diagnostic_error']=str(error)[:1024]
    return json.dumps(report,sort_keys=True)


def lib_request(name, url, certificate):
    library = ctypes.CDLL(str(LIBDIR / name))
    library.curl_easy_init.restype = ctypes.c_void_p
    library.curl_easy_setopt.argtypes = [ctypes.c_void_p, ctypes.c_int]
    library.curl_easy_perform.argtypes = [ctypes.c_void_p]
    library.curl_easy_cleanup.argtypes = [ctypes.c_void_p]
    received = bytearray()
    callback_type = ctypes.CFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p,
                                    ctypes.c_size_t, ctypes.c_size_t, ctypes.c_void_p)
    def receive(pointer, size, number, unused):
        count = size * number
        received.extend(ctypes.string_at(pointer, count))
        return count
    callback = callback_type(receive)
    error_buffer = ctypes.create_string_buffer(256)
    handle = library.curl_easy_init()
    assert handle
    try:
        assert library.curl_easy_setopt(handle, 10002, ctypes.c_char_p(url.encode())) == 0
        assert library.curl_easy_setopt(handle, 10004, ctypes.c_char_p(b'')) == 0
        assert library.curl_easy_setopt(handle, 10065, ctypes.c_char_p(str(certificate).encode())) == 0
        assert library.curl_easy_setopt(handle, 20011, callback) == 0
        assert library.curl_easy_setopt(handle, 10010, error_buffer) == 0
        code = library.curl_easy_perform(handle)
        assert code == 0, native_request_diagnostic(name, code, error_buffer, library)
        assert bytes(received) == b'ERP curl compatibility\n'
    finally:
        library.curl_easy_cleanup(handle)
    if 'gnutls' in name:
        loader = ctypes.CDLL(None)
        loader.dlvsym.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        loader.dlvsym.restype = ctypes.c_void_p
        init = loader.dlvsym(library._handle, b'curl_easy_init', b'CURL_GNUTLS_3')
        cleanup = loader.dlvsym(library._handle, b'curl_easy_cleanup', b'CURL_GNUTLS_3')
        assert init and cleanup
        handle = ctypes.CFUNCTYPE(ctypes.c_void_p)(init)()
        assert handle
        ctypes.CFUNCTYPE(None, ctypes.c_void_p)(cleanup)(handle)


def smoke():
    with tempfile.TemporaryDirectory() as temp:
        directory = Path(temp)
        cert, key = directory / 'cert.pem', directory / 'key.pem'
        run('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
            '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1',
            '-keyout', str(key), '-out', str(cert))
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', str(len(b'ERP curl compatibility\n')))
                self.end_headers()
                self.wfile.write(b'ERP curl compatibility\n')
            def log_message(self, *args):
                pass
        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'https://127.0.0.1:{server.server_port}/'
        try:
            for name in LIBRARIES:
                lib_request(name, url, cert)
            assert run('curl', '--fail', '--silent', '--show-error', '--noproxy', '127.0.0.1', '--cacert', str(cert), url) == 'ERP curl compatibility\n'
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
    new = run('curl', '--version')
    assert 'curl 8.23.0 ' in new
    check_features(cli_contract((OUTPUT / 'original-curl-version.txt').read_text()), cli_contract(new))
    print(json.dumps({'cli_verified_https': True, 'openssl_verified_https': True,
                      'gnutls_verified_https': True, 'gnutls3_symbol_alias': True,
                      'upstream_removed_protocols': sorted(REMOVED_PROTOCOLS),
                      'upstream_removed_features': sorted(REMOVED_FEATURES)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('capture', 'failurecapture', 'mtlsdiagnose', 'prepare', 'testflags', 'compilerprobe', 'resumeprobe', 'packages', 'smoke'))
    parser.add_argument('--failed-exit', type=int)
    parser.add_argument('--baseline-dir', type=Path,
                        help='Retained original-curl-version.txt for candidate-image smoke only')
    args = parser.parse_args()
    if (args.action == 'failurecapture') != (args.failed_exit is not None) or (args.failed_exit is not None and not 1 <= args.failed_exit <= 255):
        parser.error('Require the original nonzero shell exit only for failurecapture')
    if args.baseline_dir is not None:
        if args.action != 'smoke':
            parser.error('--baseline-dir is accepted only for smoke')
        OUTPUT = args.baseline_dir.resolve()
        baseline = OUTPUT / 'original-curl-version.txt'
        if baseline.is_symlink() or not baseline.is_file():
            raise ValueError('Require the retained original curl version contract')
    globals()[args.action]()
