# ERP interaction audit and correction backlog

16 November 2026. Source review of the current Flutter workspace, covering General ERP and the optional knitting pack. These are implementation findings and design opportunities, not results from a usability study. No app changes, native walkthrough, backend tests or customer-account access were performed for this audit. Existing work was preserved.

Implementation follow-up: this document preserves the pre-change findings and their original line references. The later [verification record](../setup/UX_RUN_2026-11-16.md) records the implementation and checks; it supersedes the historical “identified, not implemented” status below.

The first priorities are protecting entered work, making uncertain outcomes recoverable and retaining navigation context. Motion and visual refinement follow those corrections. The companion [research and correction catalogue](2026-11-16-erp-ux-research.md) explains the evidence and wider coverage.

## Existing behavior to preserve

- General document and child-row editors already protect dirty navigation and retain rejected input: [document_editor.dart:624](../../apps/erp_client/lib/document_editor.dart#L624) and [document_fields.dart:460](../../apps/erp_client/lib/document_fields.dart#L460).
- Knitting already separates entry, review and confirmed receipt, including an uncertain-outcome state and status checking: [knitting_forms.dart:2041](../../apps/erp_client/lib/knitting_forms.dart#L2041). Stage announcements exist in [knitting_entry_layout.dart:407](../../apps/erp_client/lib/knitting_entry_layout.dart#L407).
- Shared routes and controls have reduced-motion handling; outgoing shell panels are noninteractive. Text accompanies important statuses. Company changes revalidate access and clear scoped context.
- The catalogue distinguishes no records, no matches and unavailable access. Existing tests cover several dirty-form, rejected-save, row-identity, recovery, narrow-layout and reduced-motion cases; those tests were inspected, not rerun.

## Prioritized findings

Priority P1 means significant work-loss, recovery or repeated-task friction. P2 means a meaningful usability correction with a workaround. An opportunity is explicitly identified where the current implementation is not inherently defective. All entries remain **identified, not implemented**.

### F01 P1 Protect invoice drafts when leaving

**Evidence:** [invoice_composer.dart:46](../../apps/erp_client/lib/invoice_composer.dart#L46) tracks edits, but the screen beginning at [line 376](../../apps/erp_client/lib/invoice_composer.dart#L376) has no dirty-navigation guard. The edit check protects the Full editor handoff only. The screen also holds a pending request identity in memory.

**Correction:** Reuse the existing draft-leave guard for toolbar, system and keyboard Back. Distinguish unsaved edits, in-flight requests and uncertain outcomes. Preserve a safe recovery reference before permitting departure from an uncertain operation. Untouched or confirmed forms should leave immediately.

**Acceptance:** Enter an invoice, use every Back path, then choose Keep editing: all values remain. Explicit discard removes only the draft. An unresolved save cannot silently lose its recovery identity.

### F02 P1 Make uncertain outcomes consistent across General ERP

**Evidence:** [document_editor.dart:560](../../apps/erp_client/lib/document_editor.dart#L560) presents write failures as an error string, with stale-document detection. [payment_reconciliation.dart:169](../../apps/erp_client/lib/payment_reconciliation.dart#L169) clears selections and asks for refreshed balances. Neither supplies the same explicit outcome-verification experience as knitting.

**Correction:** Separate confirmed rejection from a lost response after possible commit. Retain attempted context and offer operation-specific status reconciliation. Confirm the backend's idempotency/status contract before exposing a retry. This finding does not establish that backend duplicate posting is possible.

**Acceptance:** In a synthetic test where commit succeeds but its response is lost, the client determines the actual outcome before offering another mutation. Confirmed validation failures return to editable retained input.

### F03 P1 Retain knitting recovery references beyond a screen

**Evidence:** [knitting_forms.dart:1525](../../apps/erp_client/lib/knitting_forms.dart#L1525) allows leaving while telling the user to keep the request reference. [knitting_models.dart:92](../../apps/erp_client/lib/knitting_models.dart#L92) keeps that draft/request state in memory.

**Correction:** Maintain server/site/account/company-scoped pending-operation references and a visible recovery entry. Retain only the minimum safe context; recheck permissions before restoring details. Company is not the tenant boundary; the backend site is. A pending-operation record is not an offline posting queue.

**Acceptance:** After navigation and app restart, the user can check the original request without reentering it or manually copying an ID. A different site/account/company cannot read or replay the pending operation. Test identical usernames and company names on two sites.

### F04 P1 Preserve the list after opening a record

**Evidence:** [main.dart:633](../../apps/erp_client/lib/main.dart#L633) refreshes after the editor closes. The refresh revision participates in the subtree key at [line 930](../../apps/erp_client/lib/main.dart#L930), recreating the module browser's initial query/page state in [module_browser.dart:43](../../apps/erp_client/lib/module_browser.dart#L43).

**Correction:** Refresh data without remounting the working list. Retain query, filters, sort, page, scroll anchor and focused record. Clear these on company or access-scope change.

**Acceptance:** Filter a list, visit page two, open a record, return: the same context and row remain visible with updated data. If the row no longer matches, explain its removal and retain a sensible neighboring anchor.

### F05 P2 Respect meaningful form sections

**Evidence:** [document_fields.dart:215](../../apps/erp_client/lib/document_fields.dart#L215) renders Tab Break, Section Break and Heading as headings within one long form.

**Correction:** Use schema groupings for real sections/tabs and named optional disclosures. Preserve a compact expert entry path. Required fields, errors and posting consequences within the user's permitted projection must be visible or automatically exposed; disclosure never reveals permission-hidden fields. This is not a blanket conversion to wizards.

**Acceptance:** Common fields are easy to locate. A hidden invalid field opens its section on submit. Expansions and values remain stable during edits; review includes every consequential value.

### F06 P2 Navigate to validation errors

**Evidence:** [document_editor.dart:496](../../apps/erp_client/lib/document_editor.dart#L496) and [document_fields.dart:494](../../apps/erp_client/lib/document_fields.dart#L494) set errors without navigation to them. [invoice_composer.dart:91](../../apps/erp_client/lib/invoice_composer.dart#L91) combines errors into one sentence. Knitting scrolls toward its first error, providing a useful starting pattern.

**Correction:** Give field-specific explanations, a linked summary, and deliberate focus/scroll after an explicit submit. Keep typing focus stable during ordinary entry.

**Acceptance:** A keyboard user can submit a long invalid form, hear what failed and reach the first affected control. The field's label, error and entered value remain available together.

### F07 P2 Stabilize linked-record search

**Evidence:** [document_fields.dart:661](../../apps/erp_client/lib/document_fields.dart#L661) starts a lookup for every change; line 674 replaces results with a spinner. The error branch lacks a retry action.

**Correction:** Debounce the query, ignore superseded responses, preserve focus and result geometry, and offer Retry without losing the query. When showing previous-query results, label or disable them until current results arrive.

**Acceptance:** A rapid typing burst produces one final lookup after the chosen debounce interval. An older response cannot replace newer results. Failure and retry preserve the query; stale choices cannot be selected as current matches.

### F08 P2 Preserve useful content during refresh

**Evidence:** [native_catalog.dart:871](../../apps/erp_client/lib/native_catalog.dart#L871), [module_browser.dart:242](../../apps/erp_client/lib/module_browser.dart#L242) and [invoice_hub.dart:410](../../apps/erp_client/lib/invoice_hub.dart#L410) replace populated content during requests.

**Correction:** Distinguish initial loading from same-scope refresh. Retain the latter's content with a clear refreshing/stale state. Clear data immediately when account, company or permissions change.

**Acceptance:** A slow refresh preserves list geometry and scroll. A failed refresh offers Retry and marks freshness honestly; it never relabels old rows as a new successful response.

### F09 P2 Add selective object continuity

**Evidence:** No Hero usage was found in the Flutter library. [design.dart:188](../../apps/erp_client/lib/design.dart#L188) supplies a shared fade/short slide; [knitting_workspace_layout.dart:374](../../apps/erp_client/lib/knitting_workspace_layout.dart#L374) transitions whole destinations. This is a design opportunity, not proof that Hero is required.

**Correction:** Pilot one job card to detail transition with a stable identifier/status/symbol. Use conventional navigation for deep hierarchies and frequent register work. Returning to the correct row matters more than the animation.

**Acceptance:** Forward and Back retain recognizable identity, return context and a single accessible destination. Reduced motion, absent source rows or changed access use a static fallback. Do not animate authoritative totals or decorative illustrations independently.

### F10 P2 Make posting reviews specific

**Evidence:** [document_editor.dart:505](../../apps/erp_client/lib/document_editor.dart#L505) shows generic action text and document identity without a compact company/party/amount-or-quantity summary.

**Correction:** Display the affected company, record, counterparty and permitted amount/currency or stock quantity and consequences. Use the server's field-permission projection: a user without financial-read permission must not fetch, render or persist restricted rates/amounts to construct a summary. Use a meaningful permitted consequence summary instead. Use an action-specific button. Ordinary reversible draft saves do not need a modal review.

**Acceptance:** Users can verify the permitted details of what will be submitted/cancelled without closing the dialog. Authoritative summaries invalidate when inputs, permissions or server revisions change. An operator lacking financial-read permission receives no restricted financial values through review or receipt.

### F11 P2 Undo local row removal

**Evidence:** [document_fields.dart:138](../../apps/erp_client/lib/document_fields.dart#L138), [invoice_composer.dart:322](../../apps/erp_client/lib/invoice_composer.dart#L322) and [pos_checkout.dart:397](../../apps/erp_client/lib/pos_checkout.dart#L397) remove local rows immediately without Undo.

**Correction:** Restore accidentally removed draft rows with an accessible Undo action, including their values and order. Submitted records still use the existing permission-checked reversal process.

**Acceptance:** Remove then Undo restores the same row and position without retyping or a server mutation. Undo never restores a row into another document/company.

### F12 P2 Separate edited filters from applied filters

**Evidence:** [report_screen.dart:183](../../apps/erp_client/lib/report_screen.dart#L183) clears the displayed result on filter changes.

**Correction:** Keep the previous result with its applied-filter summary and a visible Filters changed — run to update state. Replace result and applied-filter labels together after success. Export must reflect the displayed applied result or be disabled pending refresh.

**Acceptance:** Editing a date preserves the old result and old date label. Running applies both atomically; failed execution retains an honestly labelled old result.

### F13 P2 Announce actionable errors

**Evidence:** [document_editor.dart:853](../../apps/erp_client/lib/document_editor.dart#L853) uses ordinary text for errors while success has live semantics. [widgets.dart:344](../../apps/erp_client/lib/widgets.dart#L344) provides no live announcement in the general MessagePanel.

**Correction:** Share an error component with a visible label/icon, concise remedy and one announcement for each new failure. Preserve the message until resolved without repeating it on rebuilds. Reuse working sign-in/POS semantics where suitable.

**Acceptance:** Each new submit/network failure is announced once, remains visible and offers a relevant recovery path. Errors are distinguishable without color.

### F14 P2 Preserve readable numbers at large text sizes

**Evidence:** [widgets.dart:253](../../apps/erp_client/lib/widgets.dart#L253) scales metric values down; its footer at line 271 is 10 logical pixels, below the documented metadata minimum. Actual rendered text size remains to be measured.

**Correction:** Let metrics reflow/grow instead of shrinking critical values. Keep units and time basis readable. Abbreviations are suitable for overview scanning only when the complete value is accessible; posting reviews require exact values.

**Acceptance:** Large realistic amounts and 200% text do not hide units, overlap content or shrink essential numerals into unreadability.

### F15 P2 Support appropriate date and numeric entry

**Evidence:** Knitting descriptors at [knitting_forms.dart:194](../../apps/erp_client/lib/knitting_forms.dart#L194) and line 474 require literal date/time formats. Scalar entry at [line 2892](../../apps/erp_client/lib/knitting_forms.dart#L2892) lacks the general editor's picker, and numeric keyboard selection misses signed numeric types.

**Correction:** Offer date/time selection alongside editable text; use suitable decimal/signed keyboards and visible units. Retain efficient desktop typing and strict calendar validation.

**Acceptance:** Mobile entry supports valid dates and negative adjustments without awkward keyboard switching. Invalid dates are rejected without silently changing them or losing other input.

### F16 P2 Make shortcuts platform appropriate

**Evidence:** [main.dart:904](../../apps/erp_client/lib/main.dart#L904) registers Meta+K and Meta+R only, while Windows is a product target.

**Correction:** Use the platform command modifier and visible hints; preserve normal text-editing shortcuts. Escape should return focus to the invoking control.

**Acceptance:** Ctrl+K on Windows and Command+K on macOS open the intended workspace command/menu control with usable focus. Native Windows verification requires a Windows host.

## Documentation conflict

The approved [industry-pack design:9](../superpowers/specs/2026-11-13-industry-packs-and-knitting-design.md#L9) rejects ornamental entrance staggers and card lifting. The older motion table in [WORKSPACE_EXPERIENCE.md:57](../design/WORKSPACE_EXPERIENCE.md#L57) still proposes them. The later user-approved refinement controls. Reconcile the subordinate table during implementation; no renewed approval round is needed for that correction.

## Delivery sequence

| Order | Work | Findings | Evidence needed before completion |
| --- | --- | --- | --- |
| 1 | Protect work and reconcile uncertain operations | F01–F03 | Meaningful draft/restart tests; lost-response scenarios on the isolated native test site where server support changes |
| 2 | Preserve navigation and refresh context | F04, F07, F08, F12 | Query/page/scroll/focus retention, race/failure tests, account/company scope changes |
| 3 | Make entry, correction and review clear | F05, F06, F10, F11, F13, F15 | Long-form, hidden-error, Undo, changed-review and keyboard/touch scenarios |
| 4 | Refine adaptation and continuity | F09, F14, F16 | Large text, platform shortcuts/Back, reduced motion, native profiling and a selective continuity pilot |

## Screen and state coverage

| Surface family | Required checks |
| --- | --- |
| Sign-in, company/workspace selection, setup, team access | Identity and company clarity; retained valid values; capability explanations; session recovery; no accidental access grants |
| Overview, module browser, catalogue and hierarchy | Scan order; search/filter/scroll retention; real data freshness; expandable navigation and source drilldown |
| General editors, child rows and linked-record selection | Meaningful sections; field errors; focus; draft leave guards; Undo; lookup race handling |
| Invoices, POS, bank import/matching and reconciliation | Draft versus posted states; exact summaries; unknown outcomes; retained attempt context; permission-aware correction |
| Knitting operations | Job/owner/godown/machine context; remaining quantities; scoped defaults; review/post/receipt; restart recovery |
| Reports, charts, imported history and previews | Applied filters; period versus as-of; unit/precision; empty versus denied; source identity; export consistency |
| Files, activity, settings and system dialogs | Upload/save state; explicit consequences; focus return; error/retry; access changes |

For representative routes, cover initial load, populated, empty, filtered-empty, refreshing, stale, denied, expired session, failed read, rejected write, stale revision, uncertain write and confirmed success. Exercise 390/834/1440 logical-pixel widths, normal and 200% text, keyboard/touch, reduced motion, soft keyboard and long/localized content. Use synthetic records only on `native-test.localhost` for connected checks. Preserve the original ERPNext baseline and all application volumes.

Source inspection establishes the branches and omissions above. Screen-reader announcements, actual focus traversal, composited contrast, target sizes, animation smoothness and task-completion improvements still require native verification. No overall accessibility or UX score is claimed.
