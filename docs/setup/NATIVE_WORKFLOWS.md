# Native workflows — 13 November 2026

The current increment moves document operations into Flutter while retaining ERPNext's server-side business rules. The complete conversion is **in progress**. Metadata coverage, working native controls and verified business scenarios are separate measures. This page records the original foundation milestone. The subsequent industry-pack increment extends its design and workflows. AI remains deferred.

## Run

Double-click `scripts/erp-workspace.command`. It starts the isolated native verification site and opens **ERP Workspace.app**. The local launcher configures the service. To explore the synthetic demo, sign in with account `Administrator`, password `admin`, company **ERP Native Verification**. These are local evaluation credentials. The Android emulator address is `http://10.0.2.2:8081`. Customer release builds must supply a deployed HTTPS origin through `--dart-define=ERP_SERVER=https://workspace.example.com`. New owners choose **Create a company** in the app. Owners invite staff through **Team access** in account settings and share a code for **Join with invitation**.

The original ERPNext evaluation site remains separate at `http://localhost:8080`, company **ERP Evaluation**. Its database and files are preserved. The native extension is installed only on `native-test.localhost`. An earlier automatic approval review rejected modifying the original site's installed apps; no installation was performed there.

ERPNext, MariaDB and Redis run locally as the business server; the Flutter program is a native client. The app uses no Vercel deployment. Its document forms, lists, reports and activity routes run inside Flutter. The original application remains an explicitly labelled administrative fallback.

`setup-native-test.command` is restricted to the named verification site. It creates it when missing, installs ERPNext and the local extension, initializes its test company, configures the available wkhtmltopdf print engine, and starts its localhost gateway. Stopping services preserves all volumes.

## Implemented foundation

- Authenticated catalogue of all readable non-child record types and enabled permitted reports; native lists, search and pagination; native single settings and document routes.
- Metadata-based scalar fields, linked search, sections, child-row editors and server defaults. Conditional visibility, required fields and read-only expressions are represented as restricted data trees, without executing JavaScript.
- Native save, submit, cancel and workflow actions use original Frappe controllers. Modified timestamps protect concurrent edits and approvals. Hidden, masked, read-only and permission-restricted inputs cannot be injected. A child row cannot be taken from another document.
- Party and item defaults for the registered sales/purchase transaction types, using ERPNext helpers and calculators. Item-default previews suppress automatic Item Price creation.
- Fixed related-document mapping registry for common sales/purchase flows, returns and payments; Duplicate and Amend. New linked drafts regenerate their trusted source references on the server and validate source versions and permissions. Internal permission-bypass flags are cleared. Duplicate follows `no_copy` rules. Preview pricing overrides are local to the request and restore in `finally`; Lead/Prospect quotations require an existing saved customer before mapping.
- Structured report filters, results, native document drilldown, summaries, prepared-report generation/refresh and CSV export. Export actions follow ERPNext's Export permission. Explicit stored prepared-result identifiers are rejected; retrieval uses the current user and original filters.
- Comments, field-filtered version changes, assignments, private attachments and PDF print preview. Private file download preserves bytes exactly. Upload currently accepts up to 5 MB and download up to 10 MB; remote storage attachments need a dedicated integration.
- Native hierarchy browsing for readable nested-set types, with company/parent context, bounded paging, native leaf/group record editing and child drafts. Moves use the original document controllers. Root pages were checked for all 14 installed tree types. Real Warehouse scenarios verify children, moves, denied access and self-parent rejection; Department covers its shared blank-company root; Employee covers reporting lines and empty branches. Employee nodes can host direct reports, with their record editor available separately. Rename/delete and custom tree actions remain outstanding.
- Password and SID remain in memory. Expired native sessions prompt for the same account again, keep the open form, and require a manual retry. Writes are never automatically repeated.

## Evidence

Current checks: **71 Flutter tests**, **38 real backend tests**, **4 metadata tests**; full analyzer clean. A host-native ARM64 Mac release app and its code signature verify successfully; ARM64 iPhone simulator and Android debug APK builds pass. The Mac release uses the host architecture because this installed Xcode/Flutter pair fails its multi-architecture lipo check. Incremental Mac builds explicitly declare the embedded Flutter framework so Xcode refreshes the containing signature; deep/strict validation passed again after a Dart screen change. The launcher verifies integrity before opening the app. SDK/package deprecation warnings remain; they are not represented as a zero-warning result.

The repeatable backend suite runs against real Frappe/MariaDB, only on `native-test.localhost`, and rolls business transactions back. Its fixtures add explicitly named test DocTypes, roles and users on that site.

Verified scenarios include master creation/edit/reopening, child row identity/order, stale writes, denied permissions, typed Read Only protection, numeric document identities, workflow approval, submit/cancel, comments/private-file roundtrip, exact BOM/Windows-byte preservation, assignments and real PDF output. Financial tests post balanced Journal Entries and sales invoices, query the General Ledger, preserve invoice/credit-note and order/item references, reject submission by a create-only invoice user, and clear fulfilment fields on duplication. Stock tests receive five units, transfer two and verify the remaining three/two warehouse balances and three stock-ledger rows. A lead quotation preview is tested to avoid implicitly creating a customer.

The real Dart HTTP smoke tool additionally creates/edits/reopens a test document with a child row, posts a comment, uploads/downloads/removes a private file and receives a valid PDF. The latest foundation release was checked on the unlocked Mac and left full screen. A saved native document and its child row reopened; the fixed comment refresh worked; a private file uploaded through the Mac picker and downloaded with identical 80-byte contents; a PDF rendered in the native preview. Expired sign-in opened same-account recovery and returned to the form. Unsaved-change retention is covered by automated tests; the live test did not establish that an edited value reached the controller. The rebuilt hierarchy release then displayed the warehouse root and its four children, opened a new child draft with the correct company/parent, and ran General Ledger with the expected zero opening/total/closing balances. The latest app is left full screen on the connected overview.

Detailed logs live in ignored `.local/reports/`. Current counts and build evidence are maintained in `docs/coverage/native-verification.json`; do not substitute metadata counts for scenario coverage.

## Outstanding parity

The source inventory contains 835 DocTypes, including 364 child tables and 63 single settings, and 198 report definitions. These are not 835 fully verified native workflows. Generated filters exist for 171 reports; 138 still have custom/dynamic behavior requiring adapters. The conditional-expression inventory has 1,112 distinct rules, with 1,105 compiled; the seven unsupported expressions are recorded explicitly. Custom user expressions beyond the compiled source also need handling.

Remaining work includes full report/chart/grouped-builder parity; form-specific client scripts, buttons and dependent link queries; rich text, signatures, geolocation, barcode and field-bound attachment controls; complete POS, payment/bank reconciliation, complete tree actions, calendar/kanban, import/bulk operations, manufacturing/subcontracting/serial/batch/asset/project/quality/maintenance workflows; all installed integration setup and account-specific verification; complete scenario and accessibility coverage; production packaging and promotion to the original site. Registered mappings beyond the tested sales/credit paths are available foundations, not a claim of exhaustive verification.

Further localisation, accessibility and large-data verification are also outstanding.

Windows execution requires a Windows host. iPhone and Android device execution, distribution signing and store release require their devices/accounts. Simulator/APK builds establish compilation, not device parity or a distributable installer.
