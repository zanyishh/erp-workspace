# Complete Native ERP Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in this session, task by task. The user explicitly requested execution; AI and visual enhancement are deferred. Track uncompleted parity honestly and continue implementation without repeated approval questions.

**Goal:** Convert the installed ERPNext/Frappe feature set into connected native Flutter workflows, retaining backend business rules and the current UI.

**Architecture:** A small authenticated Frappe extension exposes catalogue, metadata, defaults, document operations and workflow/report services. Typed Dart models feed shared native lists and editors, with explicit adapters for specialised ERP flows. The pinned upstream checkouts remain untouched.

**Tech Stack:** Existing Flutter 3.38.7/Dart 3.10.7, Python/Frappe v16.55.2, ERPNext v16.54.0, local Docker/Colima.

**Spec:** `docs/superpowers/specs/2026-11-12-complete-native-erp-design.md`; builder check found nothing important left and confirmed source counts.

**Current checkpoint:** native foundation implemented; 71 Flutter tests, 38 real-backend tests and 4 metadata tests pass. Mac release, iOS simulator and Android builds pass. Foundation release live Mac checks passed after manual unlock and full-screen handoff. Native hierarchy increment passed review, all three builds and live Mac navigation/report checks; full specialised-feature parity remains unfinished. See `docs/setup/NATIVE_WORKFLOWS.md`.

## Global Constraints

- Native Create/Edit; browser handoff is not feature parity. No AI work or visual redesign now.
- Preserve upstream notices, source and evaluation data. Use `apps/erp_extensions/` and `apps/erp_client/`.
- Do not bypass ERPNext permissions, validation, workflow transitions, account/stock posting or integration hooks.
- Keep runtime ports localhost-only. Use named `erp` Colima profile/context; never delete data volumes.
- Keep credential/session data in memory; errors must not disclose stack traces or secrets. Do not auto-retry writes.
- Test writes on a separate local test site. Windows and physical-device checks require the appropriate host/device.
- Track metadata coverage separately from scenario verification; never mark untested features complete.

## Review Focus

- A forged payload cannot write hidden/read-only/permission-restricted fields or attach another parent's child row (Task 1 integration tests).
- A stale save cannot overwrite concurrent edits; validation failure retains native form entries (Tasks 1–3).
- Disabled/hidden dynamic fields, invalid numbers and unsupported client scripts are not silently treated as correct (Tasks 2–3/5).
- Network/session failure during save never invents success or causes automatic duplicate creation (Tasks 2–3).
- Financial/stock transitions call ERPNext controllers once and remain within the authorised site/company (Tasks 1/5).

### Task 1: Server contract and isolated verification

**Files:** `apps/erp_extensions/pyproject.toml`, `erp_extensions/{__init__,hooks,api}.py`, `erp_extensions/tests/test_native_api.py`; `infrastructure/erpnext/compose.yaml`, `scripts/setup-native-backend.command`.

**Interfaces:** API namespace `erp_extensions.api`: `catalog() -> {version,user,types,reports}`; `schema(doctype) -> {doctype,fields,children,permissions,single,submittable}`; `document(doctype,name=None,company=None) -> {doc,permissions,transitions}`; `save(document,action='Save') -> same`; `search_link(doctype,query,parent=None,field=None) -> [{value,label}]`; existing server exceptions remain authoritative.

- [x] Write backend integration tests for native master creation/edit persistence, denied permissions, read-only field injection, stolen child-row IDs and stale modified timestamps; observe missing-contract failure.
- [x] Implement the smallest authenticated API using existing Frappe metadata/defaults/controllers, explicit payload filtering and server validation. No guest access or arbitrary method dispatch.
- [x] Mount the extension on relevant ERP services, install it only on the separate local verification site, and preserve the original evaluation site (safer isolation after automatic-review rejection).
- [x] Run the tests against actual Frappe/MariaDB; record exact version/status and failures before continuing.

### Task 2: Typed native client contract

**Files:** `apps/erp_client/lib/native_models.dart`, `lib/erp_api.dart`, `test/native_models_test.dart`, `test/native_api_test.dart`.

