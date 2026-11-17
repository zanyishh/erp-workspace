# ERP UX corrections implementation plan

> **For agentic workers:** Use the subagent-driven-development workflow with the file ownership below. Steps use checkboxes to track completed work.

**Goal:** Implement the researched interaction corrections throughout the existing Flutter app, prioritizing work retention and safe outcome recovery.

**Architecture:** Extend existing shared forms, state handling and motion. Preserve the existing server authority, permissions and industry-pack boundaries. Use durable server-side operation references for restart recovery rather than retaining financial drafts in an unprotected local cache.

**Tech Stack:** Flutter 3.38.7, Dart 3.10.7, ERPNext/Frappe and the existing Python extension.

**Spec:** `docs/research/2026-11-16-erp-ux-research.md`, `docs/research/2026-11-16-erp-ux-audit.md`, and the approved industry-pack design.

## Global constraints

- User explicitly authorized continuous implementation without another approval round.
- Preserve existing dirty work on `feature/knitting-industry-pack`; a pre-change source snapshot is in `.local/ux-implementation-2026-11-16/baseline`.
- Connected verification only uses synthetic records on `native-test.localhost`; explicit Docker context `colima-erp` and named launchers. Do not use the customer launcher or customer profile.
- Server/site is the tenant boundary. Recovery, views and defaults remain site/account/company scoped and revalidate permissions.
- Do not fetch, render or persist financial-read-restricted values to construct reviews or receipts.
- Keep original ERPNext behavior, industry-pack permissions and authoritative quantity/money calculations. AI remains deferred.
- Motion communicates navigation/state/confirmation. No ornamental entrance staggers, card lifting or invented progress/success.
- No changes to `upstream/`, application volumes, global MCP configuration or unrelated product dependencies.
- Native Windows verification requires Windows; mobile compilation is not device usability verification.

## Review focus

1. Lost responses after committed writes: preserve request identity and reconcile instead of inviting a duplicate operation.
2. Account/company/site and access changes during requests: clear protected content and ignore stale responses.
3. Hidden invalid form fields and child-row errors: reveal/focus them while preserving all other input.
4. List refresh, paging and edited report filters: retained data is explicitly tied to its applied scope and export.
5. Large text, narrow windows, keyboard-only use and reduced motion: complete the same meaningful task without clipped controls or stolen focus.

## Task 1 Protect drafts and recover operations

**Files:** invoice_composer.dart, knitting_forms.dart, knitting_models.dart, payment_reconciliation.dart; new shared recovery UI; erp_api.dart/invoice_api.dart; relevant server operation/save/reconciliation/knitting modules and tests.

- [x] Add failing invoice tests: Back keeps edited values unless explicitly discarded; in-flight navigation cannot abandon a write; template-only changes are dirty; uncertain state cannot be silently lost.
- [x] Implement the shared leave treatment, precise field validation and draft-row Undo in invoice/POS entry.
- [x] Confirm existing receipt contracts; implement minimum server-side pending references and idempotent status support for native saves, workflow transitions, invoice saves, knitting and reconciliation where needed.
- [x] Make pending operations discoverable after restart, permission filtered, and never replayed automatically. No financial payload cache.
- [x] Test retry with the same identity, changed payload rejection, committed/lost response, missing/not-started result, in-flight checks, permission denial and user/company/site separation.

## Task 2 Shared form and error correction

**Owner:** form agent. **Files:** document_fields.dart, document_editor.dart, new form-specific helpers and their tests. Other agents will not edit these files during this task.

- [x] Test and implement meaningful schema sections/disclosure without hiding required fields, errors or unauthorized-field boundaries. Keep expert direct access.
- [x] Test and implement first-error focus/scroll, field-specific messages and an accessible error summary after explicit submit.
- [x] Test and implement debounced linked-record lookup, latest-query protection, stale-choice prevention and retry with retained query.
- [x] Test and implement exact Undo for local child-row removal, retaining identity/order.
- [x] Improve general submit/cancel review using only permitted values already supplied by the server and invalidate changed reviews.
- [x] Integrate the agreed operation-recovery API once Task 1's server contract is available; confirmed rejection remains editable, uncertain operations require reconciliation.

## Task 3 Retained navigation and results

**Owner:** navigation agent. **Files:** main.dart, module_browser.dart, native_catalog.dart, invoice_hub.dart, report_screen.dart and their tests.

