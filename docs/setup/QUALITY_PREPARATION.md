# Testing and security setup — 15 November 2026

**Historical preparation snapshot. Tool installation completed on the user-selected `infact` drive. The user subsequently authorized “Start every test”; execution began on 15 November 2026. Statements below about tests not running describe preparation only. The [completed execution report](QUALITY_RUN_2026-11-15.md) records passing checks, unresolved findings and coverage gaps. Execution completion is not release approval.**

The initial disk check found about 1.4 GiB free; subsequent checks fell below 0.4 GiB. The user selected **infact** for the larger tools. No existing application files or database volumes were removed to make space.

The drive is ExFAT. A filesystem image provides the Unix permissions and links required by these tools without reformatting the drive. The initial APFS image showed severe write delays; migration to a 40 GiB journaled HFS+ image at `/Volumes/infact/ERP-Quality-HFS.sparsebundle` completed successfully. The old image is retained as a fallback. The active image and volume identity are persisted in ignored `.local/quality/location.json`; tool home remains `/Volumes/ERPQuality/erp-quality`. Use `scripts/quality-storage.command mount` after reconnecting the drive. Keep it connected during tool use. The final inventory at 16:58 UTC on 15 November 2026 recorded 29.14 GiB free in the tool image and 45.67 GiB free on the backing drive. Internal storage remained low at 0.53 GiB; existing SDK/build outputs still need space planning before platform builds.

The core Python, Semgrep, Checkov, native security/performance, ZAP, MobSF, ScanCode and ORT installations have recorded installation evidence. Playwright, Bruno and Patrol are installed and version-verified; the headless Chromium runtime is installed without being launched. New tool environments, their configured caches, temporary files and runner reports use the external image. Existing Flutter/Xcode/Android SDKs, application build/coverage outputs and running Colima/ERP data remain in their original locations; the internal disk still needs headroom for later builds. Windows builds and memory-heavy analysis have the limits listed below.

## Prepared files

- `scripts/quality.command`: installation/status/plan launcher. A run without `--execute` prints commands only.
- `scripts/quality/quality.py`: isolated tool installation, source-scoped scanner staging, sequential runs and per-run JSON/log output. Missing tools and failed commands do not pass.
- `infrastructure/erpnext/quality/`: pinned Python/Node package requests, verified container digests, browser/API smoke examples, conservative k6/ffuf examples, local Semgrep rules, ZAP passive plan, dormant MobSF service, tox configuration and pending release gates.
- `scripts/quality/test_quality.py`: authored runner-safety tests, deliberately not executed.
- [Coverage and remaining work](QUALITY_COVERAGE.md): existing suites, excluded pilots and risk/release evidence.
- [Official tool sources](QUALITY_TOOL_SOURCES.md): versions, installation instructions and hardware constraints.

Runner logs and the new tools’ configured state use the selected external tool home. This does not relocate existing Flutter SDK/build/coverage outputs. No automatic CI triggers, scheduled tests, services, browser launches, mobile builds, test-site provisioning or scans were started.

## Installed components

