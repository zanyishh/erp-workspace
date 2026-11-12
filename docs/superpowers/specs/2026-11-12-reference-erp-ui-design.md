# Reference-led ERP Workspace UI

## User intent and confirmed direction

The user wants a precise redesign based on `/Users/nithish/Downloads/IMG_3153.JPG`, including typography, colours, controls, rounded panels, and white 3D imagery. They explicitly confirmed **a general ERP overview in this style**, rather than a truck/fleet dashboard. Flutter is the previously selected client platform for macOS, Windows, iOS and Android. The running ERPNext/Frappe services and original source remain the business foundation.

This document describes the first implementation increment: the native Flutter application shell, general ERP overview, and consistent module record browsers. Full replacements for every ERPNext document editor and AI-agent workflows are later increments. Existing ERPNext forms remain accessible from the client.

## What is actually visible in the reference

- A very light neutral grey canvas, with dark charcoal control surfaces and alternating pale cards inside dark containers.
- A compact horizontal navigation strip. Pill-shaped active module control; circular utility buttons; four inline statistics divided by thin vertical rules; profile avatar at the right.
- Three main columns: a narrow dark summary on the left, a dominant bright 3D object in the centre, and a narrow dark list container on the right.
- Tall, narrow, uppercase display headings paired with small geometric sans-serif labels and readable, larger metric numerals.
- Large rounded panel corners; smaller nested card corners; thin grey stage outlines; flat dark controls with compact white outline icons.
- Restrained peach/orange used for thin progress strokes and soft gradients rising from the bottoms of otherwise pale metric tiles.
- A white semi-realistic product render: soft frontal studio lighting, realistic grey edges and wheels, subtle contact shadow, minimal colour, and plenty of space around the subject.
- Small repeated product images in list cards with the same perspective, lighting and material treatment.
- Lower panels mixing a dense dark visual, short performance metrics and another image-led tile. The visual hierarchy is not a uniform grid of generic statistic cards.
- The tablet bezel, hands, room background and external Creatora wordmark belong to the photographed presentation, not the application's layout.

The exact original font files, colour tokens, dimensions and source assets cannot be recovered reliably from a photographed screen. The implementation values below are deliberate approximations, not claims about the original design files.

## Visual decisions for this implementation

| Token | Value | Use |
| --- | --- | --- |
| canvas | `#E7E8E4` | Entire application background |
| surface | `#F4F4F0` | Light cards and inputs |
| charcoal | `#191B19` | Summary, workspace list, buttons |
| primary text | `#20231F` | Text on light surfaces |
| muted text | `#686E66` | Secondary labels |
| fine border | `#C7CBC3` | Stage and light-card outlines |
| peach accent | `#E99A70` | Progress, selected details, key chart strokes |
| pale peach | `#F4D7C3` | Metric gradient endpoint |
| light text | `#F8F8F3` | Text on dark panels |

Display type: **Barlow Condensed SemiBold**, uppercase for compact section/record titles. Body and metric type: **Manrope**, regular/medium/semibold. Both will be bundled with their original SIL Open Font License notices. These are close visual matches chosen by the builder; the original typeface is unverified.

Use 4/8/12/16/24 spacing, 24px primary panel radii, 18px inner card radii, 999px pills, and 34–40px circular visual controls inside accessible hit areas of at least 44px. Thin 1px outlines; no heavy black outlines around every light card. Display titles roughly 20–26px, body 12–14px, metadata at least 11px, primary values 26–32px at desktop size. Permit normal OS text scaling and adequate contrast.

Peach is an accent, not a full-screen wash. Avoid saturated blue, purple gradients, glass effects and colourful emoji icons. Use consistent small outline icons. Motion is limited to gentle selection/hover feedback; respect reduced-motion settings.

## Desktop layout

At approximately 1440x900, use 24px outer padding, a 56px top bar, then a three-column content area with 16px gutters: about 240px left, flexible centre, about 280px right. Wider layouts keep the centre dominant. Page scrolls vertically when needed; do not shrink labels to fit.

