#!/bin/sh
# Runs ONLY in the disposable builder created by build-libxml2.py.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEB_BUILD_PROFILES=nopython
export DEB_BUILD_OPTIONS=parallel=1
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
apt-get update
apt-get install --no-install-recommends -y build-essential debhelper pkg-config liblzma-dev zlib1g-dev rename
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
cd /security-work
dpkg-source --no-check -x /security-input/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3.dsc source
mkdir /security-work/upstream-test-corpus
tar -xJf /security-input/libxml2-2.9.14-upstream-tests.tar.xz \
    -C /security-work/upstream-test-corpus --strip-components=1 \
    libxml2-2.9.14/test libxml2-2.9.14/result
# Restore omitted private test fixtures without replacing Debian's added tests.
# This validation corpus is never installed in the binary package.
cp -an /security-work/upstream-test-corpus/test/. source/test/
cp -an /security-work/upstream-test-corpus/result/. source/result/
test -f source/test/threads/abc.xml
cd source
# The source archive hashes are verified by the launcher before docker cp.
# Debian's source extraction applies its full existing security patch series.
autoreconf --force --install
mkdir /security-work/poc
tar -xzf /security-input/poc.tar.gz -C /security-work/poc --strip-components=1
build_instrumented() {
    variant="$1"
    mkdir "/security-work/asan-$variant"
    cd "/security-work/asan-$variant"
    /security-work/source/configure --without-python --disable-static --with-history \
        CFLAGS='-g -O1 -fsanitize=address -fno-omit-frame-pointer' \
        LDFLAGS='-fsanitize=address'
    make -j1 libxml2.la
    g++ -g -O1 -fsanitize=address -fno-omit-frame-pointer -std=c++11 \
        -I include -I /security-work/source/include \
        /security-work/poc/libxml2_xml_read_memory_fuzzer.cc \
        /security-work/poc/main_harness.cc -L .libs \
        "-Wl,-rpath,/security-work/asan-$variant/.libs" -lxml2 \
        -o "/security-work/poc/$variant"
    gcc -g -O1 -fsanitize=address -fno-omit-frame-pointer \
        -I include -I /security-work/source/include \
        /security-input/test-libxml2-xinclude.c -L .libs \
        "-Wl,-rpath,/security-work/asan-$variant/.libs" -lxml2 \
        -o "/security-work/poc/xinclude-$variant"
    cd /security-work/source
}
build_instrumented baseline
set +e
ASAN_OPTIONS=detect_leaks=0 timeout 30 /security-work/poc/baseline /security-work/poc/poc.xml > /security-output/cve-2026-6653-baseline.log 2>&1
baseline_status=$?
set -e
printf 'baseline_exit_code=%s\n' "$baseline_status" >> /security-output/cve-2026-6653-baseline.log
test "$baseline_status" -ne 0
grep -q 'AddressSanitizer: heap-use-after-free' /security-output/cve-2026-6653-baseline.log
grep -q 'xmlParseInternalSubset' /security-output/cve-2026-6653-baseline.log
set +e
ASAN_OPTIONS=detect_leaks=0 timeout 30 /security-work/poc/xinclude-baseline > /security-output/cve-2026-86144-baseline.log 2>&1
xinclude_status=$?
set -e
test "$xinclude_status" -eq 1
rm -rf /security-work/asan-baseline
cp /security-input/CVE-2026-6653.patch debian/patches/local-CVE-2026-6653.patch
patch --dry-run --fuzz=0 -p1 < debian/patches/local-CVE-2026-6653.patch
printf '\nlocal-CVE-2026-6653.patch\n' >> debian/patches/series
dpkg-source --before-build .
for advisory in 74860 86138 86140 86142 86143 86144; do
    patch_file="CVE-2026-$advisory.patch"
    cp "/security-input/$patch_file" "debian/patches/local-$patch_file"
    patch --dry-run --fuzz=0 -p1 < "debian/patches/local-$patch_file"
    printf 'local-%s\n' "$patch_file" >> debian/patches/series
    dpkg-source --before-build .
done
python3 - <<'PY'
from pathlib import Path
p = Path('debian/changelog')
p.write_text('''libxml2 (2.12.7+dfsg+really2.9.14-2.1+deb13u3+erp1) unstable; urgency=high

  * Local security rebuild: apply Canonical's maintained 2.9.14 backport
    for CVE-2026-6653 (GNOME commit 463bbeeca1805b5c4828f50d0fefc4eebaf620df).
  * Apply maintained fixes for CVE-2026-74860, CVE-2026-86138,
    CVE-2026-86140, CVE-2026-86142, CVE-2026-86143, CVE-2026-86144.
  * Preserve the complete Debian patch set and legal notices.

 -- ERP local security build <security@localhost>  Mon, 16 Nov 2026 00:00:00 +0000

''' + p.read_text())
PY
# -B builds architecture packages only; the nopython profile avoids unused
# system Python bindings. Run make check explicitly: this Debian packaging
# does not invoke it automatically for the architecture-only build.
dpkg-buildpackage -B -us -uc
# dpkg-source --after-build restores source files after packaging. Reapply the
# recorded quilt series before compiling independent regression binaries.
cp ../libxml2_*arm64.deb /security-output/
printf 'built-not-validated\n' > /security-output/status.txt
dpkg-source --before-build .
for advisory in 6653 74860 86138 86140 86142 86143 86144; do
    grep -Fxq "local-CVE-2026-$advisory.patch" .pc/applied-patches
done
make -C builddir/main -j1 check > /security-output/upstream-check.log 2>&1
printf '0\n' > /security-output/upstream-check.exit
readelf --dyn-syms --wide /usr/lib/aarch64-linux-gnu/libxml2.so.2 > /security-output/baseline-symbols.txt
readelf --dyn-syms --wide builddir/main/.libs/libxml2.so.2 > /security-output/patched-symbols.txt
python3 - <<'PY'
from pathlib import Path
def exports(name):
    result = set()
    for line in Path('/security-output/' + name).read_text().splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[4] in ('GLOBAL', 'WEAK') and fields[6] != 'UND':
            result.add(fields[7])
    return result
missing = exports('baseline-symbols.txt') - exports('patched-symbols.txt')
if missing:
    raise SystemExit('Removed public/versioned symbols: ' + repr(sorted(missing)))
Path('/security-output/symbol-compatibility.txt').write_text('PASS: all existing public/versioned symbols retained. This is not a complete public-struct ABI check; dependent runtime tests are also required.\n')
PY
build_instrumented patched
ASAN_OPTIONS=detect_leaks=0 timeout 30 /security-work/poc/patched /security-work/poc/poc.xml > /security-output/cve-2026-6653-poc.log 2>&1
ASAN_OPTIONS=detect_leaks=0 timeout 30 /security-work/poc/xinclude-patched > /security-output/cve-2026-86144-patched.log 2>&1
printf 'PASS: identical attack input completed with instrumented patched library and no sanitizer error\n' >> /security-output/cve-2026-6653-poc.log
rm -rf /security-work/asan-patched
cp ../libxml2_*arm64.deb /security-output/
cp debian/patches/local-CVE-2026-*.patch /security-output/
printf 'package-build-and-tests-passed\n' > /security-output/status.txt
