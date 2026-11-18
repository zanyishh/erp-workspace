# Catalog stage preparation

Preparation only. Overview's complete verification gate must pass before Catalog
application changes. Scope: native catalog/search, native record registers and
group changes, hierarchy browsing/rename/delete, and reviewed master CSV import.
Native reports and shared document editing retain their own later gates.

## Characterization

- Keep all existing native-catalog, native-tree and master-import cases, plus
  navigation, access-refresh and model contracts. The accepted prior feature's
  complete suite is evidence for existing behavior before extraction.
- Add old-code scope cases for reusing hierarchy screens with another company,
  type or parent and confirming a hierarchy dialog after its dependency changes.
  A changed label must never turn an old node into a command for another scope.
- Check company/type-specific gate lifetimes while an old revalidation is
  pending. Keep search/page/selection/scroll state only within its current scope.
- Preserve import preview before confirmation, the 256 KB limit, original UTF-8
  bytes/content, digest receipt checks, uncertain outcomes, no automatic confirm
  replay, and blocked Back while a write is active.

## Responsibilities

- Separate repository contracts for catalog/register data, hierarchy operations
  and master import. One scoped ERP implementation may implement these related
  contracts; do not introduce a wrapper class for every endpoint.
- View models own filtering/paging/selection, optimistic modified timestamps,
  loading/errors, command serialization and stale-result rejection. Reads may
  invalidate display state without releasing an active server mutation.
- Views own controllers, debounce, focus, dialogs and rendering. Capture the
  model and dialog intent before awaiting confirmation; reject obsolete intents.
  Document/report/task/tree/import routes are injected by app composition.
- File picking and platform save/share stay behind callbacks from composition;
  feature views/models must not import file-selector/platform plugins. Import
  parsing/validation/receipt policy belongs to the repository/model boundary.
- Shared native schema/value, condition and barcode libraries can move unchanged
  to core models to support strict imports. Preserve their public exports and
  explicit edit-copy behavior. This does not claim document editing is migrated.
- Native catalog/register/tree read results become immutable feature values.
  Do not freeze every existing dynamic document model during this stage.
- General ERP remains independent of knitting implementation. Existing
  knitting-only filtering is an injected value from the common workspace
  contract, with no dependency on knitting workflows or tables.

## Gate

Require old-code characterization and missing-contract RED before extraction,
pinned format/analyze, architecture regression/lint checks, the entire default
unit/widget suite, explicit local-launch opt-out and independent read-only
review against the accepted Overview before-images.

Connected tests must verify `native-test.localhost` before mutations. Use newly
created synthetic fixtures for CSV import and hierarchy operations. Do not run
the existing `pilot_master_import_test.dart` with an arbitrary `PILOT_DIR` or any
customer/imported migration material; provision a fresh isolated fixture or
author an equivalent native-test-only rehearsal. Retain backend records/data.
