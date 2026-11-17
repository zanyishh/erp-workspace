# Native reports stage preparation

Preparation only until Catalog's complete acceptance gate passes. Scope:
`report_screen.dart`, `native_reports.dart` and `report_chart.dart`. Imported
history's original production report remains a later, separately reviewed gate.

## Characterization

- Preserve existing filter defaults, conditional visibility, dependent multiple
  choices, exact payloads, validation and chart/table/CSV behavior.
- Preserve the distinction between edited, requested and displayed filters.
  A pending prepared report retains the last completed rows and their applied
  summary; Generate uses the requested filters even after further editing.
- A failed rerun retains safe prior rows; permission/session failures clear
  them. Superseded results cannot become the next retained result.
- Characterize company/API/report replacement, old access revalidation and
  queued report commands across reload/revalidation. A pending server command
  must retain serialization until it settles; never automatically queue again.
- CSV/clipboard operations use only the currently displayed authorized result.
  Document links and platform export are injected callbacks from composition.

## Responsibilities

- A company/report-scoped repository owns definition, run, queue and link reads,
  with client/account/company/access revision fences and immutable responses.
- A plain view model owns defaults, mutable filter drafts, validation, dependent
  choice invalidation, read generations, applied/requested filter snapshots,
  queued-command state and export eligibility. No UI or platform imports.
- Presentation owns filter controls, focus, layout, formatters, chart painting,
  dialogs, table paging and callbacks. Preserve public screen/table/chart names
  through compatibility exports and app adapters.
- The existing dynamic `DocumentFields` implementation remains in its later
  Documents gate. Compose that control through an app-supplied filter builder;
  do not introduce a Reports-to-legacy-Documents import or prematurely move its
  platform controls. Inject its lookup callback from the Reports model.
- A separate chart model is warranted only for selection/projection policy now
  embedded in the chart view. Keep painter geometry and labels in presentation.
- Native schema/field controls remain the already established shared value/UI
  contract; document editing remains its own migration. Do not add a report
  domain layer or state framework for ordinary load/filter/queue operations.

## Gate

Run old-code characterizations and new-contract RED before extraction. Require
pinned formatting/analyzer, all default unit/widget tests, explicit local-launch
opt-out, boundary regression/lint checks and independent review against the
accepted Catalog before-images. Connected report reads must verify the server
reports `native-test.localhost`, use synthetic companies only, and verify actual
filter payload/result/CSV/chart contracts without customer migration material.
