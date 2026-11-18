#!/usr/bin/env python3
"""Run complete upstream XML suites on the installed replacement extension pair."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
OUTPUT = Path('/security-output')
LOCK = json.loads((HERE / 'tool-os-pyexpat.lock.json').read_text())
spec = importlib.util.spec_from_file_location('xml_rebuild', HERE / 'tool-os-pyexpat.py')
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)


def main():
    if os.environ.get('ERP_SECURITY_SOURCE_BUILD') != '1' or os.geteuid() != 0:
        raise ValueError('Require the disposable source builder')
    # The prerequisite extensions remain the interpreter's original trusted
    # test machinery. Their absence is a preparation failure, never a test skip.
    required = tuple(LOCK['upstream_test_prerequisites'])
    prerequisites = {}
    for name in required:
        entry = importlib.util.find_spec(name)
        if entry is None or not entry.origin:
            raise ValueError('Missing upstream test prerequisite extension: ' + name)
        if entry.origin != LOCK['upstream_test_prerequisites'][name]:
            raise ValueError('Upstream test prerequisite loaded from an unexpected path: ' + name)
        prerequisites[name] = {'path': entry.origin, 'sha256': helper.digest(entry.origin)}
    identity, target = helper.prepare_pair(LOCK, OUTPUT, OUTPUT / 'test-install')
    testpath = Path('/usr/local/lib/python3.14/test')
    if testpath.exists() or testpath.is_symlink():
        raise ValueError('Unexpected existing interpreter test package')
    testpath.symlink_to(Path('/security-work/Python-3.14.10/Lib/test'), target_is_directory=True)
    # Upstream subprocesses may use -I; installing the pair and test package
    # in this disposable interpreter ensures they still test the new modules.
    prechecks = {}
    for executable in ('/usr/local/bin/python3', '/home/frappe/frappe-bench/env/bin/python'):
        prechecks[executable] = json.loads(helper.run(executable, '-B', str(HERE / 'tool-os-pyexpat.py'), 'smoke', '--modules', str(target)))
        if {Path(e['path']).name: e['sha256'] for e in prechecks[executable]['modules'].values()} != identity['modules']:
            raise ValueError('Installed test module identity differs from build')
    (OUTPUT / 'upstream-precheck.json').write_text(json.dumps({'prerequisites': prerequisites, 'interpreters': prechecks}, indent=2) + '\n')
    command = ['/usr/local/bin/python3', '-B', '-m', 'test', '-v', '-j', '1', '--junit-xml', str(OUTPUT / 'upstream-tests.xml'), *LOCK['upstream_tests']]
    state = {'status': 'running', 'suites': LOCK['upstream_tests'], 'command': command,
             'module_hashes_before': identity['modules'], 'resources': 'ordinary upstream defaults; no exclusions or skip filters added'}
    receipt = OUTPUT / 'upstream-result.json'
    receipt.write_text(json.dumps(state, indent=2) + '\n')
    with (OUTPUT / 'upstream-tests.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=1800,
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHON_COLORS='0'))
    state['exit_code'] = result.returncode
    state['module_hashes_after'] = {name: helper.digest(target / name) for name in identity['modules']}
    receipt.write_text(json.dumps(state, indent=2) + '\n')
    if result.returncode or state['module_hashes_after'] != identity['modules']:
        raise ValueError('Upstream XML tests failed or tested modules changed')
    # Use a fresh interpreter to parse XML after the actual replacement, rather
    # than relying on this driver's already imported baseline XML modules.
    summary_code = '''import json,xml.etree.ElementTree as E,sys
r=E.parse(sys.argv[1]).getroot(); cases=list(r.iter('testcase'))
print(json.dumps({'tests':len(cases),'failures':len(list(r.iter('failure'))),'errors':len(list(r.iter('error'))),'skipped':[{'class':x.get('classname'),'name':x.get('name'),'reason':x.find('skipped').get('message') or ''.join(x.find('skipped').itertext()).strip()} for x in cases if x.find('skipped') is not None],'classes':sorted({x.get('classname','') for x in cases})}))
'''
    summary = json.loads(helper.run('/usr/local/bin/python3', '-B', '-c', summary_code, str(OUTPUT / 'upstream-tests.xml')))
    if summary['tests'] == 0 or summary['failures'] or summary['errors']:
        raise ValueError('Upstream test evidence is empty or contains failures')
    # These summaries come from pinned CPython libregrtest/results.py. A
    # successful exit alone can include skipped or resource-denied modules.
    log = (OUTPUT / 'upstream-tests.log').read_text()
    helper.validate_upstream_log(log, LOCK['upstream_tests'])
    state['upstream_totals'] = [line for line in log.splitlines() if line.startswith(('Total tests:', 'Total test files:'))]
    state['upstream_skip_details'] = [line for line in log.splitlines() if ' ... skipped ' in line]
    postchecks = {}
    for executable in prechecks:
        postchecks[executable] = json.loads(helper.run(executable, '-B', str(HERE / 'tool-os-pyexpat.py'), 'smoke', '--modules', str(target)))
    state.update(status='passed', junit=summary, normal_runtime_checks=postchecks)
    receipt.write_text(json.dumps(state, indent=2) + '\n')
    identity['status'] = 'compiled-and-upstream-tests-passed'
    (OUTPUT / 'build-identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    for name in ('tool-os-pyexpat.py', 'tool-os-pyexpat.lock.json'):
        shutil.copyfile(HERE / name, OUTPUT / name)
    print(json.dumps({'status': 'passed', 'tests': summary['tests'], 'skipped': len(summary['skipped'])}))


if __name__ == '__main__':
    main()
