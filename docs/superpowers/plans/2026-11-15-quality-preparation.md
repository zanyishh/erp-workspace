# Testing and security preparation implementation plan

> **For agentic workers:** Use superpowers:executing-plans for implementation, with parallel read-only inventory and documentation support. The user's preparation-only instruction overrides test execution steps.

**Goal:** Prepare reproducible development/testing tools and safe launchers, then report readiness without running tests.

**Architecture:** Project-scoped tool environments on the selected external drive and explicit, sequential commands. A dry plan is the default; execution requires `--execute`. Configurations target only the synthetic native test site.

**Tech Stack:** Flutter/Dart, Python/uv, Node/npm, Docker/Colima and the supplied open-source testing/security tools.

**Spec:** `docs/superpowers/specs/2026-11-15-quality-preparation-design.md`.

## Global constraints

- No application tests, scans, load, fuzz, service launches or application-site provisioning in this preparation turn. Initializing a tool’s own private setup database is installation work.
- No customer data, live accounts, customer port 8082, or original baseline port 8080 as dynamic targets.
- Preserve user edits, upstream sources, licenses and all database volumes.
- Explicit Docker context `colima-erp`; localhost-only services; run heavy tools sequentially.
- Disk headroom is required before large installations. Missing tools remain blocked, never passed.

## Review focus

- Missing `--execute` must never start a suite.
- Arbitrary target overrides must be rejected; redirect-following must not escape the synthetic target.
- A failed/missing tool must not become a passing release gate.
- Scanners must exclude local customer data and generated outputs.
- Installation must not invoke test scripts or fill the disk.

## Tasks

- [x] Inventory existing suites/tools and official installation sources; document coverage and gaps.
- [x] Add manifests, dormant security/API/load/browser configurations and a release-evidence checklist.
- [x] Add explicit preparation/run launchers and runner safety tests (author only; execution deferred).
- [x] Install what safely fits; record exact installed versions and blocked components.
- [x] Parse configuration, check syntax, inspect versions and obtain an independent read-only review.
- [x] Report actual readiness, remaining blockers, and wait for the user's start command.

Ruling: keep changes in this workspace because the current app contains substantial uncommitted work which the tools must prepare to test; a clean worktree would omit it. Do not commit or stage unrelated changes. Existing test scripts are not run as part of installation verification.

Initial installation blocker (resolved by selecting external storage): available internal space fell from approximately 1.4 GiB to 0.31 GiB before packages were installed. Network downloads were retried with permitted access and installations moved to the user-selected drive. Internal disk headroom remains a runtime constraint. All test and scan execution remains deferred by the user.

## External-storage continuation

User selected the external drive `infact`, an approximately 59 GiB ExFAT drive. The initial APFS sparsebundle had severe write delays; tools and verified downloads were moved successfully to a 40 GiB journaled HFS+ image at `/Volumes/infact/ERP-Quality-HFS.sparsebundle`, mounted at `/Volumes/ERPQuality`. The original image, existing drive files/format and ERP runtime are preserved. Tool home is `/Volumes/ERPQuality/erp-quality`, selected with its volume UUID in ignored `.local/quality/location.json`. Install caches, temporary files, Python/Node environments, native binaries and larger archives belong there. Installers remain sequential because simultaneous package writes caused further stalls. No app tests or scans are authorized yet.

- [x] Create external Mac-compatible storage and persistent workspace selection.
- [x] Install and record Python, Node/browser, native security, Patrol and license tooling.
- [x] Prepare native ZAP; preserve the active ERP Docker storage.
- [x] Prepare supported native MobSF instead of adding an image to the crowded Docker runtime.
- [x] Record installation evidence and remaining platform/runtime limits; do not claim complete coverage.

Final evidence: all selected tool installations completed, including headless browser and Patrol CLI/library cache. Both Trivy/Grype download-only database preparations exited 0. The final inventory records zero quality-run reports; application tests, scans, browser/service launches and native builds remain unexecuted. Final syntax checks and independent read-only review completed. The handover explicitly preserves incomplete workflow/mobile/standards coverage, Windows host requirements, low internal disk headroom, MobSF resource limitations and ORT larger-host needs. See `docs/setup/QUALITY_PREPARATION.md` and ignored `.local/quality/final-readiness.json`.