| Group | Pinned versions and installation evidence |
| --- | --- |
| Existing Flutter SDK | Flutter 3.38.7, Dart 3.10.7 and DevTools 2.51.1, read from cached SDK metadata. The SDK was not upgraded or run for inventory. |
| Python testing | pytest 9.2.0, Hypothesis 6.170.15, tox 4.67.13, Schemathesis 4.33.4 and Testcontainers 4.15.0. All 41 installed dependencies passed their metadata compatibility check. |
| Source/infrastructure security | Semgrep 1.185.0 and Checkov 3.4.5. Isolated environments passed dependency and CLI version checks. |
| Native security/performance/supply chain | Gitleaks 8.30.1, Trivy 0.76.2, Syft 1.57.1, Grype 0.121.3, k6 2.4.0, ffuf 2.3.0, Scorecard 5.6.0 and crane 0.22.1. Publisher archive checksums, ARM64 architecture and CLI versions verified. |
| Web security | ZAP 2.17.0 native ARM bundle with bundled Java 17.0.17+10. Publisher checksum, copied-file hashes and application version metadata verified; application not launched. |
| Mobile security | MobSF 4.6.6 with JADX 1.5.6. Publisher checksums, 106-package dependency check and private setup database/operator verified; service not launched. |
| Licensing | ScanCode 32.5.0 using existing Rosetta/Intel Python; ORT 99.0.0 with external ARM Temurin 25.0.5+8. Publisher archive checksums and CLI versions verified. |
| Browser/API | Playwright 1.65.1 and Bruno CLI 4.3.0 installed with 516 locked dependencies; both CLI version checks passed. Chromium headless shell 159.0.8154.6/revision 1255 and FFmpeg revision 1013 have installation-complete markers. Neither was launched. |
| Native automation | Patrol CLI 4.9.0 activated and version-verified with its automatic doctor/update checks and analytics disabled. Patrol 4.11.0 library cached. The app itself has no new Patrol integration. |
| Vulnerability reference data | Trivy schema 2 and Grype schema 6 databases downloaded/imported successfully with both commands exiting 0. Installed database files are 1,774,080,000 and 3,443,380,224 bytes respectively. No application scan was performed. |

Detailed records are in the external tool home's `receipts/` and `logs/native-installation.json`. `.local/quality/final-readiness.json` records the final storage, database and package summary, with zero quality-run result reports. New installation checks establish package state; they do not establish application behavior or test coverage. npm's transitive-package deprecation warnings are retained in the installation log for later dependency review.

## Installation commands

The following commands install tools only. Each group enforces disk headroom first. Run sequentially and inspect every result; failed groups need resolution before readiness can be claimed.

```sh
scripts/quality.command status
scripts/quality.command install core
scripts/quality.command install node
scripts/quality.command install semgrep
scripts/quality.command install checkov
scripts/quality.command install native
scripts/quality.command install browsers
scripts/quality.command install zap
scripts/quality.command install mobsf
scripts/quality.command install mobile
scripts/quality.command install licenses
scripts/quality.command install databases
scripts/quality.command status
```

`core` contains pytest, Hypothesis, tox, Schemathesis and Testcontainers. Semgrep and Checkov have separate Python environments. The Node group holds Playwright and Bruno and disables package lifecycle scripts. Browser installation is separate and selects Chromium's headless shell for the prepared headless configuration. Headed debugging requires a later full Chromium download. The native group installs pinned official ARM64 archives for Gitleaks, Trivy, Syft, Grype, k6, ffuf, Scorecard and crane, with publisher SHA256 verification and preserved notices. Resolved Python/Node locks are recorded and consumed by future installations. Patrol’s resolved CLI lock is retained as installation evidence; its package activation still resolves according to Dart’s package manager.

Native ZAP and MobSF avoid adding large images to the existing ERP Docker runtime. MobSF is installed in its own Python environment with external SQLite state; its 35 database migrations and private operator setup completed. Database initialization was setup only, and its service remains stopped. The optional `containers` installer can prepare a digest-pinned MobSF OCI layout without using Docker, but that alternative is not part of the selected native installation. An OCI layout is not a loaded/runnable container. Patrol CLI/library installation uses an external Dart package cache. It does not add a mobile harness or modify the production app.

## Explicit future execution

After installation is complete and the user says to start, use the named synthetic-site launcher if the site needs provisioning. That launcher writes synthetic fixtures and starts services; it was not invoked during preparation.

```sh
scripts/setup-native-test.command
scripts/quality.command plan
scripts/quality.command run all             # prints only
scripts/quality.command run all --execute   # actual checks; only after instruction
```

Individual groups can be selected. `mobile`, `supply-chain` and `release` currently report blocked placeholders, so `all` deliberately cannot pass. Completing the release checklist alone does not implement those runner groups; their harnesses and reviewed evidence must be connected first. It does not mean that every possible test has been implemented. The license group runs a single-worker ScanCode inventory of the staged source, with update checks disabled; its per-file/scanner timeout is 120 seconds, not a whole-run or memory limit. ORT policy analysis and legal review remain separate release requirements. Results under the selected external tool home's `reports/` distinguish failed and blocked work; a zero tool exit is only evidence that that command completed.

