# Knitting Report Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose meaningful operational report dimensions and complete, correctly scoped original-history filtering.

**Architecture:** Reuse operational report predicates; add a fixed history-filter parser/SQL builder used by scoped rows, counts and paged choices. Keep detail/printing independent and shared cash controls global.

**Tech Stack:** Frappe/MariaDB/Python, existing Flutter controls and API client.

**Spec:** `docs/superpowers/specs/2026-11-15-knitting-report-filters-design.md`

## Global Constraints

- Synthetic native-test.localhost only; no source/customer-site requests or writes.
- Apply permissions equally to rows, counts and choices before pagination.
- Never mutate original history or infer hidden source identities/statuses.
- Preserve exact original/effective/undated distinctions and global shared cash controls.
- Use existing dependencies/design system; preserve concurrent working-tree edits and upstream.
- Hosting deferred, native Mac walkthrough explicitly unverified.

## Review Focus

- A matching record beyond page one must still appear with the exact filtered count.
- Approved undated openings must not acquire an invented original date.
- Option queries must not reveal other companies or financially restricted record families.
- An edited but unapplied control must not change next-page or export results.
- Active-only link choices must not prevent filtering valid historical/inactive IDs.

### Task 1: History filters and paged choices

**Files:** Create `migration/filtering.py` and `tests/test_migration_filters.py`; modify records/shared_cash portions of `migration/api.py`. Coordinate the single exact filter_options route allowance in `team_scope.py` with root/printing worker.

**Interfaces:** `records(..., filters=None)` and `shared_cash(..., query='', filters=None)` retain old call compatibility and return row_count. `filter_options(company, family, field, query='', start=0, filters=None)` returns bounded value/label choices and has_more under the same family/scope/financial checks.

- [x] Add failing synthetic tests for beyond-page matches, exact counts/stable ordering, AND filters plus grouped text OR, null/exact books and duplicate party names.
- [x] Add date validation/basis tests and denied company/member/financial choices/counts; verify quotes/wildcards remain data.
- [x] Implement fixed parsed filters and parameterized SQL over visible normalized fields/direct metadata only.
- [x] Test shared-cash display filtering while complete balances/control flags remain unchanged.
- [x] Acquire root's serial native-test slot and run focused native store/filter/cash tests.

### Task 2: History filter controls

**Files:** list portion only of `imported_history.dart`, records/shared_cash/options methods only of `imported_history_api.dart`, history/filter Flutter tests. Printing worker owns detail/print sections; use targeted patches.

- [x] Add failing tests for filter arguments, complete paged choices, clear/family/company/access resets and stale-choice/page suppression.
- [x] Implement date basis/range, recorded book and available original Party/Order/Status controls with accurate labels and filtered count.
- [x] Label unfiltered family totals and full shared-cash controls; preserve exact original detail navigation.
- [x] Verify a usable 360px layout and existing history regression tests.

### Task 3: Operational report dimensions

**Files:** `knitting_reports.dart`, `knitting_reports_test.dart`; a focused helper only if necessary. Production worker owns backend reports.py and production forms.

- [x] Add failing tests for relevant dimension controls, exact IDs/values, fixed embedded job and applied next-page/export parameters.
- [x] Implement an explicit per-report applicability map, existing picker reuse and exact historical-value fallback.
- [x] Reset inapplicable filters and paging when report/company/access changes; show applied criteria alongside results.
- [x] Verify narrow/desktop layout, analysis and existing report tests.

### Task 4: Review and evidence

- [x] Independently review SQL scope/permission and all draft/applied state transitions.
- [x] Resolve material findings and rerun affected checks.
- [x] Record actual checks and evidence-bounded limits; no blanket parity claim.
