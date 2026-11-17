# Flutter architecture migration implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan sequentially in this session. A fresh reviewer checks the final migration. Preserve existing uncommitted work; do not commit unrelated baseline changes.

**Goal:** Migrate the audited Flutter application to feature-first MVVM with repositories, services, explicit dependency injection and automated boundaries while preserving behavior and UI.

**Architecture:** [ARCHITECTURE.md](../../../ARCHITECTURE.md) is the design specification. Existing Flutter state primitives remain. Repository contracts hide `ErpApi`; view models own state/commands; domain policies are limited to complex/reused recovery and knitting rules.

**Tech stack:** Flutter 3.47.9, Dart 3.13.7, existing Flutter SDK state/futures/listenables and `flutter_lints`; ERPNext/Frappe on synthetic `native-test.localhost` only. Boundary tooling should use existing tooling or the standard library.

**Spec:** `ARCHITECTURE.md`; ADR `docs/architecture/decisions/0001-feature-first-mvvm.md`. The complete immutable pre-migration source/interface/test snapshot is `docs/architecture/2026-11-16-baseline-inventory.json`.

## Global constraints

- Do not modify code during the audit. Complete inventory, audit, specification, plan and ADR before the first application edit.
- Work from this dirty feature-branch baseline without discarding, resetting or committing unrelated user changes. No asset or upstream edits.
- Preserve current UI, navigation, labels, accessibility, motion, financial review/idempotency and backend semantics. Preserve state management.
- Use synthetic fixtures on `native-test.localhost`; no customer's live account or customer migration material. Keep services on localhost and never delete volumes.
- Sequential means one feature under extraction at a time. A red/unavailable verification gate blocks advancing to the next feature; diagnose it and record actual status.
- Characterization tests run and pass against old behavior before risky changes. New correctness/boundary tests must fail for the intended reason before implementation.
- After each feature: format, analyze, **all** unit/widget tests, checker tests, relevant connected integration rehearsal and review. Final completion also requires independent review of final source.
- Avoid dependency/framework changes. Keep constructor compatibility using thin adapters/exports while caller migration is in progress.

## Review focus

1. Same widget type/key receives another company, API or repository while a request is pending: no old result, token or busy state leaks.
2. Access is revoked or account changes during a read, file export or reviewed write: hide old data; preserve only safe recoverable references.
3. A write succeeds but response/acknowledgment is lost: check the same request, never create or post a duplicate.
4. A page contains duplicate IDs, empty rows or a stale out-of-order response: stable paging and errors; no fabricated zero totals.
5. Runtime-disabled knitting and non-financial staff: general ERP and permitted workflows remain usable without knitting-specific dependencies.

## Audit receipt

- [x] All 174 Dart files parsed; every source assigned one feature; 93 packages mapped.
- [x] All public top-level declarations and members, imports, parts, call sites and test declarations recorded with hashes.
- [x] Two import cycles, oversized methods and concrete scope gaps documented; unused symbols checked across the tree.
- [x] `ARCHITECTURE.md`, ranked audit, inventory, this plan and ADR produced before application changes.
- [x] Baseline analyzer: no issues, 22 seconds.
- [x] Baseline full-suite outcome recorded: preliminary attempts were interrupted and are not pass evidence. Old-feature characterizations and the required final-source full suite replace a duplicate full baseline run; see the progress ledger.

## Per-feature verification contract

From `apps/erp_client/` use the pinned selector (`python3 ../../scripts/flutter_toolchain.py`) for:

1. `--dart format --output=none --set-exit-if-changed lib test tool` (exit 0).
2. `--suppress-analytics analyze --no-pub` (no issues).
3. `--suppress-analytics test --no-pub --concurrency=4 --reporter=expanded` (every default unit/widget test passes).
4. Run `python3 scripts/check_flutter_architecture.py` and its regression tests from the root once introduced (zero violations outside the frozen migration baseline).
5. Run the connected test for the feature under the verified synthetic native-test profile. Store site, source hash, command, result and counts; never store passwords/tokens in receipts.
6. Review diff against the captured dirty baseline, including callers and public exports. Record remaining issues. Only then move to the next feature.

Logs live in ignored `.local/`; summarized receipts and the progress ledger live in `docs/architecture/MIGRATION_PROGRESS.md`. No automatically generated commit is required in this already dirty checkout. Review against source snapshots, not `HEAD` alone.

## Wave 0: Shared error seam and enforcement

**Files:** create `lib/core/models/erp_exception.dart`; adapt `lib/erp_api.dart` and `lib/knitting_models.dart`; create `scripts/check_flutter_architecture.py`, `scripts/test_flutter_architecture.py`, boundary manifest under `apps/erp_client/tool/architecture/`, and `.github/workflows/flutter-architecture.yml`.

