# Project Flutter SDK

The project pins Flutter **3.47.9** with Dart **3.13.7**. The release metadata,
framework/engine revisions and official macOS ARM64 archive checksum are recorded
in `infrastructure/erpnext/quality/flutter-toolchain.json`.

This version includes the fixes for Dart's
[package-download advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-q739-79rh-vmvp)
and [certificate-trust advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp).
Android and Windows products must be rebuilt with a patched SDK. Installing the
SDK alone does not fix existing binaries. Windows compilation needs a Windows host.

`scripts/flutter_toolchain.py` selects the isolated SDK recorded in
`.local/quality/flutter-sdk.json`. Before execution it verifies the external
volume UUID from `.local/quality/location.json`, the exact pinned SDK metadata,
and containment of the bundled Dart executables. Missing or mismatched selections
fail; there is no fallback to the global Flutter installation.

The quality runner, Patrol preparation and both named app launchers use this
selector. The client rebuild fingerprint includes the selector and release pin.
The existing global Flutter SDK remains unchanged.

Check the selection from the repository root:

```sh
python3 scripts/flutter_toolchain.py --check
python3 scripts/flutter_toolchain.py --suppress-analytics --version
scripts/quality.command run flutter --execute
```

For another Flutter command, run the selector from the app directory:

```sh
cd apps/erp_client
python3 ../../scripts/flutter_toolchain.py --suppress-analytics analyze --no-pub
```

Pub, Gradle, analyzer, Android user settings and temporary caches are scoped to
the configured external tool home. The selector fixes the package host to
`https://pub.dev` and SDK artifact host to `https://storage.googleapis.com`.
It does not replace shared Android SDK components or copy mutable Gradle caches.

When updating the SDK, retain the existing release, verify the new official
archive and extract it into a separate external directory. Review dependency
resolution and SDK migrations, then run the analyzer, complete unit/widget suite,
coverage, opt-out variant and native builds before accepting the new release.
Keep the source fingerprints, logs and resulting binary hashes with the validation
receipts; earlier SDK results do not establish that a rebuilt product passes.
