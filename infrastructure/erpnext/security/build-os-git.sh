#!/bin/sh
# GPL-3.0; use build-os-package.py, never an application container.
set -eu
umask 022
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /security-work /security-output
exec > /security-output/build.log 2>&1
test "$(dpkg --print-architecture)" = arm64
dpkg-query -L git > /security-output/original-git-paths.txt
apt-get update
apt-get install --no-install-recommends -y build-essential pkg-config gettext \
    libcurl4-gnutls-dev libexpat1-dev libpcre2-dev zlib1g-dev libssl-dev asciidoc-base xmlto
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
dpkg-query -W > /security-output/build-package-versions.txt
cd /security-work
tar -xJf /security-input/git-2.50.2.tar.xz
cd git-2.50.2
cat > config.mak <<'EOF'
prefix = /usr
sysconfdir = /etc
gitexecdir = /usr/lib/git-core
perllibdir = /usr/share/perl5
bash_completion_dir = /usr/share/bash-completion/completions
NO_TCLTK = YesPlease
USE_LIBPCRE2 = YesPlease
INSTALL_SYMLINKS = YesPlease
CFLAGS = -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2
LDFLAGS = -Wl,-z,relro,-z,now
GITWEB_PROJECTROOT = /var/lib/git
EOF
make -j1
# The normal upstream suite chooses its own available-feature prerequisites.
make -j1 test > /security-output/upstream-tests.log 2>&1
package=/security-work/git-package
make DESTDIR="$package" install
make -C contrib/subtree DESTDIR="$package" install
mkdir -p "$package/DEBIAN" "$package/etc/bash_completion.d" \
    "$package/usr/share/doc/git" "$package/var/lib/git" \
    "$package/usr/share/git-core/contrib/hooks" "$package/usr/share/git-core/templates/branches"
cp /etc/bash_completion.d/git-prompt "$package/etc/bash_completion.d/git-prompt"
cp contrib/completion/git-prompt.sh "$package/usr/lib/git-core/git-sh-prompt"
for hook in post-receive-email pre-auto-gc-battery setgitperms.perl update-paranoid; do
    cp -p "contrib/hooks/$hook" "$package/usr/share/git-core/contrib/hooks/$hook"
done
python3 - "$package" <<'PY'
from pathlib import Path
import json,sys
root=Path(sys.argv[1])
prefixes=('/usr/bin/', '/usr/lib/git-core/', '/usr/share/perl5/', '/usr/share/git-core/',
          '/usr/share/gitweb/', '/etc/bash_completion.d/', '/usr/share/bash-completion/')
missing=[]
for name in Path('/security-output/original-git-paths.txt').read_text().splitlines():
    candidate=root/name.lstrip('/')
    if name.startswith(prefixes) and not (candidate.exists() or candidate.is_symlink()):missing.append(name)
Path('/security-output/package-layout.json').write_text(json.dumps({'missing_baseline_paths':missing},indent=2)+'\n')
assert not missing,missing
PY
ln -s git "$package/usr/share/bash-completion/completions/gitk"
ln -s gitweb.cgi "$package/usr/share/gitweb/index.cgi"
# These are separate Debian packages, not part of the installed Git baseline.
rm -f "$package/usr/bin/git-cvsserver" "$package/usr/lib/git-core/git-cvsserver" \
    "$package/usr/lib/git-core/git-send-email" "$package/usr/lib/git-core/git-svn" \
    "$package/usr/share/perl5/Git/SVN.pm"
rm -rf "$package/usr/share/perl5/Git/SVN"
cp COPYING "$package/usr/share/doc/git/COPYING.upstream"
cp /usr/share/doc/git/copyright "$package/usr/share/doc/git/copyright.debian-original"
cp config.mak "$package/usr/share/doc/git/build-config.mak"
printf '%s\n' 'Official Git 2.50.2, unmodified upstream source, locally built on the pinned ERP Debian 13 base. Full corresponding source and build recipes must accompany redistribution. Debian package layout retained for the installed command-line features.' > "$package/usr/share/doc/git/README.erp-security"
mkdir -p debian
cat > debian/control <<'EOF'
Source: git
Section: vcs
Priority: optional
Maintainer: ERP local security build <security@localhost>

Package: git
Architecture: any
Description: Git, local upstream security rebuild
EOF
python3 - "$package" <<'PY' > /security-output/shlibdeps.txt
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1])
elf=[]
for p in root.rglob('*'):
    if not p.is_symlink() and p.is_file():
        with p.open('rb') as f:
            if f.read(4)==b'\x7fELF':
                subprocess.run(['strip','--strip-unneeded',str(p)],check=True)
                elf.extend(['-e',str(p)])
assert elf
subprocess.run(['dpkg-shlibdeps','-O',*elf],check=True)
PY
dependencies=$(sed -n 's/^shlibs:Depends=//p' /security-output/shlibdeps.txt)
test -n "$dependencies"
cat > "$package/DEBIAN/control" <<EOF
Package: git
Version: 1:2.50.2-0+erp1
Architecture: arm64
Multi-Arch: foreign
Source: git
Section: vcs
Priority: optional
Maintainer: ERP local security build <security@localhost>
Provides: git-completion, git-core
Depends: $dependencies, perl, liberror-perl, git-man (= 1:2.50.2-0+erp1)
Recommends: ca-certificates, patch, less, ssh-client
Description: Git, local upstream security rebuild
 Official Git 2.50.2 built and tested on the pinned ERP base.
EOF
printf '%s\n' '/etc/bash_completion.d/git-prompt' > "$package/DEBIAN/conffiles"
manual=/security-work/git-man-package
mkdir -p "$manual/DEBIAN" "$manual/usr/share/man/man3" "$manual/usr/share/doc/git-man"
tar -xJf /security-input/git-manpages-2.50.2.tar.xz -C "$manual/usr/share/man"
make -C contrib/subtree man > /security-output/manual-build.log 2>&1
cp contrib/subtree/git-subtree.1 "$manual/usr/share/man/man1/"
pod2man --section=3pm --center='Git Manual' --release='Git 2.50.2' \
    perl/Git.pm "$manual/usr/share/man/man3/Git.3pm"
find "$manual/usr/share/man" -type f -exec gzip -n -9 '{}' ';'
cp COPYING "$manual/usr/share/doc/git-man/COPYING.upstream"
cp -L /usr/share/doc/git-man/copyright "$manual/usr/share/doc/git-man/copyright.debian-original"
cat > "$manual/DEBIAN/control" <<'EOF'
Package: git-man
Version: 1:2.50.2-0+erp1
Architecture: all
Multi-Arch: foreign
Source: git
Section: doc
Priority: optional
Maintainer: ERP local security build <security@localhost>
Description: Official Git 2.50.2 manual pages
 Official matching release manuals, locally packaged with the security rebuild.
EOF
dpkg-deb --root-owner-group --build "$manual" /security-output/git-man_2.50.2-0+erp1_all.deb
dpkg-deb --root-owner-group --build "$package" /security-output/git_2.50.2-0+erp1_arm64.deb
dpkg -i /security-output/git-man_2.50.2-0+erp1_all.deb /security-output/git_2.50.2-0+erp1_arm64.deb
dpkg --audit > /security-output/dpkg-audit.txt
test ! -s /security-output/dpkg-audit.txt
python3 /security-input/os-runtime-compatibility.py git --https > /security-output/compatibility.json
printf '%s\n' 'BUILD_AND_UPSTREAM_TESTS_PASSED; application runtime validation remains required'
