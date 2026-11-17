#!/usr/bin/env python3
"""Ordinary offline image assembly; security patches/checks are supplied inputs."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import zipfile

INPUT = Path('/security-input')
SECURITY = Path('/opt/erp-security')
BENCH = Path('/home/frappe/frappe-bench')
PYTHON = BENCH / 'env/bin/python'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def run(args, log, env):
    with (SECURITY/log).open('w') as output:
        result = subprocess.run([str(item) for item in args], cwd=BENCH, env=env,
                                stdout=output, stderr=subprocess.STDOUT, timeout=1200)
    if result.returncode:
        print((SECURITY/log).read_text()[-12000:], flush=True)
        raise RuntimeError('Candidate assembly step failed: '+log)
    print('Passed '+log+' sha256='+digest(SECURITY/log), flush=True)


def install_browser(archive):
    target = BENCH/'chromium/chrome-linux'
    if target.is_symlink() or not target.resolve().is_relative_to(BENCH):
        raise ValueError('Unexpected browser target')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        for path in target.rglob('*'):
            if path.is_file() and any(word in path.name.lower() for word in ('license', 'notice', 'copyright', 'copying')):
                saved = SECURITY/'prior-browser-notices'/path.relative_to(target)
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved)
        shutil.rmtree(target)
    with tempfile.TemporaryDirectory(prefix='erp-browser-') as temporary:
        temporary = Path(temporary)
        with zipfile.ZipFile(archive) as package:
            entries = package.infolist()
            if len(entries) > 1000 or sum(entry.file_size for entry in entries) > 600 * 1024**2:
                raise ValueError('Browser archive exceeds the reviewed size bound')
            for entry in entries:
                name = PurePosixPath(entry.filename)
                if (name.is_absolute() or '..' in name.parts or not name.parts
                        or name.parts[0] != 'chrome-headless-shell-linux-arm64'
                        or (entry.external_attr >> 16 & 0o170000) == 0o120000):
                    raise ValueError('Unexpected browser archive entry')
            package.extractall(temporary)
            for entry in entries:
                path = temporary/entry.filename
                if path.is_file(): path.chmod(0o755 if entry.external_attr >> 16 & 0o111 else 0o644)
        shutil.move(str(temporary/'chrome-headless-shell-linux-arm64'), target)
    binary = target/'chrome-headless-shell'
    with binary.open('rb') as stream:
        if stream.read(4) != b'\x7fELF': raise ValueError('Browser is not an ELF executable')
    (target/'headless_shell').symlink_to('chrome-headless-shell')
    system_link = Path('/usr/bin/chromium-headless-shell')
    system_link.unlink(missing_ok=True)
    system_link.symlink_to(binary)


def main():
    if sys.platform != 'linux' or not PYTHON.is_file():
        raise RuntimeError('This helper runs only inside the candidate image build')
    manifest = json.loads((INPUT/'runtime-image-inputs.json').read_text())
    for name, metadata in manifest['files'].items():
        path = INPUT/name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != metadata['bytes'] or digest(path) != metadata['sha256']:
            raise ValueError('Build input differs from its frozen manifest: '+name)
    SECURITY.mkdir(parents=True, exist_ok=True)
    shutil.copy2(INPUT/'runtime-image-inputs.json', SECURITY/'runtime-image-inputs.json')
    for path in (INPUT/'scripts').iterdir(): shutil.copy2(path, SECURITY/path.name)
    for name in ('runtime-artifacts.lock.json', 'runtime-python-postgres.lock.json',
                 'archive-tar-artifacts.lock.json', 'lxml-artifacts.lock.json', 'pip-artifacts.lock.json',
                 'runtime-node-manifest.json', 'runtime-node-legacy-baseline.json', 'runtime-os-closure.lock.json',
                 'os-artifacts.lock.json', 'util-linux-artifacts.lock.json', 'tool-os-krb5.lock.json',
                 'tool-os-curl.lock.json', 'ncurses-artifacts.lock.json', 'tool-os-libsndfile.lock.json',
                 'sqlite-abi-contract.json', 'os-x11-abi-contract.json', 'tool-os-krb5-abi-exception.json', 'tool-os-pyexpat.lock.json', 'node-runtime.lock.json',
                 'runtime-node-native-contract.lock.json'):
        shutil.copy2(INPUT/name, SECURITY/name)
    env = dict(os.environ, DEBIAN_FRONTEND='noninteractive', NODE_OPTIONS='--max-old-space-size=512',
               GOMAXPROCS='1', UV_OFFLINE='1', UV_NO_CACHE='1', PIP_NO_INDEX='1',
               PIP_DISABLE_PIP_VERSION_CHECK='1', ERP_SECURITY_IMAGE_BUILD='1',
               ERP_NODE_TARGETS_JSON=str(SECURITY/'runtime-node-manifest.json'))
    run([PYTHON, SECURITY/'install-runtime-debs.py', '--inputs', INPUT, '--output', SECURITY/'debian'],
        'debian-install.log', env)
    run([PYTHON, SECURITY/'tool-os-pyexpat.py', 'install', '--artifacts', INPUT/'artifacts/pyexpat',
         '--output', SECURITY/'python-xml'], 'python-xml-install.log', env)
    for name in ('chromium-common', 'chromium-headless-shell'):
        source = Path('/usr/share/doc')/name/'copyright'
        if source.is_file():
            destination = SECURITY/'prior-browser-notices'/name/'copyright'
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    run(['apt-get', '--no-download', '-y', 'purge', 'chromium-common', 'chromium-headless-shell'], 'browser-package-removal.log', env)
    install_browser(INPUT/'chrome.zip')
    for path in [BENCH/'apps/frappe/node_modules/esbuild-linux-arm64/bin/esbuild', BENCH/'apps/frappe/node_modules/esbuild/bin/esbuild']:
        if not path.resolve().is_relative_to(BENCH/'apps/frappe/node_modules'):
            raise ValueError('Unexpected esbuild binary target')
        shutil.copy2(INPUT/'artifacts/esbuild-linux-arm64', path)
        path.chmod(0o755)
    shutil.copy2(INPUT/'artifacts/esbuild-LICENSE', SECURITY/'esbuild-LICENSE')
    requirements = SECURITY/'requirements-runtime.lock.txt'
    requirements.write_text(''.join(f"{item['name']}=={item['version']} --hash=sha256:{manifest['files'][item['artifact']]['sha256']}\n" for item in manifest['python_packages']))
    run(['uv', 'pip', 'install', '--python', PYTHON, '--no-index', '--no-deps', '--require-hashes',
         '--reinstall-package', 'lxml',
         '--find-links', INPUT/'wheels', '-r', requirements], 'python-install.log', env)
    run([PYTHON, SECURITY/'runtime-python-pins.py'], 'python-contract.log', env)
    run(['uv', 'pip', 'install', '--python', PYTHON, '--no-index', '--no-deps', '--no-build-isolation',
         '--reinstall-package', 'frappe', '--editable', BENCH/'apps/frappe'], 'frappe-metadata.log', env)
    run(['uv', 'pip', 'check', '--python', PYTHON], 'python-consistency.log', env)
    run([PYTHON, SECURITY/'install-runtime-pip.py', '--artifacts', INPUT/'wheels',
         '--output', SECURITY/'pip-checks'], 'pip-bootstrap-checks.log', env)
    run([PYTHON, SECURITY/'install-runtime-perl.py', '--payload', INPUT/'perl/archive-tar-runtime.tar.gz',
         '--receipt', SECURITY/'archive-tar-install-receipt.json'], 'archive-tar-install.log', env)
    run(['perl', SECURITY/'archive-tar-ordinary-compatibility.pl'], 'ordinary-archive-tar.json', env)
    run([PYTHON, SECURITY/'install-runtime-node.py', '--archive', INPUT/'artifacts/node-v24.22.3-linux-arm64.tar.xz',
         '--output', SECURITY/'node-runtime'], 'node-runtime-install.log', env)
    run(['runuser', '-u', 'frappe', '--', 'node', SECURITY/'node-runtime-ordinary.cjs'], 'node-runtime-ordinary.log', env)
    shutil.copy2(INPUT/'node-critical.tar.gz', SECURITY/'node-critical.tar.gz')
    run([PYTHON, SECURITY/'runtime-node-critical.py'], 'node-critical-install.log', env)
    (SECURITY/'node-critical.tar.gz').unlink()
    run([PYTHON, SECURITY/'install_runtime_node.py', '--manifest', SECURITY/'runtime-node-manifest.json',
         '--payload-dir', INPUT/'node', '--receipt', SECURITY/'node-remediation-receipt.json'], 'node-high-install.log', env)
    modules = BENCH/'apps/frappe/node_modules'
    checks = [('check_runtime_node.cjs', '/tmp'), ('check_runtime_vite.mjs',),
              ('check_runtime_vue.cjs', modules), ('check_runtime_decoder.cjs',),
              ('check_runtime_node_legacy.cjs', modules, SECURITY/'runtime-node-legacy-baseline.json'),
              ('check_runtime_postcss.cjs', modules/'postcss')]
    for check in checks: run(['node', SECURITY/check[0], *check[1:]], check[0]+'.log', env)
    for name in ('os-node-native-baseline.json', 'os-node-native-candidate.json', 'assessment.json', 'baseline-verification.json'):
        shutil.copy2(INPUT/'evidence/node-native'/name,
                     SECURITY/({'assessment.json': 'node-native-assessment.json',
                                'baseline-verification.json': 'node-native-baseline-verification.json'}.get(name, name)))
    run([PYTHON, SECURITY/'os-node-native-contract.py', '--expected', SECURITY/'os-node-native-candidate.json'],
        'node-native-applicability.json', env)
    run([PYTHON, SECURITY/'check-runtime-os.py'], 'ordinary-os-components.log', env)
    run([PYTHON, SECURITY/'validate-runtime.py'], 'ordinary-runtime-smoke.json', env)
    run([PYTHON, SECURITY/'runtime-component-evidence.py'], 'runtime-component-evidence.json', env)
    run([PYTHON, SECURITY/'build-assets.py'], 'asset-build.log', env)
    for item in manifest['debian_packages']:
        version = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', item['name']], text=True).strip()
        if version != item['version']: raise ValueError('Final Debian version mismatch: '+item['name'])
    audit = subprocess.check_output(['dpkg', '--audit'], text=True)
    if audit.strip(): raise ValueError('Debian package audit reports an incomplete installation')
    (SECURITY/'assembly-receipt.json').write_text(json.dumps({'status': 'passed', 'base_image': manifest['base_image'],
        'inputs_sha256': digest(INPUT/'runtime-image-inputs.json'), 'network': 'disabled', 'application_mounts': [],
        'asset_receipt_sha256': digest(SECURITY/'asset-build.json'),
        'os_checks_receipt_sha256': digest(SECURITY/'os-checks/receipt.json'),
        'python_xml_receipt_sha256': digest(SECURITY/'python-xml/installed.json'),
        'node_runtime_receipt_sha256': digest(SECURITY/'node-runtime/receipt.json'),
        'node_runtime_ordinary_sha256': digest(SECURITY/'node-runtime-ordinary.log'),
        'node_native_applicability_sha256': digest(SECURITY/'node-native-applicability.json'),
        'runtime_checks': 'ordinary-runtime-smoke.json', 'node_checks': [item[0]+'.log' for item in checks]}, indent=2)+'\n')
    print('Offline assembly and ordinary runtime/asset checks passed.', flush=True)


if __name__ == '__main__':
    main()
