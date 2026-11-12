# Reference-led Flutter ERP UI Implementation Plan

> **For agentic workers:** Execute in this session using superpowers:executing-plans. The user approved this design and explicitly requested applying it in Flutter; proceed through implementation and verification.

**Goal:** Deliver and launch a native macOS Flutter ERP overview matching the supplied visual reference, with real ERPNext data and consistent module browsers.

**Architecture:** A small Dart REST client owns its in-memory session. Immutable company/snapshot/module/record models feed an app shell, overview and record browser. Shared design tokens and a few focused visual components enforce the reference style. Original ERPNext forms remain available through browser handoff.

**Tech stack:** Flutter 3.38.7/Dart 3.10.7, Dart HTTP, intl (already installed), official url_launcher 6.3.2, bundled Manrope and Barlow Condensed fonts, original generated 3D PNG assets.

**Spec:** `docs/superpowers/specs/2026-11-12-reference-erp-ui-design.md` (approved in chat on 2026-11-12; independent builder check found no important unanswered questions).

## Global Constraints

- Keep all three upstream checkouts and existing application data unchanged.
- General ERP overview using the supplied style; no truck/fleet product or Creatora branding.
- Exact photo font identities/colour tokens are unverified; chosen matches are documented.
- No hard-coded passwords, persistent credential storage, secret logging or fake business numbers.
- First increment includes overview and native module lists; full document forms open in the original ERPNext.
- Preserve source, font and dependency notices. Use at least 44px accessible control hit areas.
- Verify layouts at 390, 834 and 1440 logical pixels; support normal text scaling and truthful empty/error/loading states.
- Root is a new workspace repository; keep the requested project path, create a feature branch, and do not create a worktree of the unrelated upstream repositories.
- Windows compilation and physical-device checks require their own hosts/devices and must not be claimed.

## Review Focus

- Expired sessions must return to sign-in rather than display stale/fabricated data.
- Company/date filters must not leak other-company totals or omit the final day's timestamp records.
- Empty and malformed REST responses must be handled explicitly; errors must not become zero counts.
- Narrow layouts and longer labels must scroll/reflow without clipping or tiny text.
- All controls must have a real action and browser handoff URLs must stay on the configured ERP origin.

### Task 1: Foundation, assets and real REST integration

**Files:** `apps/erp_client/pubspec.yaml`, `lib/erp_api.dart`, `lib/erp_models.dart`, `assets/fonts/`, `assets/images/`, `test/erp_api_test.dart`, `test/erp_models_test.dart`.

**Interfaces:** `ErpApi(Uri baseUri)`; `login(username,password)`; `snapshot(ReportingPeriod period)`; `records(ErpModule module,{String query,ReportingPeriod period,int start})`; `originalUri(ErpModule module,{String? name,bool create})`; close/sign-out lifecycle. Models expose company, real counts, sales totals, daily sales, recent records and display metadata. Module definitions contain actual doctype fields and date/company capabilities.

- [ ] Generate a minimal Flutter project with the four requested platform hosts; remove the counter app and unnecessary sample dependencies.
- [ ] Generate/save three original white 3D renders: business warehouse scene, sales terminal/receipt, and purchasing pallet/boxes. Record prompts, provenance and final filenames.
- [ ] Download verified open fonts and their OFL notices; bundle these with the application and license collection.
- [ ] Write model/query tests first: date ranges use inclusive start/exclusive end; records preserve real names/labels; original URLs safely encode record names and retain the ERP origin.
- [ ] Run those tests and observe the missing implementation failure, then implement the minimum model/query code.
- [ ] Write REST boundary tests against a local HTTP server: login cookie is sent to later reads; a 401 yields an expired-session error; company/date filters appear in actual requests; malformed data is an explicit error.
- [ ] Implement the client and run its tests. Verify read-only queries against the live evaluation service without creating business documents.

### Task 2: Reference-led UI and usable flows

**Files:** `lib/main.dart`, `lib/design.dart`, `lib/widgets.dart`, `lib/overview.dart`, `lib/module_browser.dart`, `lib/sign_in.dart`, `test/layout_test.dart`.

**Interfaces:** `ErpWorkspaceApp`, shared `WorkspaceTheme` colours/type, reusable dark/pale panels and pill/circle controls, `OverviewScreen` consuming a real snapshot, `ModuleBrowser` consuming real record pages and search state. Browser opening uses one shared callback with failure feedback.

- [ ] Write a layout test with realistic empty/non-empty snapshots at the three specified widths; test module selection/search behaviour using real model data.
- [ ] Implement palette, bundled type, spacing, outline icons, rounded panel hierarchy and peach gradient metrics.
- [ ] Build the sign-in screen; keep credentials in memory and show clear connection/auth errors.
- [ ] Build the three-column overview with dominant 3D scene, charcoal summary, business flow diagram, honest chart/empty state and image-led workspace cards.
- [ ] Build responsive module record lists/cards with company/date filtering, search, refresh, pagination and clear browser handoff for full record forms.
- [ ] Implement real module/search/settings/recent-activity actions and license/about access. Respect accessibility and reduced-motion preferences.
- [ ] Run tests and analyzer; resolve overflow or race/session handling failures.

### Task 3: Platform setup, visual verification and launch

**Files:** macOS entitlements/deployment settings, iOS local-network/deployment settings, Android network/development settings, `scripts/erp-workspace.command`, README and setup/design records.

- [ ] Add required network-client permissions and restrict local HTTP development exceptions to loopback hosts.
- [ ] Apply the verified Xcode deployment minimums (macOS 12, iOS 15) and native ARM64 simulator configuration where needed.
- [ ] Run Dart formatter, Flutter analyzer, full client tests and macOS debug build; build Android/iOS when host configuration changes warrant it.
- [ ] Launch the actual native macOS app, sign in to ERPNext, inspect the rendered design and exercise overview/module/search/refresh/browser handoff.
- [ ] Review the implementation against the reference, fix material gaps, and capture the final native app screenshot.
- [ ] Finish concise launch, design-token, license and scope documentation. Keep the original ERPNext baseline available.
