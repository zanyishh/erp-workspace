#!/usr/bin/env python3
"""Freeze Curl's eight exact local packages and verify their installed ELF bytes."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile

EXPECTED = dict.fromkeys(['curl','libcurl4t64','libcurl4-gnutls','libcurl3t64-gnutls'], '8.23.0-2+erp1')
EXPECTED.update({'libnghttp3-9':'1.15.0-1~bpo13+1',
                 **dict.fromkeys(['libngtcp2-16','libngtcp2-crypto-gnutls8','libngtcp2-crypto-ossl0'], '1.22.1-1~bpo13+1')})

def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()

def archive(path, prefix):
    raw=path.read_bytes()
    if raw[:8]!=b'!<arch>\n': raise ValueError('Invalid pinned Debian package')
    offset=8
    while offset<len(raw):
        header=raw[offset:offset+60]
        if len(header)!=60 or header[-2:]!=b'`\n': raise ValueError('Invalid Debian archive member')
        size=int(header[48:58]); name=header[:16].decode().strip().rstrip('/')
        if offset+60+size>len(raw): raise ValueError('Truncated Debian archive')
        if name.startswith(prefix): return tarfile.open(fileobj=io.BytesIO(raw[offset+60:offset+60+size]))
        offset+=60+size+(size%2)
    raise ValueError('Missing Debian archive: '+prefix)

def control(path, prefix):
    with archive(path, prefix) as stream:
        item=next(x for x in stream if x.name.lstrip('./')=='control')
        text=stream.extractfile(item).read().decode()
        return dict(re.findall(r'^(Package|Version|Architecture): (.+)$',text,re.M))

def manifest(directory):
    paths={('dependencies/' if name.startswith('libng') else '')+f'{name}_{version}_arm64.deb':name for name,version in EXPECTED.items()}
    if {str(p.relative_to(directory)) for p in directory.rglob('*.deb')}!=set(paths):
        raise ValueError('Require exactly the four Curl and four HTTP3 dependency packages')
    result={'debian_packages':[], 'files':{}}
    for relative,name in sorted(paths.items()):
        path=directory/relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(directory.resolve()):
            raise ValueError('Require a regular contained Debian package')
        expected={'Package':name,'Version':EXPECTED[name],'Architecture':'arm64'}
        if control(path,'control.tar')!=expected: raise ValueError('Unexpected Curl package identity')
        result['debian_packages'].append({'name':name,'version':EXPECTED[name],'architecture':'arm64','artifact':relative})
        result['files'][relative]={'bytes':path.stat().st_size,'sha256':digest(path)}
    return result

def elf_inventory(directory, frozen):
    result={}
    for item in frozen['debian_packages']:
        path=directory/item['artifact']; entry=frozen['files'][item['artifact']]
        if path.is_symlink() or path.stat().st_size!=entry['bytes'] or digest(path)!=entry['sha256']:
            raise ValueError('Frozen package changed before ELF inventory')
        with archive(path,'data.tar') as stream:
            for member in stream:
                if not member.isfile(): continue
                name=member.name.removeprefix('./')
                if Path(name).is_absolute() or '..' in Path(name).parts: raise ValueError('Unsafe package path')
                data=stream.extractfile(member)
                prefix=data.read(4)
                if prefix!=b'\x7fELF': continue
                if member.size>64*1024**2: raise ValueError('Unexpected ELF size')
                hashed=hashlib.sha256(prefix)
                while block:=data.read(65536): hashed.update(block)
                if name in result: raise ValueError('Duplicate packaged ELF')
                result[name]=hashed.hexdigest()
    if len(result)!=7: raise ValueError('Require the CLI, two libcurl and four HTTP3 ELF providers')
    return result

def verify_installed(expected, root=Path('/')):
    result={}
    for name,sha in expected.items():
        if Path(name).is_absolute() or '..' in Path(name).parts: raise ValueError('Unsafe installed ELF path')
        path=root/name
        if path.is_symlink() or not path.is_file() or digest(path)!=sha:
            raise ValueError('Installed ELF differs from frozen package: '+name)
        result[name]=sha
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','verify']);parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    frozen=manifest(args.inputs)
    if args.action=='prepare':
        with args.output.open('x') as stream: stream.write(json.dumps(frozen,indent=2)+'\n')
    else:
        actual=verify_installed(elf_inventory(args.inputs,frozen))
        with args.output.open('x') as stream: stream.write(json.dumps({'status':'passed','installed_ELF_sha256':actual},indent=2)+'\n')