**Interfaces:** preserve `ErpException` and `LoginVerification` constructor/field signatures and `package:erp_client/erp_api.dart` exports. Checker consumes Dart source and exact legacy edges; produces actionable diagnostics and nonzero exit on violations.

- [x] Verify audit receipt and unchanged application-source hashes; capture before-images in ignored `.local/` for review.
- [x] Add checker fixtures proving view→service, repository→view, view-model→widget, conditional export bypass, unknown file/layer and new cycle are rejected; a valid feature and shrinking baseline pass. Watch them fail before checker implementation.
- [x] Preserve public-import compatibility for the error seam, then extract shared errors and remove the API/model cycle. Existing API/knitting tests passed in the final-source full suite; no separate complete pre-extraction suite is claimed.
- [x] Implement exact dependency-direction checks, frozen legacy allowlist and CI format/analyze/unit-widget gates. The audit snapshot supplies exact legacy edges instead of a second boundary manifest.
- [x] Run the verification contract. Wave 0/1 accepted together; see the recorded 569-pass default suite, 14-pass opt-out variant and connected Task receipts.

## Wave 1: Task planner

**Files:** move implementation to `lib/features/tasks/presentation/task_planner.dart`; add `task_planner_view_model.dart`, `models/task_page.dart`, `data/task_repository.dart`, `data/erp_task_repository.dart`; keep `lib/task_planner.dart` as compatibility export. Tests: existing `test/task_planner_test.dart`, new task repository/view-model tests and scope characterization.

**Interfaces:** `TaskRepository.load({String? month, String? status, int start = 0}) → Future<TaskPage>` is company-scoped by construction. `TaskPlannerViewModel` owns calendar/date/status, page future, next-page merge, board grouping and date-range projection. `TaskPlanner` preserves `api`/`company` and additionally allows injected repository construction at the composition boundary.

- [x] Pin old behavior with existing calendar/board and new paging, error/retry and navigation characterization; repository/view-model tests cover immutable reads and date projection.
- [x] Add delayed API/company replacement cases; reproduce company replacement failure. API replacement already worked through AccessGate and is preserved.
- [x] Extract repository parsing and immutable page rows, then plain-Dart view-model state/commands without `BuildContext`; retain calendar controls and layout in the view.
- [x] Wire via constructors, preserve labels/navigation, replace dependencies on scope changes and enforce Tasks' strict boundaries. Preserve date/calendar/status selection.
- [x] Run verification contract and synthetic connected task read/date-projection rehearsal. Independent review's company gate issue was reproduced and fixed; whole-suite and opt-out gates pass.

## Wave 2: Pending operations

**Files:** `pending_operations.dart` → `features/operations/presentation/`; add `PendingOperationsViewModel`, `OperationRepository`, immutable operation status model; reuse `document_recovery.dart` policy only after characterization. Tests: `pending_operations_test.dart`, `document_recovery_test.dart`, new operation model/repository/view-model tests.

**Interfaces:** `OperationRepository` exposes list/status/close/acknowledge, never a business-write method. View-model commands return statuses; the view handles document navigation and confirmation text.

- [x] Pin old recovery/no-replay/paging/completion behavior; reproduce refresh-busy and company/access races before extraction. New unit fakes cover serialization, failed acknowledgment, raw offsets and disposal/scope.
- [x] Extract repository and view model. Keep existing ledger IDs and no-replay semantics; no generic retries.
- [x] Run verification contract including synthetic prepare/status/close/acknowledge checks: 583 default tests, 14 opt-out tests, no analyzer issues, clean review, connected check and unchanged source hashes.

## Wave 3: Team, authentication and workspace

**Files:** `team_access.dart`, `sign_in.dart`, `session_recovery.dart`, `local_workspace.dart`, `workspace_context.dart`, `workspace_picker.dart`, relevant shell methods in `main.dart`. Add `TeamRepository`/`TeamAccessViewModel`, `SessionRepository`/auth view models, `WorkspaceRepository`/workspace view model and local profile service under their owned features/core services.

**Interfaces:** keep existing `WorkspaceShell.connect` and local-opening callbacks; preserve `ErpApi` login/OTP/error behavior through the session adapter. Team token is ephemeral state owned by a single account/company/scope.

