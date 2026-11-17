#!/bin/sh
# GPL-3.0. Packaging-only completion of the first tested Git build; no compilation.
set -eu
umask 022
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
cd /security-work
dpkg-deb -R /tmp/git_2.50.2-0+erp1_arm64.deb package
# This is exactly upstream contrib/subtree's default install target (SHELL_PATH=/bin/sh).
python3 - <<'PY'
from pathlib import Path
import tarfile
with tarfile.open('/tmp/git-2.50.2.tar.xz') as source:
    data=source.extractfile('git-2.50.2/contrib/subtree/git-subtree.sh').read()
assert data.startswith(b'#!/bin/sh\n')
Path('package/usr/lib/git-core/git-subtree').write_bytes(data)
PY
chmod 755 package/usr/lib/git-core/git-subtree
mkdir -p package/usr/share/git-core/templates/branches
cp /tmp/build-os-git-finish.sh package/usr/share/doc/git/packaging-completion.sh
python3 - <<'PY'
from pathlib import Path
import json
prefixes=('/usr/bin/','/usr/lib/git-core/','/usr/share/perl5/','/usr/share/git-core/',
          '/usr/share/gitweb/','/etc/bash_completion.d/','/usr/share/bash-completion/')
missing=[]
for name in Path('/tmp/original-git-paths.txt').read_text().splitlines():
    p=Path('package')/name.lstrip('/')
    if name.startswith(prefixes) and not (p.exists() or p.is_symlink()):missing.append(name)
Path('/security-output/package-layout.json').write_text(json.dumps({'missing_baseline_paths':missing},indent=2)+'\n')
assert not missing,missing
PY
dpkg-deb --threads-max=1 --root-owner-group --build package /security-output/git_2.50.2-0+erp1_arm64.deb
cp /tmp/git-man_2.50.2-0+erp1_all.deb /security-output/
dpkg -i /security-output/git-man_2.50.2-0+erp1_all.deb /security-output/git_2.50.2-0+erp1_arm64.deb
python3 /tmp/os-runtime-compatibility.py git > /security-output/compatibility.json
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
