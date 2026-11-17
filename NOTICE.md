# Open source notices

Workspace-specific Flutter client code, configuration, launchers and documentation are provided under GNU GPL version 3; see `LICENSE`. Included upstream projects and third party components retain their own licenses and copyright notices.

- ERPNext: Frappe Technologies Pvt. Ltd. and contributors; GNU GPL v3.
- Frappe Framework: Frappe Technologies Pvt. Ltd. and contributors; MIT.
- Frappe Docker: Frappe Technologies Pvt. Ltd. and contributors; MIT.

Original notices are preserved both in the unchanged source trees under `upstream/` and as copies under `licenses/`. `upstream.lock.json` records the exact revisions and separate notice-file checksums. This notice supplements those originals.

Local deployment modifications dated 12 November 2026: pinned ERPNext application version and restricted the browser port to localhost. The original deployment recipe is MIT licensed; its copyright and permission notice remain in `licenses/frappe_docker/LICENSE`.

ERPNext and its logo are trademarks of Frappe Technologies Pvt. Ltd. No affiliation or trademark permission is implied. See `licenses/erpnext/TRADEMARK_POLICY.md`.

Flutter client added 12 November 2026: independent reference-led UI with original generated illustration assets. Manrope and Barlow Condensed fonts retain their SIL OFL notices under `licenses/fonts/` and `apps/erp_client/assets/licenses/`. Static Manrope weight instances are derived from the preserved variable font without changing its licensed family name. Flutter and package notices are available inside the app's Licenses screen. Image generation prompts and provenance are recorded under `docs/design/`.

Native workflow extension added 12 November 2026 under GPL-3.0. Upstream-derived report/condition metadata retain their ERPNext/Frappe provenance. The syntax parser is a development-only MIT dependency with notices in `licenses/development/`. Versioned package notices and their checksums are preserved in `licenses/flutter-packages/inventory.json`; the Flutter runtime also collects dependency notices in its Licenses screen. The native extension does not replace the preserved upstream licenses.
