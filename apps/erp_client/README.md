# ERP Workspace

Native Flutter client for the preserved ERPNext evaluation service. The interim product name is ERP Workspace; it is independent of Frappe and Creatora.

## Run on this Mac

Double-click `../../scripts/erp-workspace.command`, then open **Create a company** and choose **General ERP** or **Knitting**. Existing accounts can sign in. Owners select **Team access** in account settings to invite an email address with a staff role. Share the generated code with the recipient. They select **Join with invitation** and enter their code and credentials. The local evaluation service is `http://localhost:8081`; its demo account is documented in the root README. Passwords and session cookies are held in memory and sign-out revokes the ERPNext session. No credentials are written to disk.

For development, start the local service with the workspace launcher, then run:

```sh
flutter pub get
flutter run -d macos
```

## Current native increment

The overview reads company details, catalog/customer/supplier/warehouse counts, dated order counts, posted invoice totals in company currency, daily invoice activity and unpaid invoice counts. Periods include the current calendar day. Permission-denied data is marked unavailable; connection failures are errors rather than fabricated zeros.

Eight overview module browsers and the full permitted catalogue use native Flutter lists and editors. Create/Edit, linked search, child rows, save/submit/cancel/approval, report results/export and files/activity no longer require a browser. Read [current workflow coverage and explicit remaining work](../../docs/setup/NATIVE_WORKFLOWS.md). The optional Knitting workspace adds native jobs, material custody, production/QC, planning, subcontract, delivery, invoicing, credits/returns, reports and industry setup. Shared controls, typography, confirmations and reduced-motion behavior apply across core and industry pages. See [release evidence and remaining gates](../../docs/setup/KNITTING_V1.md). Complete upstream browser-script parity is not claimed; AI remains deferred.

The native verification company contains clearly named synthetic demo records; automated knitting scenarios use a separate verification company. Empty views remain honest when no permitted records exist. Stock is a shared item catalog; dated transactions use the selected company and reporting period. Customer and supplier masters are shared under ERPNext permissions. The warehouse illustration is decorative, not a model of the user's actual property.

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

For customer builds, supply the deployed HTTPS origin with `--dart-define=ERP_SERVER=https://workspace.example.com` when building for each platform. Customers never enter a server address. Debug and profile builds default to loopback for local evaluation. A release build requires an explicit service origin. Cleartext is limited to local development loopback addresses. Android emulators use `10.0.2.2:8081` for the Mac's loopback; physical phones need a separately configured reachable HTTPS server. macOS target is 12+, iOS 15+ with ARM64 simulator builds on this Mac. Windows compilation requires a Windows host; generated project files do not establish a successful build.