The fixed network target is `http://127.0.0.1:8081` / `native-test.localhost`. Native ZAP receives a generated plan for that origin and reserves loopback port 8095 for its proxy. The optional container fallback uses the synthetic frontend's Docker service name on the existing ERP network. Baseline port 8080 and customer port 8082 are excluded as host targets. No `ERP_URL` override or saved customer profile is consumed. This is application-level targeting, not an operating-system egress firewall. Browser routes and API/load request redirects are restricted where configured; extend these controls when adding operations, authentication and scanners.

## Work still required for the complete requested stack

- Scanner behavior and every application suite remain unexecuted. The native ZAP/MobSF path does not require container loading or inspection. Database download preparation does not make every later scan offline: Trivy IaC checks and some ecosystem data may still require network access.
- Integrate Patrol's Android/iOS test build configuration and meaningful synthetic device journeys. Select devices and validate platform builds later; Windows needs a Windows host.
- ScanCode 32.5.0 is installed through the existing Rosetta/Intel Python environment; its documented minimum is 8 GB RAM and 2 GB disk. ORT 99 and isolated Java 25 are installed and version-verified. ORT recommends 8 GiB JVM memory/4 CPUs, so practical full analysis needs an appropriate larger host.
- MobSF’s general runtime recommendation is 80 GB free disk and 8 GB RAM; this host does not meet the free-disk recommendation. Dynamic analysis is unconfigured, and the installed service’s runtime remains unverified. Produce and review release APK/IPA artifacts before analysis. The dormant localhost service uses `scripts/quality-mobsf.command start --execute`; its matching `stop --execute` preserves tool data. No service was started and no artifacts were uploaded.
- Extend the **ping-only** OpenAPI/Bruno contract and **login-only** Playwright example to real authenticated ERP workflows. These initial examples are not whole-app coverage. The k6/ffuf examples are bounded smoke workloads, not stress/endurance or broad discovery campaigns.
- Add property-based business invariants and Testcontainers scenarios where useful. Existing Frappe integration continues using the supported native unittest suite and synthetic Compose site.
- Local Semgrep rules are a small initial Python review set, not comprehensive Python/Dart security analysis. Syft/Trivy format support and component coverage must be checked against actual app lockfiles and shipped images. Source snapshot scanning excludes `.local`, private research, upstream working trees, generated builds and Git history; dedicated shipped-artifact/history audits are still required.
- Complete ASVS/MASVS/SSDF evidence, encrypted restore/rollback drills, agreed performance objectives, financial boundaries and qualified legal review. The release-gates file remains entirely pending. AI remains deferred.
- Prometheus, Grafana, OpenTelemetry and GlitchTip belong to a separate postrelease monitoring deployment; retention, redaction, alert ownership and capacity must be defined first. Nothing was deployed or scheduled.

## Preparation verification

Python/JSON parsing, shell/JavaScript syntax checks, YAML parsing and dormant Compose configuration validation completed successfully. Independent read-only review found three issues: potential reuse of a user-owned staging folder, missing synthetic migration discovery and missing first-party scanner inputs. These were corrected using fresh per-run staging, explicit migration discovery and additional source-only inputs. Runner safety tests were authored and remain unexecuted.

The default `run all` command was also checked in plan-only mode; it printed commands and did not start them. Syntax validity is not proof that a test/scanner workload works. Installation verification used package metadata, dependency checks, publisher checksums, CLI versions and browser installation markers as applicable; ZAP/MobSF runtime launches were deliberately deferred. The newly added repeatable ZAP installer was syntax-reviewed, while the existing native installation has its earlier checksum/bundle receipt. No claims are made about application correctness, vulnerability counts, coverage percentage or release readiness. `.local/quality/preparation-status.json` records a timestamped read-only installation inventory. Detailed external receipts record versions, checksum/dependency checks and setup evidence. These establish installation state only. Application tests and scans remain unexecuted.
