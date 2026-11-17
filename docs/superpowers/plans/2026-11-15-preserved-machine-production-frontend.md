# Preserved Machine Production Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Select a verified preserved machine for production attribution without inventing configured machine capacity or ownership.

**Architecture:** Reuse the original-employee selector/display/report pattern. Keep configured `machine` separate from opaque `production_machine`; selecting either clears the other. Existing batch row preparation supplies per-row scopes; configured production behavior is preserved.

**Tech Stack:** Existing Flutter/Dart, no new dependency.

**Spec:** Parent-approved increment; confirmed ProductionMachine lookup `rows[{name,title,machine_code}]`, payload `production_machine`, trusted report fields `production_machine_record/label/code`, stable identity group/filter `production_machine`.

## Global Constraints

- Frontend source/tests only; no backend, source/customer writes or native DB tests.
- Original machine is attribution only. No capacity, ownership, availability or raw gauge/dia interpretation claims.
- Support produce, produce_batch and rows of produce_bulk/produce_batches; preserve current posting time and real consumption rules.
- Do not display opaque historical tokens. Codes may repeat; request identity remains the canonical record token.
- Preserve all prior changes and public audit files; parent owns final full-suite/build/native review.

## Review Focus

- Duplicate machine codes retain distinct record identities through selection and review.
- Both machine kinds cannot survive review or switching in either direction.
- Job/access/company changes and delayed picker results cannot restore old machine identity.
- Row removal/editing retains its own original machine reference and readable label/code.
- Large-font phone selectors and report draft/applied state remain usable.

### Task 1 Forms and row summaries

- [x] Write/run six feature-missing RED tests in knitting_production_machine_test.dart.
- [x] Add original machine fields to individual/batch/bulk forms and mutually exclusive selection/validation.
- [x] Reuse canonical title+code in picker, initial-reference review and prepared row summaries; hide opaque tokens.
- [x] Add row/access/phone tests, observe relevant RED, implement guards, run focused GREEN.

### Task 2 Reports and integration

- [x] Add separate original machine filter/group with canonical label/code; hide original identity columns while retaining request IDs.
- [x] Verify draft/applied filter isolation, paging and source reset with native configured behavior intact.
- [x] Run affected forms/rows/reports/navigation regressions and analysis, freeze files/hashes, release Flutter runner to parent.

### Review corrections

- [x] Reproduce delayed stale reload after API/company/fixed-job replacement and fixed-job draft retention.
- [x] Reset production draft and displayed field state on a different fixed job name; retain draft on same-job refresh.
- [x] Guard stale reload success/error/finally against API/company/selected-job/fixed-job changes.
- [x] Rerun affected tests and scoped analysis; replace freeze hashes after review corrections.

- [x] Reproduce lost access listener after API replacement in form/report and delayed access revalidation across API/company/job changes.
- [x] Bind local access gates to current API/company/job; guard parent form revalidation before applying awaited sources.

### Final export boundary

- [x] Reproduce late export file/error responses after API/company/job/access/applied-report changes and stale roll-label choice.
- [x] Reject old export results/errors before file presentation while retaining applied-vs-draft semantics.
- [x] Run complete serial Flutter suite and full analysis, then record final frozen source hashes.

### Approved individual/bulk original employee extension

- [x] Reproduce missing optional original employee selection, exact number review, signer separation and Unrecorded behavior on individual and bulk roll forms (six RED cases).
- [x] Reuse shared ProductionOperator field for individual roll and each bulk row; preserve opaque identity, exact readable employee number and existing batch behavior.
- [x] Verify clearing/omission remains explicit Unrecorded and never creates signer attribution.
- [x] Complete affected regressions; await backend/report freeze before final full suite and full analysis.
