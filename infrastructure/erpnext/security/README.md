# Runtime security overlays

These are local derived-image changes. They never modify the official reference
checkouts, existing images, application containers, or database volumes. The
candidate is not approved for activation merely because its build succeeds.

`runtime-artifacts.lock.json` records exact base digests, source archives,
published integrity values and verified local artifact hashes. Staging receipts
explicitly distinguish built artifacts from runtime-validated images.

## Prepared changes

- Rebuild gosu 1.20 and the existing esbuild 0.14.54 from pinned upstream commits
  with official Go 1.27.4. This keeps esbuild's JavaScript/native API version
  aligned while replacing its affected embedded standard library.
- Preserve Frappe's Chrome PDF engine using the official ARM64 Chrome for Testing
  headless shell 157.0.8103.78. The familiar executable paths remain available.
- Replace the four MariaDB client packages with official 11.8.9 packages for
  Debian 13. This does not upgrade or restart the separate database server.
- Upgrade GitPython to 3.2.1 and pypdf to 6.21.4, update the derived Frappe
  distribution's dependency contract, and require `uv pip check`.
- Replace loader-utils 0.2.17 with 1.4.2 and shell-quote 1.8.1 with 1.12.0.
  loader-utils receives private, fixed dependencies. After a complete pinned-image
  consumer audit, a second Node resolver check permits removal of the old root
  JSON5 0.5.1 only when nothing still resolves it. License files remain bundled.

The Critical Node checks reproduce the old prototype-mutation and operator
injection cases, then verify the fixed behavior, 32 unchanged CSS class-name
outputs and eight exact shell-argument roundtrips. These are build-tool changes;
they do not establish that existing browser bundles have been updated.

## XML backport builder

`build-libxml2.py --input INPUT --output NEW_OUTPUT_DIRECTORY` creates an owned,
temporary container using the already present, pinned ERP image. It never pulls
an image or attaches an application volume. All subsequent operations and cleanup
use the newly created container ID.

The input consists of the exact installed Debian source release and its complete
patch set, Canonical's maintained CVE-2026-6653 backport, the source manifest and
the public reproducer archive. The launcher verifies their hashes before copying
them. It limits the builder to one CPU and 768 MiB RAM, requires 1100 MiB of free
VM storage at the start, and stops the builder at a 400 MiB host/VM storage floor.
Only the temporary container is removed; output evidence is copied out first.

The builder requires an ASAN-instrumented baseline library to reproduce the
reported use-after-free. It applies the backport with zero fuzz, explicitly runs
the upstream regression suite, verifies retention of public/versioned exported
symbols, then requires the identical attack input to pass against an instrumented
patched library. If the baseline does not reproduce, the build fails rather than
claiming CVE closure. The package has an honest `+erp1` local version suffix.

The patch extends public entity/parser structs. Exported-symbol preservation is
not a complete ABI guarantee. `validate-runtime.py` additionally exercises the
actual LLVM/Mesa dependents, HTML/SVG PDF rendering, XML and XLSX processing.
Application-level print/API tests on the isolated site remain required.

## Activation and evidence requirements

Build the ERP image from a staging context containing the verified browser,
Go binary, client packages, Node archive and these overlay scripts. Include the
successfully tested XML package only after its builder passes. Run the offline
`validate-runtime.py` with bench Python in a disposable candidate container with
no application volumes and no network. Then scan the actual candidate image.

Any fixes to JavaScript shipped to browsers require rebuilding the assets and
serving them from a dedicated native-test-only assets/sites volume. The existing
baseline/customer shared sites volume must not be overwritten. The secure native
backend must be separate from the backend currently shared with the customer
preview. Database-engine or gosu image changes likewise require a separate test
database container; never replace the shared database to validate this overlay.

Retain raw scanner reports. The Debian tracker has no published fixed version
for some packages, including this libxml2 issue. A successful local backport can
be supported with explicit patch/regression evidence; it does not justify an
invented package version, a blanket ignore, or a claim that the raw scan is clean.

Official security/source references:

- [Ubuntu CVE-2026-6653 status](https://ubuntu.com/security/CVE-2026-6653)
- [Published XML reproducer](https://bugs.launchpad.net/ubuntu/+source/libxml2/+bug/2141260)
- [shell-quote maintainer advisory](https://github.com/ljharb/shell-quote/security/advisories/GHSA-w7jw-789q-3m8p)
- [Go releases](https://go.dev/dl/)
- [Chrome for Testing metadata](https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json)
- [MariaDB 11.8.9 Debian archive](https://archive.mariadb.org/mariadb-11.8.9/repo/debian/)
