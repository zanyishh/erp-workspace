# ERP Workspace experience system

Design proposal dated 13 November 2026. Applies to the complete general ERP client and optional industry packs. Companion product design: `docs/superpowers/specs/2026-11-13-industry-packs-and-knitting-design.md`.

## Visual direction

Keep the approved reference's light neutral canvas, charcoal framing, rounded pale cards, restrained peach gradients, compact pills and original white 3D illustrations. Replace generic filler with actual work: due jobs, material shortages, machine queues, QC holds and pending invoices. A decorative illustration is never labelled as live factory data.

Keep Manrope for body, labels and values; use Barlow Condensed SemiBold for short display titles, not dense paragraph text or table numerals. Retain bundled font licences. No borrowed Fashion Suite or Creatora branding, photos or assets.

| Foundation | Contract |
| --- | --- |
| Colours | Canvas `#E7E8E4`; surface `#F4F4F0`; charcoal `#191B19`; ink `#20231F`; muted `#686E66`; border `#C7CBC3`; peach `#E99A70`; pale peach `#F4D7C3`; light text `#F8F8F3` |
| Semantic status | Muted green `#3E6B54`, amber `#916318`, red `#A23F38`; pale backgrounds and explicit labels/icons. Verify contrast on actual surfaces before adopting |
| Typography | Body/inputs 14 to 16; table rows 13 to 14; metadata 12, minimum 11; display 28 to 36; section 20 to 24; readable tabular numbers with unit/currency |
| Spacing | 4, 8, 12, 16, 24, 32; consistent 24 desktop outer margin and 16 gutters; compact station mode increases touch spacing |
| Shape | Primary panels 24 radius; nested surfaces 18; form controls 12 to 14; pills circular ends; consistent one-pixel borders |
| Controls | Minimum 44 by 44 touch target; clear focus; icons accompany a label or accessible name; one visual style for each action level |
| Elevation | Flat resting surfaces; subtle hover/focus elevation; no blanket heavy shadow or glass effect |
| Density | Comfortable by default; compact table mode for office use. No smaller font solely to squeeze data |

## Shared navigation and page anatomy

The desktop shell has a compact header with product mark, company/context selector, General ERP or Knitting workspace pill, search, connection state and account. A collapsible task rail can show labels or icons; shared ERP remains reachable while in Knitting. Phone uses a compact context header and a task menu/bottom navigation for the current workspace. Do not squeeze the full desktop rail onto a phone.

Every page uses the same hierarchy: context/breadcrumb, title with short purpose, status and primary action; then local filters/tabs; then content. A job, invoice or settings page shows its company visibly. Critical actions stay in the same location and use the same review treatment. Back, dirty navigation and session recovery preserve working values.

Core page patterns are overview, workbench/list, record detail, task entry, report, settings and system state. Each has a suitable layout built from shared components. Tables are not automatically replaced with large cards on a desktop. Mobile record cards preserve the fields needed to decide and act; financial results retain a readable horizontal table when necessary.

## Screen contracts

| Surface | Layout and useful behavior |
| --- | --- |
| Sign in and company selection | Clear account/server identity; company tiles from permission context; no industry choice that grants itself access |
| General overview | Existing white 3D stage and charcoal summary; honest metrics, period/time basis, real workspace cards and action drilldown |
| Knitting overview | Compact operational strip; active jobs with remaining kg and next action; machine/QC/shortage queues; one original spool/fabric illustration can support orientation |
| Jobs workbench | Search, status/due/party filters, saved local view, list/compact cards; kg, due date, progress and next eligible action; no unlabelled floating-point numbers |
| Job detail | Large job identity and status; programme-to-invoice step rail; material balance strip; Programme, Yarn, Plan, Rolls and QC, Deliveries, Billing, Activity tabs; source-linked ledger side summary |
| Machine planner | Day/shift timeline or queue columns, available-on and capacity; incompatibilities/shortages named; local plan changes with Review and Apply; accessible move actions |
| Production station | Minimal high-contrast context, large roll-weight input and machine/job choices; available yarn/programme visible; review quantity and consumption before Confirm; recent posted rolls and outcome receipt |
| Touch QC | Large machine queue cards, roll code lookup, defect chips with labels, weight/notes, Release/Hold/Rework decision and persistent inspection history |
| Delivery workbench | Eligible rolls with owner/job/dia/weight, selected total, destination and transport details; held rolls explain the blocker; reviewed DC confirmation |
| Invoice workspace | Source deliveries on one side; quantity/rate/tax preview on the other; unbilled/partial state; posted invoice and ledger links. No artificial payment-success badge |
| Reports | Same header and filter controls; as-of/period meaning explicit; summary plus virtualised/paged table; source drilldown, permission-aware CSV/PDF and print preview |
| Industry setup | Clear checklist and grouped settings; enabled features and roles visible; effective policy revision; Preview changes then Save. No unverified hospital/book modules offered as working |
| General native editors | Styled section cards/tabs; readable two-column fields when appropriate; child-table editing consistent with parent; sticky reviewed action area; same errors, files/activity and success treatment |
| Files activity hierarchy | Same record header, spacing, controls and state panels. Timeline distinguishes record history from user comments. Hierarchy rows retain clear parent/child context |

