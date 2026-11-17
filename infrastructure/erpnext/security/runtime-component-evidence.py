#!/usr/bin/env python3
"""Read-only evidence for alerts requiring absent optional server components.

This does not hide scanner rows or claim their package versions are patched.
An unexpected installed component fails the applicability gate.
"""
import json
from pathlib import Path
import shutil
import subprocess


def installed(name):
    result = subprocess.run(['dpkg-query', '-W', '-f=${Status}\t${Version}', name],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        return None
    status, _, version = result.stdout.partition('\t')
    return version if status == 'install ok installed' else None


def inspect_components():
    definitions = {
        'CVE-2026-16742': {
            'reported_packages': ['libsystemd0', 'libudev1'],
            'required_packages': ['systemd-homed'],
            'required_paths': ['/usr/lib/systemd/systemd-homed', '/usr/libexec/systemd/systemd-homed'],
            'commands': ['homectl'],
            'reason': 'The affected systemd-homed service and homed-managed login are absent; library package versions are not claimed fixed.',
            'source': 'https://github.com/systemd/systemd/security/advisories/GHSA-jm29-p7hh-vjhv',
        },
        'CVE-2026-24882': {
            'reported_packages': ['gpg', 'gpgconf'],
            'required_packages': ['gpg-tpm'],
            'required_paths': ['/usr/lib/gnupg/tpm2daemon', '/usr/lib/gnupg2/tpm2daemon',
                               '/usr/libexec/gnupg/tpm2daemon', '/usr/libexec/tpm2daemon'],
            'commands': ['tpm2daemon'],
            'reason': 'The affected TPM2 daemon is absent; the remaining GPG package versions are not claimed fixed.',
            'source': 'https://dev.gnupg.org/T8045',
        },
        'CVE-2022-4055': {
            'reported_packages': ['xdg-utils'],
            'required_packages': ['thunderbird', 'icedove'],
            'required_paths': ['/usr/lib/thunderbird', '/usr/lib/icedove', '/opt/thunderbird'],
            'commands': ['thunderbird', 'icedove'],
            'reason': 'The alert requires xdg-mail launching Thunderbird; no Thunderbird-compatible client is installed. Vulnerable xdg-mail code remains, so this is a deployment prerequisite assessment, not a source-code fix.',
            'source': 'https://security-tracker.debian.org/tracker/CVE-2022-4055',
        },
    }
    results = {}
    for advisory, definition in definitions.items():
        versions = {name: installed(name) for name in definition['reported_packages']}
        required = {name: installed(name) for name in definition['required_packages']}
        paths = {path: Path(path).exists() for path in definition['required_paths']}
        commands = {name: shutil.which(name) for name in definition['commands']}
        if any(required.values()) or any(paths.values()) or any(commands.values()):
            raise RuntimeError(f'{advisory}: required component unexpectedly present; reassess applicability')
        results[advisory] = {
            'status': 'required-component-absent-in-inspected-filesystem',
            'reported_package_versions': versions,
            'required_package_versions': required, 'required_paths_present': paths,
            'commands_found': commands, 'reason': definition['reason'],
            'source': definition['source'], 'scanner_rows_suppressed': False,
        }
    return results


if __name__ == '__main__':
    print(json.dumps(inspect_components(), indent=2))
