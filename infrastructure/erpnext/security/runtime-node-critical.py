#!/usr/bin/env python3
"""Apply the verified Critical dependency fixes only inside a derived image."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile


REPLACEMENTS = {'loader-utils': ('0.2.17', '1.4.2'), 'shell-quote': ('1.8.1', '1.12.0')}


def apply_overlay(modules, archive, expected_sha256):
    modules = Path(modules)
    archive = Path(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_sha256:
        raise ValueError('Node overlay archive hash mismatch')
    for name, (old, _) in REPLACEMENTS.items():
        manifest = json.loads((modules / name / 'package.json').read_text())
        if manifest.get('name') != name or manifest.get('version') != old:
            raise ValueError('Unexpected installed package: ' + name)
    generic_path = modules / 'generic-names/package.json'
    generic = json.loads(generic_path.read_text())
    if generic.get('version') != '1.0.3' or generic['dependencies']['loader-utils'] != '^0.2.16':
        raise ValueError('Unexpected generic-names dependency contract')
    with tempfile.TemporaryDirectory(prefix='node-security-') as temporary:
        temporary = Path(temporary)
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] not in REPLACEMENTS:
                    raise ValueError('Unexpected archive path')
                if not (member.isfile() or member.isdir()):
                    raise ValueError('Archive must not contain links or special files')
            bundle.extractall(temporary, filter='data')
        for name, (_, new) in REPLACEMENTS.items():
            replacement = json.loads((temporary / name / 'package.json').read_text())
            if replacement.get('name') != name or replacement.get('version') != new:
                raise ValueError('Unexpected replacement package: ' + name)
        for name in REPLACEMENTS:
            shutil.rmtree(modules / name)
            shutil.copytree(temporary / name, modules / name)
    # generic-names only consumes interpolateName; its unchanged CSS outputs
    # are checked against the original dependency by test_runtime_node.cjs.
    generic['dependencies']['loader-utils'] = '1.4.2'
    generic_path.write_text(json.dumps(generic, indent=2) + '\n')


def prune_orphan_json5(modules):
    """Remove the replaced loader's old root dependency only if unreferenced.

    The pinned-image import audit is retained with preparation evidence. This
    final check independently resolves every declared JSON5 dependency using
    Node itself after installing the loader's private fixed dependency.
    """
    modules = Path(modules)
    old = modules / 'json5'
    manifest = json.loads((old / 'package.json').read_text())
    if manifest.get('name') != 'json5' or manifest.get('version') != '0.5.1':
        raise ValueError('Unexpected legacy root JSON5 package')
    consumers = []
    for package in modules.rglob('package.json'):
        if package == old / 'package.json':
            continue
        data = json.loads(package.read_text())
        if 'json5' in {**data.get('dependencies', {}), **data.get('optionalDependencies', {})}:
            consumers.append(str(package.parent))
    script = "const fs=require('fs'),p=require('path'); const [old,consumers]=JSON.parse(process.argv[1]); for(const c of consumers){const target=fs.realpathSync(require.resolve('json5',{paths:[c]})); if(target.startsWith(fs.realpathSync(old)+p.sep))throw Error('Legacy JSON5 still resolved by '+c)}"
    subprocess.run(['node', '-e', script, json.dumps([str(old), consumers])], check=True)
    shutil.rmtree(old)


if __name__ == '__main__':
    base = Path('/opt/erp-security')
    lock = json.loads((base / 'runtime-artifacts.lock.json').read_text())
    apply_overlay('/home/frappe/frappe-bench/apps/frappe/node_modules',
                  base / 'node-critical.tar.gz', lock['node_critical_overlay']['sha256'])
    prune_orphan_json5('/home/frappe/frappe-bench/apps/frappe/node_modules')
