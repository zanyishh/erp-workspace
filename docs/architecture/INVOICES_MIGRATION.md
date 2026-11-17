# Invoice stage preparation

Register stage accepted 17 November 2026 after independent review, 769 default
tests plus one conditional skip, 14 opt-out cases and connected synthetic
verification. Settings/gallery/preview and composer remain open. See
`MIGRATION_PROGRESS.md` for exact receipts and before-images.

The Invoice feature owns the register, templates/gallery, company stationery
settings, source/native/sample preview, PDF renderer/art direction and composer.
The nine libraries total about 4,800 lines; endpoint methods remain on the
shared authenticated service until final transport extraction.

Migrate register first, settings/gallery/preview next, composer last, with the
complete feature verification contract at each risk gate. These are separate
from generic Documents and financial banking workflows. Public constructors,
callbacks and PDF/template helpers remain compatible exports.

The register keeps page size 25, raw offsets, 240 ms search debounce, status
choices, server permissions, amount formatting, retained refresh errors, focus
restoration and all existing responsive layouts. Controller/focus/geometry and
navigation stay in the view/app; register state, request snapshots and late
response guards move to a view model. Concrete repositories consume existing
API methods; app composition supplies cross-feature routes and the existing
invoice gallery while those components await their next gate.

Settings preserve company revision checks, uncertain save reconciliation,
logo decoding/validation, dirty drafts, explicit leave confirmation and write
serialization. Preview retains exact template selection, samples, source/native
print authority and reauthorization after platform waits. Preserve all bundled
art, fonts, notices and rendering geometry. The composer retains request ID,
review token and recovery ledger through uncertain saves; server tax/review
values remain authoritative.

Use existing invoice register/settings/composer/UX/PDF/imported-preview tests
as characterization and add dependency/company replacement and async access
regressions before extraction. Follow repository/model immutable-read versus
explicit-edit-copy boundaries. No new state framework, router, package or
unnecessary domain layer.

Connected verification uses fresh synthetic fixtures on verified
`native-test.localhost`, never customer source material. Register integration
can read invoices explicitly created for this stage; later settings/composer
gates verify save/reprint/default isolation and uncertain outcomes separately.
