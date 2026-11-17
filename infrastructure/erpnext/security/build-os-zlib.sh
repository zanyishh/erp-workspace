#!/bin/sh
# GPL-3.0; use build-os-package.py, never an application container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
# This package replaces system-owned /usr files only. Refuse to normalize an
# unexpected owner when building the Debian archive with --root-owner-group.
for path in /usr/lib/aarch64-linux-gnu/libz.so.1 \
    "$(readlink -f /usr/lib/aarch64-linux-gnu/libz.so.1)" \
    /usr/share/doc/zlib1g /usr/share/doc/zlib1g/copyright; do
    stat -c '%u:%g %a %n' "$path" >> /security-output/original-path-ownership.txt
    test "$(stat -c '%u:%g' "$path")" = 0:0
done
cp -L /usr/lib/aarch64-linux-gnu/libz.so.1 /security-work/original-libz.so.1
apt-get update
apt-get install --no-install-recommends -y build-essential
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
tar -xzf /security-input/zlib-1.4.tar.gz
cd zlib-1.4
CFLAGS='-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2' \
LDFLAGS='-Wl,-z,relro,-z,now' \
    ./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu
make -j1
make -j1 test > /security-output/upstream-tests.log 2>&1
readelf -d libz.so.1.4 > /security-output/elf-dynamic.txt
grep -q '\[libz.so.1\]' /security-output/elf-dynamic.txt
nm -D --defined-only /security-work/original-libz.so.1 | awk '{print $3}' | sort -u > /security-output/original-symbols.txt
nm -D --defined-only libz.so.1.4 | awk '{print $3}' | sort -u > /security-output/candidate-symbols.txt
comm -23 /security-output/original-symbols.txt /security-output/candidate-symbols.txt > /security-output/missing-symbols.txt
test ! -s /security-output/missing-symbols.txt
package=/security-work/zlib-package
mkdir -p "$package/DEBIAN" "$package/usr/lib/aarch64-linux-gnu" "$package/usr/share/doc/zlib1g"
cp libz.so.1.4 "$package/usr/lib/aarch64-linux-gnu/"
strip --strip-unneeded "$package/usr/lib/aarch64-linux-gnu/libz.so.1.4"
ln -s libz.so.1.4 "$package/usr/lib/aarch64-linux-gnu/libz.so.1"
cp README LICENSE ChangeLog "$package/usr/share/doc/zlib1g/"
cp /usr/share/doc/zlib1g/copyright "$package/usr/share/doc/zlib1g/copyright.debian-original"
printf '%s\n' 'Official zlib 1.4, unmodified upstream source, locally compiled and tested on the pinned ERP Debian 13 base. Original sources and build instructions retained with the build receipt.' > "$package/usr/share/doc/zlib1g/README.erp-security"
mkdir -p debian
cat > debian/control <<'EOF'
Source: zlib
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>

Package: zlib1g
Architecture: any
Description: zlib compression library, local upstream security rebuild
EOF
dependencies=$(dpkg-shlibdeps -O -e "$package/usr/lib/aarch64-linux-gnu/libz.so.1.4" | sed -n 's/^shlibs:Depends=//p')
test -n "$dependencies"
cat > "$package/DEBIAN/control" <<EOF
Package: zlib1g
Version: 1:1.4-0+erp1
Architecture: arm64
Multi-Arch: same
Source: zlib
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>
Depends: $dependencies
Description: zlib compression library, local upstream security rebuild
 Official zlib 1.4 built and tested on the pinned ERP base.
EOF
printf '%s\n' 'activate-noawait ldconfig' > "$package/DEBIAN/triggers"
printf '%s\n' 'libz 1 zlib1g (>= 1:1.4-0+erp1)' > "$package/DEBIAN/shlibs"
dpkg-deb --root-owner-group --build "$package" /security-output/zlib1g_1.4-0+erp1_arm64.deb
dpkg -i /security-output/zlib1g_1.4-0+erp1_arm64.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/os-runtime-compatibility.py zlib > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; dependent application runtime validation remains required'
