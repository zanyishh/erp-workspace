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


## Fresh release-build comparison

Two release-mode instrumented Mac applications used the ordinary signup/sign-in and mill screens. The first was rebuilt from the frozen pre-fix app, including its original artwork and renderer. The updated release used the revised app and studio artwork. The fixture, mouse input, clock boundaries and native frame callbacks were the same. Both AOT builds passed strict local signature checks. Each launch at 1404 × 754 logical pixels and 2× scale used the built-in 60 Hz display. The OS and driver caches remained under their normal release behavior. One completed warm-up on the new build and an attempted pre-fix warm-up preceded the series. The pre-fix warm-up timed out before recording a timing. Six launches then completed in pre/post, post/pre, pre/post order. Raw samples are in `.local/startup-20261114/release-fixed-{pre,post}-{1,2,3}.json`.

| Release measurement, 200 jobs and 500 events | Before, three runs (ms) | After, three runs (ms) | Before median → after median |
| --- | --- | --- | --- |
| Launch to usable sign-in | 2841 / 797 / 418 | 715 / 455 / 628 | 797 → 628 ms |
| Sign-in click to usable mill | 338 / 84 / 92 | 84 / 74 / 71 | 92 → 74 ms |
| Sign-in click to fully illustrated mill | 364 / 111 / 124 | 109 / 91 / 86 | 124 → 91 ms |
| Worst mill raster in each launch | 174.9 / 11.8 / 8.4 | 11.0 / 7.8 / 10.7 | 11.8 → 10.7 ms |
| Worst frame span through illustrated mill | 234.6 / 59.6 / 55.3 | 43.4 / 42.5 / 25.4 | 59.6 → 42.5 ms |
| Jobs click to drawn register | 34 / 22 / 18 | 27 / 32 / 51 | 22 → 32 ms |

The largest release mill raster observation fell from 174.915 to 10.972 ms. The historical 266.851 ms observation and the profile-mode comparison above remain separate experiments. The final release's 43.362 ms maximum whole-frame span exceeded one 60 Hz refresh. The updated register opened more slowly in two of the three pairs. The individual trials show how much the first baseline launch influenced the maximum. This Mac was in regular use, and CPU load, graphics caches and file caches varied across launches. There were no concurrent project builds or suites during the reported series.

The final harness moved keyboard focus to the search field after the register measurement, verified a genuine filter change and confirmed that unrelated jobs disappeared. Its instructions work with `--release` in the build command and no `--cold-shaders` switch. The original and updated release AOT digests begin with `7dddb749d753` and `6ce98e2e2a03`.

## Current release against the isolated ERP

The restricted mill account loaded 14 jobs and 163 events from the local test service. All three timed launches signed out after opening and filtering the register. One additional launch timed out before recording a usable sign-in frame and was retried. The timeout supplied no elapsed value and is excluded from the three completed runs. The earlier comparable before/after connected profile series used 12 jobs and 137 events. These final release times describe the larger current company.

| Current connected release | Three successful fresh launches (ms) | Median |
| --- | --- | --- |
| Launch to usable sign-in | 546 / 354 / 364 | 364 ms |
| Sign-in click to usable mill | 892 / 691 / 639 | 691 ms |
| Sign-in click to fully illustrated mill | 911 / 706 / 654 | 706 ms |
| Worst mill raster in each launch | 5.23 / 5.07 / 5.07 | 5.07 ms |
| Worst frame span through illustrated mill | 37.7 / 24.3 / 23.7 | 24.3 ms |
| Jobs click to drawn register | 30 / 27 / 21 | 27 ms |

Raw samples are in `.local/startup-20261114/release-connected-post-{1,2,3}.json`. An untimed validation run during compilation took 2.239 seconds from click to usable mill. These are local Mac timings. They do not predict deployed network response times.
