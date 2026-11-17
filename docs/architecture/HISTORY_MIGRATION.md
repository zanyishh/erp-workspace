# Imported history stage preparation

Status: accepted after independent source review, format/analyze, 745 passing
default cases plus one conditional skip, 14 passing opt-out cases and fresh
synthetic connected verification. See `MIGRATION_PROGRESS.md` for exact receipts. The history feature owns its register, detail, grouped original-production report, filter
dialogs and original-record PDF preview/rendering. Current implementation is
about 2,500 lines across six libraries plus the existing endpoint adapter.

## Scope and migration order

Migrate this read-only feature in the order: response values/repository,
register/detail, original-production projection, filters/choices, PDF preview.
One complete feature gate follows the finished feature. These views share the
same historical-source contracts and currently form a navigation import cycle.
Migrating them together avoids creating a second temporary legacy UI package or
new cycle exceptions merely to move their navigation in separate gates. This
uses the same feature-sized gate as Catalog's related register/tree/import
views. Invoice and document financial mutations retain their separate risk gates.

## Contracts to preserve

- Version, company, family, record, page and source-scope validation; strict
  malformed-response errors instead of fabricated rows or zero totals.
- Exact original dates, absent original dates, effective/opening dates,
  decimal strings, signed fractional quantities, missing-count indicators and
  source IDs. ERPNext remains authoritative; do not recalculate financial or
  production totals in Flutter.
- Source-job identity versus display label, case-sensitive option values,
  filter-label validation, original source-book choice and date basis.
- Register pages of 40, grouped report pages of 100, raw offsets, debounce,
  stale-result rejection, selected-family fallback and explicit shared cash.
- Read-only source records. Target document, original invoice, original PDF
  and register/report drilldown routes remain app-composed callbacks.
- Current public constructors, filter helpers and PDF function remain available
  through compatibility exports. Existing fonts, layouts and notices remain.

## Boundaries

- A company-scoped repository contract exposes summary, records, detail,
  shared cash, grouped production, filter options and source print reads. The
  existing ERP endpoint mixin remains service code until final transport work.
- Feature read values own existing response validation and freeze nested maps
  and lists. Editable filter drafts are explicit copies. Reuse a domain layer
  only if extraction demonstrates policy beyond parsing/state projection.
- Catalog and Reports already use the same recursive JSON-freeze algorithm.
  A third identical copy is unnecessary: extract that proven value-copy policy
  into core models while retaining current helper contracts and existing
  immutability tests. This changes no previously accepted data policy.
- Register/detail/production/filter/preview models own state, capabilities,
  paging, errors, validation and scope fences. Views keep controllers, debounce,
  focus, geometry, dialogs and labels. PDF generation is an injected rendering
  service; platform print/save/share stays behind service/callback boundaries.
- A single app adapter library can compose the mutually navigating public
  screens without importing feature views into one another. No root-facade or
  app import may bypass canonical feature boundaries.
- Read revalidation never releases an in-flight export/print token. Recheck
  the exact authorized result after any picker/renderer/platform wait.

## Evidence and gate

Use all existing history, original-production, source-job, imported-preview and
PDF tests as characterization. Add pending dependency/company, access-refresh,
filter-dialog, stale export and malformed/mutable-response cases before risky
changes. Prove absent contracts with RED, then run format/analyze, architecture
regressions/lint, the entire unit/widget suite, explicit local-launch opt-out
and independent review against the accepted Reports snapshot.

Connected evidence must use newly created synthetic historical-source records
on verified `native-test.localhost`; any new user account must end in
`@example.invalid`. Author a
minimal fixture through the existing historical store contract, verifying the
selected backend and site before writes. Do not run the customer migration
pilot or reuse arbitrary migration directories, source databases or customer
fixtures. Preserve created test records and all application/database volumes.
