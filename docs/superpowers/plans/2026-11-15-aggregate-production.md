# Aggregate Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record measured aggregate fabric production and continue its existing batch workflow without invented individual rolls.

**Architecture:** Extend the existing command/event/custody path with aggregate output, then connect all read projections and Flutter entry/guidance to that same event. Keep existing roll and imported stock behavior intact.

**Tech Stack:** Existing Frappe/MariaDB/Python and Flutter/Dart.

**Spec:** `docs/superpowers/specs/2026-11-15-aggregate-production-design.md`

## Global Constraints

- Only synthetic fixtures on native-test.localhost; no live source or customer-site tests/writes.
- Preserve immutable originals, exact decimal custody, permission checks and existing owned/mixed stock valuation.
- The aggregate action supports customer-owned material only; explicit input consumption, output kg, count and loss are independent facts.
- Current command permissions, idempotency, stale-version and transactional locks remain mandatory.
- Keep upstream unchanged, no new dependency or public service, preserve all prior working-tree edits.
- Native walkthrough remains unverified; hosting deferred until application work is complete.

## Review Focus

- New aggregate events must not break historical fabric-state reconstruction or count production twice.
- Positive kg with zero count is valid; negative/fractional/boolean counts are invalid.
- Imported programme output and individual-roll output still constrain the new production allowance.
- Reviewed/delivered/returned or otherwise depended-on batches cannot be cancelled as unused stock.
- Paging or denied linked records must not fabricate a unique next-action batch or leak its identity.

### Task 1: Aggregate production and safe reversal

**Files:** `knitting/batches.py`, `knitting/domain.py`, `knitting/install.py`, related native tests under `apps/erp_extensions/erp_extensions/tests/`.

**Interfaces:** Existing `command` action `produce_batch`; payload and result as defined in the design. Result uses `batch` and `roll_count`, never a numeric `rolls` masquerading as an ID list. Batch schema adds only required event provenance/cancelled state.

Provide `upgrade_batch_production_schema()` in `knitting/install.py`, reusing the schema definitions, to idempotently update only the batch's required fields/state options through the normal DocType controller. It must not modify business or Version records. The existing installer does not update Select options and its broader cleanup is unsuitable for this narrow customer-schema upgrade. Verify the updater on an existing synthetic schema. Root applies it to the local destination only after successful synthetic tests and before/after preservation evidence.

- [x] Add failing synthetic tests for 90.000 -> 88.000/7 + 2.000 loss, positive kg/zero count, exact custody units and zero individual rolls.
- [x] Add rejection/rollback tests for invalid precision, count, duplicate/denied input, ownership, unavailable quantities, stale version and unauthorized action.
- [x] Refactor shared production logic minimally; implement aggregate output without a fake roll or duplicated valuation logic.
- [x] Add idempotent replay, imported/new programme allowance and untouched-batch cancellation tests including downstream dependency blocks.
- [x] Verify two simultaneous last-balance attempts cannot both consume the same yarn.
- [x] Run focused native tests after acquiring root's serial database-test slot.

### Task 2: Reports and guided projections

**Files:** `knitting/reports.py`, `knitting/registers.py`, full job workflow projection in `knitting/domain.py`/`api.py`, focused native report/register tests.

**Interfaces:** Production reports and day totals include `produce_batch`. Batch history seeds from immutable event results. Full-job workflow adds batch inspection/held/released cohorts using permission-filtered full counts and unique IDs.

- [x] Add failing before/after/as-of/period tests for new production, partial 21.300 kg/2 delivery, invoice/credit/return and cancellation.
- [x] Implement new event projections, preserving imported baseline reconstruction and exact totals.
- [x] Test guided batch counts beyond first page and denied batch/link scope; never select an arbitrary visible page's single item.
- [x] Verify existing batch, individual-roll, bulk, subcontract, report and register regressions.

### Task 3: Flutter batch entry and next actions

**Files:** `knitting_forms.dart`, `knitting_entry_layout.dart`, `knitting_models.dart`, `mill_production.dart`, `knitting_job_workflow.dart` and focused form/workflow tests. Do not edit report-filter UI owned by another worker.

- [x] Add failing form tests for total/count entry, explicit consumption, 0.001 kg mismatch, zero count and payload without generated roll weights.
- [x] Implement the action using shared controls and confirmation. Keep individual-roll entry reachable.
- [x] Route customer-custody guided production to aggregate entry and surface proven batch review/delivery cohorts.
- [x] Verify retry/stale/access states and narrow layouts; run affected Flutter tests and analysis.

### Task 4: Independent review and evidence

- [x] Review the complete scoped change for conservation, permissions, historical reports and source-scope claims.
- [x] Fix material findings and rerun affected checks.
- [x] Record test outcomes and limits; retain no-go for unproved vendor rules rather than calling the app 100% equivalent.

## Final integration follow-up

- [x] Verify produced-batch direct reads, counts, snapshots and actions inherit source machine restrictions without cyclic permission checks.
- [x] Attribute period production reversals to the original producer while retaining the correcting user in activity history.
- [x] Reproduce both findings, run affected synthetic regressions and obtain an independent scoped re-review.
