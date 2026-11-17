# Workspace stage preparation

This is the next-stage design checklist. Authentication's full-suite gate must finish before Workspace application edits begin.

## Characterize before extraction

- Replace `WorkspaceShell.connect` while owner signup is pending. The stable bound `_connect`/`_signIn` tear-offs currently hide this replacement from the authentication adapter; old registration must not authenticate through the new factory.
- Replace that factory while login or workspace-context loading is pending. Old completion must close its own client and must not publish its company, overview or error into the replacement shell.
- Replace a local-opening dependency while its read is pending; keep the accepted local profile/company checks and close obsolete clients.
- Preserve single-company and multi-company local profiles, company selection, industry choice, retained module/query/scroll state, returning-account selection, access refresh and recovery with unsaved drafts.

## Responsibilities

- The app shell owns client lifetimes, route/dialog composition and repository construction. Capture a factory and an attempt identity for each connection; test identity after each await before publishing a client. Stable callbacks remain stable during ordinary rebuilds and change when their underlying dependency changes.
- A `WorkspaceRepository` wraps current/default context reads and explicit company selection. It validates returned company visibility and rejects results from a replaced client/account. A context refresh may itself update the access revision, so it must not reject its own authoritative response merely because that revision advanced.
- A plain Dart workspace view model owns context-loading/selection state and presentation policy. Controllers, dialogs, snackbars and navigation stay in the view/composition layer. Keep API objects out of its public data contract.
- Move the existing immutable workspace context to a shared model seam with public import compatibility. Preserve its server keys, permissions and optional-pack semantics.
- Local launch configuration remains platform I/O in a service, including strict loopback/site/profile validation. Keep credentials out of view-model state and logs. The composition root injects the resulting client; the repository owns company/access validation.
- Workspace-picker search is local presentation state over static module values. It needs a small view model, not an artificial network repository or domain use case.

## Gate

Use the established exact before-images, characterization-first sequence, format/analyze, architecture regression/lint checks, entire default unit/widget suite, explicit local-launch opt-out variant, relevant synthetic connected rehearsal and independent review. The remaining overview/shell composition work retains its separate later gates.
