#!/usr/bin/env python3
"""Checks that curl's upgrade cannot silently discard required protocols."""
import importlib.util
import copy
import json
from pathlib import Path
import shlex
import tempfile
import tarfile
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('curl_check', Path(__file__).with_name('tool-os-check-curl.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class Contracts(unittest.TestCase):
    def test_local_https_fixture_frames_the_exact_unchanged_body(self):
        import ast
        tree=ast.parse(Path(__file__).with_name('tool-os-check-curl.py').read_text())
        handler=next(node for node in ast.walk(tree) if isinstance(node,ast.ClassDef) and node.name=='Handler')
        request=next(node for node in handler.body if isinstance(node,ast.FunctionDef) and node.name=='do_GET')
        header=ast.parse("self.send_header('Content-Length', str(len(b'ERP curl compatibility\\n')))").body[0]
        ending=ast.parse('self.end_headers()').body[0]
        index=next(i for i,node in enumerate(request.body) if ast.dump(node)==ast.dump(ending))
        self.assertEqual(ast.dump(request.body[index-1]),ast.dump(header))

    def test_failed_native_request_reports_real_code_without_changing_zero_assertion(self):
        from unittest.mock import Mock
        library=SimpleNamespace(curl_easy_strerror=Mock(return_value=b'TLS failure'),curl_version=Mock(return_value=b'libcurl exact version'))
        error=check.ctypes.create_string_buffer(b'bounded native TLS detail',256)
        report=json.loads(check.native_request_diagnostic('libcurl.so.4',60,error,library))
        self.assertEqual(report['library'],'libcurl.so.4');self.assertEqual(report['curlcode'],60)
        self.assertEqual(report['strerror'],'TLS failure');self.assertEqual(report['error_buffer'],'bounded native TLS detail')
        self.assertEqual(report['curl_version'],'libcurl exact version')
        self.assertIn('providers',report)
        source=Path(__file__).with_name('tool-os-check-curl.py').read_text()
        self.assertIn('assert code == 0, native_request_diagnostic(name, code, error_buffer, library)',source)

    def test_native_failure_diagnostic_is_bounded_and_preserves_original_code(self):
        import io
        from unittest.mock import Mock
        library=SimpleNamespace(curl_easy_strerror=Mock(return_value=b'TLS failure'),curl_version=Mock(return_value=b'exact version'))
        for raw in [b'x'*(1024**2+1),''.join(f'1-2 r-xp 0 0:0 1 /lib/libcurl-{i}.so\n' for i in range(17)).encode()]:
            with patch.object(Path,'open',return_value=io.BytesIO(raw)):
                report=json.loads(check.native_request_diagnostic('libcurl.so.4',60,check.ctypes.create_string_buffer(256),library))
            self.assertEqual(report['curlcode'],60);self.assertIn('bound',report['diagnostic_error'])

    def test_post_suite_install_uses_offline_dependency_ordering(self):
        script=Path(__file__).with_name('tool-os-build-curl.sh').read_text()
        self.assertNotIn('dpkg -i ',script)
        packages=script.index('tool-os-check-curl.py packages')
        ready=script.index('offline-install-ready',packages)
        installer=script.index('install-runtime-debs.py',ready)
        smoke=script.index('tool-os-check-curl.py smoke',installer)
        self.assertLess(packages,ready);self.assertLess(ready,installer);self.assertLess(installer,smoke)

    def test_fixture_dependency_contract_is_exact_and_never_a_tls_waiver(self):
        entry=json.loads(Path(__file__).with_name('tool-os-curl.lock.json').read_text())['patches'][0]
        self.assertEqual(check.fixture_contract(entry),entry)
        for field in ['file','target','sha256','original_sha256','patched_sha256','causal_review_sha256']:
            changed=copy.deepcopy(entry);changed[field]='unexpected'
            with self.subTest(field=field),self.assertRaises(ValueError):check.fixture_contract(changed)
        with self.assertRaises(ValueError):check.patched_fixture(b'wrong source bytes',entry,Path(__file__).with_name(entry['file']).read_bytes())

    def test_main_diagnostic_log_growth_stops_only_owned_group_before_hashing(self):
        with tempfile.TemporaryDirectory() as temporary:
            output=Path(temporary)/'output';output.mkdir();work=Path(temporary)/'work';work.mkdir()
            def popen(command,**kwargs):
                kwargs['stdout'].write('x'*(16*1024**2+1));kwargs['stdout'].flush()
                return SimpleNamespace(pid=123456789,poll=lambda:None,wait=lambda **_:-15)
            killed=[]
            def killpg(pid,signal):
                if signal==0:raise ProcessLookupError
                killed.append((pid,signal))
            with patch.object(check,'WORK',work),patch.object(check,'OUTPUT',output), \
                 patch.object(check.subprocess,'Popen',side_effect=popen), \
                 patch.object(check.os,'killpg',side_effect=killpg), \
                 patch.object(check.hashlib,'sha256',side_effect=AssertionError('must check bound before hash')):
                with self.assertRaises(ValueError):check.mtlsdiagnose()
            self.assertEqual(killed,[(123456789,check.signal.SIGTERM)])
            report=json.loads((output/'mtls-diagnostic.json').read_text())
            self.assertEqual(report['runs'][0]['exit_code'],-15)
            self.assertIn('bound',report['runs'][0]['guard_failure'])
            self.assertFalse(report['ordinary_suite_pass'])

    def test_post_exit_log_bound_preserves_real_test_exit_without_reading(self):
        with tempfile.TemporaryDirectory() as temporary:
            output=Path(temporary)/'output';output.mkdir();work=Path(temporary)/'work';work.mkdir()
            def popen(command,**kwargs):
                kwargs['stdout'].write('x'*(16*1024**2+1));kwargs['stdout'].flush()
                return SimpleNamespace(pid=123456789,poll=lambda:2)
            with patch.object(check,'WORK',work),patch.object(check,'OUTPUT',output), \
                 patch.object(check.subprocess,'Popen',side_effect=popen), \
                 patch.object(check.os,'killpg',side_effect=ProcessLookupError), \
                 patch.object(check.hashlib,'sha256',side_effect=AssertionError('must check bound before hash')):
                with self.assertRaises(ValueError):check.mtlsdiagnose()
            report=json.loads((output/'mtls-diagnostic.json').read_text())
            self.assertEqual(report['runs'][0]['exit_code'],2)
            self.assertIn('bound',report['runs'][0]['guard_failure'])

    def test_actual_loader_trace_requires_original_driver_and_exact_candidate_backend(self):
        build=Path('/work/build-openssl')
        trace='initialize program: ./libtest/.libs/libtests\ncalling init: /work/build-openssl/lib/.libs/libcurl.so.4\ncalling init: /lib/aarch64-linux-gnu/libssl.so.3\n'
        self.assertTrue(check.mtls_loaded_driver(trace,build))
        for bad in [trace.replace('libtests','curl'),trace.replace('/work/build-openssl/lib/.libs','/usr/lib'),
                    trace.replace('libssl.so.3','libgnutls.so.30'),'']:
            self.assertFalse(check.mtls_loaded_driver(bad,build))

    def test_mtls_diagnosis_uses_original_isolated_then_sequence_selection(self):
        with patch.object(check,'WORK',Path('/work')):
            commands=check.mtls_commands()
        self.assertEqual([x[0] for x in commands],['mtls-isolated','mtls-sequence'])
        self.assertEqual([x[1] for x in commands],[
            ['make','-C','/work/curl-8.23.0/debian/build-openssl','-j1','test','TFLAGS=-n -j1 2095'],
            ['make','-C','/work/curl-8.23.0/debian/build-openssl','-j1','test','TFLAGS=-n -j1 2088 2089 2095']])
        controller=Path(__file__).with_name('tool-os-build-curl.py').read_text()
        self.assertIn("'--mtls-diagnose'",controller)
        self.assertIn('ERP_CURL_MTLS_DIAGNOSE=1',controller)

    def test_mtls_diagnosis_retains_both_outcomes_and_rejects_failures_or_skips(self):
        for outcomes in ([(2,False),(0,True)],[(0,False),(0,True)],[(0,True),(0,True)]):
            with self.subTest(outcomes=outcomes),tempfile.TemporaryDirectory() as temporary:
                work=Path(temporary)/'work';build=work/'curl-8.23.0/debian/build-openssl'
                logs=build/'tests/log';logs.mkdir(parents=True)
                output=Path(temporary)/'output';output.mkdir()
                (build/'tests/libtest/.libs').mkdir(parents=True)
                (build/'src/.libs').mkdir(parents=True);(build/'tests/server').mkdir()
                for name in ['tests/libtest/.libs/libtests','src/.libs/curl','tests/server/servers']:
                    (build/name).write_bytes(b'same runtime bytes')
                calls=[]
                def popen(command,**kwargs):
                    index=len(calls);calls.append(command);code,passed=outcomes[index]
                    count=1 if index==0 else 3
                    kwargs['stdout'].write(f'TESTDONE: {count if passed else 0} tests out of {count} reported OK: {100 if passed else 0}%\n')
                    (logs/'stunnel.log').write_text(str(index))
                    Path(kwargs['env']['LD_DEBUG_OUTPUT']+'.123').write_text('initialize program: ./libtest/.libs/libtests\ncalling init: '+str(build/'lib/.libs/libcurl.so.4')+'\ncalling init: /lib/aarch64-linux-gnu/libssl.so.3\n')
                    return SimpleNamespace(pid=123456789,poll=lambda:code,wait=lambda **_:code)
                with patch.object(check,'WORK',work),patch.object(check,'OUTPUT',output), \
                     patch.object(check.subprocess,'Popen',side_effect=popen), \
                     patch.object(check.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'version/verify fixture','')), \
                     patch.object(check.os,'killpg',side_effect=ProcessLookupError):
                    if all(code==0 and passed for code,passed in outcomes):check.mtlsdiagnose()
                    else:
                        with self.assertRaises(ValueError):check.mtlsdiagnose()
                report=json.loads((output/'mtls-diagnostic.json').read_text())
                self.assertEqual(len(report['runs']),2)
                self.assertFalse(report['ordinary_suite_pass'])
                with tarfile.open(output/'mtls-isolated-complete-test-log.tar.gz') as stream:
                    self.assertEqual(stream.extractfile('tests/log/stunnel.log').read(),b'0')

    def test_failure_capture_is_bounded_and_keeps_only_focused_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary)/'build'; build.mkdir()
            required = ('tests/runtests.pl', 'tests/log/stunnel.log',
                        'tests/certs/test-ca.crt', 'tests/certs/test-localhost.crt',
                        'tests/certs/test-client-cert.crt', 'tests/certs/test-client-cert.key',
                        'tests/certs/test-client-eku-only.crt', 'tests/certs/test-client-eku-only.key',
                        'tests/data/DISABLED', 'tests/data/test2088', 'tests/data/test2089', 'tests/data/test2095', 'libtool',
                        'tests/libtest/libtests', 'tests/libtest/.libs/libtests',
                        'src/curl', 'src/.libs/curl', 'tests/server/servers',
                        'lib/.libs/libcurl.so.4.9.0')
            for name in required:
                path=build/name; path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'\x7fELFfixture' if name=='tests/server/servers' else b'fixture')
                if name=='tests/server/servers':path.chmod(0o755)
            (build/'lib/.libs/libcurl.so.4').symlink_to('libcurl.so.4.9.0')
            (build/'tests/libtest/libtests.o').write_bytes(b'never retain objects')
            (build/'tests/server/servers.o').write_bytes(b'\x7fELFobject')
            (build/'tests/server/servers.o').chmod(0o755)
            (build/'tests/data/test9999').write_bytes(b'unrelated case')
            files=check.failure_files(build)
            self.assertIn(build/'tests/log/stunnel.log',files)
            self.assertIn(build/'lib/.libs/libcurl.so.4.9.0',files)
            self.assertNotIn(build/'tests/libtest/libtests.o',files)
            self.assertNotIn(build/'tests/server/servers.o',files)
            self.assertNotIn(build/'tests/data/test9999',files)
            with self.assertRaises(ValueError):check.failure_files(build,limit=1)
            (build/'tests/log/escape').symlink_to('/etc/passwd')
            with self.assertRaises(ValueError):check.failure_files(build)

    def test_failure_archive_binds_bytes_without_turning_verify_failure_into_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            work=Path(temporary)/'work'; build=work/'curl-8.23.0/debian/build-openssl'
            output=Path(temporary)/'output';output.mkdir()
            names=['tests/runtests.pl','tests/log/stunnel.log','tests/data/DISABLED','tests/data/test2088','tests/data/test2089',
                   'tests/data/test2095','tests/libtest/libtests','tests/libtest/.libs/libtests',
                   'src/curl','src/.libs/curl','tests/server/servers','lib/.libs/libcurl.so.4','libtool']
            names += ['tests/certs/'+name for name in ('test-ca.crt','test-localhost.crt','test-client-cert.crt',
                       'test-client-cert.key','test-client-eku-only.crt','test-client-eku-only.key')]
            for name in names:
                path=build/name;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(b'\x7fELFfixture' if name=='tests/server/servers' else b'exact bytes')
                if name=='tests/server/servers':path.chmod(0o755)
            for name in ('build.log','build-package-versions.txt','local-packaging-changes.json'):
                (output/name).write_text('retained failure')
            result=subprocess.CompletedProcess([],1,'','certificate verify failed')
            with patch.object(check,'WORK',work),patch.object(check,'OUTPUT',output), \
                 patch.object(check,'args',SimpleNamespace(failed_exit=2),create=True), \
                 patch.object(check.subprocess,'run',return_value=result):
                check.failurecapture()
            report=json.loads((output/'failed-openssl-runtime.json').read_text())
            self.assertEqual(report['status'],'failed-run-diagnostic-checkpoint-only')
            self.assertEqual(report['failed_exit'],2)
            self.assertFalse(report['ordinary_suite_pass'])
            self.assertTrue(all(c['exit_code']==1 for c in report['commands']))
            self.assertEqual(report['bindings'][str(output/'build.log')],check.hashlib.sha256(b'retained failure').hexdigest())
            archive=output/'failed-openssl-runtime.tar.gz'
            self.assertEqual(report['archive_sha256'],check.hashlib.sha256(archive.read_bytes()).hexdigest())
            with tarfile.open(archive) as stream:
                self.assertEqual(stream.extractfile('curl-8.23.0/debian/build-openssl/tests/log/stunnel.log').read(),b'exact bytes')

    def test_failure_capture_preserves_the_original_exit_and_suite_commands(self):
        recipe=Path(__file__).with_name('tool-os-build-curl.sh').read_text()
        self.assertIn('failurecapture --failed-exit "$rc"',recipe)
        self.assertIn('exit "$rc"',recipe)
        self.assertEqual(recipe.count("test TFLAGS='-n -j1'"),2)
        self.assertIn('dpkg-buildpackage -B -us -uc -j1',recipe)
        trap=next(line for line in recipe.splitlines() if line.startswith('trap '))
        trap=trap.replace('python3 /security-input/tool-os-check-curl.py failurecapture --failed-exit "$rc"','false')
        trap=trap.replace('/security-output/failure-capture-error.log','/dev/null')
        self.assertEqual(subprocess.run(['sh','-c',trap+'\nexit 37']).returncode,37)

    def test_curl_config_protocol_names_are_canonicalized_only(self):
        configured = check.configured_contract('HTTP\nHTTPS\n', 'SSL\nNTLM\n')
        self.assertEqual(configured, {'protocols': {'http','https'}, 'features': {'SSL','NTLM'}})
        check.check_features(configured, configured)
        with self.assertRaises(ValueError):
            check.check_features(configured, check.configured_contract('HTTP\n','SSL\nNTLM\n'))

    def test_protocol_removal_is_bound_to_reviewed_source(self):
        lock = json.loads(Path(__file__).with_name('tool-os-curl.lock.json').read_text())
        self.assertEqual(check.protocol_removals(lock), {'smb','smbs','rtmp'})
        for kind in ('version','archive','wildcard','feature','review'):
            changed = copy.deepcopy(lock)
            if kind=='version':changed['upstream_version']='8.24.0'
            elif kind=='archive':changed['sources']['tool-os-curl-8.23.0.tar.xz']['sha256']='0'*64
            elif kind=='wildcard':changed['protocol_contract']['upstream_removed_protocols'].append('https')
            elif kind=='feature':changed['protocol_contract']['upstream_removed_features'].append('NTLM')
            else:changed['protocol_contract']['rtmp_removal_review']['sha256']='0'*64
            with self.subTest(kind=kind),self.assertRaises(ValueError):check.protocol_removals(changed)

    def test_probe_uses_the_original_dpkg_build_environment(self):
        recipe = Path(__file__).with_name('tool-os-build-curl.sh').read_text()
        commands = [shlex.split(line.strip()) for line in recipe.splitlines()
                    if line.strip().startswith('dpkg-buildpackage ')]
        self.assertEqual(commands, [['dpkg-buildpackage','-B','-us','-uc','-j1']])
        self.assertNotIn('--rules-target', recipe)
        self.assertNotIn('make -f debian/rules override_dh_auto_configure', recipe)

    def test_resume_requires_exact_successful_probe(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); probe = root/'compiler-probe.json'
            original = Path.read_text
            for status, wrong_hash in [('compiler-object-fits', False), ('compiler-object-fits', True), ('compiler-object-did-not-fit', False)]:
                probe.write_text(json.dumps({'status':status}))
                decision = {'continue':True, 'probe_sha256':check.hashlib.sha256(probe.read_bytes()).hexdigest()}
                if wrong_hash: decision['probe_sha256'] = '0'*64
                def read(path,*args,**kwargs):
                    if str(path)=='/security-input/compiler-probe-continue.json':return json.dumps(decision)
                    return original(path,*args,**kwargs)
                with self.subTest(status=status,wrong_hash=wrong_hash), patch.object(check,'OUTPUT',root), patch.object(Path,'read_text',autospec=True,side_effect=read):
                    if status=='compiler-object-fits' and not wrong_hash:check.resumeprobe()
                    else:
                        with self.assertRaises(ValueError):check.resumeprobe()

    def test_only_test_object_flags_change_and_are_last(self):
        original = 'CONFIGURE_ARGS=--enable-threaded-resolver\nNUMJOBS = 1\nTFLAGS=$(NUMJOBS) * 4\ndefine configure-curl\n  $(2)\nendef\ndefine test-curl\nmake test-nonflaky\n\n# Invoke dh_auto_build for a specific curl flavour.\n'
        changed = check.bounded_test_rules(original)
        self.assertIn('libtests.$$(OBJEXT): override CFLAGS += -O0 -g0', changed)
        self.assertEqual(changed.count('make test-nonflaky'), 1)
        self.assertIn('"$(1)" = openssl',changed)
        self.assertIn('"$(ERP_CURL_MTLS_DIAGNOSE)" = 1',changed)
        self.assertIn('ifeq ($(ERP_CURL_COMPILER_PROBE),1)\n\tpython3 /security-input/tool-os-check-curl.py compilerprobe\nendif\n\n# Invoke dh_auto_build', changed)
        self.assertIn('TFLAGS=$(NUMJOBS)\n', changed)
        self.assertEqual(changed.count('--enable-ntlm'), 1)
        command = 'gcc -g -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -O0 -g0 -ftrack-macro-expansion=0 -c -o libtests.o libtests.c'
        check.require_test_compile_flags(command)
        for bad in (command+' -O2', command+' -g', command.replace('-fstack-protector-strong ', ''),
                    command+' -DCURL_DISABLE_TYPECHECK', command+' -ftrack-macro-expansion=2'):
            with self.subTest(command=bad), self.assertRaises(ValueError):
                check.require_test_compile_flags(bad)
        with self.assertRaises(ValueError): check.bounded_test_rules(changed)

    def test_compiler_fit_does_not_claim_suite_success_or_ignore_oom(self):
        before = {'memory_max_bytes': 640*1024**2, 'memory_events': {'oom': 0, 'oom_kill': 0}}
        after = {'memory_max_bytes': 640*1024**2, 'memory_events': {'oom': 0, 'oom_kill': 0}}
        self.assertTrue(check.compiler_fit(0, before, after))
        self.assertFalse(check.compiler_fit(1, before, after))
        for event in ('oom', 'oom_kill'):
            bad = dict(after, memory_events={event: 1})
            with self.subTest(event=event): self.assertFalse(check.compiler_fit(0, before, bad))
        self.assertFalse(check.compiler_fit(0, before, dict(after, memory_max_bytes=1024**3)))

    def test_backports_build_dependencies_request_locked_runtime_versions(self):
        """Stable-installed libraries must upgrade with their pinned -dev pairs."""
        directory = Path(__file__).parent
        lock = json.loads((directory / 'tool-os-curl.lock.json').read_text())
        recipe = (directory / 'tool-os-build-curl.sh').read_text().replace('\\\n', '')
        install = next(line for line in recipe.splitlines() if line.startswith('apt-get install '))
        requested = set(shlex.split(install))
        for package, version in lock['runtime_dependencies'].items():
            with self.subTest(package=package):
                self.assertIn(package + '=' + version, requested)

    def test_only_documented_upstream_removals_allowed(self):
        old = {'protocols': {'http', 'https', 'smb', 'smbs'},
               'features': {'SSL', 'SPNEGO', 'HTTP3', 'NTLM', 'TLS-SRP'}}
        new = {'protocols': {'http', 'https'}, 'features': {'SSL', 'SPNEGO', 'HTTP3', 'NTLM'}}
        check.check_features(old, new)
        for feature in ('SSL', 'SPNEGO', 'HTTP3', 'NTLM'):
            with self.subTest(feature=feature), self.assertRaises(ValueError):
                check.check_features(old, dict(new, features=new['features'] - {feature}))
        with self.assertRaises(ValueError):
            check.check_features(old, dict(new, protocols={'http'}))

    def test_versioned_gnutls_alias_keeps_abi(self):
        with patch.object(check, 'run', return_value='0000 T curl_easy_init@@CURL_GNUTLS_3\n'):
            old = check.exports(Path('old'))
        with patch.object(check, 'run', return_value='0000 T curl_easy_init@CURL_GNUTLS_3\n0000 T curl_easy_init@@CURL_GNUTLS_4\n'):
            new = check.exports(Path('new'))
        self.assertFalse(old - new)
        self.assertTrue(old - {'curl_easy_init@CURL_GNUTLS_4'})

    def test_cli_features_are_parsed_separately(self):
        self.assertEqual(check.cli_contract('curl 8.23.0\nProtocols: http https\nFeatures: SSL HTTP3 SPNEGO\n'),
                         {'protocols': {'http', 'https'}, 'features': {'SSL', 'HTTP3', 'SPNEGO'}})


if __name__ == '__main__':
    unittest.main()
