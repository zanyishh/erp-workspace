# Flutter architecture

16 November 2026. Scope: `apps/erp_client/`, its native test tools and architectural CI. The baseline is the existing working tree, including uncommitted work. The backend contract and approved ERP/knitting behavior remain authoritative.

## Audit baseline

The [complete source, dependency, interface and test inventory](docs/architecture/BASELINE_INVENTORY.md) maps all 74 source files (37,786 lines), 84 test files, 16 Dart verification tools and 93 resolved packages. Its [JSON companion](docs/architecture/2026-11-16-baseline-inventory.json) records file hashes, public declarations and member signatures, method locations, call sites, imports, parts and test names. This snapshot predates application changes; it must not be silently regenerated as evidence of the old design.

The [ranked audit](docs/architecture/AUDIT_2026-11-16.md), [migration plan](docs/superpowers/plans/2026-11-16-flutter-architecture.md) and [decision record](docs/architecture/decisions/0001-feature-first-mvvm.md) distinguish observed behavior from the target. A moved file alone is not a completed MVVM migration.

The inventory is the immutable pre-migration snapshot. The [execution ledger](docs/architecture/MIGRATION_PROGRESS.md) records the current accepted features, open stages, independent reviews and exact verification receipts.

Audited design: a flat `lib/` directory, widget-owned state, `FutureBuilder`/`RetainedFutureBuilder`, callbacks, `ValueNotifier` for a few local signals, and constructor injection. There was no external state-management framework. `ErpApi` combined authenticated HTTP, session/access lifecycle, endpoint adapters, decoding and overview aggregation. Screens often used it directly. `part` files shared private UI state. Two import cycles existed: API ↔ knitting models and imported history ↔ original production report. Current migration status is in the execution ledger.

## Target structure

```text
lib/
  main.dart                         # entry point
  app/                              # composition root, shell, navigation
  core/
    services/                       # HTTP and platform I/O
    models/                         # shared values and errors
    ui/                             # shared widgets, access gate, theme
  features/<feature>/
    data/                           # abstract repository and implementation
    models/                         # feature data and immutable read models
    presentation/                   # views, view models, local UI components
    domain/                         # only justified shared/complex policies
```

Feature ownership follows the baseline inventory: authentication, workspace, team, overview, catalog, documents, tasks, reports, invoices, banking, point of sale, operations, imported history and knitting. The shell assembles them. Shared document editing belongs to documents, not to knitting. Future industry packs depend on common contracts; general ERP must not depend on knitting workflows or tables.

These directories describe the destination. The migration ledger in the plan identifies which features actually meet it. Temporary root-level exports may preserve public import paths; they must contain no implementation and internal imports must use canonical paths once their feature is migrated.

## Responsibilities and boundaries

- **View:** builds widgets, owns focus/text/scroll/animation controllers and platform-facing dialogs, routes users, and forwards events. Simple conditional rendering and responsive layout stay here. It does not fetch, decode, aggregate, validate business quantities, retry or post data.
- **View model:** owns presentation state, filters, paging, loading/errors, stale-request rejection and commands. It receives repository interfaces by constructor. It does not import a view, use `BuildContext`, display dialogs, navigate or use sockets/platform plugins.
- **Repository:** owns application data policy, parsing into feature models, refresh semantics, scope checks and coordination with services. Abstract contracts allow small fakes. Repositories do not depend on views, view models or each other.
- **Service:** performs HTTP or local/platform I/O. HTTP endpoint adapters and transport remain shared where they use the same source. No UI dependencies. Existing transport is extracted incrementally; its broad session/access coordination remains explicit until all direct consumers migrate and the final transport/session review passes.
- **Domain:** only for complex or reused policy, such as decimal knitting quantities or durable operation reconciliation across invoice/document/payment flows. Do not add a use-case for a single forwarding call. ERPNext remains the authority for tax, stock, money, permissions and posting.
- **Composition root:** creates session-scoped services and repository instances and passes them to feature views/view models. Views may accept the existing `api` parameter as a compatibility adapter while call sites migrate. No global service locator, static mutable container or new state framework.

