#!/usr/bin/env python3
"""Overlay rebuilt utilities onto exact original Debian package payloads.

This runs only in the disposable builder. Original configuration, package
scripts, permissions and notices survive. Every shipped ELF must be replaced;
missing files or removed public symbols fail the build.
"""
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile

ROOT = Path('/security-work')
OUTPUT = Path('/security-output')
INSTALLED = ROOT / 'installed'
VERSION = '2.41.6-0+erp1'
PACKAGES = 'util-linux mount bsdutils libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2 login'.split()


def run(*args):
    return subprocess.check_output(args, text=True)


def elf(path):
    if not path.is_file() or path.is_symlink():
        return False
    with path.open('rb') as source:
        return source.read(4) == b'\x7fELF'


def rebuilt_elf(installed, relative):
    # Debian uses a merged /usr and explicitly changes these three upstream
    # program categories. Preserve Debian's destination; map only known inputs.
    overrides = {
        Path('usr/bin/rename.ul'): Path('usr/bin/rename'),
        Path('usr/bin/partx'): Path('usr/sbin/partx'),
        Path('usr/sbin/chmem'): Path('usr/bin/chmem'),
        Path('usr/sbin/isosize'): Path('usr/bin/isosize'),
    }
    source = overrides.get(relative, relative)
    candidates = [installed / source]
    if source.parts[:2] in (('usr', 'bin'), ('usr', 'sbin')):
        candidates.append(installed / Path(*source.parts[1:]))
    matches = [candidate for candidate in candidates if elf(candidate)]
    if len(matches) != 1:
        raise RuntimeError(f'Expected one rebuilt ELF for {relative}, found {len(matches)}')
    return matches[0]


def symbols(path):
    return {line.split()[-1] for line in run('nm', '-D', '--defined-only', str(path)).splitlines() if line.split()}


def fields(text):
    return re.split(r'\n(?=\S)', text.rstrip('\n'))


def resolve_elf_dependencies(dependencies):
    # Debian's shlibs.local intentionally emits an exact same-source variable.
    # Normally dpkg-gencontrol expands it; this overlay must do the equivalent
    # only for the five libraries actually rebuilt together here.
    same_source = {'libblkid1', 'liblastlog2-2', 'libmount1', 'libsmartcols1', 'libuuid1'}
    resolved = []
    for dependency in dependencies.split(', '):
        if '${binary:Version}' in dependency:
            match = re.fullmatch(r'([a-z0-9+.-]+) \(= \$\{binary:Version\}\)', dependency)
            if not match or match[1] not in same_source:
                raise RuntimeError('Unreviewed same-source dependency variable: ' + dependency)
            dependency = dependency.replace('${binary:Version}', VERSION)
        if '${' in dependency:
            raise RuntimeError('Unresolved dependency variable: ' + dependency)
        resolved.append(dependency.replace('2.41.5-0+deb13u1', VERSION))
    return ', '.join(resolved)


def payload_metadata(archive):
    payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(archive)])
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:') as files:
        return {str(Path(item.name)): {
            'uid': item.uid, 'gid': item.gid, 'mode': item.mode,
            'directory': item.isdir(),
            'symlink': item.linkname if item.issym() else None,
        } for item in files}


def verify_payload_metadata(original, rebuilt):
    for path, metadata in original.items():
        if rebuilt.get(path) != metadata:
            raise RuntimeError(f'Original ownership/mode/link changed: {path}')


def control_integrity(archive):
    payload = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(archive)])
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:') as files:
        result = {}
        for item in files:
            name = str(Path(item.name))
            if name in ('.', 'control', 'md5sums'): continue
            result[name] = {'uid': item.uid, 'gid': item.gid, 'mode': item.mode,
                            'type': item.type.decode(), 'link': item.linkname,
                            'sha256': hashlib.sha256(files.extractfile(item).read()).hexdigest() if item.isfile() else None}
        return result


