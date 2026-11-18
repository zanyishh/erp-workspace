# ERP Workspace

Native Flutter client for the preserved ERPNext evaluation service. The interim product name is ERP Workspace; it is independent of Frappe and Creatora.

## Run on this Mac

Double-click `../../scripts/erp-workspace.command`. The Mac opens **ERP Workspace Local** directly into **Meridian Trading**, a synthetic General ERP company. The company selector also offers **Kaveri Loomworks**, a separate knitting company with its own invoices and jobs. Switching company opens its own industry workspace and permission-scoped account. The launcher installs the signed local app in `~/Applications` and creates its permission-scoped credential in the app’s private macOS Application Support directory. Future launches from Finder reuse that credential. Other builds use normal sign-in and invitation flows.

For the separately prepared customer copy, double-click `../../scripts/erp-customer.command`. It installs **ERP Workspace Customer** alongside the local demo app, uses normal password sign-in against `http://127.0.0.1:8082`, and does not load demo profiles or bundle credentials. Customer scope members receive knitting-only navigation, **Masters & accounts**, permitted accounting tools and original history. The general ERP foundation remains available in other workspaces. This is a local Mac review build; it is not a public deployment or an approval to switch live operations. See the private 15 November parity audit.

For development, start the local service with the workspace launcher, then run:

```sh
flutter pub get
flutter run -d macos
```

The plain Mac debug command opens the provisioned local review workspace. Use `flutter run -d macos --dart-define=ERP_LOCAL_WORKSPACE=false` to develop customer sign-in.

## Invoices

Open **Invoices** from the business overview, Sales, Accounts or the knitting menu. The register supports customer/number searches, ERPNext statuses and paging. **New invoice** opens the customer-and-item composer. The server calculates the draft using the company price list and configured taxes; **Review** shows the result before saving. Existing bills open in the full document editor.

Owners can open **Invoices → Invoice settings** to select the company default, upload a PNG or JPEG logo, and enter their bank and UPI details. General ERP and Knitting share one profile per company. New invoices inherit the design automatically. To keep a design for one bill, open its preview and save a template. Choose **Use company default** to follow the company again. Reprinting uses the current logo and bank details, and the outstanding balance at print time. Keep the exported PDF when you need the original issued copy.

**Templates** shows all 15 A4 designs. Posted, unpaid INR sales invoices can display a payment QR when the company has a UPI ID and the receivable is also in INR. Drafts, credit notes, cancelled and fully paid bills omit the payment QR. Static bank details can still appear. Existing GSTIN, HSN/SAC, taxes, place of supply and supported government e-invoice references print when recorded. Payment and government verification QRs have separate labels.

See the [15-page PDF lookbook](../../docs/design/invoice-template-lookbook.pdf) and the [visual index](../../docs/design/invoice-templates-overview.jpg). The workflow reference was [Swipe's published guide to invoice templates](https://getswipe.in/blog/article/how-to-change-invoice-template-on-web). The Indian field reference was [CBIC's invoice rules](https://cbic-gst.gov.in/gst-invoice-rules.html).

## Current native increment

The overview reads company details, catalog/customer/supplier/warehouse counts, dated order counts, posted invoice totals in company currency, daily invoice activity and unpaid invoice counts. Periods include the current calendar day. Permission-denied data is marked unavailable; connection failures are errors rather than fabricated zeros.

Eight overview module browsers and the full permitted catalogue use native Flutter lists and editors. Create/Edit, linked search, child rows, save/submit/cancel/approval, report results/export and files/activity no longer require a browser. Read [current workflow coverage and explicit remaining work](../../docs/setup/NATIVE_WORKFLOWS.md). The optional Knitting workspace adds native jobs, material custody, production/QC, planning, subcontract, delivery, invoicing, credits/returns, reports and industry setup. Shared controls, typography, confirmations and reduced-motion behavior apply across core and industry pages. See [release evidence and remaining gates](../../docs/setup/KNITTING_V1.md). Complete upstream browser-script parity is not claimed; AI remains deferred.

The native verification company contains clearly named synthetic demo records; automated knitting scenarios use a separate verification company. Empty views remain honest when no permitted records exist. Stock is a shared item catalog; dated transactions use the selected company and reporting period. Customer and supplier masters are shared under ERPNext permissions. The warehouse illustration is decorative, not a model of the user's actual property.

## Architecture

See the [architecture guide](../../ARCHITECTURE.md), [complete baseline inventory](../../docs/architecture/BASELINE_INVENTORY.md), [migration plan](../../docs/superpowers/plans/2026-11-16-flutter-architecture.md) and [current verification ledger](../../docs/architecture/MIGRATION_PROGRESS.md). The migration preserves Flutter state primitives and moves features into views, view models and repositories in sequence.

## Design and licensing

See the [approved design](../../docs/superpowers/specs/2026-11-12-reference-erp-ui-design.md), [reference analysis](../../docs/design/REFERENCE_ANALYSIS.md), and [original image prompts/provenance](../../docs/design/ASSET_PROMPTS.md). Bundled Manrope and Barlow Condensed retain their SIL OFL notices. The app includes a Licenses screen with the GPL, Frappe MIT, Flutter BSD and dependency notices. Original upstream source and notices remain unchanged.

The code is GPL-3.0; see [LICENSE](LICENSE) and the workspace [NOTICE](../../NOTICE.md).

## Verification

The [owner and staff rehearsal](../../docs/coverage/2026-11-14-owner-signup.md) covers signup, team access, a newly established company's first transactions and Mac startup. The [connected staff pilot](../../docs/coverage/2026-11-14-connected-pilot.md) covers production, quality inspection, dispatch, invoicing, yarn returns and paid purchase and sales orders. The earlier [workspace frame measurements](../../docs/coverage/workspace-frame-timings.json) cover register scrolling and chart interaction.

```sh
flutter analyze
flutter test
flutter build macos --release --dart-define=ERP_SERVER=http://localhost:8081
flutter build ios --simulator --debug
flutter build apk --debug --target-platform android-arm64
```

Read-only live verification: set `ERP_USERNAME` and `ERP_PASSWORD` in the process environment, then run `dart run tool/verify_connection.dart`. It reports only company/currency/counts and signs out afterward. Do not put credentials in checked-in files.

For customer builds, supply the deployed HTTPS origin with `--dart-define=ERP_SERVER=https://workspace.example.com` when building for each platform. Customers never enter a server address. Debug and profile builds default to loopback for local evaluation. A release build requires an explicit service origin. Android requires Android 11 (API 30) or newer. Android release and profile builds require HTTPS; only debug builds allow the explicit local-development loopback addresses. Android app backup and device-transfer data extraction are disabled. Debug Android emulators use `10.0.2.2:8081` for the Mac's loopback; physical phones need a separately configured reachable HTTPS server. macOS target is 12+, iOS 15+ with ARM64 simulator builds on this Mac. Windows compilation requires a Windows host; generated project files do not establish a successful build.