- [x] Test search/page/row context after record open/return and implement refresh without unrelated remounts.
- [x] Retain same-scope loaded lists during refresh with clear progress/stale errors; clear on site/account/company/access changes and ignore superseded results.
- [x] Test report filter edits keep old applied result and summary; rerun replaces both atomically; export never mixes pending filters with old rows.
- [x] Add platform-appropriate command modifiers, hints and focus behavior.
- [x] Reserve a shell entry for the shared pending-operation screen supplied by Task 1; coordinate integration with the root agent.

## Task 4 Cross-app accessibility and purposeful motion

**Owner:** root after tasks' shared contracts settle. **Files:** design.dart, widgets.dart, ui/workspace_ui.dart, knitting field/layout/workspace files, report/sales chart consumers as needed, documentation and regression tests.

- [x] Standardize actionable accessible feedback, target/focus behavior and readable metric layout; verify large values and 200% text without shrinking critical numerals.
- [x] Add date/time pickers alongside typed knitting entry and signed numeric input with strict validation.
- [x] Implement selective record identity continuity with a static reduced-motion fallback and retained source context.
- [x] Inspect remaining entry/settings/import/bank/history surfaces for the same protections; reuse shared changes instead of duplicating a parallel design system.
- [x] Reconcile the stale motion documentation and record C01–C60 as implemented, retained or explicitly verified/applicability-limited with evidence.

## Task 5 Verification and review

- [x] Run focused regression tests, then full Flutter tests with bounded concurrency and analysis.
- [x] Install/reload extension changes through the isolated test-site launcher, run affected server tests and an end-to-end connected Flutter rehearsal on `native-test.localhost`.
- [x] Build macOS and inspect the actual native app using only the synthetic test configuration; record screenshots and reachable state checks.
- [x] Obtain an independent implementation review against the pre-change snapshot; resolve material findings and rerun affected checks.
- [x] Save verification evidence and platform limitations in `docs/setup/UX_RUN_2026-11-16.md`. Do not claim Windows/device or screen-reader checks not actually performed.

## Execution rulings and progress

- Use the current feature workspace because the authorized app already exists in its uncommitted state; creating a clean checkout would omit that work. The baseline snapshot permits scoped review without staging or committing unrelated changes.
- Independent tasks may proceed concurrently under disjoint ownership; heavyweight Flutter/backend runs are serialized on this 8 GB Mac.
- Research instructions are acceptance criteria, not an instruction to add every possible feature. Preserve correctly implemented patterns and verify them; fix the 16 demonstrated findings and shared consistency gaps.
- Baseline source snapshot contains 317 files. The initial full Flutter run was intentionally stopped after 72 passing cases with no reported failures, to prioritize targeted regressions; this is partial baseline evidence, not a full-suite pass.
- Active ownership: operation_contract handles server/API recovery; form_corrections owns generic forms/editors; navigation_corrections owns shell/lists/reports; root owns invoice/POS/knitting UI and shared accessibility/recovery UI.

- Focused implementation verification completed for shared forms, navigation/reports and POS; the import/settings/payment batch passed 36/36. Full integration analysis/tests, connected UI rehearsal and native macOS verification subsequently completed as recorded below.
- Independent review corrected delayed preparation/status responses after company/form round trips. Native journaling explicitly opts out of 11 proven internal-commit administrative controllers plus virtual doctypes, retaining their original save path.
- The native verification launcher uses a separate app identity and the explicit synthetic loopback service; it bypasses saved local/customer profiles.

- Integrated Flutter suite passed 543 tests with one configuration-specific skip. The explicit local-launch opt-out case passed separately with the same flag used by the isolated native build. Final review added inherited access-scope invalidation for lookup overlays and corrected the bounded legacy-receipt preparation edge before the successful connected rehearsal.

- Final backend aggregate passed 71/71 after legacy invoice/knitting receipt-race correction. Connected UI rehearsal passed 2/2 on the refreshed synthetic site, recovering one real write per invoice/customer/knitting operation. A delayed invoice-default readiness gap discovered during rehearsal was corrected and passed 12/12 affected invoice tests. Final whole-app Flutter analysis reported no issues.
- The macOS release build and native synthetic-site walkthrough completed. Eleven screenshots record general ERP and knitting compact layouts, required-field correction, unsaved-work protection, operation receipts, template preview navigation and retained invoice search. Native shortcut automation was inconclusive; the report explicitly separates that limit from passing widget tests. Verification evidence and remaining platform/accessibility limits are recorded in `docs/setup/UX_RUN_2026-11-16.md`.