- [x] Pin invitation results and delayed token invalidation, role selection, revoke confirmation, OTP, portal restriction, local profile checks and company access refresh. Use existing onboarding, access-refresh, local-workspace and workspace-picker tests plus new unit fakes.
- [x] Migrate **team first**, complete the full gate; then authentication; then workspace. These are separate feature gates, not a combined edit.
  - [x] Team access: accepted; 600 default tests, 14 opt-out tests, two connected onboarding cases, clean analysis/format/boundaries and reviewed serialization fix.
  - [x] Authentication: accepted; 616 default tests, 14 opt-out tests, two connected onboarding cases, clean format/analysis/boundaries and independent review. Measured bounded serial validation handled local storage pressure without deleting data.
  - [x] Workspace: accepted; 638 default tests, 14 opt-out tests, three connected checks, no analysis/format/boundary issues and reviewed regression fixes.
- [x] Extract access observation/revalidation and authentication presentation ownership after characterizing listeners/recovery. Preserve access revisions and no write replay. Authenticated transport I/O stays behind the session repository; the broader endpoint/transport decomposition retains its final Wave 10 review.
- [x] Run each feature's verification contract; connected `tool/pilot_onboarding_test.dart` covers synthetic signup/invitation and company-scoped destinations. No customer pilot is authorized.

## Wave 4: Overview, catalog and reports

**Files:** `overview.dart`, `sales_chart.dart`, `module_browser.dart`, `erp_models.dart`; then `native_catalog.dart`, `native_tree.dart`, `master_import_screen.dart`; then `report_screen.dart`, `report_chart.dart`, `native_reports.dart`.

**Interfaces:** `OverviewRepository` preserves company/period snapshot semantics; `CatalogRepository` owns types/records/tree/import policy; `ReportRepository` owns definitions/run/queue/export model. Corresponding view models expose immutable read results and commands.

- [x] Pin permission-unavailable totals, date/currency filters and retained-result scope; migrate overview and run full gate. Accepted: 652 default tests, 14 opt-out tests, connected two-company reads, clean analysis/format/boundaries and independent review.
- [x] Pin hierarchy pagination/group changes and CSV preview/apply behavior; migrate catalog and run full gate. Accepted: 689 default tests, 14 opt-out tests, synthetic hierarchy/import check, clean format/analysis/boundaries and independent review. Shared document navigation remains a callback/approved adapter.
- [x] Pin filter payload, queue/error behavior and CSV/chart rendering; migrate reports and run full gate. Accepted: 711 default tests, 14 opt-out tests, six synthetic report runs, clean format/analysis/boundaries and independently reviewed export fix.
- [x] Use existing overview/module/catalog/tree/report/model tests and fresh native-test-only Catalog/import/Reports verifiers. The new Catalog verifier replaces reliance on arbitrary pilot directories. No arbitrary upstream script was executed.

## Wave 5: Imported history

**Files:** all six history-owned libraries from the baseline inventory plus invoice-preview adapters. Add history repository/read models/view models; split shared history formatting/response validation from navigation to break the history/report cycle.

**Interfaces:** `ImportedHistoryRepository` exposes summary/page/detail/filter-options/production/shared-cash/print data. Responses retain version, company and source-job filter/label contracts. History does not write source records.

- [x] Pin every existing imported-history, source-job, original-production and PDF test before extraction, including malformed/scope-mismatched data, negative quantities and original dates.
- [x] Extract models/validation and repository, then migrate register/detail, production report, filters and original-record preview in that order within the single read-only History feature. Run the full feature gate when it is finished; see `docs/architecture/HISTORY_MIGRATION.md` for the cycle/cohesion rationale. Inject routes instead of circular view imports. Financial invoice/document migrations keep their separate risk gates.
- [x] Verify with newly created synthetic history fixtures only. Existing customer migration pilot/material is not authorized for this work; mark connected verification unavailable until synthetic fixtures cover the contract.

## Wave 6: Invoices

**Files:** nine invoice-owned libraries; `invoice_api.dart` remains endpoint adapter until consumers migrate. Add invoice register/settings/preview/composer view models and `InvoiceRepository`; keep PDF layout/art in its own rendering service and bundled assets unchanged.

**Interfaces:** repository preserves defaults/review/save/request-ID/print/settings/template methods. Server review/tax values stay authoritative. Composer exposes draft/validation/command results; focus and route decisions remain in the view.

- [x] Migrate the register and pass its full gate (769 tests, 14 opt-out tests, fresh synthetic connected check and independent review).
- [x] Migrate settings/gallery/preview and pass its full gate (801 default tests, 14 opt-out tests, fresh complete-fingerprint native/PDF check and independent review).
- [ ] Migrate the financial composer as a separate gate; run the full verification contract.
- [ ] Pin debounce/page/search/status scope, template settings, logo validation, payment/government QR rules, lost-save response and acknowledgment timing with existing invoice tests plus new repository/view-model tests.
- [ ] Keep request ID and review token across uncertain outcomes. Verify new/draft/reprint and cross-company defaults through the fresh, guarded `tool/verify_invoice_presentation_test.dart` and targeted native tests. Do not use the existing local-profile-dependent company pilot or customer material.

