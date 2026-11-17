#!/usr/bin/env python3
"""Run every prepared ordinary OS compatibility check in the offline candidate."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

INPUT = Path('/security-input')
SECURITY = Path('/opt/erp-security')
PYTHON = '/home/frappe/frappe-bench/env/bin/python'
COMPONENTS = {'git', 'sqlite', 'x11', 'zlib', 'util-linux', 'krb5', 'curl', 'ncurses', 'libsndfile'}


def main():
    closure = json.loads((INPUT/'runtime-os-closure.lock.json').read_text())
    if set(closure['components']) != COMPONENTS or any(item['status'] != 'verified-build-handoff' for item in closure['components'].values()):
        raise ValueError('Every reviewed OS handoff must be complete before candidate checks')
    output = SECURITY/'os-checks'; output.mkdir()
    for name, item in closure['components'].items():
        destination = output/name; destination.mkdir()
        for basename in item['required_baselines']:
            entry = item['evidence_files'][basename]; source = INPUT/entry['artifact']
            if (Path(basename).name != basename or source.is_symlink()
                    or hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']):
                raise ValueError('Ordinary OS baseline differs from reviewed bytes')
            shutil.copy2(source, destination/basename)
    commands = {name: [PYTHON, str(SECURITY/'os-runtime-compatibility.py'), name]
                for name in ('git', 'sqlite', 'x11', 'zlib')}
    commands['sqlite'] += ['--sqlite-abi-contract', str(SECURITY/'sqlite-abi-contract.json')]
    commands['x11'] += ['--x11-abi-contract', str(SECURITY/'os-x11-abi-contract.json')]
    commands.update({
        'util-linux': ['runuser', '-u', 'frappe', '--', PYTHON, str(SECURITY/'util-linux-ordinary-compatibility.py')],
        'krb5': [PYTHON, str(SECURITY/'tool-os-package-krb5.py'), 'smoke', '--consumer-output', str(output/'krb5')],
        'curl': [PYTHON, str(SECURITY/'tool-os-check-curl.py'), 'smoke', '--baseline-dir', str(output/'curl')],
        'ncurses': [PYTHON, str(SECURITY/'ncurses-compatibility.py'), 'runtime',
                    str(output/'ncurses/ncurses-baseline.json'),
                    str(output/'ncurses/ncurses-compatibility.json'), str(output/'ncurses')],
    })
    checks = {}
    for name, command in commands.items():
        logfile = output/name/'ordinary-checks.log'
        with logfile.open('w') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
        if result.returncode: raise RuntimeError('Ordinary OS candidate check failed: '+name)
        checks[name] = {'exit_code': 0, 'log_sha256': hashlib.sha256(logfile.read_bytes()).hexdigest()}
    # Reuse the same codec-preservation/roundtrip function, with its explicit
    # builder output location redirected to this component's retained evidence.
    spec = importlib.util.spec_from_file_location('ordinary_sndfile', SECURITY/'tool-os-check-libsndfile.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    module.OUTPUT = output/'libsndfile'
    module.smoke()
    checks['libsndfile'] = {'exit_code': 0, 'candidate_codecs_sha256':
        hashlib.sha256((output/'libsndfile/candidate-codecs.json').read_bytes()).hexdigest()}
    (output/'receipt.json').write_text(json.dumps({'status': 'passed', 'checks': checks,
        'closure_sha256': hashlib.sha256((INPUT/'runtime-os-closure.lock.json').read_bytes()).hexdigest(),
        'network': 'offline; curl uses only its in-process loopback TLS fixture'}, indent=2)+'\n')
    print(json.dumps({'status': 'passed', 'ordinary_components': sorted(checks)}))


if __name__ == '__main__': main()
