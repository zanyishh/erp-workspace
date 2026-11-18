#!/bin/sh
# GPL-3.0; invoked only by the isolated build-expat.py launcher.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
apt-get update
apt-get install --no-install-recommends -y build-essential pkg-config
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
cd /security-work
tar -xJf /security-input/expat-2.10.0.tar.xz
cd expat-2.10.0
./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu \
    --disable-static --disable-maintainer-mode --without-docbook \
    CFLAGS='-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2' \
    LDFLAGS='-Wl,-z,relro,-z,now'
make -j1
make -j1 check > /security-output/upstream-tests.log 2>&1
make DESTDIR=/security-work/installed install
candidate=/security-work/installed/usr/lib/aarch64-linux-gnu/libexpat.so.1
test -L "$candidate"
readelf -d "$candidate" > /security-output/elf-dynamic.txt
grep -q '\[libexpat.so.1\]' /security-output/elf-dynamic.txt
nm -D --defined-only /usr/lib/aarch64-linux-gnu/libexpat.so.1 | awk '{print $3}' | sort -u > /security-output/original-symbols.txt
nm -D --defined-only "$candidate" | awk '{print $3}' | sort -u > /security-output/candidate-symbols.txt
comm -23 /security-output/original-symbols.txt /security-output/candidate-symbols.txt > /security-output/missing-symbols.txt
test ! -s /security-output/missing-symbols.txt
# The Debian package honestly identifies the new upstream code and local build.
package=/security-work/package
mkdir -p "$package/DEBIAN" "$package/usr/lib/aarch64-linux-gnu" "$package/usr/share/doc/libexpat1"
cp -a /security-work/installed/usr/lib/aarch64-linux-gnu/libexpat.so.1* "$package/usr/lib/aarch64-linux-gnu/"
cp COPYING "$package/usr/share/doc/libexpat1/COPYING.upstream"
cp /usr/share/doc/libexpat1/copyright "$package/usr/share/doc/libexpat1/copyright.debian-original"
printf '%s\n' 'Local rebuild of official Expat 2.10.0 on the pinned ERP base. Original source and build instructions are retained with the build receipt. No upstream source modification.' > "$package/usr/share/doc/libexpat1/README.erp-security"
mkdir -p debian
cat > debian/control <<'EOF'
Source: expat
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>

Package: libexpat1
Architecture: any
Description: Expat XML parser library, local security rebuild
EOF
dependencies=$(dpkg-shlibdeps -O -e "$candidate" | sed -n 's/^shlibs:Depends=//p')
test -n "$dependencies"
cat > "$package/DEBIAN/control" <<EOF
Package: libexpat1
Version: 2.10.0-0+erp1
Architecture: arm64
Multi-Arch: same
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>
Depends: $dependencies
Description: Expat XML parser library, local security rebuild
 Official Expat 2.10.0 compiled and tested on the pinned ERP base.
EOF
printf '%s\n' 'activate-noawait ldconfig' > "$package/DEBIAN/triggers"
printf '%s\n' 'libexpat 1 libexpat1 (>= 2.10.0-0+erp1)' > "$package/DEBIAN/shlibs"
dpkg-deb --root-owner-group --build "$package" /security-output/libexpat1_2.10.0-0+erp1_arm64.deb
cp /security-input/expat-2.10.0.tar.xz /security-output/
cp /security-input/build-expat.sh /security-output/
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; dependent runtime validation remains required'
