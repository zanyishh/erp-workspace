# ERP usability research and correction catalogue

16 November 2026 · Flutter for macOS, Windows, iOS and Android · General ERP and optional knitting pack

The strongest improvement for this app is a consistent interaction system: preserve work and context, make consequences clear, help users correct mistakes, and make frequent work efficient. Selective shared-element transitions and progressive disclosure belong within that system. Neither is a universal treatment for every screen.

This research provides **60 proposed correction rules across 12 areas**, an evidence assessment, and a delivery/measurement approach. The companion [source audit and prioritized backlog](2026-11-16-erp-ux-audit.md) identifies **16 concrete findings** with file references and acceptance criteria. These findings are identified, not implemented. No customer account was accessed; no app code was changed for this research.

The user subsequently authorized implementation. See the later [verification record](../setup/UX_RUN_2026-11-16.md) for actual changes and results; the statements above describe the research stage only.

## What the evidence supports

“Proven psychology” needs care. Empirical studies, accessibility standards, platform conventions and design heuristics answer different questions. A guideline can be useful without proving that a specific change improves our ERP. The catalogue below contains proposed ERP adaptations; its sources support the underlying principles, not a measured improvement in this app.

| Evidence | Supported conclusion | Limit for this app |
| --- | --- | --- |
| Seckler and colleagues, CHI 2014, controlled study with 65 participants | A package of form improvements improved several performance and experience measures; completion-time improvement was significant for two of three forms. | Registration forms in a laboratory; individual rules were not isolated. Do not promise the same productivity gain for ERP. [Study](https://research.google.com/pubs/archive/42513.pdf) |
| Scheibehenne and colleagues, 2010 meta-analysis | Choice-overload effects varied substantially, with an approximately zero average across the included experiments. | Fewer visible choices are not automatically better; the study does not establish an optimum menu size. [Paper](https://scheibehenne.com/ScheibehenneGreifenederTodd2010.pdf) |
| Chernev and colleagues, 2015 meta-analysis | Complexity, task difficulty, preference uncertainty and decision goal help explain when choice overload occurs. | Consumer-choice findings require contextual adaptation; this is not independent replication of every earlier study. [Paper](https://chernev.com/wp-content/uploads/2017/02/ChoiceOverload_JCP_2015.pdf) |
| Miller, 1956 | Immediate memory and absolute judgment have limits; meaningful grouping changes what can be retained. | No prescription for seven cards, fields or navigation items. Visible information differs from information that must be recalled. [Original paper](https://labs.la.utexas.edu/gilden/files/2016/04/MagicNumberSeven-Miller1956.pdf) |
| Kalyuga, 2007 review | Instruction that helps novices can become redundant as expertise develops. | Evidence concerns learning; an ERP expert path is a design inference to test. [Review](https://www.uky.edu/~gmswan3/EDC608/Kalyuga2007_Article_ExpertiseReversalEffectAndItsI.pdf) |
| Material Research, 2022 | In a food-menu prototype, participants generally preferred container transforms and described continuity and positive emotional qualities. | Qualitative preference in a specific setting; no quantified ERP speed/error benefit or universal requirement. [Research report](https://m3.material.io/blog/motion-research-container-transform) |
| Heer and Robertson, 2007, two controlled experiments with 24 participants | Carefully designed animated transitions helped object tracking and some judgments of changing charts. | Statistical graphics, not ERP navigation; not every transition benefited equally. [Full paper](https://idl.cs.washington.edu/files/2007-AnimatedTransitions-InfoVis.pdf) |
| Tversky, Morrison and Bétrancourt, 2002 review | Apparent animation benefits can reflect added information or interactivity; complex/fast animation can be hard to understand. | Mainly explanatory graphics and learning; supports restraint, not a prohibition on useful motion. [Full paper](https://studio.courseware.epfl.ch/assets/courseware/v1/b4165ba2e4c9c5d3c8f48b67e2a65462/asset-v1:EPFL+DEMO+2020+type@asset+block/https___web.cs.dal.ca__sbrooks_csci4166-6406_seminars_readings_Tversky_AnimationFacilitate_IJHCS02.pdf) |
| WCAG 2.2 and WCAG2ICT | Accessibility offers concrete criteria; WCAG2ICT explains applying relevant principles to native software. | WCAG is a web standard; WCAG2ICT is informative guidance, not a new normative standard or automatic native certification. [WCAG 2.2](https://www.w3.org/TR/WCAG22/), [WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/) |

Authoritative design-system advice is a strong starting point, but its component sizes, thresholds and patterns are conventions rather than universal psychological constants. In particular, SAP advises against wizards for familiar daily tasks, and Material advises restraint with container transforms in deep or frequently used navigation. [SAP wizard guidance](https://www.sap.com/design-system/fiori-design-web/v1-145/ui-elements/wizard), [Material transition guidance](https://m3.material.io/styles/motion/transitions/applying-transitions)

## The two requested examples applied to our app

| Pattern | Recommended ERP treatment | When to use another treatment |
| --- | --- | --- |
| Shared-element transition | Pilot an active job card opening into the same job's detail header. Preserve job ID, status and a modest identity anchor; return to the originating row and filter state. | Frequent accounting-register navigation, unrelated destinations, deep hierarchies, missing source rows, reduced motion or changed permissions. Use stable identity and ordinary navigation instead. |
| Progressive disclosure | Show the common task's necessary fields; reveal clearly named Shipping, Additional charges or Accounting dimensions when relevant. Guided company setup can use steps and a review. | Routine invoice/production entry should retain direct editing and fast keyboard access. Do not hide required errors, stock ownership, tax/amount consequences or non-default values that need review. |

A shared-element animation cannot repair a Back action that loses a filter. A step indicator cannot repair a workflow that discards input after an error. Both patterns should build on retained state and honest outcomes. Flutter provides Hero for shared elements; introducing it selectively does not require replacing the app's design system. Verify compatibility with the project's pinned SDK before implementation. [Flutter Hero documentation](https://docs.flutter.dev/ui/animations/hero-animations)

## How Impeccable and SaglitzDesign were used

**Impeccable 4.9.1** was inspected at commit `2b86d9c07b97d4bed7de23583e1bd1e58dd2baae`. Its Operate mode, critique, native audit and platform guidance were applied to the source review. Operate emphasizes scanability, consistency, native expectations and restrained expression. Its native audit explicitly covers Flutter; its HTML/CSS detector is not suitable for this app. The context launcher was attempted once with its cache confined to disposable local storage, but the pinned engine download failed. Existing approved project documentation supplied context; no automated Impeccable score is claimed. [Pinned project](https://github.com/pbakaus/impeccable/tree/2b86d9c07b97d4bed7de23583e1bd1e58dd2baae), [native audit guidance](https://github.com/pbakaus/impeccable/blob/2b86d9c07b97d4bed7de23583e1bd1e58dd2baae/skill/reference/audit.native.md)

**SaglitzDesign MCP 0.29.0** was built from inspected source at commit `b69521e5beca35d060164fb9455ee1d22371a7f5` and invoked through a temporary local MCP session. It exposed 36 tools; 19 read-only calls produced 17 useful results covering review/interaction guidance, platform comparisons, contrast calculations and narrow native runner checks. Two document-name misses were followed by a corrected lookup and topic search. No global MCP configuration or app dependency was changed. Its native source scanners inspect platform runner/configuration files, not the Dart screen tree; empty findings there do not establish that the Flutter UI passes. [Pinned project](https://github.com/HalidSaglam/saglitzdesign-mcp/tree/b69521e5beca35d060164fb9455ee1d22371a7f5)

Some toolkit suggestions conflict with this ERP's needs. Do not adopt arbitrary option limits, single-column-only forms, Undo for every posted mutation, ornamental staggers or optimistic financial success. The approved product contract, transaction semantics and primary accessibility guidance take precedence.

Saglitz's solid-color calculations gave ink/surface **14.30:1**, muted/surface **5.31:1**, muted/canvas **4.77:1**, and light/charcoal **16.00:1**. These pairs meet the 4.5:1 normal-text contrast benchmark. They do not certify composited gradients, disabled states or every screen. Peach/surface was **2.04:1** and border/surface **1.45:1**: check whether each rendered accent/border is required to perceive a control or state before declaring a failure. An upcoming-step number pair was **1.50:1**, but its shared component is currently unused, so it is component debt rather than a demonstrated live-screen defect.

Pinned source, tool receipts and launcher diagnostics are retained under local toolkit evidence (`.local/ux-research-2026-11-16/toolkits/evidence`). Disposable evidence is ignored by Git; the conclusions and backlog remain in repository documentation.

## Correction catalogue

The following rules define coverage for implementation. They are not 60 claims that the app currently fails. A rule is complete only when its relevant states and representative workflows pass. The companion audit establishes which gaps were actually found in source.

### 1 Orientation and navigation

Purpose: reduce what users must remember and make their location and return path predictable. Platform keyboard guidance supports deliberate initial focus and complete keyboard operation. [Microsoft keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions)

| ID | Correction and acceptance check |
| --- | --- |
| C01 | **Keep business context visible.** Company, record identity and relevant warehouse/owner remain identifiable during editing and review. A context change cannot silently reassign a draft. |
| C02 | **Return to the same working place.** Preserve filters, sort, page, scroll anchor and selection after detail navigation. Clear protected state on scope changes. |
| C03 | **Match navigation to the task.** Organize destinations around recognizable work, with labels and useful search. Keep equivalent actions in predictable locations across modules. |
| C04 | **Return keyboard focus deliberately.** Dialog close and Back restore a sensible control; deletion moves to a valid neighbor. No invisible or duplicate focus stops. |
| C05 | **Make alternatives discoverable.** Hierarchy, breadcrumbs and the selected navigation state clarify location; essential actions never depend on hover or a remembered gesture. |

### 2 Progressive disclosure and workflow structure

Purpose: reduce irrelevant decisions while preserving the information needed to act safely. Defer infrequent detail only when the path to it stays clear. Daily expert work and unfamiliar setup need different treatments. [Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/), [SAP wizard guidance](https://www.sap.com/design-system/fiori-design-web/v1-145/ui-elements/wizard)

| ID | Correction and acceptance check |
| --- | --- |
| C06 | **Expose the common task first.** Keep required and frequently used controls readily available; put optional detail under meaningful business labels. |
| C07 | **Reveal dependent questions at the right time.** Selecting a transaction type exposes its relevant fields. Hidden invalid values cannot silently block completion or remain consequential without review. |
| C08 | **Use steps for real dependency or unfamiliarity.** Show meaningful step names, current position and Back/Next; retain prior values and allow correction from review. Do not force all daily entry into a wizard. |
| C09 | **Support an efficient expert path.** Permit direct section access, keyboard entry and reusable authorized defaults without instructional detours. Both paths obey the same validation. |
| C10 | **Expose what was deferred.** Collapsed sections summarize permitted consequential selections and errors. An error opens its section; changing layout does not reset expansion or data. Disclosure never reveals permission-hidden fields. |

### 3 Field and row entry

Purpose: reduce recall, ambiguity and avoidable correction. Labels and group relationships must survive both visual entry and spoken interaction. [WAI labels](https://www.w3.org/WAI/tutorials/forms/labels/), [WAI grouping](https://www.w3.org/WAI/tutorials/forms/grouping/)

| ID | Correction and acceptance check |
| --- | --- |
| C11 | **Keep labels visible after entry.** Use precise labels, required/optional meaning and nearby units. Quantity, rate, weight, source and destination must not depend on placeholder memory. |
| C12 | **Use appropriate input methods.** Dates support selection and fast typing; money/weight support decimals; signed adjustments allow a minus sign. Validate calendar and numeric meaning explicitly. |
| C13 | **Explain and constrain defaults.** Default company, warehouse or unit only from valid scope; show consequential defaults and let authorized users change them. Never carry a default across an incompatible company. |
| C14 | **Preserve all valid work after failure.** Retain field values and row identities on rejection, retry and session recovery, subject to access revalidation. Avoid reset controls beside Save. |
| C15 | **Make repeated entry efficient.** Offer suitable row navigation, add-another and safe copying of compatible values. Revalidate copied context and preserve stable row identity when rows are inserted or removed. |

### 4 Validation and recovery

Purpose: turn a failure into a clear next action. Validation timing depends on the field; a partially typed date is not necessarily an error. [WAI notifications](https://www.w3.org/WAI/tutorials/forms/notifications/)

| ID | Correction and acceptance check |
| --- | --- |
| C16 | **Validate at a useful moment.** Check format on appropriate completion/blur and business rules on review/save. Avoid repeated premature warnings while the user is still entering a valid value. |
| C17 | **Place the error beside its cause.** Say what is wrong and how to fix it, with field-specific messages and a linked summary for long forms. Do not rely on red borders alone. |
| C18 | **Take the user to the first actionable error.** On failed submit, open the relevant section, scroll and manage focus. Ordinary background validation must not steal typing focus. |
| C19 | **Differentiate failure classes.** Validation, stale revision, denied permission, expired session, failed read and unknown write outcome need different recovery actions. A generic Retry cannot safely cover all of them. |
| C20 | **Recover accidental local edits.** Provide Undo for removing unsaved rows and appropriate draft-leave protection. Preserve original values/order; posted records use explicit correction or reversal history. |

### 5 Transaction confidence

Purpose: help users understand the difference between intent, processing and confirmed business state. Review or reversal/checking protects consequential actions; it does not mean every draft save needs a confirmation dialog. [WCAG error prevention](https://www.w3.org/TR/WCAG22/#error-prevention-legal-financial-data)

| ID | Correction and acceptance check |
| --- | --- |
| C21 | **Name actions by their outcome.** Distinguish Save draft, Submit invoice, Record production and Cancel posting. The label and subsequent state agree. |
| C22 | **Review the exact permitted consequence.** Show company, party, permitted quantities/amounts, ownership and dependencies before posting/reversal. Use authoritative server projections; users without financial-read permission must not fetch, render or persist restricted rates/amounts for a summary. |
| C23 | **Invalidate outdated reviews.** A changed quantity, date, price, permission or server revision requires a fresh relevant check. A stale preview cannot remain an apparently valid approval. |
| C24 | **Handle duplicate intent and unknown outcomes.** Disable repeated activation while processing; retain request identity where supported and reconcile the original operation after a lost response. Never manufacture a success state. |
| C25 | **Provide a durable result and next action.** Show the actual reference, permitted result details and safe follow-up. Unresolved operations remain discoverable after navigation/restart, keyed by server/site/account/company and protected by fresh access checks. |

### 6 Feedback and waiting

Purpose: maintain orientation and communicate real progress. The familiar 0.1/1/10-second thresholds are approximate heuristics, not universal deadlines or artificial delays. [Response-time guidance](https://www.nngroup.com/articles/response-times-3-important-limits/)

| ID | Correction and acceptance check |
| --- | --- |
| C26 | **Acknowledge intent immediately.** Show pressed/working state promptly while keeping the real result separate. Animation must not delay input or server work. |
| C27 | **Separate initial loading from refresh.** Use a stable first-load footprint; keep same-scope loaded content during refresh with a freshness label. Clear it on site/account/company/access changes. |
| C28 | **Show honest progress.** Use percentages only when measurable; otherwise name the current stage. Never animate invented totals or fabricate how near completion is. |
| C29 | **Make failures recoverable in place.** Retry preserves query/input/context. Longer work exposes cancellation only if supported, and describes what cancellation actually stops. |
| C30 | **Match feedback persistence to consequence.** Small reversible actions can use brief status messages; consequential results/errors remain available. Announce new states once without repeated screen-reader chatter. |

### 7 Motion and visual continuity

Purpose: explain spatial relationships and state change without competing with work. Apple recommends brief, purposeful, interruptible motion and restraint for frequent interactions. Material recommends different patterns for different navigation relationships. [Apple motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Material transitions](https://m3.material.io/styles/motion/transitions/applying-transitions)

| ID | Correction and acceptance check |
| --- | --- |
| C31 | **Animate a relationship, not decoration.** Use a selective job/card identity transition when it makes the destination clearer. Do not morph unrelated objects or animate financial totals in flight. |
| C32 | **Keep navigation meaning consistent.** Forward/Back, peer tabs and top-level switches should convey their actual relationships. Honor platform Back behavior; do not use one dramatic transition everywhere. |
| C33 | **Make motion interruptible and economical.** Repeated entry remains responsive. Rebuilds and refreshes do not replay entrances; no ornamental stagger, hover lift or celebration blocking routine work. |
| C34 | **Respect reduced motion throughout.** Routes, charts, disclosures, status changes and loaders all adapt. Use static updates or restrained fades with the same information and controls. |
| C35 | **Preserve stable geometry and semantics.** Keep identity anchors, avoid abrupt content shifts and prevent outgoing layers receiving input or being read twice. Return to the same meaningful context. |

### 8 Search, tables and bulk work

Purpose: support scanning and comparison without sacrificing precision. A readable table and an editable grid have different interaction obligations. Carbon documents dense enterprise tables and explicit batch-action scope; WAI describes structured grid keyboard behavior. [Carbon tables](https://www.carbondesignsystem.com/building-blocks/core/components/data-table/guidelines), [WAI grid pattern](https://www.w3.org/WAI/ARIA/apg/patterns/grid/)

| ID | Correction and acceptance check |
| --- | --- |
| C36 | **Keep search stable.** Debounce where useful, ignore superseded responses, preserve focus and show progress without blanking the chooser. Stale results cannot masquerade as current matches. |
| C37 | **Make filter and sort state explicit.** Show active criteria, sort direction, result count/scope where known and an obvious reset. Preserve these on return navigation. |
| C38 | **Support comparison at appropriate density.** Keep identifying columns and aligned values readable; offer relevant column/density choices. Compact office rows must not become tiny touch targets. |
| C39 | **State exactly what is selected.** Distinguish current-page selection from all matching records; display selected count and batch consequences. Recheck scope/eligibility before applying an action. |
| C40 | **Define row and cell interaction.** Row open, checkbox selection and inline editing must not conflict. Provide keyboard equivalents, bounded paging/lazy rendering and stable focus when data updates. |

### 9 Reports, numbers and data meaning

Purpose: make the basis of a number inspectable and keep comparison reliable. These are ERP-specific proposals informed by enterprise table guidance and the existing server-authority contract, rather than claims of directly measured psychological effects.

| ID | Correction and acceptance check |
| --- | --- |
| C41 | **Show units, precision and basis.** Every consequential metric identifies currency/weight/count, applicable period or as-of time, and relevant scope. Do not mix stock balances and period movement under one label. |
| C42 | **Distinguish zero, missing and unavailable.** No records, filtered-out records, loading, not configured and permission denial must not all become “0” or an empty panel. |
| C43 | **Separate pending filters from applied results.** Show which filters generated the visible table. Rerun replaces both labels and result together; exports match the applied result. |
| C44 | **Make summaries traceable.** Totals and charts lead to the relevant source set when permitted. Explain an unavailable drilldown without exposing restricted data. |
| C45 | **Keep authoritative numbers stable.** Use exact server results in review/export, readable alignment and consistent formatting. Overview abbreviations provide the full value; charts also offer accessible data. |

### 10 Accessibility and input parity

Purpose: make the same task achievable through sight, touch, keyboard and assistive technology. Native acceptance draws on platform guidance and Flutter verification, not a claim that web CSS measurements directly apply. [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Flutter accessibility](https://docs.flutter.dev/ui/accessibility)

| ID | Correction and acceptance check |
| --- | --- |
| C46 | **Expose names, roles, values and states.** Labels, selected/expanded/disabled states, errors and status changes are intelligible through native accessibility APIs. Decorative art stays out of the reading order. |
| C47 | **Complete frequent work with a keyboard.** Logical traversal, visible focus, sensible compound-control navigation and platform shortcuts cover searching, editing, correcting and saving. No keyboard traps. |
| C48 | **Provide usable hit areas and spacing.** Apply platform-appropriate targets; use 48 logical pixels as a proposed shared touch baseline, larger where station use needs it. Verify actual hit regions rather than icon artwork alone. |
| C49 | **Make essential information independent of color.** Text/icons identify statuses and errors; inspect contrast on actual surfaces and focus/selection states. A theme-level calculation is only a starting check. |
| C50 | **Honor large text and input alternatives.** Reflow instead of shrinking important values; controls remain reachable at 200% text. Drag/swipe/hover actions have discoverable alternatives. |

WCAG 2.2 AA's pointer-target criterion uses **24×24 CSS pixels with exceptions**; it is not the native product target above. Interaction-triggered motion disabling is **AAA** in WCAG, while this product deliberately adopts reduced-motion support regardless. Neither a rule checklist nor a widget test establishes complete native accessibility. [WCAG target size](https://www.w3.org/TR/WCAG22/#target-size-minimum), [WCAG interaction animation](https://www.w3.org/TR/WCAG22/#animation-from-interactions)

### 11 Responsive layout and visual hierarchy

Purpose: preserve comprehension as window size, input method and text size change. The following are product design decisions to verify with native layouts; they do not require replacing the approved palette, typography or brand assets.

| ID | Correction and acceptance check |
| --- | --- |
| C51 | **Adapt composition, not just scale.** Desktop supports useful adjacent context and dense comparison; phone focuses on the current task. Do not squeeze the full desktop rail onto a small screen. |
| C52 | **Keep actions reachable while editing.** Keyboard/IME, safe areas, resizable windows and scrolling must not cover the active field or primary action. Sticky controls cannot hide focused content. |
| C53 | **Use a clear local action hierarchy.** The primary action is visually identifiable for the current task; secondary and destructive actions stay distinguishable and consistently placed. |
| C54 | **Group with meaningful spacing and type.** Related labels/values stay together; headings reflect business structure. Do not solve a crowded form by shrinking type or wrapping every fragment in another card. |
| C55 | **Keep visual effects subordinate to readability and speed.** Preserve approved materials where useful; use solid/high-contrast alternatives and lightweight repeated rows. Profile blur, charts and transitions on the target hardware. |

### 12 Language, onboarding and user control

Purpose: reduce interpretation and repeat learning while keeping meaningful choices under the user's control. Expert/novice differences motivate optional guidance rather than compulsory explanations on every visit. [Expertise reversal review](https://www.uky.edu/~gmswan3/EDC608/Kalyuga2007_Article_ExpertiseReversalEffectAndItsI.pdf)

| ID | Correction and acceptance check |
| --- | --- |
| C56 | **Use concrete business language.** Name the affected object and remedy; keep raw technical detail secondary. Status text distinguishes draft, posted, held, completed and pending verification. |
| C57 | **Teach the next useful action.** Empty states and setup checklists explain why the screen is empty and what the authorized user can do next. Guidance is dismissible/revisitable and does not repeat unnecessarily. |
| C58 | **Respect saved preferences without changing truth.** Remember appropriate views/density and compatible defaults within server/site/account/company scope. Preferences never grant permissions or silently change business policy. |
| C59 | **Handle localization and real content lengths.** Verify long names, translated labels, date/number presentation and text direction when supported. Display formatting never changes authoritative precision or date meaning. |
| C60 | **Make capability and control honest.** Explain unavailable actions when useful and permitted; distinguish not configured from denied. No fake urgency, preselected consequential consent or success before acknowledgement. |

## Shared patterns to build and reuse

Apply these patterns to General ERP and industry screens through shared components. Avoid a new parallel UI system just for knitting.

| Pattern | Required behavior | Existing starting point |
| --- | --- | --- |
| Retained editor session | Dirty state, safe leave, rejected-input retention, pending-reference recovery keyed by site/account/company, access revalidation | General editor and knitting draft/review flow |
| Sectioned form and error summary | Schema grouping, optional details, hidden-error reveal, field focus, direct expert editing | DocumentFields and knitting error navigation |
| Lookup/result controller | Debounce, latest-query protection, stable loading, retry, scope-aware invalidation | Existing register lookup patterns |
| Review and receipt | Exact company/record/consequences, changed-preview invalidation, acknowledged receipt, unknown-outcome recovery | Knitting review/receipt |
| Retained list/report state | Query/page/scroll/focus retention, applied-filter identity, honest stale data and export scope | Module browsers, catalogue and reports |
| Accessible feedback | Consistent labels, focus, single announcements, errors with remedies, reachable Undo | Existing success/sign-in/POS semantics |
| Context-sensitive motion | Standard navigation, selective identity transitions, interruptibility, reduced motion, one semantic destination | WorkspaceRouteTransition and shared motion helper |

Motion timings and lookup debounce intervals are tuning choices, not psychological constants. Reuse the existing short timing scale as a starting point, then measure responsiveness on the 8 GB Mac and actual mobile devices. At 60 Hz the frame budget is about 16.7 ms; at 120 Hz it is about 8.3 ms. Record profile/release traces rather than claiming smoothness from a widget test.

## Implementation order and success measures

1. **Protect work and outcomes.** Address audit F01–F03, draft row Undo, review clarity and error recovery. Success means retained input, known operation outcomes and no ambiguous invitation to repeat a write.
2. **Preserve working context.** Address list return, lookup refresh and report filter state. Success means users resume the same task without reconstructing it.
3. **Improve entry and accessibility.** Introduce meaningful sections, navigable validation, date/numeric input, native semantics and keyboard parity. Keep experienced operators' direct path.
4. **Refine continuity and visual consistency.** Pilot selective shared elements, large-text layout, status/action consistency and performance. Remove any remaining guidance that contradicts the approved ban on ornamental lifts/staggers.

Evaluate occasional administrators, daily office operators and shop-floor users separately. Proposed synthetic tasks are: configure a company; find an invoice from a filtered second page; enter and correct a multi-row invoice; remove/restore a draft line; record production and recover a lost response; resolve QC/delivery eligibility; and change a report filter before exporting.

For each task, record completion, first-attempt success, correction time, total time, lost context, duplicate intent and whether the user understands the resulting state. Collect perceived effort/confidence as secondary measures. Compare baseline and corrected versions with equivalent task variants and counterbalanced order to reduce practice effects. Use early sessions to find problems; determine sample size from a specific hypothesis and observed variability before making statistical improvement claims. Record median/spread and failure cases, not only averages.

For the shared-element pilot, compare ordinary retained navigation with retained navigation plus motion. Otherwise a state-retention fix could be incorrectly credited to animation. For disclosure, compare first-time and repeated use; fewer visible fields or fewer clicks alone is not success.

Connected validation uses synthetic fixtures on `native-test.localhost`, the named launchers and explicit `colima-erp` context. Preserve the original ERPNext baseline, stock/financial behavior and all data volumes. Company/permission boundaries remain server-enforced. AI remains deferred. Windows compilation and native interaction require a Windows host; mobile build success alone does not establish device behavior.

## Remaining evidence to collect

The source audit does not establish native screenshot quality, actual screen-reader output, device hit regions, composited contrast, gesture behavior, animation performance or measured operator productivity. Those are the next verification activities after corrections. No “all aspects proven” or overall UX score is justified at this stage.

The immediate actionable result is the [16-item backlog with acceptance criteria](2026-11-16-erp-ux-audit.md). The wider catalogue prevents later work from stopping at color, rounded corners and animations while entry, recovery, accessibility or transaction confidence remain inconsistent.
