# Invoice financial composer stage preparation

Wave 6c starts only after the separate stationery/preview gate is accepted.
Capture the accepted source as the exact before-image; do not compare only to
the repository commit because the original working tree was already dirty.

The 986-line composer combines draft editing, numeric validation, server review,
request identity and recovery, link queries, focus, dialogs and navigation.
Preserve its public `InvoiceComposer(api, company, templateId)` constructor,
labels, layout, keyboard focus, leave confirmations and full-editor handoff.
Preserve the existing state primitives and server-owned totals/tax authority.

Use a separate composer repository contract so register/settings/preview fakes
do not acquire unrelated methods. It owns company-bound defaults, link reads,
review, prepare/save/status/close/acknowledge and template metadata calls. Fence
reads before and after access changes, freeze read values, and snapshot mutable
drafts before asynchronous calls. A completed write may have committed; do not
invent a rejection after its response because access changed.

The model owns explicit draft copies, line identities, validation outcomes,
server review, selected style, busy/uncertain/prepared state, immutable attempted
payload and review token, and the durable request ID. Inputs cannot change while
a save is pending or uncertain. An exact retry must reuse all three: payload,
review token and request ID. Preparation failure cannot send a business write.
Completed preparation/closure must reconcile a saved result before deciding it
is safe to edit. Review/defaults refreshes cannot release an active write token.

Keep focus nodes, date/leave/advanced dialogs, scroll anchors, snackbars and
navigation in the view. App composition owns the old API constructor and full
document-editor route. Link selection is an injected callback. A saved receipt
must reach a rendered confirmation before acknowledging its durable reference.
Capture owner, access and intent around dialogs/routes so returning from an old
company cannot style or dismiss a replacement company's composer. Row removal
and Undo retain stable identities and respect the current owner/access scope.

Existing `invoice_composer_test.dart` and `invoice_ux_test.dart` cover style
inheritance, exact retry, delayed defaults, round-trip preparation, lost-response
status, closure, preparation failure, busy navigation and field focus. Run them
unchanged against the old implementation. Add missing pending-owner/defaults,
advanced-editor return, stale review and serialization characterizations before
source extraction. Prove new repository/model seams missing before implementation.

No domain layer is justified for a forwarding endpoint or file movement. Retain
feature orchestration in the model. Extract a shared recovery domain policy only
when the later document migration proves equivalent repeated behavior and can
preserve its distinct native-document receipt and closure contracts.

Run formatting, whole-app analysis, every default unit/widget test, the explicit
local-launch opt-out, boundary checker regressions and independent review. Use
fresh guarded synthetic composer companies/customer/service item on the exact
verified native-test site for real review/draft/status/idempotency/navigation
checks. Do not add invoices to the accepted immutable register or presentation
fixtures. Assert draft-only effects and zero financial/stock postings; retain all
test data. The local-profile-dependent pilot and customer material are excluded.
