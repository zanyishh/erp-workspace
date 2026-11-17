#!/bin/sh
# GPL-3.0; invoke with the data-free build-os-package.py launcher.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEB_BUILD_OPTIONS=parallel=1
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
python3 /security-input/tool-os-check-libsndfile.py capture
apt-get update
apt-get install --no-install-recommends -y build-essential autogen debhelper \
    libasound2-dev libflac-dev libmp3lame-dev libmpg123-dev libogg-dev \
    libopus-dev libspeex-dev libsqlite3-dev libvorbis-dev pkgconf python3
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
tar -xzf /security-input/libsndfile_1.2.2.orig.tar.gz
cd libsndfile-1.2.2
tar -xJf /security-input/libsndfile_1.2.2-2+deb13u1.debian.tar.xz
python3 /security-input/tool-os-check-libsndfile.py prepare
# Original Debian rules invoke the complete ordinary upstream make check suite.
dpkg-buildpackage -B -us -uc -j1
printf '%s\n' 'DEBIAN_BUILD_AND_ORDINARY_MAKE_CHECK_EXIT=0'
python3 /security-input/tool-os-check-libsndfile.py package
dpkg -i /security-output/libsndfile1_*.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/tool-os-check-libsndfile.py smoke > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; application validation remains required'
