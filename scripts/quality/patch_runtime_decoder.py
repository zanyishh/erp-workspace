"""Add a pinned CommonJS adapter to the unchanged maintained URI decoder."""
from pathlib import Path
import argparse
import hashlib
import json
import tarfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-archive',type=Path,required=True)
parser.add_argument('--package-dir',type=Path,required=True)
args=parser.parse_args()
package=args.package_dir.resolve()
archive=args.source_archive.resolve()
archive_sha='68747a955bbb6a700d758155cf5ff15595c0dfa38504d385abdb249c688bfb15'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==archive_sha
with tarfile.open(archive) as tar:
    originals={}
    for member in tar.getmembers():
        if member.isdir():continue
        assert member.isfile() and member.name.startswith('package/')
        relative=Path(member.name).relative_to('package')
        assert not relative.is_absolute() and '..' not in relative.parts
        originals[relative]=tar.extractfile(member).read()
allowed=set(originals)|{Path('index.cjs'),Path('ERP_PATCH.json')}
assert {p.relative_to(package) for p in package.rglob('*') if p.is_file()}<=allowed
for relative,data in originals.items():
    destination=package/relative
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(data)
source=(package/'index.js').read_text()
expected='6a86ac891edf15c5efa0841ebb31935e3669d58b98318b57d7b08a4530317cb0'
assert hashlib.sha256(source.encode()).hexdigest()==expected
needle='export default function decodeUriComponent(encodedURI) {'
assert source.count(needle)==1
commonjs=source.replace(needle,'function decodeUriComponent(encodedURI) {')
commonjs+='\n// ERP compatibility: retain the legacy CommonJS plus-to-space convention.\n'
commonjs+="module.exports = encodedURI => decodeUriComponent(typeof encodedURI === 'string' ? encodedURI.replace(/\\+/g, ' ') : encodedURI);\n"
(package/'index.cjs').write_text(commonjs)
metadata=json.loads((package/'package.json').read_text())
assert metadata['version']=='0.5.1'
metadata['version']='0.5.1+erp.1'
metadata['main']='./index.cjs'
metadata['exports']={'types':'./index.d.ts','import':'./index.js','require':'./index.cjs','default':'./index.js'}
metadata['files'] += ['index.cjs','ERP_PATCH.json']
(package/'package.json').write_text(json.dumps(metadata,indent=2)+'\n')
provenance={'upstream_version':'0.5.1','local_version':'0.5.1+erp.1',
 'upstream_tar_sha256':archive_sha,
 'unchanged_esm_sha256':expected,
 'change':'Add CommonJS export of the maintained linear decoder; preserve legacy CJS plus-to-space input convention. ESM source and original license are unchanged.',
 'security_advisory':'https://github.com/SamVerschueren/decode-uri-component/security/advisories/GHSA-qr28-fpjm-wq7f',
 'maintenance':'Regenerate and review this adapter against the pinned upstream hash when updating.'}
(package/'ERP_PATCH.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(json.dumps(provenance,indent=2))
