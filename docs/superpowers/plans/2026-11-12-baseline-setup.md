# ERPNext Baseline Setup Plan

> **For agentic workers:** Execute the authorized setup in this session using superpowers:executing-plans. Track actual results below.

**Goal:** Preserve the official ERPNext source and notices, verify Flutter development tools, and run unmodified ERPNext locally on this Mac for evaluation.

**Architecture:** Keep official Git checkouts in `upstream/`, local deployment configuration in `infrastructure/erpnext/`, and setup evidence in `docs/setup/` and `.local/reports/`. Retain ERPNext/Frappe as the server. A future Flutter client will target macOS, Windows, iOS and Android after the user reviews the original application.

**Tech stack:** Flutter/Dart; official ERPNext v16 and Frappe v16; official frappe_docker evaluation configuration; an open source container runtime where possible.

**Spec:** User request in this chat on 2026-11-12. Install/check tools, obtain complete source working trees, preserve all required licenses, run the baseline, and defer UI/UX and AI changes until user feedback.

## Global Constraints

- Preserve upstream copyright, license, third party notices and required legal notices.
- Do not redesign or add AI integrations during baseline setup.
- Use named folders and reproducible pinned source revisions.
- Windows compilation requires a Windows host; do not claim it has been verified from macOS.
- No removal of the user's files to create disk space.
- Bind evaluation services to localhost and retain data on stop.

## Review Focus

- Insufficient disk space: stop large downloads and request capacity before installation.
- Mismatched ERPNext/Frappe versions: stay on major version 16 and record exact revisions.
- Unsupported runtime architecture: verify ARM64 image support before launch.
- Source/notice loss: leave upstream Git trees intact and inventory notice files and checksums.
- Missing mobile SDK configuration: inspect existing tools before installing duplicates.

### Task 1: Flutter toolchain

- [x] Run Flutter version, doctor and device checks; save evidence.
- [x] Configure already installed Android SDK and Java if valid.
- [x] Record macOS/iOS/Android status and Windows host prerequisite.

### Task 2: Official source and licenses

- [x] Clone complete working trees of ERPNext, Frappe and frappe_docker at explicit versions (shallow Git history conserves storage).
- [x] Verify source origins/revisions and inventory license and notice files without modifying upstream files.
- [x] Write an evidence based license summary and retain exact license copies.

### Task 3: Local baseline runtime

- [x] Resolve available disk space before installing a container runtime or downloading service images.
- [x] Prepare a pinned local evaluation deployment and start/stop instructions.
- [x] Start runtime, initialize ERPNext and verify login and application page.
- [x] Open the running baseline for the user and report access details and remaining platform limitations.
