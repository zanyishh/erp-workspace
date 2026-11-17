#!/usr/bin/env python3
"""Install only frozen local Debian inputs with dependency ordering and no repositories."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transaction(text, expected):
    changes = {}
    for line in text.splitlines():
        if line.startswith('Remv '):
            raise ValueError('Offline transaction must not remove packages')
        if not line.startswith(('Inst ', 'Conf ')):
            continue
        # APT appends bracketed interim dependency diagnostics while ordering exact upgrades.
        match = re.fullmatch(r'(Inst|Conf) (\S+)(?: \[[^\]]+\])? \((\S+) [^()\[\]\n]* \[([^\]]+)\]\)(?: \[[^\[\]\n]*\])*', line)
        if not match:
            raise ValueError('Unrecognized APT package action: '+line)
        action, qualified, version, selected_architecture = match.groups()
        name, separator, architecture = qualified.partition(':')
        if (name not in expected or version != expected[name]['version']
                or selected_architecture != expected[name]['architecture']
                or separator and architecture != expected[name]['architecture']):
            raise ValueError('APT selected an unlisted package/version: '+line)
        if action == 'Inst':
            if name in changes: raise ValueError('Duplicate APT package action')
            changes[name] = version
    return changes


def package_state():
    output = subprocess.check_output(['dpkg-query', '-W', '-f',
        '${Package}\t${Version}\t${Architecture}\t${db:Status-Abbrev}\n'], text=True)
    records = {}
    for line in output.splitlines():
        name, version, architecture, status = line.split('\t')
        records[name+':'+architecture] = {'version': version, 'status': status}
    return records


def verify_state(before, after, expected):
    allowed = {name+':'+item['architecture'] for name, item in expected.items()}
    if {key: value for key, value in before.items() if key not in allowed} != {
            key: value for key, value in after.items() if key not in allowed}:
        raise ValueError('An unlisted Debian package changed')
    for name, item in expected.items():
        if after.get(name+':'+item['architecture']) != {'version': item['version'], 'status': 'ii '}:
            raise ValueError('Requested Debian package did not configure successfully: '+name)


def install(inputs, output):
    if sys.platform != 'linux' or os.geteuid() != 0 or os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1':
        raise RuntimeError('This installer is restricted to the isolated candidate/probe')
    if set(path.name for path in Path('/sys/class/net').iterdir()) != {'lo'}:
        raise RuntimeError('Offline Debian installation requires only the loopback interface')
    manifest = json.loads((inputs/'runtime-image-inputs.json').read_text())
    expected = {item['name']: item for item in manifest['debian_packages']}
    if not expected or len(expected) != len(manifest['debian_packages']):
        raise ValueError('Require unique frozen Debian package inputs')
    packages = []
    for item in expected.values():
        path = inputs/item['artifact']; frozen = manifest['files'][item['artifact']]
        if (path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(inputs.resolve())
                or path.stat().st_size != frozen['bytes'] or digest(path) != frozen['sha256']):
            raise ValueError('Debian package differs from its frozen input')
        fields = dict(line.split(': ', 1) for line in subprocess.check_output([
            'dpkg-deb', '--field', str(path), 'Package', 'Version', 'Architecture'], text=True).strip().splitlines())
        if fields != {'Package': item['name'], 'Version': item['version'], 'Architecture': item['architecture']}:
            raise ValueError('Debian package control differs from its frozen identity')
        packages.append(str(path.resolve()))
    output.mkdir(parents=True, exist_ok=False)
    before = package_state()
    (output/'packages-before.json').write_text(json.dumps(before, indent=2)+'\n')
    env = dict(os.environ, LC_ALL='C', DEBIAN_FRONTEND='noninteractive')
    def run(args, log):
        with (output/log).open('w') as stream:
            result = subprocess.run(args, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
        if result.returncode: raise RuntimeError('Offline Debian check failed: '+log)
        return (output/log).read_text()
    with tempfile.TemporaryDirectory(prefix='erp-offline-apt-') as temporary:
        root = Path(temporary)
        # APT must acquire the local files; --no-download disables that step too.
        (root/'sources.list').write_text('')
        for name in ('sourceparts', 'lists/partial', 'archives/partial'):
            (root/name).mkdir(parents=True)
        options = []
        for key, value in {
                'Dir::Etc::sourcelist': root/'sources.list', 'Dir::Etc::sourceparts': root/'sourceparts',
                'Dir::State::lists': root/'lists', 'Dir::Cache::archives': root/'archives',
                'Dir::Cache::pkgcache': root/'pkgcache.bin', 'Dir::Cache::srcpkgcache': root/'srcpkgcache.bin',
                'Acquire::Retries': '0'}.items():
            options += ['-o', key+'='+str(value)]
        run(['apt-config', *options, 'dump'], 'effective-apt-config.txt')
        base = ['apt-get', *options, '--no-remove', '--no-install-recommends', '-y']
        plan = run([*base, '--simulate', 'install', *packages], 'transaction-plan.log')
        selected = transaction(plan, expected)
        needed = {name: item['version'] for name, item in expected.items()
                  if before.get(name+':'+item['architecture']) != {'version': item['version'], 'status': 'ii '}}
        if selected != needed: raise ValueError('APT did not select exactly the required local changes')
        (output/'selected-transaction.json').write_text(json.dumps(selected, indent=2)+'\n')
        run([*base, 'install', *packages], 'install.log')
        run([*base, 'check'], 'apt-dependency-check.log')
        if any(path.is_file() for path in (root/'lists').rglob('*') if path.name != 'lock'):
            raise ValueError('Offline APT unexpectedly acquired repository metadata')
    if run(['dpkg', '--audit'], 'dpkg-audit.txt').strip():
        raise ValueError('Debian package audit is not empty')
    after = package_state(); verify_state(before, after, expected)
    (output/'packages-after.json').write_text(json.dumps(after, indent=2)+'\n')
    receipt = {'status': 'passed', 'packages': expected, 'selected': selected,
        'repositories': [], 'network': 'loopback-only', 'unlisted_package_changes': [],
        'evidence': {path.name: digest(path) for path in sorted(output.iterdir()) if path.is_file()}}
    (output/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    install(args.inputs, args.output)
