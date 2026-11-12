# ERP workspace

This workspace holds the original ERPNext baseline for evaluation and the setup records for a future open source Flutter application on macOS, Windows, iOS and Android. UI redesign and AI agents come after reviewing the original application.

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
| `scripts/` | Named start and stop launchers |
| `docs/setup/` | Toolchain, licensing and verification records |
| `.local/` | Ignored verification project and reports |

The official source trees retain their own Git repositories and notices. Git history is shallow to conserve space; all tracked files at the selected releases are present. The root workspace does not vendor these repositories into another Git history. Use `upstream.lock.json` to identify the originals precisely.

## Development direction

Use Flutter for the future client and keep ERPNext/Frappe business logic and APIs as the starting server. The baseline currently runs in a browser on this Mac; a native Flutter ERP client has not been implemented. Product name, UI/UX, AI permissions and workflows will be decided after evaluation.

See [license review](docs/setup/LICENSES.md) and [setup status](docs/setup/STATUS.md). Windows builds require a Windows host with Visual Studio's Desktop development with C++ workload. macOS cannot validate a native Windows build.

## License

Workspace-specific files use GNU GPL v3; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Upstream components retain their original licenses.
