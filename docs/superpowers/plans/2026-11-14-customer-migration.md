# Customer Migration Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans. User authorization includes necessary implementation without another generic approval round.

**Goal:** Migrate the four companies into a separate local customer workspace, preserve original history, and verify supported operational balances and workflows.

**Architecture:** Immutable source records and one posting-authority registry bind verified source facts to native financial and batch-stock effects. Shared cash remains scope-level; native company permissions govern the app. Original records and source anomalies remain visible without becoming duplicate postings.

**Tech Stack:** Existing Python/Frappe/ERPNext, Flutter, standard-library offline conversion and the explicit colima-erp local deployment.

**Spec:** docs/superpowers/specs/2026-11-14-customer-migration-design.md

## Global constraints

- No Knitpack writes or implementation/test connections; use the preserved verified source copy.
- Four separate Companies, one shared cash balance, effective opening date 2023-04-01 with raw dates retained.
- No invented allocations, individual rolls, historical stock signs or original cancellation dates.
- Synthetic tests stay on native-test; actual customer records stay on a separate destination.
- Preserve upstream checkouts and all database volumes; do not commit private source data or credentials.

## Tasks

- [x] Add immutable migration scope/history/authority schema, guarded import services and permission-scoped read APIs; test tampering, retries, dates, shared access and source-secret rejection.
- [x] Compile native source vouchers/openings into explicit financial mappings; test exact amounts, original party roles, three books, native GL/PLE results and later payments before customer posting.
- [x] Add source-supported physical batch balance/operations without invented roll weights; preserve historical documents and test conservation, dates, idempotency and company ownership.
- [x] Implement versioned customer launch profiles and native imported-history navigation/printing with synthetic Flutter tests.
- [x] Provision the separate loopback customer site, retain a backup, normalize the verified archive into scoped batches, and verify complete source identity coverage before applying.
- [x] Apply validated customer batches idempotently, reconcile source-to-target controls, rehearse supported workflows without changing original imported history, and verify restore/retry behavior.
- [x] Build/install the Mac app, verify four-company switching and visible records, and update evidence with exact results and remaining source limitations.

Completed 15 November 2026 for the accessible, captured source scope. The installed Mac source fingerprint and strict signature check pass; four-company navigation was verified by the automated client pilot. The destination backup was restored and independently reconciled. See the private migration evidence for exact results, unresolved source allocation evidence, unavailable current job and machine/HR setup limitations. Completion of this migration plan is not public-launch certification or proof of unavailable source database history.

## Review focus

Empty or unavailable source values must never become zero; source and accounting parties remain independent; shared cash never fans out into four openings; original-date metadata never becomes target audit timestamps; retries never duplicate ledger/stock effects. Explicit review is required when a source-native anomaly prevents a supported target effect. Do not declare operational completion for an archive viewer alone.
