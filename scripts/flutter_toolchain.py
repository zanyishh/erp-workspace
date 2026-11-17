#!/usr/bin/env python3
"""Use the verified project Flutter SDK, with caches on its external drive. GPL-3.0."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION_KEYS = {'frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion', 'channel'}


def selected_sdk(root=ROOT):
    try:
        location = json.loads((root / '.local/quality/location.json').read_text())
        selection = json.loads((root / '.local/quality/flutter-sdk.json').read_text())
        lock = json.loads((root / 'infrastructure/erpnext/quality/flutter-toolchain.json').read_text())
        sdk, home, mount = (Path(value) for value in
                            (selection['sdk'], location['tool_home'], location['mountpoint']))
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise RuntimeError('The verified project Flutter SDK selection is missing or invalid; global SDK fallback is disabled.') from error
    if not all(path.is_absolute() for path in (sdk, home, mount)):
        raise RuntimeError('Flutter SDK and cache selection must use absolute external paths.')
    if not os.path.ismount(mount):
        raise RuntimeError('The selected external Flutter drive is not mounted.')
    try:
        identity = plistlib.loads(subprocess.check_output(
            ['/usr/sbin/diskutil', 'info', '-plist', str(mount)], timeout=120))
        if not location.get('volume_uuid') or identity.get('VolumeUUID') != location['volume_uuid']:
            raise ValueError('Volume UUID differs')
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise RuntimeError('Could not verify the mounted Flutter drive against the selected volume identity.') from error
    sdk, home, mount = sdk.resolve(), home.resolve(), mount.resolve()
    if not home.is_relative_to(mount) or not sdk.is_relative_to(home):
        raise RuntimeError('The selected SDK must stay inside the configured external tool home.')
    try:
        version = json.loads((sdk / 'bin/cache/flutter.version.json').read_text())
        expected = lock['version']
        if set(expected) != VERSION_KEYS or any(not isinstance(expected[key], str) or
                                               version.get(key) != expected[key] for key in VERSION_KEYS):
            raise ValueError('Version mismatch')
        for relative in ('bin/flutter', 'bin/dart', 'bin/cache/dart-sdk/bin/dart',
                         'bin/cache/dart-sdk/bin/dartvm', 'bin/cache/dart-sdk/bin/dartaotruntime'):
            path = sdk / relative
            if not path.is_file() or not path.resolve().is_relative_to(sdk) or not os.access(path, os.X_OK):
                raise ValueError('Executable missing or outside SDK')
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise RuntimeError('The selected Flutter/Dart SDK does not match the pinned release; fallback is disabled.') from error
    return sdk, home, expected


def environment(sdk, home, root=ROOT):
    env = os.environ.copy()
    project = hashlib.sha256(str(root.resolve()).encode()).hexdigest()[:16]
    cache = home / 'flutter-project' / project
    paths = {
        'PUB_CACHE': home / 'pub-cache', 'TMPDIR': cache / 'tmp',
        'XDG_CACHE_HOME': cache / 'cache', 'XDG_CONFIG_HOME': cache / 'config',
        'XDG_DATA_HOME': cache / 'data', 'ANALYZER_STATE_LOCATION_OVERRIDE': cache / 'cache/analyzer',
        'GRADLE_USER_HOME': cache / 'gradle', 'ANDROID_USER_HOME': cache / 'android',
    }
    for key, path in paths.items():
        if not path.resolve().is_relative_to(home):
            raise RuntimeError('A project cache points outside the external tool home: ' + key)
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env.update({
        'PATH': str(sdk / 'bin') + os.pathsep + env.get('PATH', ''), 'FLUTTER_ROOT': str(sdk),
        'PUB_HOSTED_URL': 'https://pub.dev', 'FLUTTER_STORAGE_BASE_URL': 'https://storage.googleapis.com',
    })
    return env


def main(arguments=None, *, root=ROOT):
    arguments = list(sys.argv[1:] if arguments is None else arguments)
    if not arguments:
        raise RuntimeError('Provide Flutter arguments, --dart followed by Dart arguments, or --check.')
    sdk, home, version = selected_sdk(root)
    if arguments == ['--check']:
        print(json.dumps({'sdk': str(sdk), 'version': version}, sort_keys=True))
        return 0
    tool = 'dart' if arguments[0] == '--dart' else 'flutter'
    if tool == 'dart': arguments.pop(0)
    if not arguments: raise RuntimeError('Dart arguments are required.')
    executable = str(sdk / 'bin' / tool)
    os.execvpe(executable, [executable, *arguments], environment(sdk, home, root))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