1. Top strip: interim wordmark **WORKSPACE.**, active module pill, compact module selector, live inline counts, refresh/search controls, and user menu.
2. Left charcoal panel: company name, a small connected status, selected reporting period, and two pale nested metric tiles with soft peach gradients. Follow with a dark business-flow panel using a thin line diagram of Buying → Stock → Selling → Paid, replacing the fleet-specific route map.
3. Centre: compact action strip, a large lightly outlined stage with an original white 3D business/warehouse object and a soft ground shadow. Below, a small activity area and restrained chart/metric panels. Empty business data produces truthful empty states and zeros rather than invented trends or transactions.
4. Right charcoal panel: **WORKSPACES** title and three pale image-led cards for Stock, Selling and Buying. Each has a small white 3D visual, concise description, relevant count, and an obvious open action.
5. A compact module menu provides Accounts, Selling, Buying, Stock, Manufacturing, Projects, Assets and Quality without recreating a permanent wide sidebar unlike the reference.

No Creatora logo, truck model names, profile portraits or screenshots will be reused as our branding or assets.

## Responsive behaviour

- Desktop/wide tablet (>=1180 logical pixels): three-column overview.
- Medium (780–1179): two columns; workspaces move below the main stage.
- Compact (<780): a vertically stacked overview with a compact header and horizontally scrollable module controls. Summary, 3D stage, metrics and workspaces appear in a deliberate reading order.
- Tables become readable record cards at narrow widths. No horizontal clipping or unintended overflows at 390, 834 and 1440 logical pixels.

## Behaviour and integration

- A styled sign-in screen connects to the existing ERPNext service using the user's normal credentials. Default server is the local evaluation service. Credentials/session cookies stay in memory; no hard-coded password, secret file or credential logging.
- Use actual ERPNext REST responses for company details, counts and records. Apply the selected company to company-specific transactions. Reference illustration is decorative; it is never presented as an actual warehouse model or live camera view.
- Show explicit loading, empty and connection-error states. A failed/expired session returns to sign-in rather than showing invented data.
- Module selection opens a styled native record browser. Initial document types: Sales Invoice (Accounts), Sales Order (Selling), Purchase Order (Buying), Item (Stock), Work Order (Manufacturing), Project, Asset, and Quality Inspection.
- Search and refresh operate on the current record browser. Selecting a record or choosing to create a document opens the corresponding original ERPNext page using the default browser. Label that handoff clearly. This preserves full existing business functionality while native document forms are built later.
- Match typography, colour, borders and control shapes on overview, sign-in and record browsers. Keep tooltips and accessible labels on icon controls.
- The header's period selector has real date filtering for relevant dated transaction lists/metrics. Do not show a decorative switch that does nothing. Hide date controls where they do not apply.
- Do not add AI controls before AI behaviour is specified.

## Technical and organization decisions

- Create `apps/erp_client/` as a new Flutter app; keep all three `upstream/` checkouts unchanged.
- Native macOS is the first launched preview. Generate platform hosts for macOS, iOS, Android and Windows. Windows compilation and physical-device tests remain separate host/device checks.
- Reuse the verified Flutter 3.38.7 installation and documented Xcode minimum deployment targets. Do not upgrade unrelated tools.
- Use Flutter drawing/layout for panels, charts, controls and icons. Use image generation only for original bitmap 3D assets; save final images and generation prompts in the project.
- Prefer Dart's HTTP facilities for the small REST client; use the official `url_launcher` package for cross-platform browser handoff if no existing dependency supplies it. Keep dependencies minimal.
- Local HTTP exceptions are limited to development loopback hosts. HTTPS remains the normal path for remote server connections. Do not publicly expose the ERPNext service.
- Preserve root GPL and upstream notices. Bundle font notices and Flutter dependency license information; provide an About/Licenses entry.
- The workspace is not yet a root Git repository. Initialize a root repository and feature branch for client work without importing or editing upstream repositories; do not create a worktree of an unrelated nested upstream repo.

## Acceptance and verification

- Reference features must be recognizable: compact strip, charcoal framing, condensed headings, peach gradients, round controls, dominant softly lit white 3D object and pale image cards.
- Sign in to the running local ERPNext, display the real evaluation company, open a module browser, exercise search/refresh and verify a browser handoff.
- Test REST parsing and session/error behaviour, and test layout at 390/834/1440 without overflow. Test module filtering on real model data rather than only matching widget labels.
- Run formatter, Flutter analyzer, the client test suite and a macOS build. Build other locally supported targets if changes to their host configuration need verification; do not claim Windows or physical-device testing.
- Launch the native macOS app and visually inspect it, adjusting spacing and imagery before the handoff. Save a final screenshot and record known scope limits.

## Review and approval

Independent builder check: nothing important left. The user approved applying this design in Flutter on 12 November 2026. Implementation will proceed in this workspace.
