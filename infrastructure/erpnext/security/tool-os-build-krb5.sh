#!/bin/sh
# GPL-3.0; run only in the data-free builder through tool-os-build-krb5.py.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
python3 /security-input/tool-os-package-krb5.py capture
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    build-essential pkg-config bison comerr-dev ss-dev libkeyutils-dev \
    libldap2-dev liblmdb-dev libssl-dev libverto-dev libnss-myhostname \
    keyutils libcmocka-dev python3 python3-kdcproxy python3-pyrad
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
# Use Debian's Python with the Debian test-support modules just installed.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
tar -xzf /security-input/tool-os-krb5-1.22.3.tar.gz
cd krb5-1.22.3
for patch in /security-input/tool-os-krb5-0*.patch; do
    patch -p1 --batch --fuzz=0 -i "$patch"
done
mkdir build
cd build
../src/configure --prefix=/usr --libdir=/usr/lib/aarch64-linux-gnu \
    --sysconfdir=/etc --localstatedir=/etc --with-system-et --with-system-ss \
    --disable-rpath --enable-shared --with-ldap --without-tcl \
    --with-system-verto --with-lmdb \
    CFLAGS='-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2' \
    LDFLAGS='-Wl,-z,relro,-z,now'
make -j1
# Keep original baseline copies untouched; only the disposable source/test paths
# belong to this exclusive, capability-free ordinary-test account.
if getent passwd 194812 || getent group 194812; then
    printf '%s\n' 'KEYRING SECURITY GUARD: reserved container UID/GID already exists' >&2
    exit 1
fi
groupadd --gid 194812 erp-krb5-tests
useradd --uid 194812 --gid 194812 --no-create-home --home-dir /security-work/krb5-test-home erp-krb5-tests
python3 /security-input/tool-os-krb5-test-environment.py prepare
touch /security-output/keyring-test-ready
python3 /security-input/tool-os-krb5-test-environment.py wait-start
setpriv --reuid 194812 --regid 194812 --clear-groups --bounding-set=-all \
    --inh-caps=-all --ambient-caps=-all --no-new-privs \
    env HOME=/security-work/krb5-test-home USER=erp-krb5-tests LOGNAME=erp-krb5-tests \
    python3 /security-input/tool-os-krb5-test-environment.py run-tests \
    > /security-output/upstream-tests.log 2>&1
touch /security-output/keyring-tests-finished
python3 /security-input/tool-os-krb5-test-environment.py wait-cleanup
make DESTDIR=/security-work/installed install
python3 /security-input/tool-os-package-krb5.py package
dpkg -i /security-output/libkrb5support0_*.deb /security-output/libk5crypto3_*.deb \
    /security-output/libkrb5-3_*.deb /security-output/libgssapi-krb5-2_*.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/tool-os-package-krb5.py smoke > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; application image validation remains required'