The Invoice logo service is the one explicitly checked platform-engine adapter
allowed to use `dart:ui` for image metadata decoding. It may not import Flutter
Material/widgets; view models and views may not import the service. App
composition injects its picker function. The existing size/header/dimension
bounds stay in the I/O adapter, and the model owns authorization and results.

Production imports point from views to view models and from view models to repository contracts. Repository implementations depend on services and models; app composition constructs and injects those implementations. View models must not import concrete repositories. Runtime flow is `view → view model → injected repository → service → backend`. Shared model/value libraries have no UI dependencies. Cross-feature navigation is supplied as callbacks at the app boundary; a feature does not reach into another feature's view model. Approved cross-feature UI composition must be listed explicitly by the boundary checker, not hidden in a broad directory exemption.

## State and data flow

Preserve Flutter's current `setState`, futures and listenables. Plain Dart view models can expose futures/values consumed by the existing view; a notifier is appropriate only when multiple state changes need observation. Constructor injection is sufficient for the present app; provider, Riverpod, Bloc, code generation and a new router are not required for this migration.

1. A user event calls a view-model command.
2. The command snapshots account, company, access revision and request generation.
3. A repository calls the API/platform service and validates the response's shape and scope.
4. The view model publishes the result only if its scope is still current.
5. The view renders the new state. Errors remain explicit; permission-denied data is not converted into zero.

Reads may retain prior results only within the same account, service origin, company and authorized access scope. If requested filters change, any retained result must keep its own applied-filter snapshot and label; it must never be presented as the new request's result. Access invalidation hides cached data until current permission and source data have been checked. Disposal and replacing a dependency invalidate pending work. A response for a previous company must never be published under a new company label.

Financial mutations preserve the existing review tokens, modified timestamps, request IDs and server recovery ledger. Preparation precedes the write. A timeout means unknown outcome, and status checks use the same ID. Automatic retries must never replay a non-idempotent write. Do not clear a durable request until its confirmed result is shown or its unposted closure is acknowledged.

Revalidation can invalidate cached display state immediately, but it does not cancel a server mutation. Keep an in-flight write serialized until its own completion/timeout handler settles; a newer read generation must not release its busy token. Reject stale results separately. This also applies to invitation writes, where overlapping requests can invalidate each other's codes.

An attempted financial save retains its immutable payload, review token, request ID and recovery mode together. A refreshed capability must not change the protocol for that attempt. A later rejected retry cannot prove that an earlier unknown write did not commit. Keep it locked until the same request is confirmed or its unposted closure is established.

Confirmation receipts carry an access scope, separately from their durable request. Show the confirmation in a rendered frame before acknowledging or closing its owner, including zero-duration routes. If access changes during that handoff, restore recovery of the same attempt instead of retaining an unusable receipt lock. Data reads/writes require ready access; confirming departure with a durable reference requires the same owner and captured scope but can work while access is unavailable. An unresolved legacy write without a durable reference remains blocked. Dismiss independently mounted dialog routes when their owner changes or is disposed.

Read models should expose unmodifiable collections. Editable form drafts are explicit copies; focus nodes and controllers do not belong in data models. Do not deep-freeze every existing JSON map in one change: characterize each parser and edit-copy boundary first.

## Existing end-to-end flows

