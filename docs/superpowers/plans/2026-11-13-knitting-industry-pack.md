# Knitting Industry Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add company-enabled knitting workflows to the shared Flutter ERP, with real server posting, consistent UI and purposeful motion.

**Architecture:** Extend the existing Frappe app with company setup, permission-scoped domain records and fixed transactional commands. Standard ERPNext controllers remain authoritative for owned inventory and financial posting; customer material uses a non-valued, immutable custody ledger. Add native task screens using shared components and the existing authenticated client.

**Tech Stack:** Existing Flutter 3.38.7/Dart 3.10.7, Frappe 16.55.2/ERPNext 16.54.0, MariaDB, built-in Flutter animation; no new product dependency planned.

**Spec:** `docs/superpowers/specs/2026-11-13-industry-packs-and-knitting-design.md`, `docs/design/WORKSPACE_EXPERIENCE.md`, `docs/coverage/knitting-acceptance.md`.

## Global Constraints

- Preserve general ERP and unchanged `upstream/`; no customer live access or copied vendor internals.
- Synthetic data on `native-test.localhost` only; explicit Docker context `colima-erp`; preserve all volumes.
- Authoritative Decimal quantities on server, decimal strings in the knitting API; fixed action registry, scoped references, source-version checks and idempotent atomic writes.
- Company-level enablement plus permissions; enforce direct/generic access, reports, files and prints, not just menus.
- Existing original notices and dependency/font licences remain intact; AI stays deferred.
- User approved continuous execution in the current workspace. Existing deployment mounts/launchers use this directory: use a dedicated feature branch in place, preserving the prior branch and app.
- Refine approved motion: no decorative entrance staggers or lifting cards; selection, route transitions, expansions and server-confirmed outcomes have shared, reduced-motion-aware behavior.
- Windows build requires Windows; physical devices/signing/providers and exact customer export parity cannot be invented.

## Review Focus

1. A role or pack revoked after login must deny subsequent writes and direct resource access without hiding permitted core ERP.
2. Mixed customer yarn and owned lycra must preserve finished ownership and post stock/cost only once.
3. Repeated or uncertain writes and simultaneous consumption must not duplicate rolls, deliveries, invoices or balances.
4. Cancellation, partial billing, source revisions and job closure must conserve quantities and submitted history.
5. Changing company or recovering a session must not leak cached financial values, overwrite drafts or replay writes; reduced motion must retain all meaning.

---

### Task 1: Industry setup and access policy

**Files:** Create `apps/erp_extensions/erp_extensions/workspace.py`, `knitting/install.py`, `knitting/permissions.py`, `knitting/__init__.py`, `tests/test_knitting.py`; modify `hooks.py`, `api.py`, `setup.py`.

**Interfaces:** Produces `workspace.context(company=None) -> dict`, `workspace.configure(company, settings) -> dict`, `knitting.install.install()`, `permissions.require(company, capability, history=False)`, query/document hooks. Context returns `version`, companies, selected company, setup state/revision and permitted capabilities. Settings include pack state, scoped operational policy and company-specific service/stock accounts/items.

- [ ] Write tests for general-only context, configured knitting company, operator/accountant capability boundaries, inactive/closing state, cross-company and direct generic access. Assert missing feature fails before implementation.
- [ ] Run real database tests: `docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml exec -T backend /home/frappe/frappe-bench/env/bin/python -m unittest erp_extensions.tests.test_knitting -v`. Expected RED for missing workspace/knitting behavior.
- [ ] Implement scoped setup/context and install schemas/hooks using normal Frappe permissions. New domain writes require an internal service context, never a caller flag. Keep the native catalogue compatible and filter pack types by context.
- [ ] Run new and existing backend suites. Expected PASS, no general ERP regression. Commit task files and ledger evidence.

### Task 2: Canonical material production delivery and invoice cycle

**Files:** Create `knitting/api.py`, `knitting/domain.py`, `knitting/posting.py`; extend schemas and `tests/test_knitting.py`.

**Interfaces:** Produces `api.snapshot(company)`, `api.command(company, action, payload, request_id, modified=None)` and `api.command_status(company, request_id)`; actions use a fixed registry and return persisted source records and decimal-string balances. Core actions: job create/revise, yarn receive/allocate/transfer/return/repack, produce, QC, roll split, deliver, invoice, close/reopen and cancel/correct. Own-stock and customer-custody adapters share one event identity.

- [ ] Write the exact service fixture in acceptance steps 1–14 plus owned-stock and mixed-lycra assertions. Add failed-post rollback, repeated request, changed-payload collision, stale source and last-balance consumption tests. Expected RED on unimplemented commands.
- [ ] Run targeted tests and inspect their actual failure.
- [ ] Implement immutable events/ledger, locked source checks and validated Decimal quantities; own-stock uses Stock Entry/Delivery Note adapters and invoice uses Sales Invoice controller. No customer-yarn valuation or double stock issue. Validate knitting links on standard document hooks too.
- [ ] Run service and owned/mixed scenarios against MariaDB; assert kg/counts, GL balance, source links and exact rollback/reversal effects. Run complete backend suite, commit and ledger.

### Task 3: Factory planning subcontract maintenance and estimates

**Files:** Create `knitting/factory.py`; extend `install.py`, action registry and backend tests.

