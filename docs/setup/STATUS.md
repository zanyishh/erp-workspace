# Setup status — 12 November 2026

The first Flutter UI preview is now implemented and open on this Mac. Read [CLIENT_PREVIEW.md](CLIENT_PREVIEW.md) for product build evidence, checks and the remaining native-form scope. The original ERPNext service remains the local backend.

ERPNext is running. Browser sign-in, a full stop/restart check, and Flutter sample builds for macOS, the iPhone simulator, and Android have passed. Windows compilation requires a Windows host.

## Verified environment

- Apple Silicon Mac, macOS 26.6.2, 8 GB memory.
- Flutter 3.38.7 stable; Dart 3.10.7. Existing SDK retained, no major upgrade performed.
- Xcode 27.2 and CocoaPods 1.16.2 pass Flutter's tool checks. iOS 27 simulator runtime installed.
- Configured the existing Android SDK 36 at `/opt/homebrew/share/android-commandlinetools` and Java 21 at `/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`.
- The installed standard Android SDK license records were preserved. Flutter doctor also lists an unaccepted, optional microXR emulator license. It was reviewed and declined because XR is outside this project; no microXR package was installed.
- No Android device/emulator or physical iPhone is currently connected for a device execution check.
- Windows requires a separate Windows host with Visual Studio and the Desktop development with C++ workload. No Windows build has been validated on this Mac.

## Source preservation

Official source working trees and Git objects verified; no upstream files changed. All tracked files are present. Exact tags and commits are in `../../upstream.lock.json`. Notice-file checksum comparisons passed for the originals and separate preserved copies.

## Storage cleanup

Removed browser/package caches, app updater cache and Xcode generated data. Kept source projects, personal documents, databases, simulator device data, installed SDKs and active Codex runtimes. The 6.4 GB iPhone debug-symbol cache can be copied from the device again by Xcode. Some npm cache files were not removable with this account; no ownership or permission changes were made.

An initial runtime startup was rejected by automatic approval review because of limited free storage. After further cache cleanup, free space was verified above 12 GB and the approved configuration was reduced to 8 GB of virtual data-disk capacity and 4 GB of root-disk capacity, with sparse allocation. The dedicated `erp` runtime uses 2 CPUs and 3 GB of memory. It does not change the active Docker context for other projects.

## Local deployment

The configuration in `../../infrastructure/erpnext/compose.yaml` derives from the official Frappe Docker v4.2.0 evaluation recipe. Local changes pin ERPNext v16.54.0 and bind the browser port to `127.0.0.1:8080`. Standard evaluation credentials are Administrator / admin. Data is kept in named volumes when services stop.

The original ERPNext browser UI remains unchanged. A separate native Flutter client has now been implemented under `apps/erp_client/`, following the approved reference-led design. AI behavior remains a future increment.

## Build evidence so far

- macOS debug sample: PASS, with deployment target adjusted to macOS 12.0.
- iPhone simulator debug sample: PASS for native ARM64, with deployment target iOS 15.0. The installed lipo rejects Flutter's combined Intel/ARM simulator verification; the sample was restricted to the native ARM64 simulator.
- Android ARM64 debug sample: PASS. NDK 28.2.13676358 and CMake 3.22.1 were installed automatically by the build.
- Docker: the default containerd image store ran out of virtual disk space extracting ERPNext. The dedicated ERP profile now uses classic overlay2 storage, which does not retain duplicate compressed image layers. Existing virtual disk limits are unchanged.

See FLUTTER.md for commands and compatibility details. No Flutter SDK code was modified.

## Running baseline

ERPNext 16.54.0 and Frappe 16.55.2 are installed. The Frappe source checkout and notice inventory were aligned with that exact image version after inspection. The login page returned HTTP 200 and `/api/method/ping` returned `pong`. Browser login succeeded and the original ERPNext Home dashboard was displayed. A screenshot is saved as `erpnext-baseline.png`.

The evaluation company is **ERP Evaluation**, abbreviation **EVAL**, country **India**, currency **INR**, timezone **Asia/Kolkata**, with fiscal year 1 April 2026–31 March 2027 and the Standard chart of accounts. No personal email, real financial transactions or AI provider was configured. The original source/UI remains unchanged.

## Persistence and service verification

A full stop through `scripts/stop-erpnext.command` and restart through the same commands used by the start launcher passed. Administrator login, HTTP 200 for the dashboard, the `pong` API response, and the ERP Evaluation company were verified afterward. `bench doctor` reports two workers online with no scheduler warning. Docker image IDs, repository digests and ARM64 architecture are recorded in `upstream.lock.json`.

## Final verification

All three requested build targets available on this Mac compiled successfully: macOS, native ARM64 iPhone simulator, and Android ARM64 APK. Windows project files were generated, but no Windows build or physical-device execution was performed. Sample build output was deleted after recording the results to recover disk space; the small verification project and build logs remain under `.local/`. These initial sample builds established the toolchain. Product-client verification is recorded separately below; AI integrations remain future work.

## Recreating the runtime profile

The dedicated profile configuration is `~/.colima/erp/colima.yaml`. Its Docker section sets `features.containerd-snapshotter: false` to select the tested classic overlay2 store. Retain that setting when recreating the profile; the launchers preserve an existing profile. The start launcher uses 2 CPUs, 3 GB memory, an 8 GB data disk and a 4 GB root disk. These are local evaluation limits for this 8 GB Mac, not production sizing.