| Feature | Input → state/data access → output | Authority and risk |
| --- | --- | --- |
| Authentication | Shell/sign-in → login/OTP/invitation → cookie, workspace context → shell | Portal login restrictions, cookie lifecycle and no write replay |
| Local workspace | Launcher preference file → validated loopback API token → authorized context | Synthetic local profiles only; backend determines company permissions |
| Workspace/team | Company selection/context; invite/revoke → Frappe workspace/team endpoints → access-gated destinations/token | Clear old company/account results and invitation tokens |
| Overview/modules | Period/company → snapshot and records → module counts, chart and lists | Permission-denied is unavailable; amounts use company/record currency |
| Catalog/tree/import | Catalog/schema, search, hierarchy, CSV review → native endpoints → document routes/import result | Schema permissions, modified timestamp, preview before import |
| Documents | Schema + document → draft copy → defaults/validation/review → save/transition → confirmation | Shared editor powers many doctypes; preserve dynamic conditions, child rows, recovery |
| Tasks | Board/calendar/month/status → task page(s) → board and date agenda → document editor | Stable pagination, deduplication, date-only inclusion and scope changes |
| Reports | Definition/filter fields → report run/queue → table/chart/export | Backend scoping; sanitize rich report text; safe file export |
| Invoices | Register/defaults → draft → server review → request-ledger save → editor/preview | Server prices/taxes; company settings; issue/payment QR eligibility |
| Banking | CSV or bank match → preview/confirmation → import/match; payment/invoice balances → allocation | Decimal strings and expected balances; uncertain outcomes kept recoverable |
| Point of sale | Configure/open shift → quote cart → checkout/refund/close → receipt | Review tokens, request identity, shift/cash scope and no duplicate posting |
| Pending operations | Read durable references → check/close/acknowledge → receipt/document | Opening/refreshing never resends a business mutation |
| Imported history | Permitted family/filter/date/page → summary/records/detail → original record/PDF | Read-only source contracts, strict response company/version and source-job labels |
| Knitting pack | Authorized destinations/job/register → action schema/draft/review → command/status → production/custody/delivery/billing | `Kg` decimal policy, capabilities, source quantities, recovery and original-history compatibility |
| Files/printing | Authorized bytes → native selector/preview/printing/share | Keep private files private; recheck access before export; assets/notices preserved |

The [API/data-flow contract map](docs/architecture/API_CONTRACTS.md) lists every public API method, direct endpoint and source/test/tool consumer; full signatures and call sites are in the inventory JSON. This table explains flow direction, not a claim that every current flow already follows MVVM.

## Verification and release gates

The project pins Flutter 3.47.9 / Dart 3.13.7. Preserved backend references are ERPNext v16.54.0 and Frappe v16.55.2; exact revisions remain in `upstream.lock.json`. Use `scripts/flutter_toolchain.py` locally; no global SDK fallback. CI must use the same pinned SDK. Run after **each** feature migration:

```sh
# From apps/erp_client; formatter checks must fail on any outstanding change.
python3 ../../scripts/flutter_toolchain.py --dart format --output=none --set-exit-if-changed lib test tool
python3 ../../scripts/flutter_toolchain.py --suppress-analytics analyze --no-pub
python3 ../../scripts/flutter_toolchain.py --suppress-analytics test --no-pub --concurrency=4
```

Also run architectural dependency checks, their regression tests and the feature's connected rehearsal. Characterization tests must pass on the old behavior before risky extraction; new boundary/contract tests must demonstrate the missing behavior before implementation. Unit tests cover service/repository/view-model logic; widget tests preserve labels, controls, navigation, failure and recovery. Existing connected tests live under `tool/`, not `integration_test/`; the default `flutter test` does not execute them.

Connected verification may target only `native-test.localhost` through the named local launchers, using synthetic fixtures. Verify the server-reported site before any mutation. No customer live account, customer launcher or imported customer fixture is authorized for this work. Never delete volumes. Windows compilation requires a Windows host.

Do not mark migration complete until all planned features and boundary checks are implemented, formatter and analyzer pass, the entire unit/widget suite and relevant connected integration tests pass against the final source, and an independent review has no unresolved material findings. A staged feature can be verified while the overall migration remains open.

## Official reference and adaptation

Flutter recommends separate UI/data responsibilities, repositories, services, view models, dependency injection and independently tested components. Its state-management and domain-layer choices are conditional. This project applies those recommendations with feature ownership and existing Flutter state primitives. See [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) and the [architecture guide](https://docs.flutter.dev/app-architecture/guide), retrieved 16 November 2026. Website examples target a newer SDK; keep the repository's validated SDK pin during this architecture change.