def main():
    receipt = {'packages': {}, 'all_original_elf_replaced': False}
    for name in PACKAGES:
        archives = list((ROOT / 'original-packages').glob(name + '_*.deb'))
        if len(archives) != 1:
            raise RuntimeError(f'Expected one original archive for {name}')
        archive = archives[0]
        package = ROOT / 'packages' / name
        package.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['dpkg-deb', '--raw-extract', str(archive), str(package)], check=True)
        original_control = (package / 'DEBIAN/control').read_text()
        old_version = re.search(r'^Version: (.+)$', original_control, re.M)[1]
        version = ('1:' if name in ('bsdutils', 'login') else '') + VERSION
        if name == 'login':
            # Preserve Debian's epoch/really ordering relative to shadow login.
            version = '1:4.16.0-2+really' + VERSION
        replacements, libraries, source_paths = [], [], {}
        for original in sorted(package.rglob('*')):
            relative = original.relative_to(package)
            if relative.parts[0] == 'DEBIAN' or original.is_dir():
                continue
            candidate = INSTALLED / relative
            if elf(original):
                candidate = rebuilt_elf(INSTALLED, relative)
                source_paths[str(relative)] = str(candidate.relative_to(INSTALLED))
                before, after = symbols(original), symbols(candidate)
                old_dynamic = run('readelf', '-d', str(original))
                new_dynamic = run('readelf', '-d', str(candidate))
                old_needed = set(re.findall(r'\(NEEDED\).*?\[(.*?)\]', old_dynamic))
                new_needed = set(re.findall(r'\(NEEDED\).*?\[(.*?)\]', new_dynamic))
                if new_needed - old_needed:
                    raise RuntimeError(f'New library dependencies require review for {relative}: {sorted(new_needed - old_needed)}')
                if '.so.' in original.name:
                    missing = before - after
                    if missing:
                        raise RuntimeError(f'Public symbols removed from {relative}: {sorted(missing)}')
                    old_soname = re.findall(r'\(SONAME\).*?\[(.*?)\]', old_dynamic)
                    new_soname = re.findall(r'\(SONAME\).*?\[(.*?)\]', new_dynamic)
                    if not old_soname or old_soname != new_soname:
                        raise RuntimeError(f'SONAME changed for {relative}')
                    libraries.append({'path': str(relative), 'soname': new_soname[0], 'preserved_symbols': len(before)})
                mode = stat.S_IMODE(original.stat().st_mode)
                shutil.copyfile(candidate, original)
                subprocess.run(['strip', '--strip-unneeded', str(original)], check=True)
                original.chmod(mode)
                replacements.append(str(relative))
            elif candidate.is_file() and not candidate.is_symlink() and not original.is_symlink():
                # Keep distro configuration/notices; update generated manuals and completions.
                if str(relative).startswith(('usr/share/man/', 'usr/share/bash-completion/')):
                    shutil.copyfile(candidate, original)
        if not replacements:
            raise RuntimeError(f'No rebuilt executable/library in {name}')
        # Recompute minimum imported-symbol requirements using Debian's
        # shlibs/symbols metadata and the rebuilt libraries, not just SONAMEs.
        requirements = subprocess.check_output(
            ['dpkg-shlibdeps', '-O', '-l' + str(INSTALLED / 'usr/lib/aarch64-linux-gnu')]
            + ['-e' + str(package / path) for path in replacements],
            cwd=ROOT / 'util-linux-2.41.6', text=True,
        )
        dependency_lines = [line.partition('=')[2] for line in requirements.splitlines()
                            if line.startswith('shlibs:Depends=')]
        if len(dependency_lines) != 1 or not dependency_lines[0]:
            raise RuntimeError(f'Could not establish ELF dependencies for {name}')
        computed_dependencies = resolve_elf_dependencies(dependency_lines[0])
        control = []
        has_depends = False
        for field in fields(original_control):
            key = field.split(':', 1)[0]
            if key in ('Installed-Size', 'Version', 'Source'):
                continue
            if key in ('Depends', 'Pre-Depends', 'Provides', 'Breaks', 'Replaces'):
                # Same-source exact dependencies move together; all other constraints remain.
                field = field.replace('2.41.5-0+deb13u1', VERSION)
            if key == 'Depends':
                has_depends = True
                field += ', ' + computed_dependencies
            control.append(field)
        if not has_depends:
            control.append('Depends: ' + computed_dependencies)
        control += ['Source: util-linux (' + VERSION + ')', 'Version: ' + version]
        (package / 'DEBIAN/control').write_text('\n'.join(control) + '\n')
        doc = package / 'usr/share/doc' / name
        # Some original doc directories are symlinks into util-linux's common docs.
        if not doc.is_symlink():
            doc.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / 'util-linux-2.41.6/COPYING', doc / 'COPYING.upstream')
            (doc / 'README.erp-security').write_text(
                'Local util-linux 2.41.6 rebuild. Original Debian package configuration, '
                'maintainer scripts and notices retained. All original ELF files rebuilt. '
                'Source archives, Debian patches, build recipe and test results retained '
                'with the external build receipt.\n')
        checksums = []
        for path in sorted(package.rglob('*')):
            relative = path.relative_to(package)
            if relative.parts[0] != 'DEBIAN' and path.is_file() and not path.is_symlink():
                checksums.append(hashlib.md5(path.read_bytes()).hexdigest() + '  ' + str(relative))
        (package / 'DEBIAN/md5sums').write_text('\n'.join(checksums) + '\n')
        # Use conventional epoch-free archive names; the control Version and
        # receipt retain the complete Debian package version, including epochs.
        target = OUTPUT / f'{name}_{version.split(":", 1)[-1]}_arm64.deb'
        # The exact Debian archive includes non-root groups (notably setgid-tty
        # wall). Preserve raw-extract's ownership; never force root/root here.
        subprocess.run(['dpkg-deb', '--build', str(package), str(target)], check=True)
        original_metadata = payload_metadata(archive)
        verify_payload_metadata(original_metadata, payload_metadata(target))
        original_control_files = control_integrity(archive)
        if control_integrity(target) != original_control_files:
            raise RuntimeError(f'Original maintainer scripts/configuration records changed: {name}')
        receipt['packages'][name] = {
            'original_version': old_version, 'version': version,
            'original_archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'package': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'replaced_elf': replacements, 'library_compatibility': libraries,
            'rebuilt_source_paths': source_paths,
            'recomputed_elf_dependencies': computed_dependencies,
            'original_path_metadata_preserved': len(original_metadata),
            'original_control_files_preserved': sorted(original_control_files),
        }
    receipt['all_original_elf_replaced'] = True
    (OUTPUT / 'package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
