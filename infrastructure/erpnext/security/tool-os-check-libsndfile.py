#!/usr/bin/env python3
"""Check the installed libsndfile codec/API contract and ordinary audio I/O."""
import ctypes
import email.utils
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

WORK, OUTPUT = Path('/security-work'), Path('/security-output')
LIBRARY = Path('/usr/lib/aarch64-linux-gnu/libsndfile.so.1')
VERSION = '1.2.2-2+deb13u1+erp1'
PATCH_NAME = 'tool-os-libsndfile-CVE-2026-37555.patch'
# Exact unmodified ordinary harness files from the locked 1.2.2 source archive.
SERIAL_HARNESS_HASHES = {
    'configure.ac': '305e353e61a588df6aa4594f34cd0a7733737cbc62d63442b51c1ab6eb4a9f74',
    'Makefile.am': 'ac7c6c911893b127746c2b27480805d892c6b4562c3481e3c86689f0300049e6',
    'tests/test_wrapper.sh.in': '3f1ea7031d5a91a760fc0e92a998ac2e7d5c9ead5c53ce6849bc05f115ced6a3',
}


class Info(ctypes.Structure):
    _fields_ = [('frames', ctypes.c_int64), ('samplerate', ctypes.c_int),
                ('channels', ctypes.c_int), ('format', ctypes.c_int),
                ('sections', ctypes.c_int), ('seekable', ctypes.c_int)]


class Format(ctypes.Structure):
    _fields_ = [('format', ctypes.c_int), ('name', ctypes.c_char_p),
                ('extension', ctypes.c_char_p)]


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                          check=True).stdout


def library():
    value = ctypes.CDLL(str(LIBRARY))
    value.sf_command.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
    value.sf_command.restype = ctypes.c_int
    value.sf_format_check.argtypes = [ctypes.POINTER(Info)]
    value.sf_format_check.restype = ctypes.c_int
    return value


def inventory():
    lib = library()
    result = {}
    for key, command in [('major', 0x1030), ('subtype', 0x1032)]:
        count = ctypes.c_int()
        assert lib.sf_command(None, command, ctypes.byref(count), ctypes.sizeof(count)) == 0
        assert 0 < count.value < 200
        formats = []
        for index in range(count.value):
            item = Format(index, None, None)
            assert lib.sf_command(None, command + 1, ctypes.byref(item), ctypes.sizeof(item)) == 0
            formats.append({'id': item.format, 'name': item.name.decode(),
                            'extension': item.extension.decode() if item.extension else None})
        result[key] = formats
    combinations = []
    for major in result['major']:
        for subtype in result['subtype']:
            info = Info(0, 48000, 2, major['id'] | subtype['id'], 0, 0)
            if lib.sf_format_check(ctypes.byref(info)):
                combinations.append(info.format)
    result['valid_stereo_48khz_formats'] = sorted(combinations)
    return result


def require_features(old, new):
    for key in ('major', 'subtype'):
        missing = {f['id'] for f in old[key]} - {f['id'] for f in new[key]}
        if missing:
            raise ValueError('Removed audio ' + key + ' formats: ' + str(sorted(missing)))
    missing = set(old['valid_stereo_48khz_formats']) - set(new['valid_stereo_48khz_formats'])
    if missing:
        raise ValueError('Removed supported codec combinations: ' + str(sorted(missing)))


def capture():
    control = run('dpkg-query', '-s', 'libsndfile1')
    assert 'Version: 1.2.2-2+deb13u1\n' in control
    (OUTPUT / 'original-package-control.txt').write_text(control)
    shutil.copy2(LIBRARY, WORK / 'original-libsndfile.so.1')
    (OUTPUT / 'original-codecs.json').write_text(json.dumps(inventory(), indent=2) + '\n')


def prepare():
    source = WORK / 'libsndfile-1.2.2'
    lock = json.loads(Path('/security-input/tool-os-libsndfile.lock.json').read_text())['libsndfile']
    patch = Path('/security-input') / PATCH_NAME
    assert hashlib.sha256(patch.read_bytes()).hexdigest() == lock['patch_sha256']
    series = source / 'debian/patches/series'
    assert len(series.read_text().splitlines()) == 16
    shutil.copy2(patch, source / 'debian/patches' / PATCH_NAME)
    series.write_text(series.read_text().rstrip() + '\n' + PATCH_NAME + '\n')
    changelog = source / 'debian/changelog'
    assert changelog.read_text().startswith('libsndfile (1.2.2-2+deb13u1) ')
    changelog.write_text(f'libsndfile ({VERSION}) trixie; urgency=medium\n\n  * Apply maintained upstream commit cdadf9a65fdc1f28da9d235eb443d5f5e57010d2\n    for CVE-2026-37555, retaining all sixteen Debian patches and codecs.\n\n -- ERP local security build <security@localhost>  {email.utils.formatdate(localtime=False)}\n\n' + changelog.read_text())
    (OUTPUT / 'source-remediation.json').write_text(json.dumps({
        'upstream_version': '1.2.2', 'package_version': VERSION,
        'patch_sha256': lock['patch_sha256'], 'commit': lock['commit'],
        'original_debian_patches': 16, 'added_maintained_patches': 1,
        'tracker_discrepancy': lock['tracker_discrepancy'],
        'tests_disabled': [], 'codecs_disabled': []}, indent=2) + '\n')


def exports(path):
    return {line.split()[-1] for line in run('nm', '-D', '--defined-only', str(path)).splitlines() if line.split()}


