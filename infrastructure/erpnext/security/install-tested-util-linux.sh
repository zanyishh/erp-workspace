#!/bin/sh
# Validate the already-built local packages with all dpkg dependencies enforced.
set -eu
umask 022
mkdir -p /security-output
exec > /security-output/build.log 2>&1
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
python3 - <<'PY'
from pathlib import Path
import hashlib,json,subprocess
root=Path('/security-input')
lock=json.loads((root/'util-linux-packages.lock.json').read_text())
for name,entry in lock['files'].items():
    path=root/name
    if (path.is_symlink() or not path.is_file() or path.stat().st_size!=entry['bytes']
        or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']):
        raise RuntimeError('Copied package/provenance differs before installation: '+name)
receipt=json.loads((root/'package-receipt.json').read_text())
for name,entry in receipt['packages'].items():
    actual=[subprocess.check_output(['dpkg-deb','-f',str(root/entry['package']),field],text=True).strip()
            for field in ('Package','Version','Architecture')]
    if actual!=[name,entry['version'],'arm64']: raise RuntimeError('Package control identity differs: '+name)
PY
cp /security-input/package-receipt.json /security-output/
cp /security-input/prior-package-install-failed.json /security-output/
cp /security-input/receipt.json /security-output/prior-build-failed-receipt.json
cp /security-input/*.deb /security-output/
cp /security-input/upstream-tests.log /security-input/source-applicability.json \
    /security-input/validated-build-inputs.json /security-output/
# Exact Pre-Depends require configured libraries before utility unpacking.
# This reviewed graph has four leaves, libmount depending on libblkid, then the
# utilities. No force option, network acquisition, or package removal is used.
dpkg -i /security-input/libblkid1_*.deb /security-input/libuuid1_*.deb \
    /security-input/libsmartcols1_*.deb /security-input/liblastlog2-2_*.deb
dpkg -i /security-input/libmount1_*.deb
dpkg -i /security-input/bsdutils_*.deb /security-input/login_*.deb \
    /security-input/mount_*.deb /security-input/util-linux_*.deb
runuser -u frappe -- python3 /security-input/util-linux-ordinary-compatibility.py > /security-output/compatibility.json
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
printf '%s\n' 'EXACT_TESTED_PACKAGES_INSTALLED_AND_ORDINARY_COMPATIBILITY_PASSED; final image checks pending'
