# OS source upgrades

These recipes build ordinary upstream releases on the pinned Debian 13 ERP
image. They never mount application data, contact a customer service, install
into the preserved ERP baseline, or import binary packages from Debian unstable.
The output is not a deployment and must pass the final isolated runtime check.

## Provenance and compatibility

- Git 2.50.2 is the oldest maintenance release named in the Git project's
  [10 November 2026 announcement](https://github.blog/open-source/git/git-security-vulnerabilities-announced-7/).
  It fixes CVE-2026-105437, CVE-2026-111760, and CVE-2026-114466. The source and
  matching manual archives match the HTTPS-published kernel.org SHA-256 list.
  Its OpenPGP signature has not been independently verified.
- SQLite 3.54.1's canonical source matches the SHA3-256 on the official
  [download page](https://sqlite.org/download.html). Debian's
  [security tracker](https://security-tracker.debian.org/tracker/source-package/sqlite3)
  identifies the fixes for CVE-2026-119373, CVE-2026-119374, and CVE-2026-119379 in
  3.54.0. Version 3.54.1 includes the fixes and subsequent corrections.
- Neither stable Debian candidate was fixed when inspected on 16 November 2026.
  Debian's newer SQLite packaging requires Tcl 9.1; the upstream recipe uses
  stable Debian's Tcl 8.6 and preserves the baseline runtime feature flags.
- The packages retain their real upstream versions, original source package
  names, and an explicit `+erp1` local revision. Dependencies are derived from
  the actual ELF files. A stable-distribution vulnerability feed with no fixed
  version may continue to report a finding: retain that evidence and the verified
  upstream fix separately; do not suppress findings or claim a clean scan.

Git retains GnuTLS-backed curl/HTTPS, PCRE2, Perl modules, translations, templates,
scalar, subtree, gitweb, shell completion, and the Debian command locations. Git GUI and
other separately packaged integrations are not introduced. SQLite retains its
legacy `libsqlite3.so.0` SONAME, FTS3/4/5, session/preupdate hooks, math, URI,
metadata, RTree, and Debian variable limits. The build compares exported SQLite
symbols with the installed library before packaging. All 336 baseline exports
identified in the official public core/session/RBU headers must remain. Seven
specific removed internal symbols are recorded with their internal-header
declarations and a pinned read-only audit finding no importers in 1,240 baseline
ELF files. Every other removed export fails the gate. See
`sqlite-abi-contract.json`; this exception does not suppress vulnerability findings.

## Running a build

Download each source URL in `os-artifacts.lock.json` to a dedicated source
directory. The launcher checks exact sizes and hashes before any Docker action.
Only run one build at a time on this 8 GB Mac. It requires 800 MiB host free and
1000 MiB VM free, limits the container to one CPU and 640 MiB memory, and stops at
a 400 MiB free-space floor or one hour. No image pull is implicit. Each output
directory must be new.

```sh
python3 infrastructure/erpnext/security/os-build-guards-test.py
python3 infrastructure/erpnext/security/build-os-package.py git \
  --input /path/to/verified-sources --output /path/to/new-git-evidence
python3 infrastructure/erpnext/security/build-os-package.py sqlite \
  --input /path/to/verified-sources --output /path/to/new-sqlite-evidence
```

The launcher uses only Docker context `colima-erp`; it removes only the container
that the invocation itself created, after exporting evidence. If evidence export
fails, it retains that stopped container and records its ID for recovery. If its
stopped state cannot be confirmed, it retains the container without attempting
an export or removal. Two empty, bounded temporary memory mounts override the
base image's sites/logs volume locations; the actual mounts are checked and
recorded before starting. No persistent volumes are attached or removed. The
builder reaches Debian package repositories; Git's final compatibility check
also reads the official Git repository over verified HTTPS.

## Evidence and limits

Git runs the ordinary upstream `make test` suite. SQLite runs the upstream
single-configuration `testrunner.tcl --jobs 1 veryquick` suite as a dedicated
unprivileged user with a disposable home. This documented binary-test runner
isolates each test script's process and working directory. Its newer `quicktest`
and release targets rebuild multiple configurations and are not used on this VM.
Feature prerequisites skipped by upstream must be reported from the logs.
No new attack payloads are generated. Additional synthetic compatibility checks
cover Git commits, clone, bundle, fsck, Perl, HTTPS linkage and remote access;
and Python SQLite WAL, transactions, rollback, FTS5, JSON, integrity and backup.

Each successful receipt records package checksums and still says application
runtime validation is pending. Install all Git and git-man packages together in
the candidate image; install the SQLite library package there; repeat the
compatibility checks in that final image before running isolated ERP tests.

Keep the complete source archives, lock, build recipes, package notices and test
evidence with the output. In particular, Git's GPL-covered binaries require
corresponding source when conveyed. A link to this recipe alone is not that
source. These new packages do not modify the official checkouts in `upstream/`.

## X11 library batch

The `x11` component rebuilds Debian's maintained source packages for libX11
1.8.14, libXi 1.8.4, libXrender 0.9.13, and libXtst 1.2.6, identified by the
[X.Org security announcement](https://lists.x.org/archives/xorg-announce/2026-October/003752.html).
The original library sources and Debian rules are retained. The changelog records
the explicit `+erp1` local rebuild. Five transport-table exports already present
in the pinned baseline receive exact additive local symbols metadata when built
with stable Debian's xtrans; strict `dpkg-gensymbols -c4` and the full original
export comparison remain enabled. The sole removal exception is seven exact
libXi linker boundary markers, classified as internal by the matching dpkg
version, absent from both public XInput headers, and imported by none of 1,240
audited baseline ELF files. All 88 original Debian API symbols remain required;
every other removed export fails. The pinned evidence and baseline hashes are
in `os-x11-abi-contract.json`. Static import inspection cannot exclude dynamic
symbol lookup or future consumers.
The exact `.dsc`, archive and packaging-file
hashes are locked. Upstream interfaces, locales, headers and manuals are built;
debug information is omitted to bound disk consumption. Only runtime `.deb`
files are delivered, while development packages are used inside the disposable
builder to build the remaining libraries against the same interfaces.

The build runs Debian's ordinary test hooks and compares all previously exported
symbols and SONAMEs. libX11 includes its normal compose-table test; the other
three release archives contain no automated `TESTS` targets. Dynamic loading,
thread initialization and locale checks supplement those upstream checks.
Dependent Chrome/PDF smoke tests remain required in the final candidate image.
The runtime check requires `--x11-abi-contract` and resolves all 88 approved
libXi API symbols. A bounded pre-binary dpkg hook saves the compiled tree, build
log and source-lock hash before packaging, and pending package families are
retained before install/ABI checks. These recovery artifacts do not establish
success: the full build receipt and all compatibility checks must still pass.
Use the same launcher with `x11` and its dedicated verified-source directory.
The batch also finishes the two matching Git manuals omitted from the upstream
manual archive, using these existing documentation tools. The source lock pins
the Git source and prior manual package; Git runtime binaries are unaffected.

## zlib

The `zlib` component builds official 1.4. The installed upstream 1.3.1 is within
the 1.2.8–1.3.2 range affected by the dictionary-buffer issue described in the
[official release notes](https://zlib.net/). Do not infer that every 1.4 advisory
applies to 1.3.1: some features were introduced later. Its original API/SONAME and
versioned exports are compared, upstream `make test` runs, and Python exercises
normal zlib, raw deflate, gzip and preset-dictionary round trips. The package
uses honest version `1:1.4-0+erp1`; no unsupported contrib code is installed.
