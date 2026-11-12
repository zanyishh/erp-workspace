# ERP workspace conventions

- This project will use Flutter for macOS, Windows, iOS and Android, with ERPNext/Frappe as the initial business backend.
- The current user-directed increment converts the full ERPNext feature set to native Flutter workflows using the approved reference-led style. AI and further UX enhancement are deferred. Preserve the original ERPNext baseline and verify changes on the isolated native test site.
- Keep official checkouts in `upstream/` unchanged as a reference. Record their exact versions in `upstream.lock.json`.
- Put local deployment configuration in `infrastructure/erpnext/`, launchers in `scripts/`, setup evidence in `docs/setup/`, and disposable output in ignored `.local/`.
- When requested, place the Flutter product in `apps/erp_client/` and server extensions in `apps/erp_extensions/`. Use an independent product name once the user chooses one.
- Preserve original copyright headers, license/attribution files and required legal notices. Read `NOTICE.md` and `docs/setup/LICENSES.md` before redistributing or removing bundled assets.
- Keep evaluation services bound to localhost. Start/stop through the named launchers; stopping must retain application data.
- This Mac has 8 GB RAM. Its dedicated Colima profile is `erp`, Docker context `colima-erp`, Compose project `erp-baseline`. Use the explicit context so other projects are unaffected.
- Never delete application/database volumes as part of cache cleanup.
- Windows compilation needs a Windows host. A generated Windows project folder is not proof of a successful Windows build.
