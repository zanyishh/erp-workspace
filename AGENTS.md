# ERP workspace conventions

- This project will use Flutter for macOS, Windows, iOS and Android, with ERPNext/Frappe as the initial business backend.
- The current user-directed increment keeps the general ERP foundation and adds an optional company-enabled, permission-scoped knitting industry pack, plus consistent UI/UX across the whole Flutter app. The user approved `docs/superpowers/specs/2026-11-13-industry-packs-and-knitting-design.md` on 13 November 2026 and explicitly directed continuous implementation without another approval round. Motion must communicate state, navigation and confirmations; avoid ornamental entrance staggers, card lifting and gratuitous animation. AI remains deferred. Preserve the original ERPNext baseline and verify changes on the isolated native test site.
- Do not connect implementation or tests to the customer's live Fashion Suite account. Use synthetic fixtures on `native-test.localhost`; customer migration or integration samples require separate authorised test material. Future industries reuse the pack contract, not knitting-specific tables or workflows.
- Keep official checkouts in `upstream/` unchanged as a reference. Record their exact versions in `upstream.lock.json`.
- Put local deployment configuration in `infrastructure/erpnext/`, launchers in `scripts/`, setup evidence in `docs/setup/`, and disposable output in ignored `.local/`.
- When requested, place the Flutter product in `apps/erp_client/` and server extensions in `apps/erp_extensions/`. Use an independent product name once the user chooses one.
- Preserve original copyright headers, license/attribution files and required legal notices. Read `NOTICE.md` and `docs/setup/LICENSES.md` before redistributing or removing bundled assets.
- Keep evaluation services bound to localhost. Start/stop through the named launchers; stopping must retain application data.
- This Mac has 8 GB RAM. Its dedicated Colima profile is `erp`, Docker context `colima-erp`, Compose project `erp-baseline`. Use the explicit context so other projects are unaffected.
- Never delete application/database volumes as part of cache cleanup.
- Windows compilation needs a Windows host. A generated Windows project folder is not proof of a successful Windows build.
