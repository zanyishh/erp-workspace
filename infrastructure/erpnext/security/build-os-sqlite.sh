#!/bin/sh
# GPL-3.0; use build-os-package.py, never an application container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
cp -L /usr/lib/aarch64-linux-gnu/libsqlite3.so.0 /security-work/original-libsqlite3.so.0
apt-get update
apt-get install --no-install-recommends -y build-essential pkg-config tcl8.6-dev
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
python3 -m zipfile -e /security-input/sqlite-src-3540100.zip .
cd sqlite-src-3540100
# Match the installed Debian options, including extensions used by consumers.
export CFLAGS='-O2 -fno-strict-aliasing -fstack-protector-strong -D_FORTIFY_SOURCE=2 -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS3_TOKENIZER -DSQLITE_ENABLE_RTREE -DSQLITE_SOUNDEX=1 -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ALLOW_ROWID_IN_VIEW -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT=1 -DSQLITE_ENABLE_LOAD_EXTENSION -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_THREADSAFE=1 -DSQLITE_USE_URI=1 -DSQLITE_MAX_SCHEMA_RETRY=25 -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_STMTVTAB -DSQLITE_MAX_VARIABLE_NUMBER=250000 -DSQLITE_MAX_FUNCTION_ARG=127'
export LDFLAGS='-Wl,-z,relro,-z,now'
chmod +x configure autosetup/autosetup-find-tclsh autosetup/autosetup-test-tclsh
./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu \
    --with-tcl=/usr/lib/aarch64-linux-gnu/tcl8.6 --enable-threadsafe \
    --soname=legacy --disable-rpath --enable-load-extension --enable-json \
    --enable-fts4 --enable-fts5 --enable-session --disable-amalgamation
make -j1 libsqlite3.so sqlite3
# Preserve fully compiled bytes if a later resource/test/package gate stops the
# build. This is deliberately not a Debian artifact or an accepted handoff.
cp libsqlite3.so /security-output/unvalidated-libsqlite3.so
sha256sum libsqlite3.so > /security-output/unvalidated-library.sha256
# The documented binary-test runner executes the complete veryquick selection
# in separate processes/directories. Legacy tcltest shares process/filesystem
# state between scripts; do not mask those failures by excluding test cases.
make -j1 testfixture > /security-output/testfixture-build.log 2>&1
ln -s /security-output/upstream-details.log testrunner.log
# Upstream exercises file permissions and explicitly rejects uid 0. This is a
# disposable account/home within the data-free builder, not the ERP site user.
useradd --system --home-dir /security-work/test-home --create-home sqlite-tests
chown -R sqlite-tests:sqlite-tests /security-work/sqlite-src-3540100
touch /security-output/upstream-details.log
chown sqlite-tests:sqlite-tests /security-output/upstream-details.log
test_status=0
runuser -u sqlite-tests -- env HOME=/security-work/test-home \
    ./testfixture test/testrunner.tcl --jobs 1 veryquick > /security-output/upstream-tests.log 2>&1 || test_status=$?
cp testrunner.db /security-output/testrunner.db
test "$test_status" -eq 0
readelf -d libsqlite3.so > /security-output/elf-dynamic.txt
grep -q '\[libsqlite3.so.0\]' /security-output/elf-dynamic.txt
nm -D --defined-only /security-work/original-libsqlite3.so.0 | awk '{print $3}' | sort -u > /security-output/original-symbols.txt
nm -D --defined-only libsqlite3.so | awk '{print $3}' | sort -u > /security-output/candidate-symbols.txt
comm -23 /security-output/original-symbols.txt /security-output/candidate-symbols.txt > /security-output/missing-symbols.txt
python3 /security-input/sqlite-abi-check.py \
    --original /security-output/original-symbols.txt \
    --candidate /security-output/candidate-symbols.txt \
    --contract /security-input/sqlite-abi-contract.json \
    --imports /security-input/sqlite-private-symbol-imports.json \
    --classification /security-input/sqlite-removed-symbol-classification.json \
    > /security-output/abi-compatibility.json
package=/security-work/sqlite-package
mkdir -p "$package/DEBIAN" "$package/usr/lib/aarch64-linux-gnu" "$package/usr/share/doc/libsqlite3-0"
cp -L libsqlite3.so "$package/usr/lib/aarch64-linux-gnu/libsqlite3.so.3.54.1"
strip --strip-unneeded "$package/usr/lib/aarch64-linux-gnu/libsqlite3.so.3.54.1"
ln -s libsqlite3.so.3.54.1 "$package/usr/lib/aarch64-linux-gnu/libsqlite3.so.0"
cp LICENSE.md "$package/usr/share/doc/libsqlite3-0/LICENSE.upstream.md"
cp /usr/share/doc/libsqlite3-0/copyright "$package/usr/share/doc/libsqlite3-0/copyright.debian-original"
printf '%s\n' 'Official SQLite 3.54.1 canonical sources, unmodified, compiled locally with Debian-compatible feature flags and legacy SONAME. Sources and build recipe retained with the build receipt.' > "$package/usr/share/doc/libsqlite3-0/README.erp-security"
mkdir -p debian
cat > debian/control <<'EOF'
Source: sqlite3
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>

Package: libsqlite3-0
Architecture: any
Description: SQLite library, local upstream security rebuild
EOF
dependencies=$(dpkg-shlibdeps -O -e "$package/usr/lib/aarch64-linux-gnu/libsqlite3.so.3.54.1" | sed -n 's/^shlibs:Depends=//p')
test -n "$dependencies"
cat > "$package/DEBIAN/control" <<EOF
Package: libsqlite3-0
Version: 3.54.1-0+erp1
Architecture: arm64
Multi-Arch: same
Source: sqlite3
Section: libs
Priority: optional
Maintainer: ERP local security build <security@localhost>
Depends: $dependencies
Breaks: crowdsec (<< 1.4), python-migrate (<< 0.11.0-4~), python3-migrate (<< 0.11.0-4~)
Description: SQLite library, local upstream security rebuild
 Official SQLite 3.54.1 built and tested on the pinned ERP base.
EOF
printf '%s\n' 'activate-noawait ldconfig' > "$package/DEBIAN/triggers"
printf '%s\n' 'libsqlite3 0 libsqlite3-0 (>= 3.54.1-0+erp1)' > "$package/DEBIAN/shlibs"
dpkg-deb --root-owner-group --build "$package" /security-output/libsqlite3-0_3.54.1-0+erp1_arm64.deb
dpkg -i /security-output/libsqlite3-0_3.54.1-0+erp1_arm64.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/os-runtime-compatibility.py sqlite \
    --sqlite-abi-contract /security-input/sqlite-abi-contract.json > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; application runtime validation remains required'