**Interfaces:** Consumes Task 2 command/event transaction and posting adapter. Adds estimate-to-job, plan/replan, calendar, subcontract order/issue/receipt/return/bill/close, stoppage, consumable issue/return and component lifecycle actions. Snapshot includes queues and eligibility; all actions retain company/job/owner context.

- [ ] Add RED tests for A08, A14–A16, A25–A28: versioned quotation conversion; 100 = 99 + 1 repack; capability/overlap/holiday planning; SC quantity roundtrip; boundary/run/remaining kg and replacement history.
- [ ] Implement focused factory actions using the same canonical events and original ERP financial controllers. Test standard/bulk/multi-size entry through the same production logic.
- [ ] Run all backend tests, including direct permission denial and stale/cancel/retry cases for these actions. Expected PASS; commit and ledger.

### Task 4: Native company setup and connected knitting experience

**Files:** Create `apps/erp_client/lib/workspace_context.dart`, `knitting_models.dart`, `knitting_screen.dart`, `knitting_forms.dart`, `ui/workspace_ui.dart`; modify `erp_api.dart`, `main.dart`, `design.dart`, `widgets.dart`, and existing native page surfaces. Create `test/knitting_models_test.dart`, `test/knitting_screen_test.dart`, `test/workspace_context_test.dart`, `test/workspace_ui_test.dart`.

**Interfaces:** `ErpApi.workspaceContext({company})`, `configureIndustry(company, settings)`, `knittingSnapshot(company)`, `knittingCommand(company, action, values, requestId, {modified})`, `knittingCommandStatus(company, requestId)`; typed immutable company context and knitting projections. `KnittingScreen(api, context, onContextChanged)` uses command forms and source drilldown. Shared UI provides page/panel/actions/steps/table states and reduced-motion-aware state/route transitions.

- [ ] Write RED tests for decimal parsing/invalid values, role-based navigation, company switch clearing state, server failure retaining a form, uncertain command status and reduced-motion state updates. Layout tests at 390/834/1440 assert no overflow for all main views.
- [ ] Implement typed API and app integration: select company; show enabled knitting pack; provide real job detail/material/production/QC/delivery/billing/planner/factory/reports/setup routes. Real data and eligibility replace preview values; no dead primary action or browser fallback.
- [ ] Retrofit shared typography, action controls, status/error/empty states, panels and motion across overview, catalogue/list, editor/child rows, report, hierarchy, files/activity, settings and session recovery. Keep working field behavior and draft protection.
- [ ] Run `flutter analyze` and full `flutter test`; expected clean analyzer and passing tests. Run a real Dart HTTP cycle against test site; commit and ledger.

### Task 5: Operational reports prints and integration contracts

**Files:** Create `knitting/reports.py`, `knitting/exports.py`; extend native screens and tests; add safe print formats and `docs/coverage/knitting-integration-contracts.md`.

**Interfaces:** `api.report(company, report, filters=None)` returns columns, decimal-string rows, source refs and summary. `api.export(company, format, filters=None)` returns permission-checked bytes/content. Print uses current native PDF mechanism. Provider status remains Not configured until a verified provider exists.

- [ ] Write RED fixture assertions for job/yarn/fabric/roll/planning/production/QC/SC/component/stoppage/margin/billing reports, as-of versus period, field scope, export denial, fiscal/roll-label tokens, GST/Tally golden files and valid PDF.
- [ ] Implement report families over canonical records and standard ledgers. Define export schema explicitly and verify deterministic output; do not claim customer format parity without samples. Present actionable Not configured states for conditional statutory/payment providers without outbound calls.
- [ ] Run backend and Flutter suites plus print/export fixtures; expected matching source totals and permissions. Commit and ledger.

### Task 6: Full regression native walkthrough and release evidence

**Files:** Update `scripts/setup-native-test.command`, `scripts/erp-workspace.command`, app docs, coverage results and setup evidence; add repeatable safe fixture tooling under the extension/tool directory.

**Interfaces:** Demo seed and verification entry points refuse sites other than `native-test.localhost`; produce real persisted demo records for user exploration separately from rolled-back tests. Launcher validates current Mac app and preserves data.

- [ ] Run all server, Flutter and metadata suites. Exercise concurrent connections, rollback/duplicate/source checks, synthetic migration repeatability and backup/restore on disposable test fixtures. Record every remaining failure by name.
- [ ] Build Mac ARM64 release, iOS simulator and Android supported target with current toolchain; preserve Mac signing fix. Native Mac walkthrough must open the connected pack and complete the same job/stock/QC/delivery/invoice path, with truthful empty/error/session behavior and UI screenshots.
- [ ] Update all 232 scope entries by actual evidence, separating shared reuse, independent substitute, implemented, automated and native verified. Keep conditional hardware/provider/customer-sample and Windows/device checks explicit.
- [ ] Request one fresh whole-branch code review, fix material findings with RED→GREEN tests, rerun suites and save final evidence. Commit and finish without merging/publishing unless authorised.

## Plan review and execution

Self-review: all spec sections map to Tasks 1–6. Shared interfaces are context/capabilities (1→4), event/posting commands (2→3/4/5), response/report contracts (2/3/5→4), and evidence (all→6). All five Review Focus conditions have explicit scenario tests above. The user has already approved the design and instructed immediate continuous implementation; use native execution in this session without another approval question.