The first implementation pass must cover these existing surfaces: sign-in, overview, workspace picker, native catalogue/list, module browser, document editor, child-row dialog, reports, hierarchy, activity/files, session recovery, confirmations, settings and license/about. A new knitting dashboard alone cannot satisfy the UI work.

## Motion contract

Motion communicates hierarchy, selection and actual completion. All screens use shared timings and curves rather than independent animations.

| Interaction | Proposed motion |
| --- | --- |
| Button/card hover or keyboard focus | 140 ms colour/shadow transition; interactive cards may rise 2 logical pixels; no movement of reading rows |
| Card first appearance | 220 ms fade and 8-pixel settle; optional 25 ms stagger capped at 150 ms; only on first entry |
| Tab/route change | 200 to 240 ms short fade/slide preserving scroll, identity and focus; reduced motion uses immediate change or a short fade |
| Expansion and selection | 160 to 200 ms size/highlight transition; selected roll/job remains visible |
| Planner queue movement | 180 ms movement after local selection; Review and Apply remains explicit; no fake background posting |
| Confirm success | One brief 180 ms check/state change after server acknowledgement; show durable reference and next action |
| Loading | Stable skeleton footprint or labelled progress. No fabricated values, indefinite decorative loops or shimmer when reduced motion is requested |

Use Flutter's built-in animation and transition facilities first. Respect `MediaQuery.disableAnimations` and platform reduced-motion settings everywhere, including charts, skeletons and route transitions. Rebuilds/refreshes must not restart entrance animations, reset focus or change field contents. Do not animate authoritative numbers while a user checks quantities or totals. No extra delay around Save/Confirm to finish an animation.

## State accessibility and performance

Every data component defines loading, populated, empty, filtered-empty, stale, offline/unreachable, validation failure, denied permission and expired session. Distinguish no data from not allowed and not configured. A failed request keeps working input; an uncertain write outcome offers Check status by request reference.

Use visible labels, keyboard traversal and shortcuts, screen-reader semantics and text plus icon status cues. Preserve 44-pixel targets, normal OS text scaling and error text beside the affected field. Keyboard actions have an alternative to drag or swipe. Do not rely on hover for essential actions.

Test at 390, 834 and 1440 logical pixels and large text, with mouse/keyboard and touch-sized layouts. New long lists use bounded server paging and lazy rendering. A source list of 10,000 synthetic rolls must not instantiate 10,000 widgets. Profile animated pages in release/profile mode on this Mac; aim for the display frame budget and record actual measurements. Do not claim 60 fps from a widget test or from a browser mockup.

## Preview and acceptance

The browser preview is a disposable design presentation with synthetic data. Its tabs let the user inspect connected pages and representative motion. It cannot prove Flutter rendering, accessibility semantics, backend posting or production performance. Carry accepted choices into real shared Flutter components and verify the native app independently.

Acceptance requires a screenshot/state matrix for the existing core surfaces and the new industry screens, plus interactions: navigate, filter, open detail, edit a child row, handle a server error, retain a draft through recovery, review/post and see the resulting ledger. There must be no dead decorative primary action, clipped table, unreadable label, focus loss or mismatched control style in the agreed screens. Each shipped metric and action uses real connected data and a tested route.
