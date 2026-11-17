# Overview stage preparation

Preparation only. Workspace's complete verification gate must pass before
Overview application edits begin. Overview includes the module record browser
and sales chart; catalog and native reports retain their separate gates.

## Existing behavior to preserve

- Existing overview/chart and module-browser tests characterize credit notes,
  missing days, monthly buckets, currency, inaccessible totals, reduced motion,
  chart keyboard/semantic selection, debounce, paging and retained reads.
- Navigation-retention tests cover query/page/scroll/focus while opening records
  and refreshing the shell. Local-workspace and access-refresh tests cover
  company replacement and permission revalidation.
- Preserve the existing public screen constructors, record-loader callback,
  labels, layout breakpoints, navigation callbacks and reporting-period filters.
  No data fixture from a customer account is authorized.

## Responsibilities

- An Overview repository wraps company-scoped snapshot and module-record reads.
  Preserve unavailable values as null, original errors, periods, unpaid filters,
  page size/offsets and record currencies. Reject changed client/account/access
  identity and wrong-company responses; freeze read collections at this boundary.
- The existing authenticated API remains the transitional service adapter.
  This stage must not claim that transport/session/endpoint decomposition is
  finished or duplicate its authoritative financial aggregation.
- An Overview view model owns period-scoped loading futures. The shell retains
  the app's shared reporting-period selection, client ownership, session
  recovery, routes and screen composition; it injects that period into the model.
  Existing retained-future widgets continue to control same-scope display.
- A chart view model owns bucket projection and selected date. Formatting,
  pointer/keyboard/semantics handling, axis measurement and painting stay in UI.
  This one-consumer presentation projection does not warrant a domain layer.
- A module-browser view model owns committed search, page and opened-record
  state. The view owns its text/focus/scroll controllers and input debounce.
  Inject a repository; adapt the existing loader callback at composition.
  Ordinary parent rebuilds must not discard query/page/scroll state.
- Split the browser's header, controls and result rendering by responsibility.
  Keep callbacks for documents, invoices, banking, POS and original-history
  navigation at the app boundary.

## Gate

Run existing old-code characterizations before extraction. Add missing-seam unit
contracts before implementation, including immutable read boundaries, scope
replacement, filters/paging and chart projection/selection. Then require pinned
format/analyze, architecture checks, the entire default unit/widget suite, the
explicit local-launch opt-out, a native-test-only synthetic snapshot/records
contract check and independent review against the accepted Workspace snapshot.
