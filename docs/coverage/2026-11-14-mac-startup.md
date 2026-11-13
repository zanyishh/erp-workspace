# Native Mac launch and mill-opening measurements

On the isolated ERPNext service, the median time from the sign-in button press to the drawn, actionable mill fell from **3.713 s to 1.248 s**. With the 200-job in-memory fixture, the median fell from **75 ms to 56 ms**. The historical pilot's 266.851 ms raster frame came from a separate run. The directly comparable three-launch fixture series had a worst mill raster frame of **144.062 ms before and 6.017 ms after**.

## Fresh application launches

Each table cell lists run 1, run 2 and run 3 in milliseconds, rounded. “Mill” requires the rendered company overview, its running-job card and hit-testable Jobs navigation. “Illustrated” additionally requires all mounted studio images to have a decoded image in the recorded frame. Worst frame measurements cover the entire interval from sign-in click through the illustrated frame. Raster measures renderer work. Frame span measures the interval from vsync to raster finish, including time waiting in the pipeline.

| Workload and app | Launch to usable sign-in | Click to mill | Click to illustrated mill | Worst raster | Worst frame span | Jobs click to register |
| --- | --- | --- | --- | --- | --- | --- |
| Local ERPNext, before | 578 / 418 / 611 | 3378 / 3713 / 5418 | 3394 / 3962 / 5742 | 8.9 / 8.0 / 314.4 | 26.5 / 24.8 / 315.0 | 24 / 118 / 19 |
| Local ERPNext, after | 1154 / 474 / 457 | 1248 / 713 / 1327 | 1266 / 727 / 1356 | 5.0 / 5.1 / 7.8 | 113.7 / 23.5 / 26.1 | 47 / 26 / 80 |
| In-memory mill, before | 1122 / 372 / 445 | 245 / 47 / 75 | 265 / 65 / 93 | 144.1 / 7.8 / 7.6 | 194.6 / 19.2 / 38.7 | 47 / 16 / 17 |
| In-memory mill, after | 772 / 431 / 350 | 47 / 56 / 58 | 64 / 75 / 76 | 5.8 / 5.6 / 6.0 | 18.7 / 21.4 / 30.2 | 23 / 21 / 33 |

Launch-to-sign-in varied between runs. The longest final connected launch took 1.154 s. The slowest final connected Jobs click took 80 ms and contained an 18.9 ms raster frame. The final connected sign-in series still had a 113.7 ms frame span even though its worst build and raster stages measured 15.1 and 7.8 ms respectively.

## Changes isolated

- With the frozen application source, enabling Flutter's precompiled Impeller renderer on macOS lowered peak mill raster from 10.3 / 13.1 / 9.7 ms to 5.4 / 6.4 / 6.2 ms across three graphics-cache-reset launches per renderer. The final builds reported their active renderer at runtime using Flutter 3.38.7's `ImageFilter.isShaderFilterSupported`, which reads the engine's Impeller flag.
- With the updated client and the original snapshot service, the restricted test account still took 3608 / 4558 / 4102 ms from click to mill. As events, ledger entries and their parent jobs referred to the same records, the service ran the same Frappe visibility queries repeatedly. The read-only snapshot now reuses each exact DocType, account and record lookup within one call. A database regression counted nine identical warehouse permission queries before and one after. Restricting that manager's warehouse caused the very next snapshot to deny the same job. The checker test also verified that a purchase-order link remained private.
- The final connected run used the same client binary as the intermediate connected series, after reloading the updated service. Both clients used the same HTTP service, account, company, 12 jobs and 137 events in the initial A/B comparison. The final three samples used the same data and newly reloaded service. OS caches and other activity on this 8 GB development Mac could vary between launches.

## Method and reproduction

Native ARM64 MacBook Air, macOS 26.6.2 (25G83), Flutter 3.38.7 profile mode, Dart 3.10.7, 1404 × 754 logical pixels, 2× scale, 60 Hz. Each sample opened a fresh foreground app through macOS Launch Services. The launch clock started immediately before invoking `open`. The frame timeline ends at the engine's raster completion wall time. This includes app opening, and excludes physical panel scan-out and the time a person spends typing. Flutter's graphics cache reset switch was identical for both builds. OS and Metal driver caches stayed under OS control. Fixture and pre-service-update live pairs alternated order. The final service was measured chronologically after its reload.

The harness uses synthetic mouse down/up and editable-text updates in the live native app. It waits for UI conditions tied to actual frames, validates the displayed running count, opens Jobs, filters to a known job and verifies the unrelated row disappears. It also checks the test-site identity and signs out of each connected session. Timings use the engine's frame IDs and timestamps, independently of when it delivers its batched timing reports. The 200-job fixture includes 500 production postings, 500 rolls and 200 plans. The connected workload includes login, permission checks, network and database latency on the localhost test deployment.

Build from `apps/erp_client` with `flutter build macos --profile --no-pub -t tool/profile_startup.dart --dart-define=ERP_SERVER=http://127.0.0.1:8081`. From the repository root, run the launcher once per sample, passing a fresh output path.

```sh
python3 scripts/profile-startup.py --cold-shaders \
  'apps/erp_client/build/macos/Build/Products/Profile/ERP Workspace.app' \
  .local/startup-sample.json
```

Add `--credentials <owner-only-test-credentials.json>` for the existing restricted mill pilot on `native-test.localhost`. The launcher supplies the synthetic credentials on standard input. Each output contains the source, actual renderer flag, record counts, window configuration, timings and individual build/raster/span data. Baseline source, binaries and raw frame logs from this rehearsal are under `.local/startup-20261114/`. The frozen and updated AOT application SHA-256 digests begin with `e4db97e2bd09` and `112d2e39a71e`.
