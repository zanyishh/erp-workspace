# Document editor stage preparation

Do not change document implementations until the Invoice composer frozen gate
is accepted. Capture its accepted before-images for the next sequential gate.
The original audit inventory remains the immutable public-interface baseline.

The existing `document_editor.dart` combines `DocumentEditor` and the public
callback-driven `NativeDocumentForm`. Its editor reads the form's private `_doc`
and `_data` through a typed private global key; the form also consumes the
editor's recovery receipt for rendered acknowledgment. Loading, retained drafts
and write reconciliation therefore share one lifetime and cannot be moved as
independent complete components without temporary cycles or new legacy escapes.

Treat editor loading, form state/default coordination and write/recovery as one
cohesive editor migration, testing each new seam before wiring. Run the full
gate when this pair is migrated. Dynamic field controls/row editors and their
default/condition policies, then activity/files/platform behavior, remain later
sequential gates within Documents. Update the execution plan to this dependency
order before implementation; do not add an `app/legacy` escape, a new import
exception or a service locator to simulate separation.

Preserve both public constructors and all callbacks, direct-form embedding,
schema/document/new-from inputs, tree parent, source origin, create callback,
fresh server authority, field paths and existing UI. App composition owns the
legacy-compatible API constructor, routes, native field-control builder and
platform callbacks. Canonical views receive models and small UI callbacks;
they do not import legacy API/form libraries. A UI focus/error handle can bridge
existing controls until their next gate, without moving controllers into data
or exposing private widget state to a repository.

Use company/doctype/document/origin-scoped repository contracts and immutable
read snapshots, with explicit mutable draft copies. Do not globally freeze
every `NativeDocument`/schema constructor in one edit: existing standalone
callers and fake services rely on their current edit-copy contract. Characterize
the concrete repository's freeze boundary and preserve public shared-model
factories while introducing any narrowly scoped read-only construction helper.

The form model owns validation results, dirty/stale/uncertain state and draft
revision. Its retained-edit merge is real domain policy: visible/locked fields,
submitted-document rules, stable child names, unsaved row identity, deleted
server rows and newly added server rows must remain equivalent. Extract this
policy with before/after fixtures instead of rewriting it. UI keeps controllers,
focus, field anchors, dialogs and navigation. General ERP form logic must not
depend on knitting repositories; industry-specific handoffs stay app-composed
through the pack contract.

Use the now-tested financial lifetime rules in `ARCHITECTURE.md`: immutable
attempts and capability mode, independent read/write generations, same-owner
unknown results, rendered acknowledgment before disposal, stale confirmation
lease recovery, safe durable departure without ready access and owned-dialog
cleanup. Compare the existing `DocumentOperation` contract before extracting a
shared/domain policy: native document receipts, modified timestamps, non-atomic
inspection and closure behavior differ from Invoice composer receipts.

Run existing native model/condition, row safety, editor access, document
interaction/recovery, specialized field, operational handoff and scope tests
unchanged before risky extraction. Add delayed company/API/document/origin,
mutable-read/draft-copy, defaults, receipt, dialog and write-scope regressions
before fixing gaps. Do not count fixture setup failures as product RED.

Every accepted gate requires format, whole-app analysis, all default unit/widget
tests, explicit local-launch opt-out, boundary/checker tests, synthetic connected
rehearsal and independent source review. Create fresh guarded native-test-only
companies and documents; do not alter accepted invoice/history fixtures or use
local-profile-dependent/customer pilots. Keep a submitted financial transition
distinct from draft-only verification and report actual GL/stock effects.
