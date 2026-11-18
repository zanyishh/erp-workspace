# Imported History Implementation Plan

> **For agentic workers:** Execute inline with test-first changes; preserve all existing workspace edits.

**Goal:** Open a separately configured local company workspace in the native app and expose immutable imported business history, preserving original dates and review notes.

**Architecture:** Version2 private launch profiles select a local site/account; authenticated server context supplies the permitted companies. Existing operational ERP screens remain available. A native history register/detail screen consumes the permission-scoped migration API and reuses the existing invoice PDF preview for supported source invoices.

**Tech Stack:** Existing Flutter/Dart, ErpApi transport, AccessGate, invoice PDF/printing dependencies; no new dependency.

**Spec:** User-authorized migration into the app, with separate demo workspaces, shared cash once per workspace, original records immutable, and effective opening dates distinct from source dates. Root coordinates provisioning and backend contract.

## Global constraints

- Client files only; no source access, target database writes, or customer values in tracked code/fixtures.
- Preserve the two version1 synthetic demo accounts and all existing dirty product changes.
- Local credentials go only to the configured literal loopback origin, without redirect/proxy forwarding.
- Company choices and financial visibility come from the authenticated server.
- Never route imported originals into editable document forms or label historical controls as posted balances.
- Source invoice printing requires explicit server permission and grounded source values; export rechecks access.

## Review focus

- Company/profile changes discard old account data and cannot show stale responses.
- Revoked financial permission hides cached lists/details and disallows printing.
- Original missing dates stay missing; effective dates display separately.
- Empty pages, malformed scope responses, and pagination errors do not masquerade as complete records.
- Back navigation returns to the same filtered register; narrow screens and large text remain usable.

## Task1: Local profiles

Files: local_workspace.dart, erp_api.dart, main.dart; tests local_workspace_test.dart.

- [x] Add failing tests for version2 profile selection, remote-origin rejection, and backward-compatible demo launch.
- [x] Implement version2 `{version:2, selected_workspace, workspaces:[{id,label,origin,site,account,key,secret,company}]}`.
- [x] Use only workspace id/label in profile choices; company choices come from workspace context.
- [x] Add a separate configured-local credential initializer restricted to literal loopback origins and local site names; keep version1 restrictions.
- [x] Test server-authorized four-company selection and switching back to a separate demo profile.

## Task2: Native imported history

Files: imported_history.dart, imported_history_api.dart, workspace_context.dart, main.dart, invoice_hub.dart, knitting_screen.dart, knitting_workspace_layout.dart; synthetic tests imported_history_test.dart.

- [x] Add failing register/detail tests for scope validation, search/paging, original/effective dates, review notes and back navigation.
- [x] Implement migration.api summary/records/detail/shared_cash transport methods using existing authenticated transport.
- [x] Render server-labeled fields and tables without raw JSON or technical provenance keys.
- [x] Add “Imported history” access from normal workspace, invoice and knitting navigation. Shared cash is a single workspace destination.
- [x] Clear/hide cached views on access change and reject stale company/family responses.

## Task3: Original invoice PDF

Files: invoice_preview.dart and imported_history.dart; synthetic PDF/widget tests.

- [x] Add tests for immutable source invoice preview, no template-save action, and export permission refetch.
- [x] Reuse existing PDF generator with backend-supplied source print schema; never derive missing unit rates or line identities in Flutter.
- [x] Preserve source reference and original date, label original copy/review notes, and expose no mutation action.

## Verification

- [x] Run focused workspace/history/invoice/knitting tests with synthetic fixtures only.
- [x] Run Flutter analysis and the full Flutter test suite; report any pre-existing failures separately.
- [x] Ask root or available sibling for a focused permission/navigation review before integration.

## Execution notes

- Existing shared worktree and dirty changes are intentional; do not create a checkout that drops them or commit another agent’s work.
- Provisioning, customer configuration, database installation and native-app integration checks belong to root; tests use fakes and temporary local files only.

## Fabric batch extension

- Use existing quality/delivery capabilities and confirmed, versioned command forms for `review_batch`, `deliver_batch` and `return_batch`.
- Batch and source-delivery selectors use bounded job registers; retain the selected native event and batch identity. Billing uses the server's expanded Delivery lookup.
- Display aggregate measured weight and roll count independently, including negative original stock. Never manufacture individual roll weights.
- Reject negative release in the form; show a review state instead of an unsigned-number exception in the job workflow. The server remains authoritative for quantities, availability and billing dependencies.
- Synthetic tests verify pagination, scope, explicit inspection choice, negative release, exact return references, independent quantities and the current job version.

## Verified result

- Full synthetic Flutter suite: 269 passed, one expected local-workspace opt-out skip.
- Focused batch/workflow/pagination suite: 52 passed.
- Source PDFs cannot change a template; export rechecks read permission. Missing original rates stop printing rather than being inferred.
- Actual target-site installation and native app smoke checks remain with root; no source connection or database mutation was made by this client task.
