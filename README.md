# ERP workspace

This workspace holds the preserved ERPNext backend and the first native Flutter client, **ERP Workspace**, for macOS, Windows, iOS and Android. The reference-led overview and eight module record browsers use real ERPNext data. AI workflows and full native document editors are later increments.

## Flutter application

Double-click `scripts/erp-workspace.command` to start the local services and open the Mac app. Sign in with the local evaluation account below. The approved first increment includes the business overview, module navigation, search, refresh, date filtering and paginated lists. Full forms open in the original ERPNext browser application.

Client code and development instructions: [apps/erp_client](apps/erp_client/README.md). Design decisions: [reference analysis](docs/design/REFERENCE_ANALYSIS.md). Start and stop launchers preserve business data.

## Original application

Open http://localhost:8080 after starting the local services. Evaluation login: **Administrator** / **admin**. Sample company: **ERP Evaluation** (India, INR). This is a local evaluation environment, bound to the Mac's loopback address.

Start: double-click `scripts/erpnext.command` in Finder, or run it from Terminal. Stop: double-click `scripts/stop-erpnext.command`. Stopping retains database and uploaded files. The first launch may take several minutes to initialize the site.

```sh
./scripts/erpnext.command
./scripts/stop-erpnext.command
```

## Organization

| Folder or file | Purpose |
| --- | --- |
| `upstream/erpnext/` | Complete official ERPNext source working tree |
| `upstream/frappe/` | Complete official Frappe framework source working tree |
| `upstream/frappe_docker/` | Original official deployment source |
| `upstream.lock.json` | Exact versions, revisions and notice checksums |
| `licenses/` | Original licenses, bundled component notices and trademark policy |
| `infrastructure/erpnext/` | Local evaluation deployment |
| `apps/erp_client/` | Native Flutter ERP Workspace client |
| `docs/design/` | Reference observations, image prompts, provenance and screenshots |
| `scripts/` | Named start and stop launchers |
| `docs/setup/` | Toolchain, licensing and verification records |
| `.local/` | Ignored verification project and reports |

The official source trees retain their own Git repositories and notices. Git history is shallow to conserve space; all tracked files at the selected releases are present. The root workspace does not vendor these repositories into another Git history. Use `upstream.lock.json` to identify the originals precisely.

## Development direction

Keep ERPNext/Frappe business logic and APIs as the starting server. This first Flutter increment applies the approved visual style to the overview and module browsers. The product name is provisional. Native document forms and AI permissions/workflows will be developed after the user reviews this preview.

See [license review](docs/setup/LICENSES.md) and [setup status](docs/setup/STATUS.md). Windows builds require a Windows host with Visual Studio's Desktop development with C++ workload. macOS cannot validate a native Windows build.

## License

Workspace-specific files use GNU GPL v3; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Upstream components retain their original licenses.
