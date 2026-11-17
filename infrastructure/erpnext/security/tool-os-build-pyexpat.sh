#!/bin/sh
# Prepare only inside the named disposable source builder; no application mounts.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C PYTHONDONTWRITEBYTECODE=1
export ERP_SECURITY_IMAGE_BUILD=1 ERP_SECURITY_SOURCE_BUILD=1
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
python3 -B /security-input/tool-os-pyexpat.py baseline
apt-get update
apt-get install --no-install-recommends -y gcc libc6-dev binutils
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-packages.txt
dpkg -i /security-input/libexpat1_2.10.0-0+erp1_arm64.deb
ldconfig
python3 -B /security-input/tool-os-pyexpat.py build
python3 -B /security-input/tool-os-build-pyexpat-inside.py
