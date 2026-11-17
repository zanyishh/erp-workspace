#!/usr/bin/env python3
"""Check ncurses ABI and ordinary terminal-capability behavior, no payloads."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

OUTPUT = Path('/security-output')
BASELINE = OUTPUT / 'ncurses-baseline.json'
LIBRARY_NAMES = ['libncurses.so.6', 'libncursesw.so.6', 'libtinfo.so.6', 'libtic.so.6',
                 'libform.so.6', 'libformw.so.6', 'libmenu.so.6', 'libmenuw.so.6',
                 'libpanel.so.6', 'libpanelw.so.6']
LIBRARY_DIR = Path('/usr/lib/aarch64-linux-gnu')


def run(*args, env=None):
    return subprocess.check_output(args, env=env, text=True, stderr=subprocess.PIPE)


def normal_checks():
    commands = [['infocmp', '-1', '-I', 'xterm-256color'],
                ['infocmp', '-1', '-i', 'xterm-256color'],
                ['tput', '-T', 'xterm-256color', 'colors'],
                ['tput', '-T', 'vt100', 'cols']]
    results = {}
    for command in commands:
        output = run(*command)
        # Source/destination comments contain database locations, not behavior.
        data = '\n'.join(line for line in output.splitlines() if not line.startswith('#'))
        results[' '.join(command)] = hashlib.sha256(data.encode()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='erp-terminal-') as directory:
        source = Path(directory) / 'xterm.src'
        source.write_text(run('infocmp', '-x', '-1', 'xterm-256color'))
        compiled = Path(directory) / 'terminfo'
        run('tic', '-x', '-o', str(compiled), str(source))
        roundtrip = run('infocmp', '-x', '-1', '-A', str(compiled), 'xterm-256color')
        data = '\n'.join(line for line in roundtrip.splitlines() if not line.startswith('#'))
        results['tic-infocmp-roundtrip'] = hashlib.sha256(data.encode()).hexdigest()
    library = ctypes.CDLL('libtinfo.so.6')
    library.setupterm.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    status = ctypes.c_int()
    assert library.setupterm(b'xterm-256color', 1, ctypes.byref(status)) == 0 and status.value == 1
    library.tigetnum.argtypes = [ctypes.c_char_p]
    assert library.tigetnum(b'colors') == 256
    results['libtinfo-setupterm-colors'] = 256
    return results


def libraries(directory=LIBRARY_DIR):
    result = {}
    for name in LIBRARY_NAMES:
        path = directory / name
        assert path.is_file(), name
        lines = run('nm', '-D', '--defined-only', str(path)).splitlines()
        symbols = sorted({line.split()[-1] for line in lines if line.split()})
        import re
        dynamic = run('readelf', '-d', str(path))
        sonames = re.findall(r'\(SONAME\).*?\[(.*?)\]', dynamic)
        assert sonames == [name], (name, sonames)
        result[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'symbols': symbols, 'soname': name}
    return result


def main():
    global OUTPUT, BASELINE
    tested = None
    if len(sys.argv) == 5 and sys.argv[1] == 'runtime':
        # Candidate validation receives the exact retained builder baseline.
        BASELINE = Path(sys.argv[2])
        evidence = Path(sys.argv[3]); OUTPUT = Path(sys.argv[4])
        if (BASELINE.is_symlink() or not BASELINE.is_file() or evidence.is_symlink()
                or not evidence.is_file() or not OUTPUT.is_dir()):
            raise ValueError('Require a verified ordinary baseline and existing output directory')
        tested = json.loads(evidence.read_text())
        if tested['status'] != 'normal-checks-passed': raise ValueError('Builder ABI/ordinary checks did not pass')
        sys.argv[1] = 'verify'
    if sys.argv[1] == 'baseline-behavior':
        BASELINE.write_text(json.dumps({'normal_checks': normal_checks()}, indent=2)+'\n')
        return
    if sys.argv[1] == 'snapshot':
        baseline = json.loads(BASELINE.read_text())
        baseline['libraries'] = libraries(Path('/security-work/original-ncurses'))
        BASELINE.write_text(json.dumps(baseline, indent=2)+'\n')
        return
    assert sys.argv[1] == 'verify'
    baseline = json.loads(BASELINE.read_text())
    if tested is None:
        actual = libraries()
    else:
        # The runtime deliberately lacks nm/readelf. Verify exact bytes against
        # the ordinary-tested build's ABI inventory, then load every library.
        actual = tested['libraries']
        if set(actual) != set(LIBRARY_NAMES): raise ValueError('Incomplete tested ncurses library inventory')
        for name in LIBRARY_NAMES:
            path = LIBRARY_DIR/name
            if hashlib.sha256(path.read_bytes()).hexdigest() != actual[name]['sha256'] or actual[name]['soname'] != name:
                raise ValueError('Installed ncurses bytes differ from the ABI-tested build')
            ctypes.CDLL(str(path))
    for name, original in baseline['libraries'].items():
        assert not (set(original['symbols']) - set(actual[name]['symbols'])), name
    checks = normal_checks()
    assert checks == baseline['normal_checks'], 'Normal terminal capability behavior changed'
    versions = {name: run('dpkg-query', '-W', '-f=${Version}', name) for name in
                ['ncurses-base', 'ncurses-bin', 'libncurses6', 'libncursesw6', 'libtinfo6']}
    assert set(versions.values()) == {'6.5+20250216-2+erp1'}, versions
    (OUTPUT / ('ncurses-runtime-compatibility.json' if tested else 'ncurses-compatibility.json')).write_text(json.dumps({
        'status': 'normal-checks-passed', 'versions': versions,
        'checks': checks, 'libraries': actual, 'interactive_example_tests_executed': False,
        'abi_validation': 'byte-identical to ABI-tested build; all libraries loaded' if tested else 'export/SONAME comparison',
    }, indent=2)+'\n')
    print(json.dumps({'status': 'normal-checks-passed', 'versions': versions,
                     'baseline_sha256': hashlib.sha256(BASELINE.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
