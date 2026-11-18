#!/bin/sh
# GPL-3.0; ordinary Debian rebuild in the owned build-os-package.py container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
# Retain actual pinned-base libraries and behavior before apt can update them.
mkdir -p /security-work/original-ncurses
for library in libncurses.so.6 libncursesw.so.6 libtinfo.so.6 libtic.so.6 libform.so.6 libformw.so.6 libmenu.so.6 libmenuw.so.6 libpanel.so.6 libpanelw.so.6; do
    cp -L "/usr/lib/aarch64-linux-gnu/$library" "/security-work/original-ncurses/$library"
done
python3 /security-input/ncurses-compatibility.py baseline-behavior
apt-get update
# Includes the declared dependency of the selected terminfo-check profile.
apt-get install --no-install-recommends -y build-essential debhelper-compat libgpm-dev pkgconf autoconf-dickey ncurses-term
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
python3 /security-input/ncurses-compatibility.py snapshot
cd /security-work
tar -xzf /security-input/ncurses_6.5+20250216.orig.tar.gz
cd ncurses-6.5-20250216
tar -xJf /security-input/ncurses_6.5+20250216-2.debian.tar.xz
python3 - <<'PY'
import hashlib,json
from pathlib import Path
from email.utils import formatdate
lock=json.loads(Path('/security-input/ncurses-artifacts.lock.json').read_text())['ncurses']
patch=Path('/security-input/ncurses-CVE-2025-69720.patch').read_bytes()
assert hashlib.sha256(patch).hexdigest()==lock['patch_sha256']
Path('debian/patches/erp-infocmp-bounds.patch').write_bytes(patch)
with Path('debian/patches/series').open('a') as f: f.write('\nerp-infocmp-bounds.patch\n')
changelog=Path('debian/changelog')
changelog.write_text('ncurses ('+lock['package_version']+') trixie; urgency=high\n\n'
 '  * Backport the maintained infocmp bounds fix for CVE-2025-69720.\n'
 '    Preserve the complete Debian packaging and all existing patches.\n\n'
 ' -- ERP local security build <security@localhost>  '+formatdate(localtime=False)+'\n\n'+changelog.read_text())
PY
dpkg-source --before-build .
export DEB_BUILD_OPTIONS='parallel=1 noautodbgsym'
export DEB_CFLAGS_MAINT_APPEND='-O2 -g0'
export DEB_CXXFLAGS_MAINT_APPEND='-O2 -g0'
# Run Debian's optional terminfo comparison as well as its normal
# narrow/wide/static/shared builds. The unmodified tidiff tool reports differences
# but always exits 0; retain its output as a diagnostic, not an equality assertion.
# Interactive terminal examples are compiled, not counted as executed tests.
export DEB_BUILD_PROFILES=pkg.ncurses.terminfocheck
# Keep dpkg's dependency check enabled, including version/profile constraints.
dpkg-buildpackage -b -us -uc > /security-output/debian-build.log 2>&1
cd /security-work
dpkg -i ./*.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
# The maintained autopkgtests need no privileged operations or application data.
# Match their declared harness contract: nonzero status or unexpected stderr fails.
useradd --system --no-create-home --home-dir /security-work/ncurses-tests-home ncurses-tests
mkdir -p /security-work/ncurses-tests-home
chown "$(id -u ncurses-tests):$(id -g ncurses-tests)" /security-work/ncurses-tests-home
python3 - <<'PY'
import hashlib, json, subprocess
from pathlib import Path
source=Path('/security-work/ncurses-6.5-20250216')
output=Path('/security-output')
receipt={'status':'running', 'restriction':'superficial', 'tests':[],
         'unexpected_stderr_is_failure':True,
         'terminfocheck':'diagnostic output retained in debian-build.log; exit 0 does not prove database equality'}
receipt_path=output/'ncurses-autopkgtests.json'
for name in ['manpage-references','backspace-delete-keys','infocmp-dumb']:
    script=source/'debian/tests'/name
    result=subprocess.run(['runuser','-u','ncurses-tests','--','env',
        'HOME=/security-work/ncurses-tests-home',str(script)],cwd=source,capture_output=True)
    (output/('autopkgtest-'+name+'.stdout')).write_bytes(result.stdout)
    (output/('autopkgtest-'+name+'.stderr')).write_bytes(result.stderr)
    passed=result.returncode == 0 and not result.stderr
    receipt['tests'].append({'name':name, 'script_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),
        'exit_code':result.returncode, 'stdout_sha256':hashlib.sha256(result.stdout).hexdigest(),
        'stderr_bytes':len(result.stderr), 'status':'passed' if passed else 'failed'})
    receipt['status']='running' if passed else 'failed'
    receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
    if not passed: raise SystemExit('Debian autopkgtest failed: '+name)
receipt['status']='debian-autopkgtests-passed'
receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
PY
python3 /security-input/ncurses-compatibility.py verify
for package in ncurses-base ncurses-bin libncurses6 libncursesw6 libtinfo6; do
    cp "${package}_"*.deb /security-output/
done
cp /security-input/ncurses_*.tar.* /security-output/
cp /security-input/ncurses-CVE-2025-69720.patch /security-output/
printf '%s\n' 'DEBIAN_BUILD_AUTOPKGTESTS_AND_NORMAL_COMPATIBILITY_PASSED; terminfo comparison is diagnostic; interactive examples not executed'