## Wave 7: Documents and file/platform seams

**Files:** all document-owned libraries plus `file_actions.dart`/shared UI. Add document repository and editor/form/activity view models. Extract shared recovery policy only where duplicate real behavior is proven; keep dynamic schemas/conditions and explicit edit copies.

**Interfaces:** repository preserves schema/document/new-from/default/prepare/save/transition/attachment/activity contracts. View models expose errors with field paths; view owns focus anchors, dialogs and row editor navigation.

- [ ] Run existing native-model/condition/row-safety/editor-access/document-interaction/recovery/specialized-field tests as characterization. Add tests for mutable read vs draft copies and replacing scope mid-defaults/save/export.
- [ ] Extract editor loading first, form/defaults next, writes/recovery next, activity/files last, each with the full gate. Preserve empty child-row, modified timestamp and ambiguous-write behavior.
- [ ] Verify `tool/pilot_specialized_fields_test.dart` and synthetic `tool/verify_native.dart`; retain legal notices/assets and platform save/share behavior.

## Wave 8: Banking and point of sale

**Files:** `bank_statement_import.dart`, `bank_statement_matching.dart`, `payment_reconciliation.dart`; separately `pos_checkout.dart`. Add banking repositories/view models and POS repository/view models; share only established operation-domain policy.

**Interfaces:** retain decimal-string balances/expected amounts, review tokens, ledger/request identity, shift and account scope. No cross-repository dependency; multi-source coordination is a view-model/domain concern.

- [ ] Pin all existing banking/POS tests plus delayed-scope, double-tap, lost-write and completion-before-close cases.
- [ ] Migrate CSV import, bank matching, payment reconciliation and POS as separate full gates, in that order. Keep confirmation dialogs and receipt rendering unchanged.
- [ ] Run `tool/verify_pos.dart` and synthetic bank/allocation rehearsals; assert `native-test.localhost` before mutation. Never use actual bank/customer data.

## Wave 9: Knitting industry pack

**Files:** all 12 knitting libraries plus API adapter and pack-related shell composition. Add knitting repository/read models, workspace/register/setup/report/command view models. Move action metadata, `Kg` policy and command/recovery state out of widget libraries; keep form controls/icons/layout in presentation.

**Interfaces:** preserve capability strings, `KnittingSnapshot`, `KnittingDraft`, `CommandState`, action IDs/payloads, original-machine/operator labels, programme/source IDs and request-ID status behavior. No general-ERP dependency on knitting-specific repositories.

- [ ] Use all knitting tests and synthetic tool verification as characterization. Add isolated domain/view-model tests for quantities, source capacity, late scope responses and unknown outcomes before extracting each rule.
- [ ] Migrate overview/registers, reports, setup, navigation and command forms in that order, with a full gate after each. Split UI by existing responsibility, not a maximum line count.
- [ ] Connected `tool/verify_knitting.dart` and synthetic mill pilot cover production/QC/custody/delivery/invoice/return/recovery; do not use customer migration tests or customer fixtures.

## Wave 10: Composition, cleanup and final review

**Files:** `main.dart` → entry point plus `app/`; shared `core/ui`; remaining compatibility exports, manifest, CI, architecture docs.

**Interfaces:** composition root owns lifetimes and injects repository interfaces; old public imports remain exports until all tests/tools/callers use canonical paths. Shared UI is independent of feature business models where practical.

- [ ] Pin shell navigation, general/knitting-enabled and disabled states, company replacement, session expiry and returning-account selection with current shell/access/navigation tests.
- [ ] Move composition without replacing router/state framework. Remove each legacy edge/allowlist only when its consumer migration passes. Recheck dead code and delete confirmed unused helpers.
- [ ] Fail CI on new cycle, forbidden import, legacy implementation growth or obsolete baseline exception. No remaining broad exceptions at completion.
- [ ] Run formatter, analyzer, boundary tests, complete unit/widget suite and all relevant synthetic connected rehearsals against the final source. Record platform builds separately; Windows remains unverified without a Windows host.
- [ ] Independent review of the final change against the original dirty baseline, plan, public contracts and verification receipts. Fix material findings with failing regression → fix → full gate.
- [ ] Update architecture docs and migration ledger with actual results. Claim completion only when every applicable gate passes and review is clean.
