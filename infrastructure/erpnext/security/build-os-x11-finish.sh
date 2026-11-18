#!/bin/sh
# GPL-3.0; checksum-bound finish-only recovery through build-os-package.py.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
python3 - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('/security-input/checkpoint')
lock=json.loads(Path('/security-input/os-x11-recovery.lock.json').read_text())
for name,expected in lock['files'].items():
    path=root/name
    assert not path.is_symlink() and path.is_file() and path.resolve().is_relative_to(root)
    assert path.stat().st_size==expected['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==expected['sha256'],name
PY
apt-get update
apt-get install --no-install-recommends -y make binutils asciidoc xmlto w3m xsltproc python3 xz-utils
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
dpkg-query -W > /security-output/build-package-versions.txt
cp /security-input/checkpoint/*.deb /security-output/
dpkg -i /security-output/*.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
for soname in libX11.so.6 libX11-xcb.so.1 libXi.so.6 libXrender.so.1 libXtst.so.6; do
    cp "/security-input/checkpoint/$soname.original-symbols.txt" /security-output/
    candidate="/usr/lib/aarch64-linux-gnu/$soname"
    readelf -d "$candidate" > "/security-output/$soname.elf-dynamic.txt"
    grep -Fq "[$soname]" "/security-output/$soname.elf-dynamic.txt"
    nm -D --defined-only "$candidate" | awk '{print $3}' | sort -u > "/security-output/$soname.candidate-symbols.txt"
    python3 /security-input/os-x11-abi-check.py --soname "$soname" \
        --baseline "/security-output/$soname.original-symbols.txt" \
        --candidate "/security-output/$soname.candidate-symbols.txt" \
        --original-library "/security-input/checkpoint/original-libraries/$soname" \
        --contract /security-input/os-x11-abi-contract.json > "/security-output/$soname.abi.json"
done
python3 /security-input/os-runtime-compatibility.py x11 \
    --x11-abi-contract /security-input/os-x11-abi-contract.json > /security-output/compatibility.json
cd /security-work
tar -xJf /security-input/git-2.50.2.tar.xz
cd git-2.50.2
make -C contrib/subtree man > /security-output/git-manual-build.log 2>&1
manual=/security-work/git-man-package
dpkg-deb -R /security-input/git-man_2.50.2-0+erp1_all.deb "$manual"
mkdir -p "$manual/usr/share/man/man3"
gzip -n -9 -c contrib/subtree/git-subtree.1 > "$manual/usr/share/man/man1/git-subtree.1.gz"
pod2man --section=3pm --center='Git Manual' --release='Git 2.50.2' perl/Git.pm /security-work/Git.3pm
gzip -n -9 -c /security-work/Git.3pm > "$manual/usr/share/man/man3/Git.3pm.gz"
cp -L /usr/share/doc/git-man/copyright "$manual/usr/share/doc/git-man/copyright.debian-original"
python3 - <<'PY'
from pathlib import Path
import json
root=Path('/security-work/git-man-package')
missing=[name for name in Path('/security-input/checkpoint/original-git-man-paths.txt').read_text().splitlines()
         if name.startswith('/usr/share/man/') and not (root/name.lstrip('/')).exists()]
Path('/security-output/git-man-layout.json').write_text(json.dumps({'missing_baseline_manual_paths':missing},indent=2)+'\n')
assert not missing,missing
PY
dpkg-deb --threads-max=1 --root-owner-group --build "$manual" /security-output/git-man_2.50.2-0+erp1_all.deb
printf '%s\n' 'CHECKPOINT_INSTALL_ABI_88_EXPORTS_AND_COMPLETE_GIT_MANUAL_LAYOUT_PASSED; final candidate checks pending'
