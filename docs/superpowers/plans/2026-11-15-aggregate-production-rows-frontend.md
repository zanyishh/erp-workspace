# Aggregate Production Rows Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Review and post several measured customer-owned production rows atomically, preserving independent job/version/programme/input/operator scopes.

**Architecture:** Register the approved company action `produce_batches`. Reuse the current single-row batch form as a row preparation dialog, with a preparation callback that returns reviewed values without submitting a command. A focused new part file manages row editing and summaries; the existing command draft/review/post/retry path submits the final company payload once.

**Tech Stack:** Existing Flutter/Dart; no new dependencies.

**Spec:** Root-approved contract in `.local/knitpack-functional-2026-11-15/aggregate-row-operator-proposal.md` plus parent implementation authorization.

## Global Constraints

- Frontend files/tests only; no backend, customer/source writes or native DB tests.
- `produce_batches` payload `entries` contains 1–50 rows: job, modified, programme_line, quantity_kg, rolls, inputs, loss_kg, warehouse, optional machine/remarks/production_operator and shift.
- Current posting time stays explicit; no per-roll weights or invented automatic consumption/valuation.
- Production operator is an optional verified original employee selector, separate from signed-in recording user; no HR Employee/User creation.
- Preserve all existing dirty changes, single-row and individual-roll forms; no commits, reset, dependencies or audit publication.

## Review Focus

- A row's job change must clear only that row's programme/input/source selections.
- Prepared row data and version must survive edit/review without making a backend command.
- Access/company revisions invalidate prepared source identities and late picker/row results.
- Atomic multi-row stale/uncertain outcomes must use existing explicit reload/status flow rather than retrying with a new request ID.
- All row controls, review, removal and picker paging remain reachable at 360×510 /1.8 text scale.

### Task 1: Row preparation and original operator

**Files:** Modify `apps/erp_client/lib/knitting_forms.dart`; tests `apps/erp_client/test/knitting_batch_production_test.dart`.

**Interfaces:** Add optional `prepareOnly` navigation mode returning frozen payload, source modified version and display references. Its confirm action prepares a local row and does not call `knittingCommand`. Add optional `ProductionOperator` lookup field to `produce_batch`; display its title without raw identity subtitle.

- [x] Write failing tests that local preparation returns exact zero-count data/version without a command and original operator title/value survives review.
- [x] Run focused tests to expected feature-missing RED.
- [x] Implement local preparation and lookup using existing validation/access/leave behavior.
- [x] Run focused GREEN plus existing batch form regressions.

### Task 2: Atomic row form and navigation

**Files:** Create `apps/erp_client/lib/knitting_batch_rows.dart` as a forms part; modify `knitting_forms.dart` and `mill_production.dart`; NEW `apps/erp_client/test/knitting_production_rows_test.dart`.

**Interfaces:** `produce_batches` is a job-optional production action with `entries` in a focused row editor. Each Add/Edit opens the single-row batch form with an independent job and initial values/references. Final confirmation submits one action with all row versions and exact decimals.

- [x] Write RED tests for two independently scoped rows, editing/removal, exact one-command payload and no invented weights.
- [x] Implement row preparation and review summaries with 50-row bound and per-job consistent-version validation.
- [x] Add RED stale/access/late-result tests and narrow large-font interaction case; implement invalidation and responsive controls.
- [x] Verify targeted GREEN, affected forms/production/context regressions and scoped analysis. Coordinate Flutter runner with root.

### Task 3: Evidence and integration handoff

- [x] Record RED/GREEN logs under `.local/knitpack-functional-2026-11-15/production-rows-ui*`.
- [x] Confirm backend lookup/result contract matches UI labels and action payload.
- [x] Send parent frozen changed paths, focused/affected test counts, analysis and remaining acceptance limits. Parent owns final full-suite/native/build/review integration.
