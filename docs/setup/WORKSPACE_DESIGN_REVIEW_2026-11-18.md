# Flutter workspace design review, 18 November 2026

The macOS production entry point compiled for Apple Silicon with the pinned Flutter 3.47.9 engine and passed strict recursive code-signature verification. The build uses the normal sign-in flow and the isolated HTTP origin on port 8081. A separate offline review build starts the production workspace shell with synthetic Loomfield Works data. The test server and a visible signed-in desktop session require separate verification.

| Operator task | Change and evidence |
| --- | --- |
| Read today's business activity | The desktop dashboard uses a 13:8 column split, with one stock illustration. Portrait phones lead with sales and recent invoices. Knitting emphasizes running jobs, queues and balances. |
| Find a workspace | Module icons follow the shared graphite palette. Text labels identify each destination. Search supports arrow navigation, submission from the keyboard and clearing the query. Four picker regressions passed. |
| Open a saved invoice | The record identifier transitions between register and editor and returns to the original scroll position. Reduced Motion skips the shared transition. A rejected read cancels the label in flight. The backend checks the selected company on an existing invoice read. |
| Enter an order | Fresh long forms follow visible ERPNext tabs and sections. Large tabs with multiple named sections split at section boundaries. Existing invoices and linked drafts retain the full editor. The phone layout shows one operation title and keeps Next reachable. |
| Correct a draft | Back and Next retain values. A cross-step conditional requirement returns the operator to its field. Pressing Back immediately after typing requires a discard decision. The combined guided-entry, document editor and invoice transition suite passed all 19 tests. |
| Use glass and motion | Translucency and a stationary edge distinguish navigation controls. Work surfaces remain readable. Reduced Transparency and high contrast select solid surfaces. Transitions communicate navigation and selection. |

The material treatment follows [Apple’s materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). The register transition follows [Flutter’s shared-element mechanism](https://docs.flutter.dev/ui/animations/hero-animations). The form hierarchy applies [progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/). Phone layouts and hit areas were reviewed against [Android adaptive layouts](https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts) and [Android accessibility guidance](https://developer.android.com/guide/topics/ui/accessibility/apps).

## Verification

The pinned-engine sweep discovered 122 Flutter test files. It recorded 849 passes, 38 failures when the test process tried to bind a loopback HTTP fixture, and one build-flag-specific skip. The latter runs separately with local-workspace mode disabled. Static analysis returned zero diagnostics. The architecture check covered 229 source files and found zero import cycles. All 253 migration tests and 74 top-level script tests passed.

The macOS native test launcher could not write its dedicated Colima profile. The test service on port 8081 was unreachable from the session. Real ERPNext authentication, connected posting and installed Android/iOS use remain open. The recorded phone outputs are Flutter renders at phone dimensions. Historical source limits and customer migration discrepancies are documented in the [data reconciliation](../coverage/2026-11-18-knitpack-data.md) and [workflow audit](../coverage/2026-11-18-knitpack-workflows.md).

## Separate knitting customer delivery

For the local knitting customer use `scripts/erp-customer.command`. It targets the customer site on 127.0.0.1:8082, builds with `ERP_KNITTING_CUSTOMER=true` and installs an app with its own macOS bundle identity. The login screen shows Knitting Workspace. The client requires the server to confirm an enabled knitting-only company before entering the workspace. The customer launcher starts its own site and queues without seeding the general demo. The general launcher provisions a single general-company profile in its own settings file. Existing shared profile files are preserved for older installations.

The separate read-only **Knitting Preview** was opened and inspected on the Mac. It displayed Mill overview, three sample jobs and a knitting-only sidebar. Yarn store, Production and Billing were opened and the window was left at Mill overview. The connected app requires the customer ERPNext service on port 8082. Its startup was blocked in the verification session by Colima profile filesystem permissions. Live authentication and posting are outstanding.

## Knitting dashboard and entry refresh

| Screen | Implemented interaction | Design basis |
| --- | --- | --- |
| Mill overview | One charcoal running-jobs card establishes the main destination. Work-queue icons use one graphite treatment and status words accompany the peach active-state accent. Phones place recent jobs directly below the primary card. | [Visual hierarchy](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/) |
| Wide mill overview | The primary and supporting columns use 13:8 proportions at widths that can support both. Narrow views and larger text use a single column. Research on rectangle proportions shows that preferences depend on the task and context. | [Rectangle proportions and context](https://pubmed.ncbi.nlm.nih.gov/10742842/) |
| Running jobs and job detail | The interactive dashboard card uses the existing translucent navigation material. Selecting a recent or registered job expands the detail card from its row bounds. Reduced Motion opens the detail immediately. | [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Material container transform](https://m2.material.io/design/motion/the-motion-system.html) |
| New job and estimate on phones | The brief comes first, followed by the fabric programme and review. Back retains values and validation reveals the relevant step. Short operational forms retain direct entry. | [Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/) |

The focused Flutter matrix passed 155 cases. Software renders of the dashboard and job details passed at 1280 × 900, 390 × 844 and 360 × 780 with the bundled fonts and icons. The Mac preview was signed and left at Mill overview with explicit sample data. Static analysis returned zero diagnostics. All 75 top-level script tests and 253 migration tests passed. The isolated launcher exited when Colima could not write its dedicated profile, leaving authenticated ERPNext verification and installed phone checks outstanding.
