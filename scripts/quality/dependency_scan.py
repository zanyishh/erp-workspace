#!/usr/bin/env python3
"""Scan source plus all tool locks, retaining raw findings and checking coverage."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_python_locks(source):
    destination = source / 'dependency-lock-inputs'
    destination.mkdir(exist_ok=False)
    mapping = []
    for name in ('core', 'semgrep', 'checkov'):
        original = source / f'infrastructure/erpnext/quality/requirements-{name}.lock.txt'
        if original.is_symlink() or not original.is_file():
            raise RuntimeError('Missing regular dependency lock: ' + str(original))
        target = destination / name / 'requirements.txt'
        target.parent.mkdir()
        expected = digest(original)
        shutil.copyfile(original, target)
        mapping.append({'source': str(original.relative_to(source)),
                        'target': str(target.relative_to(source)), 'sha256': expected})
    verify_mapping(source, mapping)
    return mapping


def verify_mapping(source, mapping):
    for row in mapping:
        for key in ('source', 'target'):
            path = source / row[key]
            if path.is_symlink() or digest(path) != row['sha256']:
                raise RuntimeError('Dependency lock changed during scan: ' + str(path))


def summarize(data, expected_python):
    results = data.get('Results', [])
    recognized = {row.get('Target', '') for row in results if row.get('Type') == 'pip'}
    for target in expected_python:
        if not any(actual == target or actual.endswith('/' + target) for actual in recognized):
            raise RuntimeError('Python dependency lock was not recognized: ' + target)
    severities = Counter(v.get('Severity', 'UNKNOWN') for row in results
                         for v in (row.get('Vulnerabilities') or []))
    return {'severities': dict(severities),
            'high_critical_occurrences': severities['HIGH'] + severities['CRITICAL'],
            'recognized_targets': [{'target': row.get('Target'), 'type': row.get('Type')} for row in results]}


def main():
    import quality
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    report = args.report.resolve()
    source = report / 'source'
    if source.is_symlink() or not source.is_dir():
        raise RuntimeError('A fresh source snapshot is required')
    state = {'status': 'running', 'scope': 'product source and quality tool locks including development dependencies',
             'suppressed_findings': False, 'uses_cached_database': True}
    receipt = report / 'dependency-coverage.json'
    with receipt.open('x') as output:
        output.write(json.dumps(state, indent=2) + '\n')
    try:
        mapping = stage_python_locks(source)
        state['lock_mapping'] = mapping
        database_metadata = quality.TOOL_HOME / 'cache/trivy/db/metadata.json'
        state['database'] = json.loads(database_metadata.read_text())
        metadata_hash = digest(database_metadata)
        config = report / 'dependency-empty-config.yaml'
        config.write_text('{}\n')
        command = [str(quality.TOOL_HOME / 'bin/trivy'), '--config', str(config), 'fs', '--parallel', '1',
                   '--scanners', 'vuln', '--severity', 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL', '--include-dev-deps',
                   '--cache-dir', str(quality.TOOL_HOME / 'cache/trivy'), '--skip-db-update', '--skip-java-db-update',
                   '--skip-check-update', '--skip-vex-repo-update', '--offline-scan', '--disable-telemetry',
                   '--skip-version-check', '--no-progress', '--ignorefile', '', '--timeout', '10m',
                   '--format', 'json', '--exit-code', '0', '--output', str(report / 'trivy.json'), str(source)]
        env = quality.environment()
        for name in list(env):
            if name.startswith(('TRIVY_', 'AWS_', 'AZURE_', 'GOOGLE_', 'GITHUB_')):
                env.pop(name)
        env.update(GOMAXPROCS='1', GOMEMLIMIT='768MiB')
        subprocess.run(command, env=env, cwd=report, timeout=660, check=True)
        if digest(database_metadata) != metadata_hash:
            raise RuntimeError('Advisory database changed during scan; rerun for an attributable result')
        verify_mapping(source, mapping)
        data = json.loads((report / 'trivy.json').read_text())
        state.update(summarize(data, [row['target'] for row in mapping]))
        if not any(row.get('Type') == 'npm' and row.get('Target', '').endswith('infrastructure/erpnext/quality/package-lock.json')
                   for row in data.get('Results', [])):
            raise RuntimeError('Quality-tool npm lock was not recognized')
        state['status'] = 'high-critical-found' if state['high_critical_occurrences'] else 'passed-high-critical-gate'
        return int(bool(state['high_critical_occurrences']))
    except BaseException as error:
        state.update(status='execution-or-coverage-failed', error=str(error))
        raise
    finally:
        receipt.write_text(json.dumps(state, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
