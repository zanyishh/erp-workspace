# ADR 0001: Feature-first MVVM with existing Flutter state

- Date: 16 November 2026
- Status: selected for implementation under the user's architecture request; staged rollout, not a completed migration
- Scope: Flutter client. Backend business semantics and the public UI are preserved.

## Context

The audited client has 74 source files with mostly flat organization. `State` objects coordinate data loading, input policy and financial recovery alongside rendering. `ErpApi` is constructor-injected but is a concrete, broad dependency. The current state solution is Flutter's built-in state/futures/listenables. The [audit](../AUDIT_2026-11-16.md) and [baseline inventory](../BASELINE_INVENTORY.md) record exact evidence.

The user requested feature-first MVVM, repositories, services, dependency injection, an optional domain layer, characterization tests and architectural CI. Existing workspace instructions authorize continuous work, preserve the general ERP/optional pack contract and require isolated synthetic verification. No separate approval round or framework migration is needed.

## Alternatives

1. **Move files into feature folders only.** Low immediate churn, but widgets would still post data and own workflow rules. Rejected because directory movement does not meet the requested separation or permit isolated logic tests.
2. **Feature-first MVVM with incremental repository seams.** Keep widgets, state primitives and constructor APIs during extraction. Introduce small repository contracts and view models per feature, then move composition to the shell. Selected: behavior can be characterized and reviewed in bounded migrations.
3. **Replace state management and router while adopting a full clean/domain architecture.** More simultaneous behavior changes, dependencies and generated code; no demonstrated benefit for the current app. Rejected. Flutter treats these choices as adaptable recommendations, and the user explicitly requested preserving state management.

## Decision

Use the [responsibilities and dependency direction](../../../ARCHITECTURE.md) in `ARCHITECTURE.md`. Keep `setState`, `FutureBuilder`, retained futures, callbacks and existing listenables. Inject repository contracts and view models through constructors, with session-scoped instances assembled by `app/`. No global service locator. No provider/Riverpod/Bloc or router migration.

Repositories expose application models and own data policy; services wrap external I/O. `ErpApi` is the transitional authenticated service adapter. Do not rename it and claim transport/session separation is finished. Extract shared errors first to remove the API/model cycle. Keep old public import paths through thin exports during consumer migration.

Views own controllers, layout, animation, dialogs and navigation. View models own state transformation and commands. Create a domain policy only when at least two consumers reuse it or one algorithm is complex enough to crowd the view model; operation reconciliation and knitting decimal quantities qualify. Simple read features use no domain layer.

Each feature's migration is a sequential gate: characterization → extraction → format/analyze/full unit-widget suite/relevant connected test → review. Stop advancing to a new feature when the gate is red or unavailable. Do not replay writes after timeouts, loosen permissions or use customer data to make tests pass.

Architectural checks must understand imports, exports and parts; reject forbidden dependencies and new cycles. Existing violations can be explicitly baselined during rollout with exact source/target entries and an owner/removal wave. The baseline cannot grow or silently bless a new violation. Delete an exception when its feature is migrated. CI runs these checks and all default tests, with separate evidence for connected synthetic rehearsals.

## Consequences

- Smaller feature contracts make test fakes independent of socket construction.
- Temporary adapters/exports add a modest amount of transitional code. They have explicit removal gates.
- Widget labels, navigation and platform behavior stay stable; moving focus/controllers into models would violate the decision.
- Scope identity includes service/client, account, company and access revision. Pending reads/writes also carry request generation; disposing or replacing the owner invalidates results.
- Read invalidation does not cancel a server write. Revalidation hides sensitive state but keeps a same-model mutation serialized until its own completion handler settles. Regression tests enforce both request generation and write lifetime; neither substitutes for the other.
- Financial attempts pin payload, review token, request ID and recovery mode. Confirmation leases expire with access; the exact durable attempt remains recoverable. Acknowledgment follows a rendered confirmation before owner disposal, and stable-owner departure with a durable reference remains possible while access is unavailable. These boundaries have dedicated model and public-view regressions.
- Immutability applies at repository read boundaries. Existing edit-copy behavior is pinned before shared dynamic models are changed.
- The general foundation remains usable with knitting disabled. Cross-pack behavior depends on the common pack contract.
- This is a multi-feature migration, not one large rename. Completion requires final full-suite and connected receipts plus independent review with no unresolved material issues.

## References

[Official Flutter recommendations](https://docs.flutter.dev/app-architecture/recommendations), [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide), retrieved 16 November 2026. Keep the validated Flutter 3.47.9 / Dart 3.13.7 pin during this change.
