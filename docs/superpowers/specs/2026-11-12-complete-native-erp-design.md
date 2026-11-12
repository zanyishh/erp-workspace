# Complete native ERP rebuild

## Intent and authorization

The user explicitly requested rebuilding everything into a complete Flutter app, all integrations, verification before declaring completion, and postponing visual enhancement. The current overview and eight lists are insufficient: opening Create/Edit must stay within Flutter. Continue building without repeated implementation approval questions. Retain the current reference-led design.

## Scope and completion rule

The pinned source contains 534 ERPNext and 301 Frappe DocTypes (835 total, including 364 child tables and 63 single settings records), plus 198 report definitions. Inventory is a source count, not proof of usable features. Existing installed apps are ERPNext and Frappe; HRMS and other separately installed apps are not present.

The product must provide native navigation/search across permitted record types, native creation/editing, child rows, linked record search, save/submit/cancel/amend, workflow approvals, reports/filters/export, attachments, comments/history/assignments, printing, settings and installed integrations. All business validation, account/stock posting, permissions and integration hooks continue to execute in ERPNext. Do not duplicate accounting math in Dart or bypass permissions to make a form work.

Track metadata coverage, workflow implementation and workflow verification separately. Never equate generic form rendering with complete business parity. In particular, ERPNext JavaScript field events, mapped documents, tax/item defaults, POS, reconciliation, tree/calendar/kanban pages and external-provider handoffs require explicit adapters and scenario verification. Preserve those as outstanding work until verified; never silently substitute a browser or unsupported field for a completed native workflow.

## Architecture

- Keep upstream source unchanged. Add a small GPL Frappe app under `apps/erp_extensions/` exposing a versioned native-client interface around existing Frappe document/permission/report APIs. No guest access, no ignore-permissions document mutations, no arbitrary code execution or arbitrary RPC entry box.
- Reuse the Dart client's in-memory authenticated session. Add typed metadata/document models and native record type/catalog, editor, child-row, linked-record and report screens. Native navigation replaces browser callbacks. Original browser application remains available only as an explicitly named administrative fallback, never the default Create/Edit path.
- Get new-document defaults from Frappe, evaluated permissions from Frappe, and field metadata from the current server including custom fields. Keep the document's original modification timestamp; stale saves must fail without overwriting another user's work.
- Server-side preparation uses existing document-controller methods for defaults and totals. Dispatch only reviewed operations by name; do not trust a caller-supplied Python method path. No submit/cancel side effect in a preparation/read call.
- Unknown client-only behavior must remain visible in the coverage ledger rather than being marked implemented automatically. Field dependency expressions are data, not executable trusted instructions; no general eval in the client.
- Use a backend extension mount consistently across API, workers, scheduler and configurator so restarts retain installed functionality. Keep localhost bindings and existing named data volumes. Preserve original evaluation data.

## Native form behavior

Render labelled sections/tabs and supported scalar fields using the existing palette and fonts. Support text/numbers/dates/times/checks/select/link/dynamic link/password/long text/JSON, structured child tables and settings. Numbers must reject nonfinite/invalid values. Child rows retain their server identifiers and order. Sensitive masked values must not be guessed or overwritten. Hidden/read-only/permission-restricted fields are not made editable. Server validation messages are displayed as plain text; stack traces and secrets are not shown.

Create/Edit remains open on a native route. Dirty navigation prompts preserve work. Save is one explicit operation with duplicate clicks disabled; failure preserves entered values. Submission, cancellation and workflow actions require a clear in-app review; the server rechecks permissions and workflow rules. Do not offer irreversible deletion as an incidental demo action. New form data and originals must not share mutable nested structures.

## Integrations

Preserve all installed ERPNext integration hooks and surface their settings/status natively. Do not invent credentials, enable outbound mail/payment services, send messages or charge real accounts during verification. Test using an isolated local test site. The user explicitly deferred all AI work until ERPNext feature parity is complete, followed by UX planning. AI is outside this rebuild. No provider, agent controls or AI scaffolding should be added.

## Verification and packaging

Tests must cover metadata parsing, numeric/required validation, child edits, linked search, permission denial, stale writes, server validation messages, save persistence and submitted-document protection. Exercise real end-to-end test-site scenarios for master data, sales/purchase/stock, manufacturing/project/asset/quality, approvals/reports/files and configured integration hooks. Report scenario results, not only widget counts.

Build on macOS, iOS simulator and Android with installed tools; execute native Mac flows. Windows requires a Windows host and device execution needs devices; neither can be declared tested from generated files. Final packaging must distinguish a development launcher from a distributable installer and must handle backend availability. A universally error-free guarantee is impossible; completion requires no known blocking defects and explicit tested coverage/remaining host or account constraints.

## Builder decisions

Use the existing Flutter 3.38.7/Dart 3.10.7, Python/Frappe versions and UI components. Prefer a small direct REST interface to additional client frameworks. Work in the existing project directory on a new feature branch because launchers/runtime mounts and the shared user preview use this path. Execute tasks in this session. Preserve licenses and date modification notices. External AI/provider selection remains the user's decision; no other implementation reconfirmation is required by this request.