**Interfaces:** `NativeField`, `NativeSchema`, `NativeDocument`, `NativeType`, `NativeReport`; `ErpApi.nativeCatalog/nativeSchema/nativeDocument/saveNative/searchLinks`. Child data is deep-copied; required/finite numeric validation is local feedback, server validation is final.

- [x] Write failing tests for schema parsing, safe edit copies, required/finite numeric validation, child order/identifiers, POST save payload and readable server validation/conflict errors.
- [ ] Implement models and API methods with existing in-memory SID. Reject malformed contract responses; no retry of writes. Run the full Flutter suite.

### Task 3: Native document editor and child/link controls

**Files:** `lib/document_editor.dart`, `lib/document_fields.dart`, `test/document_editor_test.dart`.

**Interfaces:** `DocumentEditor(api,doctype,name?,company?,onSessionExpired)` opens a native route; callback follows the saved document rather than a browser. `DocumentFields` edits one schema/document, including child rows and linked search.

- [x] Write tests for native Create→fill→Save, failed validation preserving input, duplicate-click prevention, dirty back navigation, child-row add/edit/remove and restricted fields.
- [ ] Render supported fields/sections using existing UI components. Add linked-record search dialogs, child editors, date/time pickers and clear inline errors. Unsupported special widgets must be labelled pending in coverage, not fabricated.
- [ ] Wire save, server-calculated refresh, submit/cancel/workflow review and reloading of saved data; run layout tests at 390/834/1440 and keyboard-constrained heights.

### Task 4: Complete permitted catalogue and native navigation

**Files:** `lib/native_catalog.dart`, `lib/main.dart`, `lib/module_browser.dart`, `lib/workspace_picker.dart`, related widget tests.

**Interfaces:** Native catalogue groups server-permitted types/reports by module; single settings open directly, record types open paginated native lists. Existing eight overview entry points use the same native editor.

- [x] Test menu/catalogue search, permissions, pagination, returning from a saved record, and all existing Create/Edit callbacks remaining native.
- [x] Connect the overview, modules, recent activity and New document picker. Keep the original browser application only as an explicit settings fallback. Run live Mac create/edit and reopening flows.

### Task 5: Reports, collaboration, files and specialised workflows

**Files:** `erp_extensions/api.py` and scenario tests; Flutter `report_screen.dart`, `document_activity.dart`, `workflow_actions.dart`; coverage ledger.

- [ ] Implement native report catalogue, structured filter schemas, results, drilldown, export and prepared-report status. Test financial/stock/project reports against known test fixtures.
- [ ] Implement attachments/upload/download/preview, comments/history, assignments, linked documents and print/export using the authenticated backend. Test private-file and permission handling.
- [ ] Inventory and implement explicit document mappings, item/party/tax defaults, returns, payments, stock/serial/batch operations, manufacturing/subcontracting, project/asset/quality/maintenance/CRM/support and approvals. Each adapter earns scenario evidence before completion.
- [ ] Implement dedicated POS/reconciliation/tree/calendar/kanban/import/bulk tools and installed integration settings/status. Preserve their existing hooks; no real external messages or payments in verification.

### Task 6: Feature parity, platform/runtime packaging and handoff

**Files:** `docs/coverage/`, `docs/setup/`, launcher/runtime packaging, platform hosts, end-to-end scenario tests.

- [ ] Every inventory feature has implemented adapter coverage or an explicit outstanding entry; no known blocking native flow remains. Verify feature dependencies as end-to-end scenarios, not only individual screens.
- [ ] Package/start/stop/restart and backend-unavailable recovery; preserve data and local-only services. Distinguish development preview from distributable installer.
- [ ] Analyzer/tests, macOS/iOS/Android builds, live Mac UI verification, independent whole-change review and relevant fixes. Windows/device executions remain explicit constraints until their hosts are available.
- [ ] Record remaining account/device constraints; retain all required notices and local checkpoints. Do not describe the whole rebuild as complete while Tasks 5/6 or known defects remain.
