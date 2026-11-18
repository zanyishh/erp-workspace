"""Verify the one reviewed lxml compiled checkpoint before test-only recovery."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import tarfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_archive(path, lock):
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        if (len(members) > lock['archive_entries_limit']
                or sum(member.size for member in members) > lock['archive_expanded_bytes_limit']):
            raise ValueError('Compiled recovery archive exceeds its bounded size')
        names = set()
        for member in members:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or '..' in name.parts or not name.parts
                    or name.parts[0] != lock['archive_root'] or str(name) in names
                    or not (member.isfile() or member.isdir() or member.issym() or member.islnk())):
                raise ValueError('Unexpected compiled recovery archive member')
            names.add(str(name))
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                resolved = PurePosixPath(posixpath.normpath(str(name.parent/target) if member.issym() else str(target)))
                if target.is_absolute() or not resolved.parts or resolved.parts[0] != lock['archive_root']:
                    raise ValueError('Compiled recovery link escapes its source tree')
        return {'entries': len(members), 'expanded_bytes': sum(member.size for member in members)}


def verify(directory, lock, source_lock_sha256):
    if any(path.is_symlink() for path in (directory, *directory.parents)):
        raise ValueError('Recovery directory must not use symbolic links')
    if source_lock_sha256 != lock['source_lock_sha256']:
        raise ValueError('Recovery source lock differs from the reviewed checkpoint')
    for name, expected in lock['files'].items():
        path = directory/name
        if (Path(name).name != name or path.is_symlink() or not path.is_file()
                or path.stat().st_size != expected['bytes'] or digest(path) != expected['sha256']):
            raise ValueError('Recovery checksum/size differs: '+name)
    prior = json.loads((directory/'resource-receipt.json').read_text())
    phase = json.loads((directory/'compiled-source.json').read_text())
    if (prior.get('status') != 'failed' or prior.get('exit_code') != 1
            or prior.get('base_image') != lock['base_image'] or prior.get('base_id') != lock['base_id']
            or prior.get('source_lock_sha256') != source_lock_sha256
            or prior.get('helpers') != lock['prior_helpers'] or prior.get('application_mounts') != []
            or prior.get('cleanup_errors') or prior.get('container_retained')
            or phase.get('status') != 'compiled-before-ordinary-tests-not-validated'
            or phase.get('base_image') != lock['base_image'] or phase.get('source_lock_sha256') != source_lock_sha256
            or len(phase.get('compiled_extensions', {})) != 7
            or phase.get('sha256') != lock['files']['compiled-source.tar.gz']['sha256']
            or phase.get('bytes') != lock['files']['compiled-source.tar.gz']['bytes']
            or phase.get('recipes') != {name: lock['prior_helpers'][name]
                for name in ('build-lxml-inside.py', 'lxml-offline-setup.py')}):
        raise ValueError('Recovery phase or prior build identity differs')
    result = validate_archive(directory/'compiled-source.tar.gz', lock)
    return dict(result, archive_sha256=phase['sha256'], compiled_extensions=phase['compiled_extensions'],
                tests_reused=False, production_recompiled=False)


def restore(directory, work, output, lock, source_lock_sha256):
    result = verify(directory, lock, source_lock_sha256)
    source = work/lock['archive_root']
    if source.exists(): raise ValueError('Compiled recovery destination must be new')
    with tarfile.open(directory/'compiled-source.tar.gz') as archive:
        archive.extractall(work, filter='data')
    verify_binaries(source, result['compiled_extensions'])
    evidence = output/'prior-build'; evidence.mkdir()
    for name in lock['files']:
        if name != 'compiled-source.tar.gz': shutil.copyfile(directory/name, evidence/name)
    (output/'recovery-receipt.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def verify_binaries(source, expected):
    for name, sha256 in expected.items():
        path = source/name
        if (PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts
                or path.is_symlink() or not path.is_file() or digest(path) != sha256):
            raise ValueError('Production binary changed during test-only recovery: '+name)


def fixture_source(dependency, inputs, source_lock):
    entry = next(item for item in source_lock['sources'] if item['name'] == 'libxml2')
    with tarfile.open(inputs/entry['filename']) as archive:
        original = archive.extractfile('libxml2-'+entry['version']+'/testdso.c').read()
    fixture = dependency/'testdso.c'
    if fixture.read_bytes() != original:
        raise ValueError('Ordinary module fixture differs from unchanged official source')
    libtool = (dependency/'libtool').read_text()
    if '\nbuild_libtool_libs=no\n' not in libtool:
        raise ValueError('Expected the reviewed static-only dependency configuration')
    return {'source_sha256': digest(fixture), 'generated_makefile_sha256': digest(dependency/'Makefile'),
            'generated_libtool_sha256': digest(dependency/'libtool'), 'production_static_configuration_preserved': True}
