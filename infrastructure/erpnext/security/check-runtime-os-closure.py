#!/usr/bin/env python3
"""Fail closed on incomplete OS handoffs before any candidate container exists.

Each reviewed component supplies build_receipts entries with artifact/sha256 and
source_snapshot/source_snapshot_sha256. evidence_files maps retained basenames to
artifact/sha256. package_artifacts maps each expected package to artifact/sha256,
proof_artifact and proof_path (JSON keys leading to the package hash in one of
those verified documents). Git's corrected manual can use the verified X11 proof.
"""
import hashlib
import json
from pathlib import Path
import re

COMPONENTS = {'git', 'sqlite', 'x11', 'zlib', 'util-linux', 'krb5', 'curl', 'ncurses', 'libsndfile'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_script_results(document, scripts):
    records = document.get('tests', [])
    if not isinstance(records, list) or any(not isinstance(record, dict) for record in records):
        raise ValueError('Ordinary script test records must use the retained list schema')
    tests = {record.get('name'): record for record in records}
    if not scripts or len(tests) != len(records) or set(tests) != set(scripts):
        raise ValueError('Ordinary script test set is incomplete or unexpected')
    for name, sha in scripts.items():
        result = tests[name]
        if (result.get('status') != 'passed' or result.get('exit_code') != 0
                or result.get('stderr_bytes') != 0 or result.get('script_sha256') != sha
                or not re.fullmatch('[0-9a-f]{64}', result.get('stdout_sha256', ''))):
            raise ValueError('Ordinary script identity/result did not pass: '+name)


def verify(manifest, files, directory):
    closure = json.loads((directory/'runtime-os-closure.lock.json').read_text())
    if closure['base_image'] != manifest['base_image'] or set(closure['components']) != COMPONENTS:
        raise ValueError('OS closure scope differs from the reviewed candidate')
    pending = [name for name, item in closure['components'].items() if item.get('status') != 'verified-build-handoff']
    if pending: raise ValueError('Ordinary-tested OS artifact handoffs remain pending: '+', '.join(sorted(pending)))
    documents = {}
    origins = {}
    def verified_file(entry):
        name = entry['artifact']; sha = entry['sha256']
        if (name not in files or not re.fullmatch('[0-9a-f]{64}', sha)
                or manifest['artifacts'][name]['sha256'] != sha or digest(files[name]) != sha):
            raise ValueError('OS evidence/artifact hash differs from its reviewed handoff: '+name)
        return files[name]
    for name, item in closure['components'].items():
        lock_name = item['source_lock']
        if Path(lock_name).name != lock_name: raise ValueError('OS source locks must be local basenames')
        source = json.loads((directory/lock_name).read_text())
        if source['base_image'] != manifest['base_image']: raise ValueError('OS source base differs')
        expected_source = source[item['source_key']] if item['source_key'] else source
        if not item['build_receipts']: raise ValueError('OS component lacks completed build receipts: '+name)
        origins[name] = []
        for entry in item['build_receipts']:
            path = verified_file(entry)
            snapshot = verified_file({'artifact': entry['source_snapshot'], 'sha256': entry['source_snapshot_sha256']})
            saved_source = json.loads(snapshot.read_text())
            selected = saved_source[item['source_key']] if item['source_key'] else saved_source
            receipt = json.loads(path.read_text())
            if (saved_source.get('base_image') != manifest['base_image'] or selected != expected_source
                    or receipt.get('source') != selected
                    or receipt.get('base_image', receipt['source'].get('base_image')) != manifest['base_image']
                    or receipt.get('status') != item['expected_build_status'] or receipt.get('exit_code') != 0
                    or receipt.get('cleanup_errors') or receipt.get('evidence_copy_errors')
                    or receipt.get('container_retained') or receipt.get('application_mounts') != []
                    or snapshot.parent != path.parent):
                raise ValueError('OS build receipt/source validation failed: '+name)
            documents[entry['artifact']] = receipt
            origins[name].append(path.parent)
        for basename, entry in item['evidence_files'].items():
            path = verified_file(entry)
            if Path(basename).name != basename or not any(path.parent == origin for origin in origins[name]):
                raise ValueError('Ordinary OS evidence must come from its validated build: '+name)
            if path.suffix == '.json': documents[entry['artifact']] = json.loads(path.read_text())
        for basename in item['required_baselines']:
            if basename not in item['evidence_files']: raise ValueError('Missing ordinary runtime baseline: '+name+'/'+basename)
        for basename, expected_hash in item.get('required_local_contracts', {}).items():
            if (Path(basename).name != basename or digest(directory/basename) != expected_hash
                    or item['evidence_files'].get(basename, {}).get('sha256') != expected_hash):
                raise ValueError('OS ABI contract differs from the approved source and build: '+name)
        for basename, required in item['required_json_evidence'].items():
            entry = item['evidence_files'].get(basename)
            if not entry: raise ValueError('Missing ordinary OS compatibility evidence: '+name+'/'+basename)
            actual = documents[entry['artifact']]
            if any(actual.get(key) != value for key, value in required.items()):
                raise ValueError('Ordinary OS compatibility did not pass: '+name+'/'+basename)
        for basename, scripts in item.get('required_script_checks', {}).items():
            entry = item['evidence_files'].get(basename)
            if not entry: raise ValueError('Missing ordinary script test evidence: '+name+'/'+basename)
            verify_script_results(documents[entry['artifact']], scripts)
    actual_packages = {item['name']: item for item in manifest['debian_packages']}
    for name, item in closure['components'].items():
        if not item['packages'] or set(item['package_artifacts']) != set(item['packages']):
            raise ValueError('OS package closure is incomplete: '+name)
        for package, expected in item['packages'].items():
            entry = item['package_artifacts'][package]; path = verified_file(entry)
            actual = actual_packages.get(package, {})
            if (actual.get('version') != expected['version'] or actual.get('architecture') != expected['architecture']
                    or actual.get('artifact') != entry['artifact']):
                raise ValueError('OS package identity/version differs: '+package)
            proof_name = entry['proof_artifact']
            if proof_name not in documents or not path.is_relative_to(files[proof_name].parent):
                raise ValueError('OS package does not originate beside its validated build proof: '+package)
            proof = documents[proof_name]
            if not entry['proof_path']: raise ValueError('OS package hash proof is missing')
            for key in entry['proof_path']: proof = proof[key]
            if proof != entry['sha256']: raise ValueError('OS package bytes differ from their completed build: '+package)
    return closure
