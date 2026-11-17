#!/bin/sh
# Run only in the owned, disposable build-util-linux.py container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
mkdir -p /security-work /security-output /security-work/original-packages
exec > /security-output/build.log 2>&1
build_test_uid=$(id -u frappe)
build_test_gid=$(id -g frappe)
test "$build_test_uid" -gt 0
id frappe > /security-output/test-identity.txt
cd /security-work/original-packages
apt-get update
# Exact originals provide Debian's control scripts, configuration, legal notices
# and file ownership map. No application or customer volume is mounted.
for package in util-linux mount bsdutils libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2 login; do
    version=$(dpkg-query -W -f='${Version}' "$package")
    apt-get download "$package=$version"
done
apt-get install --no-install-recommends -y build-essential pkg-config bison flex \
    gettext autopoint autoconf automake libtool libaudit-dev libcap-ng-dev libcrypt-dev libcryptsetup-dev \
    libncurses-dev libpam0g-dev libreadline-dev libselinux1-dev libsqlite3-dev \
    libsystemd-dev libudev-dev zlib1g-dev asciidoctor bc socat
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
cd /security-work
tar -xJf /security-input/util-linux-2.41.6.tar.xz
cd util-linux-2.41.6
tar -xJf /security-input/util-linux-debian.tar.xz
# The two upstream patches in the Debian series are incorporated in 2.41.6.
# Retain all nine Debian integration patches, including login/PAM behavior.
while IFS= read -r patch; do
    case "$patch" in
        debian/*) patch -p1 --batch --fuzz=0 < "debian/patches/$patch" ;;
        upstream/*) printf 'Already in upstream 2.41.6: %s\n' "$patch" ;;
        *) printf 'Unexpected patch series entry: %s\n' "$patch"; exit 1 ;;
    esac
done < debian/patches/series
# Maintained stable/v2.41 follow-ups to the idmap security correction.
patch -p1 --batch --fuzz=0 < /security-input/util-linux-idmap-include.patch
patch -p1 --batch --fuzz=0 < /security-input/util-linux-idmap-config.patch
python3 - <<'PY'
from pathlib import Path
import hashlib,json
# Verify maintained branch contents, including the older subdir code path.
source = Path('libmount/src/hook_subdir.c').read_text()
assert 'mnt_context_target_fd_required(cxt)' in source
assert 'subdir mount refused for non-root user' in source
assert 'return -ENOTSUP;' in source
assert 'api->subdir' not in source and 'KERNEL_VERSION(6, 15' not in source
context = Path('libmount/src/context.c').read_text()
assert 'if (mnt_context_is_restricted(cxt))' in context
assert 'ul_startswith(src, "/dev/")' in context
loop = Path('lib/loopdev.c').read_text()
assert loop.count('ul_open_no_symlinks(lc->filename') >= 2
Path('/security-output/source-applicability.json').write_text(json.dumps({
    'CVE-2026-78409': '2.41.6 lacks 2.42 detached-tree restricted-user path; existing restriction retained',
    'debian_raw_tracker_disagreement_retained': True,
    'hook_subdir_sha256': hashlib.sha256(source.encode()).hexdigest(),
    'debian_patch_series': Path('debian/patches/series').read_text().splitlines(),
    'upstream_debian_patches_incorporated': True,
}, indent=2)+'\n')
PY
# Debian integration patches include Makefile.am changes.
AM_OPTS=--copy LT_OPTS=--copy ./autogen.sh
./configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu --sysconfdir=/etc \
    --localstatedir=/var --runstatedir=/run --enable-usrdir-path \
    --disable-makeinstall-chown --with-selinux --with-smack --enable-partx \
    --with-systemd --with-udev --with-audit --with-cryptsetup=dlopen \
    --enable-newgrp --enable-login --enable-nologin --without-python \
    --disable-mesg --disable-write --disable-kill --disable-chfn-chsh \
    --disable-cal --disable-last --disable-utmpdump --disable-hwclock-gplv3 \
    CFLAGS='-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2' \
    LDFLAGS='-Wl,-z,relro,-z,now'
cp config.log config.status /security-output/
make -j1
make -j1 check-programs
# Upstream warns root tests alter fstab and loop devices. Run ordinary checks
# as the existing unprivileged user; unavailable privileged cases remain skips.
chown -R "$build_test_uid:$build_test_gid" /security-work/util-linux-2.41.6
runuser -u frappe -- make -j1 check TS_OPTS='--parallel=1' > /security-output/upstream-tests.log 2>&1
make DESTDIR=/security-work/installed install
# Retain the tested install tree and exact Debian packaging inputs before the
# packaging phase, so a packaging-only failure cannot discard validated code.
tar -czf /security-output/validated-build-inputs.tar.gz -C /security-work \
    installed original-packages util-linux-2.41.6/debian util-linux-2.41.6/COPYING
python3 - <<'PY'
from pathlib import Path
import hashlib,json
out=Path('/security-output')
names=['validated-build-inputs.tar.gz','upstream-tests.log','source-applicability.json']
receipt={'status':'upstream-tests-and-install-completed-packaging-pending',
         'source_lock':json.loads(Path('/security-input/util-linux-artifacts.lock.json').read_text()),
         'files':{name:{'bytes':(out/name).stat().st_size,
                        'sha256':hashlib.sha256((out/name).read_bytes()).hexdigest()} for name in names}}
(out/'validated-build-inputs.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
python3 /security-input/package-util-linux.py
cp /security-input/util-linux-*.tar.xz /security-output/
cp /security-input/build-util-linux.sh /security-input/package-util-linux.py /security-output/
cp /security-input/util-linux-*.patch /security-input/util-linux-artifacts.lock.json /security-output/
cp Documentation/releases/v2.41.6-ReleaseNotes /security-output/
printf '%s\n' 'PACKAGES_BUILT_AND_ORDINARY_UPSTREAM_TESTS_PASSED; final image runtime tests remain required'
