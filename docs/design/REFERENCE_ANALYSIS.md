# Reference UI record

The detailed visual observations, colour tokens, typography choices, layout measurements, first-increment scope and acceptance checks are maintained in [the UI design brief](../superpowers/specs/2026-11-12-reference-erp-ui-design.md).

Reference: `/Users/nithish/Downloads/IMG_3153.JPG`. The user confirmed a general ERP overview using this visual style. Exact source font identities and colour values are unverified; our implementation values are deliberate close matches.

Manrope source has a default variable weight of 200. Explicit static 400/500/600 instances are generated with the installed fontTools instancer and bundled with matching Flutter weight declarations, so regular/medium/semibold are rendered deterministically. The original variable file remains unchanged alongside the instances; its OFL notice is retained.

Visual QA tightened the summary spacing and kept the desktop header to one strip. Utility controls retain 44px hit targets; narrow summaries wrap instead of shrinking text.

The finished first preview is shown in [the native Mac screenshot](erp-workspace-overview.png). The business-flow drawing is clipped within its panel, and workspace cards expose real accessibility tap actions. See [client verification and scope](../setup/CLIENT_PREVIEW.md): overview and module lists are native; Create/Edit still uses the original ERPNext browser forms.
