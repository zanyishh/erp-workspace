#!/bin/sh
# GPL-3.0; use build-os-package.py, never an application container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
export DEB_BUILD_OPTIONS='parallel=1'
export DEB_CFLAGS_MAINT_STRIP='-g'
export DEB_CXXFLAGS_MAINT_STRIP='-g'
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
dpkg-query -L git-man > /security-output/original-git-man-paths.txt
mkdir -p /security-work/original-libraries
for soname in libX11.so.6 libX11-xcb.so.1 libXi.so.6 libXrender.so.1 libXtst.so.6; do
    cp -L "/usr/lib/aarch64-linux-gnu/$soname" "/security-work/original-libraries/$soname"
done
apt-get update
apt-get install --no-install-recommends -y build-essential debhelper pkgconf \
    xtrans-dev x11proto-dev libxcb1-dev quilt xutils-dev xmlto xorg-sgml-doctools \
    w3m libx11-dev libxext-dev libxfixes-dev asciidoc lynx xsltproc libxi-dev
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-package-versions.txt
for soname in libX11.so.6 libX11-xcb.so.1 libXi.so.6 libXrender.so.1 libXtst.so.6; do
    nm -D --defined-only "/security-work/original-libraries/$soname" | awk '{print $3}' | sort -u > "/security-output/$soname.original-symbols.txt"
done
cd /security-work
for source in libx11_1.8.14-1 libxi_1.8.4-1 libxrender_0.9.13-1 libxtst_1.2.6-1; do
    package=${source%%_*}
    dpkg-source --no-check -x "/security-input/$source.dsc" "$package"
    cd "$package"
    # Only package metadata changes. The maintained source and rules remain intact.
    python3 - <<'PY'
from pathlib import Path
import email.utils
import re
p=Path('debian/changelog');original=p.read_text()
match=re.match(r'([\w.+-]+) \(([^)]+)\)',original);assert match
name,version=match.groups()
header=f'{name} ({version}+erp1) unstable; urgency=medium\n\n  * Local rebuild on the pinned ERP Debian 13 image; no upstream code changes.\n\n -- ERP local security build <security@localhost>  {email.utils.formatdate()}\n\n'
p.write_text(header+original)
PY
    if [ "$package" = libx11 ]; then
        # Stable xtrans retains five transport tables exported by the pinned
        # baseline. Describe only those exports; keep the strict -c4 gate.
        python3 /security-input/os-x11-symbol-metadata.py \
            --baseline /security-output/libX11.so.6.original-symbols.txt \
            --symbols debian/libx11-6.symbols \
            > /security-output/libx11-symbol-metadata.json
    fi
    dpkg-buildpackage -b -us -uc -j1 \
        --hook-binary='python3 /security-input/os-x11-retain-build.py' \
        > "/security-output/$package.build-tests.log" 2>&1
    cd /security-work
    # Keep complete package bytes before install/ABI checks. These nested outputs
    # remain pending evidence and are never accepted solely because they exist.
    python3 - "$package" <<'PY'
from pathlib import Path
import hashlib,json,shutil,sys
output=Path('/security-output')/('pending-'+sys.argv[1]+'-packages')
files=sorted(Path('.').glob('*.deb'))
assert files and all(p.is_file() and not p.is_symlink() for p in files)
assert shutil.disk_usage('/security-output').free>400*1024**2+sum(p.stat().st_size for p in files)
output.mkdir()
receipt={'status':'debian-packaging-completed-install-and-abi-pending','files':{}}
for path in files:
    target=output/path.name;shutil.copyfile(path,target)
    receipt['files'][path.name]={'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
    case "$package" in
        libx11) runtime='libx11-6 libx11-data libx11-xcb1'; libraries='libX11.so.6 libX11-xcb.so.1' ;;
        libxi) runtime='libxi6'; libraries='libXi.so.6' ;;
        libxrender) runtime='libxrender1'; libraries='libXrender.so.1' ;;
        libxtst) runtime='libxtst6'; libraries='libXtst.so.6' ;;
    esac
    # Install the matching development packages too, only in this disposable builder,
    # so subsequent libraries compile against the exact replacement interface.
    dpkg -i ./*.deb
    for soname in $libraries; do
        candidate="/usr/lib/aarch64-linux-gnu/$soname"
        readelf -d "$candidate" > "/security-output/$soname.elf-dynamic.txt"
        grep -Fq "[$soname]" "/security-output/$soname.elf-dynamic.txt"
        nm -D --defined-only "$candidate" | awk '{print $3}' | sort -u > "/security-output/$soname.candidate-symbols.txt"
        comm -23 "/security-output/$soname.original-symbols.txt" "/security-output/$soname.candidate-symbols.txt" > "/security-output/$soname.missing-symbols.txt"
        python3 /security-input/os-x11-abi-check.py --soname "$soname" \
            --baseline "/security-output/$soname.original-symbols.txt" \
            --candidate "/security-output/$soname.candidate-symbols.txt" \
            --original-library "/security-work/original-libraries/$soname" \
            --contract /security-input/os-x11-abi-contract.json \
            > "/security-output/$soname.abi.json"
    done
    for binary in $runtime; do cp "${binary}_"*.deb /security-output/; done
    cp ./*.buildinfo ./*.changes /security-output/
    # These are only this invocation's compiler outputs, never application data.
    rm -rf "$package"
    rm -f ./*.deb ./*.udeb ./*.ddeb ./*.buildinfo ./*.changes
done
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/os-runtime-compatibility.py x11 \
    --x11-abi-contract /security-input/os-x11-abi-contract.json \
    > /security-output/compatibility.json
# Complete the matching Git manuals using documentation tools already needed by
# this batch. The upstream Git archive omits contrib/subtree and Perl manuals.
tar -xJf /security-input/git-2.50.2.tar.xz
cd git-2.50.2
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
make -C contrib/subtree man > /security-output/git-manual-build.log 2>&1
manual=/security-work/git-man-package
dpkg-deb -R /security-input/git-man_2.50.2-0+erp1_all.deb "$manual"
mkdir -p "$manual/usr/share/man/man3"
gzip -n -9 -c contrib/subtree/git-subtree.1 > "$manual/usr/share/man/man1/git-subtree.1.gz"
pod2man --section=3pm --center='Git Manual' --release='Git 2.50.2' \
    perl/Git.pm /security-work/Git.3pm
gzip -n -9 -c /security-work/Git.3pm > "$manual/usr/share/man/man3/Git.3pm.gz"
cp -L /usr/share/doc/git-man/copyright "$manual/usr/share/doc/git-man/copyright.debian-original"
python3 - <<'PY'
from pathlib import Path
import json
root=Path('/security-work/git-man-package')
missing=[name for name in Path('/security-output/original-git-man-paths.txt').read_text().splitlines()
         if name.startswith('/usr/share/man/') and not (root/name.lstrip('/')).exists()]
Path('/security-output/git-man-layout.json').write_text(json.dumps({'missing_baseline_manual_paths':missing},indent=2)+'\n')
assert not missing,missing
PY
dpkg-deb --threads-max=1 --root-owner-group --build "$manual" /security-output/git-man_2.50.2-0+erp1_all.deb
printf '%s\n' 'SOURCE_BUILDS_UPSTREAM_CHECKS_AND_ABI_CHECKS_PASSED; dependent Chrome/ERP runtime validation remains required'
