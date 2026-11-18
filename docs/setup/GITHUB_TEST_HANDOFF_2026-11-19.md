# GitHub tester handoff — 19 November 2026

Private repository: https://github.com/zanyishh/erp-workspace

## Windows downloads and verification

The [successful Windows run](https://github.com/zanyishh/erp-workspace/actions/runs/44389520255) built both native x64 editions from commit `416de695692843f0a9b46e119a667d0c3a457bff` on Windows Server 2025. Each job passed its pinned Flutter SDK check, static analysis, full unit/widget suite and separate local-launch opt-out variant. Each release executable opened a native window before packaging. Launch screenshots are retained as CI artifacts; these are automated checks, not manual acceptance of every business workflow.

| Download | Artifact |
| --- | --- |
| General ERP | [ERP-Workspace-Windows-x64](https://github.com/zanyishh/erp-workspace/actions/runs/44389520255/artifacts/14469207065) |
| Knitting | [Knitting-Workspace-Windows-x64](https://github.com/zanyishh/erp-workspace/actions/runs/44389520255/artifacts/14467547425) |

Both artifacts are approximately 19.9 MB, contain the executable, DLLs, data, notices and an exact source link, and are retained for 30 days. Extract the entire package. Friends require access to the private repository before downloading. See [Windows testing](WINDOWS_TESTING.md) for Docker Desktop setup, generated test accounts and the operator checklist.

The [backend job](https://github.com/zanyishh/erp-workspace/actions/runs/44389520255/job/135103049799) ran the same PowerShell launcher on an empty Linux Docker host. It created the isolated ERPNext site, seeded both companies, verified their separate logins and sample invoices, rejected cross-company reads, stopped/restarted the stack without removing volumes, and repeated the login checks. This validates the portable Compose/bootstrap path; installation of Docker Desktop/WSL on each friend's Windows hardware remains their prerequisite.

## Other checks and limits

Fresh local verification passed 77 top-level Python script tests, 253 offline migration tests, 113 quality-runner tests, four Android configuration tests and eight JavaScript metadata tests: 455 checks. The Flutter architecture check covered 231 source files with zero import cycles. All 89 current hosted package versions are represented in the notice inventory, all 95 notice file digests matched, and the official upstream revisions and original notice hashes matched their lockfile.

The publishable source and complete existing Git history include the client, server extension, synthetic fixtures, lockfiles and licenses. Customer research, runtime credentials, local databases, build caches and official upstream working copies remain excluded. The scoped source credential-pattern scan found no matches to common GitHub/AWS tokens or private-key headers. This is not an exhaustive credential audit.

[Mobile CI](https://github.com/zanyishh/erp-workspace/actions/runs/44389035684) compiled the Android release bundle/debug APK and unsigned iOS release/simulator app. Android device automation timed out while booting the emulator. The Intel iPhone simulator rejected the ARM-only simulator app. The simulator configuration now selects the host architecture; that correction still requires a fresh iOS simulator run. Physical Android/iOS use and printer acceptance remain unverified. macOS was not rebuilt in this session because the selected external Flutter SDK drive was unavailable.

Later source changes concern test formatting, CI diagnostics and the iOS simulator architecture; they do not change the Windows application's production Dart code or native runner. The strict source formatting check is rerun separately. A successful native build is distinct from customer migration and business acceptance. See the [delivery review](DELIVERY_2026-11-18.md) for the original customer-data and workflow limits.
