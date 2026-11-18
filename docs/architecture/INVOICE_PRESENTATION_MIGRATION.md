# Invoice stationery and preview stage preparation

Invoice register is accepted; this stationery/preview gate is open. Exact
before-images are `.local/architecture-after-invoice-register/`. No settings,
preview, gallery or PDF implementation changes preceded this preparation.

This is Wave 6b from the original plan: company stationery settings, the pure
presentation gallery, native/sample/original-invoice preview and PDF rendering.
The financial composer remains a separate later gate. Existing root constructors,
template helpers and PDF functions remain compatibility exports. Preserve all
art, fonts, notices, labels, geometry, Hero continuity and source-copy behavior.

Extend the Invoice data implementation with separate settings/print contracts;
register fakes should not acquire unrelated methods. Validate and freeze scoped
read values; expose explicit editable settings copies. Keep tax, stock, payment
QR policy and financial review authority on the server. Rendering moves intact
into a service with an injected function; no domain layer is justified by file
movement or a forwarding call.

Settings models own loaded values, dirty/stale/uncertain state, revision and
attempt snapshots, logo validation outcomes and command serialization. The view
keeps controllers, form/focus anchors and leave/style dialogs. File selection,
image decoding and dimension/size checks use an injected service, preserving
all existing bounds and errors. Revalidation must retain an in-flight write's
busy token, and unknown saves must inspect the same attempted values/revision
before another edit.

Preview models own source identity (native invoice, original record or sample),
template selection, fresh render results, saved override and mutation/export
state. Characterize replacing company/API/invoice/source while a read, renderer,
picker or template write is pending. No old bytes or style may be published
under a new identity. Recheck permission and exact owner after platform waits;
use the established fresh-authorization pattern from Imported History. Native
print/save/share stays app-composed. A read refresh must not release an active
export/template-write token.

The gallery is already a pure widget; move it without adding a view model.
Keep the existing PDF body and art-direction part byte-identical apart from
canonical imports. Existing settings, UX, PDF, source-preview, register and
navigation tests characterize behavior; add missing scope/serialization cases
before risky changes and prove missing seams before implementation.

Run the complete stage gate: format, analyze, automated boundaries/checker
regressions, all unit/widget tests, explicit local-launch opt-out, connected
synthetic stationery/native/source/sample reads and saves, and independent
review. Connected work must select and verify `native-test.localhost`, use
fresh or explicitly staged synthetic fixtures and preserve all data/volumes.
Do not use the customer migration pilot, local customer profile or customer
source databases. Record physical printing/share and platform builds separately.
