# Original Record Printing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print faithful source copies of preserved operational records from the knitting app.

**Architecture:** Reuse authorized historical detail projections in a small read-only printing endpoint. Render a dedicated Flutter PDF and revalidate permission at preview/export. Keep invoice printing and immutable storage unchanged.

**Tech Stack:** Existing Frappe/Python, Flutter/Dart, pdf and printing packages.

**Spec:** `docs/superpowers/specs/2026-11-15-original-record-printing-design.md`

## Global Constraints

- Use synthetic fixtures on native-test.localhost only; never connect implementation or tests to the customer's live source.
- Preserve originals, posting authorities, financial balances and source decimal strings.
- Enforce scope and print permissions on the server; existing financial masking remains in force.
- No new dependency, public service or change to upstream checkouts.
- Native walkthrough remains unverified by user direction; hosting is deferred.
- Work in the existing user-directed working tree, preserving all prior edits; no broad commits or resets.

## Review Focus

- Cross-company IDs and revoked roles must not yield a printable payload.
- A nonfinancial user must not recover hidden amounts through PDF export.
- Missing dates, zero quantities and source header/detail differences must remain distinguishable.
- Very wide tables and long content must retain every original field/row in legible pages.
- Access changes while preview/export is pending must prevent stale content export.

### Task 1: Authorized original operational print data

**Files:** Create `apps/erp_extensions/erp_extensions/migration/printing.py`; modify only the historical detail print capability in `migration/api.py` and the exact route allowance in `team_scope.py`; create `tests/test_migration_printing.py`.

**Interfaces:** `can_print(company, record) -> bool`; whitelisted `record_data(company, name) -> dict` as specified. Families job/yarn_receipt/yarn_return/production/delivery/subcontract require the corresponding Knitting Job or Knitting Event print permission. Other families remain unsupported here.

- [x] Add synthetic failing tests for supported/unsupported families, denied print, denied scope, financial masking, unchanged digest and managed-route denial for cashiers.
- [x] Run focused native tests and confirm the failures identify missing print behavior.
- [x] Implement the projection using existing detail filtering, retaining only the documented print keys and excluding raw data/links.
- [x] Expose `record_printable` on detail without changing the existing invoice `printable` meaning; allow the one reviewed route for managed accounts.
- [x] Rerun focused tests and existing historical invoice/store tests on native-test.localhost.

### Task 2: Operational PDF preview and export

**Files:** Create `apps/erp_client/lib/imported_record_pdf.dart`, `imported_record_preview.dart`, related tests; modify only the new print method in `imported_history_api.dart` and original-detail action in `imported_history.dart`.

**Interfaces:** `buildImportedRecordPdf(Map<String, dynamic> data) -> Future<Uint8List>`; `ImportedRecordPreviewScreen(api, company, name)`; `ErpApi.importedRecordPrintData(company, name)` calls `migration.printing.record_data`.

- [x] Add failing tests for source markers, exact zero/decimal values, missing original date, preserved effective date, all long-table rows, wrong company/name and revoked access during export.
- [x] Implement A4 source-copy PDF using bundled fonts and existing PDF libraries, preserving full readable content and repeating page identification.
- [x] Add preview/save/print with fresh authorized reads and access-revision checks before side effects, matching the existing invoice preview conventions.
- [x] Integrate the server-gated detail button; retain dedicated invoice action.
- [x] Run focused Flutter tests and analysis; render and visually inspect synthetic short, wide and long PDF examples.

### Task 3: Review and evidence

- [x] Independently review the scoped diff against the design, including permission paths and unchanged invoice behavior.
- [x] Resolve material findings and rerun affected checks.
- [x] Record exact tested scope and remaining legacy-layout/native/online limits; do not claim 100% parity.
