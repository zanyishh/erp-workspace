#!/bin/sh
set -eu
mkdir -p /security-output /security-work
exec > /security-output/build.log 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential pkg-config file
dpkg-query -W > /security-output/build-package-versions.txt
apt-get clean
rm -rf /var/lib/apt/lists/*
touch /security-output/dependencies-ready
# The launcher disconnects the owned builder before permitting source execution.
while [ ! -f /security-input/offline-ready ]; do sleep 1; done
chown "$(id -u frappe):$(id -g frappe)" /security-output /security-work
exec runuser -u frappe -- /home/frappe/frappe-bench/env/bin/python /security-input/build-lxml-inside.py
