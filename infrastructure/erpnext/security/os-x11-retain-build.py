#!/usr/bin/env python3
"""Retain a bounded compiled X11 tree at dpkg's documented pre-binary hook."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile

PACKAGES={'libx11','libxi','libxrender','libxtst'}
FLOOR=400*1024**2
LIMIT=128*1024**2


def inventory(source):
    source=source.resolve()
    paths=[source,*sorted(source.rglob('*'))]
    total=0
    for path in paths:
        if path.is_symlink():
            if not path.resolve().is_relative_to(source):
                raise ValueError('Compiled tree link escapes source: '+str(path))
        elif path.is_file():total+=path.stat().st_size
        elif not path.is_dir():raise ValueError('Unexpected compiled tree entry: '+str(path))
    if total>LIMIT or len(paths)>20000:raise ValueError('Compiled tree exceeds retention budget')
    return paths,total


def main():
    source=Path.cwd().resolve()
    if (source.parent!=Path('/security-work') or source.name not in PACKAGES
            or os.environ.get('DPKG_BUILDPACKAGE_HOOK_NAME')!='binary'):
        raise ValueError('Use only as the owned X11 pre-binary hook')
    paths,total=inventory(source)
    output=Path('/security-output')
    # Bound gzip/tar overhead conservatively and preserve the ordinary disk floor.
    if shutil.disk_usage(output).free < FLOOR+total+16*1024**2:
        raise ValueError('Insufficient space to retain compiled tree above the disk floor')
    archive=output/(source.name+'.compiled-tree.tar.gz')
    if archive.exists():raise ValueError('Do not overwrite retained build evidence')
    with tarfile.open(archive,'w:gz',compresslevel=1) as target:
        for path in paths:target.add(path,arcname=str(path.relative_to(source.parent)),recursive=False)
    original=output/'original-libraries'
    if not original.exists():shutil.copytree('/security-work/original-libraries',original)
    log=output/(source.name+'.pre-binary.log')
    shutil.copyfile(output/(source.name+'.build-tests.log'),log)
    lock=Path('/security-input/os-artifacts.lock.json')
    proof={'status':'debian-build-target-completed-binary-packaging-and-abi-pending',
           'package':source.name,'hook':'binary','build_target_completed':True,
           'packaging_and_abi_accepted':False,'entries':len(paths),'logical_bytes':total,
           'archive':archive.name,'archive_bytes':archive.stat().st_size,
           'archive_sha256':hashlib.file_digest(archive.open('rb'),'sha256').hexdigest(),
           'source_lock_sha256':hashlib.sha256(lock.read_bytes()).hexdigest(),
           'build_log':log.name,'build_log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),
           'documentation':'https://manpages.debian.org/trixie/dpkg-dev/dpkg-buildpackage.1.en.html#DESCRIPTION'}
    (output/(source.name+'.compiled-tree.json')).write_text(json.dumps(proof,indent=2)+'\n')


if __name__=='__main__':main()
