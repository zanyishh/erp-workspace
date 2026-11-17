#!/bin/sh
# GPL-3.0; run only through tool-os-build-curl.py in a data-free builder.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEB_BUILD_OPTIONS=parallel=1
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
trap 'rc=$?; if [ "$rc" -ne 0 ]; then python3 /security-input/tool-os-check-curl.py failurecapture --failed-exit "$rc" 2>/security-output/failure-capture-error.log || :; fi; exit "$rc"' EXIT
test "$(dpkg --print-architecture)" = arm64
python3 /security-input/tool-os-check-curl.py capture
# Package installation must not start system services in this disposable builder.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
cat > /etc/apt/sources.list.d/erp-curl-build-backports.sources <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
apt-get update
apt-get install --no-install-recommends -y build-essential debhelper autoconf \
    automake ca-certificates gnutls-bin groff-base libbrotli-dev libgnutls28-dev \
    libidn2-dev libkrb5-dev libldap2-dev libnghttp2-dev libpsl-dev librtmp-dev \
    libssh2-1-dev libssl-dev libtool libzstd-dev locales-all openssh-server \
    python3-impacket python3 stunnel4 zlib1g-dev \
    libnghttp3-9=1.15.0-1~bpo13+1 \
    libngtcp2-16=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-gnutls8=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-ossl0=1.22.1-1~bpo13+1 \
    libnghttp3-dev=1.15.0-1~bpo13+1 \
    libngtcp2-dev=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-gnutls-dev=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-ossl-dev=1.22.1-1~bpo13+1
# Keep the upstream test runners on Debian's Python and its test dependencies.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /security-output/dependencies /security-output/apt-provenance
cd /security-output/dependencies
apt-get download libnghttp3-9=1.15.0-1~bpo13+1 \
    libngtcp2-16=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-gnutls8=1.22.1-1~bpo13+1 \
    libngtcp2-crypto-ossl0=1.22.1-1~bpo13+1
cp /usr/share/keyrings/debian-archive-keyring.gpg /security-output/apt-provenance/
find /var/lib/apt/lists -maxdepth 1 -type f -name '*trixie-backports*' \
    -exec cp '{}' /security-output/apt-provenance/ ';'
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
tar -xJf /security-input/tool-os-curl-8.23.0.tar.xz
cd curl-8.23.0
tar -xJf /security-input/tool-os-curl_8.23.0-2.debian.tar.xz
python3 /security-input/tool-os-check-curl.py prepare
dpkg-buildpackage -B -us -uc -j1
# Run the complete ordinary upstream suite for both backends, including cases
# outside Debian's normal test-nonflaky target. No individual tests are disabled.
make -C debian/build-openssl -j1 test TFLAGS='-n -j1' > /security-output/upstream-openssl-tests.log 2>&1
make -C debian/build-gnutls -j1 test TFLAGS='-n -j1' > /security-output/upstream-gnutls-tests.log 2>&1
python3 /security-input/tool-os-check-curl.py packages
python3 /security-input/tool-os-curl-install.py prepare --inputs /security-output --output /security-output/runtime-image-inputs.json
# The controller disconnects this proven owned builder's sole default bridge.
# Bound the wait; the unchanged installer independently requires only loopback.
touch /security-output/offline-install-ready
remaining=180
while [ ! -f /security-input/offline-install-approved ]; do
    test "$remaining" -gt 0
    remaining=$((remaining - 1))
    sleep 1
done
ERP_SECURITY_IMAGE_BUILD=1 python3 /security-input/install-runtime-debs.py --inputs /security-output --output /security-output/offline-install
python3 /security-input/tool-os-curl-install.py verify --inputs /security-output --output /security-output/installed-ELF.json
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/tool-os-check-curl.py smoke > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_BOTH_UPSTREAM_SUITES_PASSED; application validation remains required'
