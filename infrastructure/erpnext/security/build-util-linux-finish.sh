#!/bin/sh
# Package the exact tested install tree; no compilation or upstream test rewrite.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
mkdir -p /security-output
exec > /security-output/build.log 2>&1
apt-get update
apt-get install --no-install-recommends -y binutils dpkg-dev
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
python3 /security-input/recover-util-linux.py --input /security-input \
    --destination /security-work --output /security-output
python3 /security-input/package-util-linux.py
# Resolve exact Pre-Depends before unpacking dependent utilities. No download,
# implicit removal, or force-dependency override is permitted.
apt-get -y --no-download --no-remove --no-install-recommends install /security-output/*.deb
runuser -u frappe -- python3 /security-input/util-linux-ordinary-compatibility.py > /security-output/compatibility.json
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
printf '%s\n' 'TESTED_INSTALL_TREE_PACKAGED_AND_ORDINARY_COMPATIBILITY_PASSED; final image checks pending'
