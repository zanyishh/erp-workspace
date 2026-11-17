#!/bin/sh
set -eu
mkdir -p /security-output /security-work
exec > /security-output/build.log 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends make libtest-pod-perl libtext-diff-perl libio-compress-lzma-perl
dpkg-query -W > /security-output/build-package-versions.txt
apt-get clean
rm -rf /var/lib/apt/lists/*
python3 - <<'PY'
import hashlib,json,tarfile
from pathlib import Path,PurePosixPath
source=Path('/security-input/Archive-Tar-3.14.tar.gz')
lock=json.loads(Path('/security-input/archive-tar-artifacts.lock.json').read_text())['archive-tar']
assert hashlib.sha256(source.read_bytes()).hexdigest()==lock['sources'][source.name]['sha256']
with tarfile.open(source) as archive:
    members=archive.getmembers()
    assert len(members)<200 and sum(m.size for m in members)<2*1024**2
    for member in members:
        name=PurePosixPath(member.name)
        assert not name.is_absolute() and '..' not in name.parts and name.parts[0]=='Archive-Tar-3.14'
        assert member.isfile() or member.isdir()
    archive.extractall('/security-work',filter='data')
PY
chown -R "$(id -u frappe):$(id -g frappe)" /security-work /security-output
cd /security-work/Archive-Tar-3.14
runuser -u frappe -- perl Makefile.PL -d INSTALLDIRS=perl > /security-output/configure.log 2>&1
runuser -u frappe -- make > /security-output/make.log 2>&1
runuser -u frappe -- make test TEST_VERBOSE=1 > /security-output/upstream-tests.log 2>&1
python3 /security-input/package-archive-tar.py
ERP_SECURITY_IMAGE_BUILD=1 python3 /security-input/install-runtime-perl.py --payload /security-output/archive-tar-runtime.tar.gz --receipt /security-output/install-receipt.json
perl /security-input/archive-tar-ordinary-compatibility.pl > /security-output/ordinary-compatibility.json
python3 - <<'PY'
import hashlib,json,re
from pathlib import Path
root=Path('/security-output')
log=(root/'upstream-tests.log').read_text()
counts=re.findall(r'Files=(\d+), Tests=(\d+)',log)
assert counts and 'Result: PASS' in log
assert int(counts[-1][0])>0 and int(counts[-1][1])>0
files=['archive-tar-runtime.tar.gz','upstream-tests.log','ordinary-compatibility.json','install-receipt.json']
receipt={'status':'passed','version':'3.14','upstream_test_files':int(counts[-1][0]),'upstream_tests':int(counts[-1][1]),'upstream_tests_exit_code':0,'test_summary':log[-2500:],'files':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in files},'scope':'Archive::Tar modules and ptar tools only; Perl interpreter and its package versions unchanged.'}
(root/'archive-tar-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
