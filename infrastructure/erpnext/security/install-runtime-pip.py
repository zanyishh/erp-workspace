#!/usr/bin/env python3
"""Install the official locked pip wheel and refresh Python's offline seed."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile

DIRECTORY = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_file(path, sha256, size=None):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Require a regular file: ' + str(path))
    data = path.read_bytes()
    if digest(data) != sha256 or (size is not None and len(data) != size):
        raise ValueError('Pinned file changed: ' + str(path))
    return data


def patch_ensurepip(data, entry):
    if digest(data) != entry['sha256']:
        raise ValueError('ensurepip source preimage changed')
    old, new = entry['old_constant'].encode(), entry['new_constant'].encode()
    if data.count(old) != 1 or new in data:
        raise ValueError('Unexpected ensurepip version constant')
    return data.replace(old, new)


def verify_artifacts(directory, lock):
    for name, entry in lock['artifacts'].items():
        if Path(name).name != name:
            raise ValueError('Artifact name must be a basename')
        verify_file(directory / name, entry['sha256'], entry['bytes'])
    wheel = directory / ('pip-' + lock['version'] + '-py3-none-any.whl')
    with zipfile.ZipFile(wheel) as archive:
        vendor = archive.read('pip/_vendor/vendor.txt')
        if digest(vendor) != lock['new_vendor_sha256']:
            raise ValueError('Unexpected upstream vendored dependency contract')
        for name, version in lock['vendored_fixes'].items():
            if name + '==' + version not in [line.strip() for line in vendor.decode().splitlines()]:
                raise ValueError('Required maintained vendor version missing: ' + name)
        names = set(archive.namelist())
        if ('pip/_vendor/pkg_resources/LICENSE' not in names
                or any(name.startswith('pip/_vendor/setuptools/') for name in names)):
            raise ValueError('Unexpected setuptools vendoring scope')
    return wheel


def installed_matches_wheel(site, wheel):
    with zipfile.ZipFile(wheel) as archive:
        names = [name for name in archive.namelist() if not name.endswith('/')]
        expected_pip = {name for name in names if name.startswith('pip/')}
        actual_pip = set()
        for path in (site / 'pip').rglob('*'):
            if path.is_symlink():
                raise ValueError('Unexpected symlink in installed pip')
            if path.is_file() and '__pycache__' not in path.parts:
                actual_pip.add(str(path.relative_to(site)))
        if actual_pip != expected_pip:
            raise ValueError('Installed pip has missing or stale package files')
        for name in names:
            if name.endswith('.dist-info/RECORD'):
                continue  # The installer adds entrypoint scripts to RECORD.
            path = site / name
            if path.is_symlink() or not path.is_file() or path.read_bytes() != archive.read(name):
                raise ValueError('Installed bytes differ from the official wheel: ' + name)
    return len(names) - 1


def run(command, output, name, env):
    with (output / (name + '.log')).open('w') as stream:
        result = subprocess.run([str(arg) for arg in command], env=env, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=180)
    if result.returncode:
        raise RuntimeError('Ordinary pip command failed; inspect ' + name + '.log')


def pip_command(python, *args):
    return [python, '-I', '-m', 'pip', '--isolated', '--disable-pip-version-check', *args]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--preflight', action='store_true')
    args = parser.parse_args()
    lock = json.loads((DIRECTORY / 'pip-artifacts.lock.json').read_text())
    artifacts = args.artifacts.resolve()
    wheel = verify_artifacts(artifacts, lock)
    if args.preflight:
        print(json.dumps({'status': 'verified-artifacts-only', 'installed': False, 'version': lock['version']}))
        return
    if (sys.platform != 'linux' or platform.machine() != 'aarch64' or os.geteuid() != 0
            or os.environ.get('ERP_SECURITY_IMAGE_BUILD') != '1'):
        raise RuntimeError('Run only as root during the isolated ARM64 candidate image assembly')
    if args.output is None or args.output.exists():
        raise ValueError('Require a new output directory for retained evidence')
    entry = lock['ensurepip']
    source = Path(entry['source'])
    original = verify_file(source, entry['sha256'])
    replacement = patch_ensurepip(original, entry)
    bundle = source.parent / '_bundled'
    old_wheel = bundle / entry['previous_wheel']
    verify_file(old_wheel, entry['previous_wheel_sha256'], entry['previous_wheel_bytes'])
    if sorted(path.name for path in bundle.glob('pip-*.whl')) != [old_wheel.name]:
        raise ValueError('Unexpected ensurepip bundle contents')
    # Validate both installed environments before the first mutation.
    probe = ('import json, pip, sys; print(json.dumps({"prefix":sys.prefix, '
             '"file":pip.__file__, "version":pip.__version__, "python":list(sys.version_info[:2])}))')
    for target in lock['targets']:
        info = json.loads(subprocess.check_output([target['python'], '-I', '-c', probe], text=True, timeout=30))
        site = Path(target['site_packages'])
        expected = {'prefix': target['prefix'], 'file': str(site / 'pip/__init__.py'),
                    'version': target['previous_version'], 'python': [3, 14]}
        if info != expected or (site / 'pip').is_symlink():
            raise ValueError('Unexpected installed pip preimage: ' + target['name'])
        verify_file(site / 'pip/_vendor/vendor.txt', target['previous_vendor_sha256'])
        if target['previous_version'] == lock['version']:
            installed_matches_wheel(site, wheel)
    output = args.output.resolve()
    output.mkdir(parents=True)
    shutil.copy2(DIRECTORY / 'pip-artifacts.lock.json', output / 'pip-artifacts.lock.json')
    (output / 'ensurepip-original.py').write_bytes(original)
    receipt = {'status': 'running', 'version': lock['version'], 'network': 'offline-only', 'targets': {}}
    env = dict(os.environ, PIP_CONFIG_FILE=os.devnull, PIP_NO_INDEX='1', PIP_NO_CACHE_DIR='1',
               PIP_DISABLE_PIP_VERSION_CHECK='1', PYTHONDONTWRITEBYTECODE='1')
    try:
        for target in lock['targets']:
            site = Path(target['site_packages'])
            for directory in (site / 'pip', site / ('pip-' + target['previous_version'] + '.dist-info')):
                for path in directory.rglob('*'):
                    if path.is_file() and any(word in path.name.lower() for word in ('license', 'copying', 'copyright')):
                        if path.is_symlink():
                            raise ValueError('Unexpected notice symlink: ' + str(path))
                        saved = output / 'prior-notices' / target['name'] / path.relative_to(site)
                        saved.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(path, saved)
            action = 'verified-existing-official-version'
            if target['previous_version'] != lock['version']:
                run(pip_command(target['python'], 'install', '--no-index', '--no-deps', '--no-cache-dir',
                                '--no-user', '--force-reinstall', wheel), output, target['name'] + '-install', env)
                action = 'upgraded-offline'
            receipt['targets'][target['name']] = {'action': action, 'official_wheel_files_verified':
                installed_matches_wheel(site, wheel)}
            run(pip_command(target['python'], 'check'), output, target['name'] + '-pip-check', env)
        shutil.copy2(wheel, bundle / wheel.name)
        source.write_bytes(replacement)
        old_wheel.unlink()
        verify_file(bundle / wheel.name, lock['artifacts'][wheel.name]['sha256'])
        receipt['ensurepip_source_sha256'] = digest(source.read_bytes())
        global_python = lock['targets'][0]['python']
        with tempfile.TemporaryDirectory(prefix='erp-pip-ordinary-') as temporary:
            temporary = Path(temporary)
            fresh = temporary / 'fresh'
            run([global_python, '-I', '-m', 'venv', '--without-pip', fresh], output, 'fresh-venv', env)
            python = fresh / 'bin/python'
            run([python, '-I', '-m', 'ensurepip', '--default-pip'], output, 'fresh-ensurepip', env)
            run([python, '-I', '-c', 'import ensurepip, pip; assert ensurepip.version() == pip.__version__ == "26.3"'],
                output, 'fresh-seed-version', env)
            installed_matches_wheel(fresh / 'lib/python3.14/site-packages', wheel)
            project = temporary / 'project'
            project.mkdir()
            (project / 'pyproject.toml').write_text('[build-system]\nrequires=["flit_core==3.12.0"]\n'
                'build-backend="flit_core.buildapi"\n[project]\nname="erp-pip-ordinary-smoke"\n'
                'version="1.0.0"\ndescription="Synthetic offline package check"\n')
            (project / 'erp_pip_ordinary_smoke.py').write_text('VALUE = "offline-install-passed"\n')
            wheels = temporary / 'wheels'
            run(pip_command(python, 'wheel', '--no-index', '--no-deps', '--no-cache-dir', '--find-links', artifacts,
                            '--wheel-dir', wheels, project), output, 'ordinary-flit-wheel', env)
            candidates = list(wheels.glob('erp_pip_ordinary_smoke-1.0.0-*.whl'))
            if len(candidates) != 1:
                raise RuntimeError('Ordinary offline wheel build did not produce exactly one wheel')
            built = candidates[0]
            receipt['ordinary_wheel_sha256'] = digest(built.read_bytes())
            for name, interpreter in [('fresh', python), *[(t['name'], t['python']) for t in lock['targets']]]:
                target = temporary / ('install-' + name)
                run(pip_command(interpreter, 'install', '--no-index', '--no-deps', '--no-cache-dir',
                                '--target', target, built), output, name + '-ordinary-install', env)
                code = 'import sys; sys.path.insert(0, ' + repr(str(target)) + '); import erp_pip_ordinary_smoke as m; assert m.VALUE == "offline-install-passed"'
                run([interpreter, '-I', '-c', code], output, name + '-ordinary-import', env)
            run(pip_command(python, 'check'), output, 'fresh-pip-check', env)
        receipt['status'] = 'passed-offline-install-wheel-and-ensurepip-checks'
    except BaseException as error:
        receipt.update(status='failed', error=str(error))
        raise
    finally:
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
