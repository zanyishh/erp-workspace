# First Flutter UI preview — historical record

**Superseded by the ongoing [native workflow increment](NATIVE_WORKFLOWS.md).** The browser handoff below describes the first checkpoint, not the current document routes.

This is a **partial native client**, not a complete native replacement for ERPNext. The Flutter overview and eight record browsers are implemented. Creating/editing documents still opens the original browser-based ERPNext forms. ERPNext runs locally on this Mac at `http://localhost:8080`; no Vercel deployment was made. AI workflows are not implemented.

## Verified

- Flutter analyzer: no issues. Full client suite: 22 tests passed, including signed financial values, company/date filters, calendar boundaries, denied permissions, session expiry, malformed amounts, POST logout, search, pagination recovery, module menu lifecycle and accessibility taps.
- Overview layout passed at 390, 834 and 1440 logical pixels. Compact sign-in supports 1.3× text. A keyboard-constrained 390×240 module area scrolls without overflow.
- Product builds passed: macOS debug app, native ARM64 iPhone simulator app, Android ARM64 debug APK. Windows compilation and physical-device execution remain unverified.
- Live read-only login, company overview, all eight module queries and logout passed against the local evaluation service. Company ERP Evaluation, INR, five warehouses, no business transactions.
- Actual Mac app: sign-in, Stock card, record search, clear search, refresh and Stock → Accounts menu navigation verified. Browser handoff opened the correct local Sales Invoice login redirect in the default browser; browser sessions are separate from the native client's session. No business document was created or changed.
- Native preview left open full screen on the overview. Screenshot: [ERP Workspace overview](../design/erp-workspace-overview.png).
- All three upstream checkouts remain unchanged. Source/font notices and app/dependency license access are preserved.

## Run again

Double-click `scripts/erp-workspace.command` from the workspace. It starts the dedicated local ERP service and opens the existing Mac debug build, building it first if missing. For code changes, use `flutter run -d macos` or rebuild before reopening. Stop the backend with `scripts/stop-erpnext.command`; data is retained.

Client source: `apps/erp_client/`. Original generated 3D assets and open fonts are bundled inside that folder. The palette/type/spacing decisions and image prompts are recorded under `docs/design/`. Rebuild commands and connection notes are in the client README. Disposable detailed verification logs are in ignored `.local/reports/`.

## Next scope

To deliver the user's eventual fully native product, implement the Create/Edit document workflows inside Flutter while retaining ERPNext's business rules and permissions. The current browser handoff is a temporary scope boundary, not a finished replacement for those workflows. Product branding, store signing/distribution and AI agent behavior remain future work.