def serial_harness_labels(files):
    if set(files) != set(SERIAL_HARNESS_HASHES) or any(
            hashlib.sha256(files[name]).hexdigest() != digest
            for name, digest in SERIAL_HARNESS_HASHES.items()):
        raise ValueError('Original serial test harness changed')
    return re.findall(r'echo "  \$sfversion (passed[^"\n]+)"',
                      files['tests/test_wrapper.sh.in'].decode())


def serial_suite_report(text, labels):
    """Verify the original serial driver's output, without inventing test counts."""
    if len(labels) != 30 or len(set(labels)) != 30:
        raise ValueError('Original serial wrapper section inventory changed')
    if re.search(r'^(?:FAIL|ERROR|XFAIL|XPASS):|^DEBIAN_BUILD_AND_ORDINARY_MAKE_CHECK_EXIT=(?!0$)', text, re.M):
        raise ValueError('Ordinary serial suite reported failure')
    markers = ['Running unit tests from src/ directory of source code tree.',
               'Running end-to-end tests from tests/ directory.']
    markers += ['  libsndfile-1.2.2 ' + label for label in labels]
    markers += ['PASS: tests/pedantic-header-test.sh', '1 test passed',
                'DEBIAN_BUILD_AND_ORDINARY_MAKE_CHECK_EXIT=0']
    lines = text.splitlines()
    previous = -1
    for marker in markers:
        if lines.count(marker) != 1 or lines.index(marker) <= previous:
            raise ValueError('Missing, repeated or out-of-order serial suite marker: ' + marker)
        previous = lines.index(marker)
    return {'status': 'passed', 'driver': 'original-automake-serial-tests',
            'debian_build_and_ordinary_make_check_exit_code': 0,
            'completed_wrapper_sections': len(labels),
            'automake_test_drivers_passed': 1, 'tests_disabled': []}


def package():
    source = WORK / 'libsndfile-1.2.2'
    harness = {name: (source / name).read_bytes() for name in SERIAL_HARNESS_HASHES}
    labels = serial_harness_labels(harness)
    log = OUTPUT / 'upstream-serial-tests.log'
    shutil.copy2(OUTPUT / 'build.log', log)
    report = serial_suite_report(log.read_text(), labels)
    for name, data in harness.items():
        target = OUTPUT / 'upstream-harness' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    report.update(log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
                  source_harness_sha256=SERIAL_HARNESS_HASHES)
    (OUTPUT / 'upstream-serial-tests.json').write_text(json.dumps(report, indent=2) + '\n')
    matches = list(WORK.glob(f'libsndfile1_{VERSION}_arm64.deb'))
    assert len(matches) == 1, matches
    target = OUTPUT / matches[0].name
    shutil.copy2(matches[0], target)
    extract = WORK / 'package'
    extract.mkdir()
    run('dpkg-deb', '--extract', str(target), str(extract))
    candidate = extract / str(LIBRARY).lstrip('/')
    dynamic = run('readelf', '-d', str(candidate))
    assert re.search(r'\(SONAME\).*\[libsndfile\.so\.1\]', dynamic)
    old = exports(WORK / 'original-libsndfile.so.1')
    new = exports(candidate)
    assert not old - new, sorted(old - new)
    (OUTPUT / 'abi-comparison.json').write_text(json.dumps({
        'soname': 'libsndfile.so.1', 'original_exports': len(old),
        'candidate_exports': len(new), 'missing_exports': [],
        'dynamic_section': dynamic, 'package_sha256': hashlib.sha256(target.read_bytes()).hexdigest()}, indent=2) + '\n')


def roundtrip(format_id):
    lib = library()
    lib.sf_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(Info)]
    lib.sf_open.restype = ctypes.c_void_p
    lib.sf_close.argtypes = [ctypes.c_void_p]
    lib.sf_close.restype = ctypes.c_int
    for name in ('sf_write_short', 'sf_read_short'):
        fn = getattr(lib, name)
        fn.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_short), ctypes.c_int64]
        fn.restype = ctypes.c_int64
    samples = [((n * 29) % 20001) - 10000 for n in range(2048)]
    data = (ctypes.c_short * len(samples))(*samples)
    with tempfile.TemporaryDirectory() as temp:
        file = str(Path(temp) / 'normal-audio').encode()
        info = Info(0, 48000, 2, format_id, 0, 0)
        handle = lib.sf_open(file, 0x20, ctypes.byref(info))
        assert handle
        try:
            assert lib.sf_write_short(handle, data, len(samples)) == len(samples)
        finally:
            assert lib.sf_close(handle) == 0
        info = Info()
        handle = lib.sf_open(file, 0x10, ctypes.byref(info))
        assert handle
        try:
            assert (info.samplerate, info.channels, info.frames) == (48000, 2, 1024)
            result = (ctypes.c_short * len(samples))()
            assert lib.sf_read_short(handle, result, len(samples)) == len(samples)
            assert list(result) == samples
        finally:
            assert lib.sf_close(handle) == 0


def smoke():
    new = inventory()
    require_features(json.loads((OUTPUT / 'original-codecs.json').read_text()), new)
    (OUTPUT / 'candidate-codecs.json').write_text(json.dumps(new, indent=2) + '\n')
    roundtrip(0x010000 | 0x0002)  # WAV / PCM16
    roundtrip(0x020000 | 0x0002)  # AIFF / PCM16
    assert run('dpkg-query', '-W', '-f=${Version}', 'libsndfile1') == VERSION
    print(json.dumps({'version': VERSION, 'all_baseline_codecs_preserved': True,
                      'wav_pcm16_roundtrip': True, 'aiff_pcm16_roundtrip': True}))


if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('capture', 'prepare', 'package', 'smoke'):
        raise SystemExit('Expected capture, prepare, package or smoke')
    globals()[sys.argv[1]]()
