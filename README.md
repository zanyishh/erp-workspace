# ERP workspace

This workspace holds the preserved ERPNext backend and the native Flutter client, **ERP Workspace**, with an optional company-enabled knitting industry pack. General ERP remains available; knitting adds its own scoped factory workflow and records. AI is deferred.

During company setup, a manager chooses General ERP or Knitting ERP. An active knitting company opens its role-permitted mill overview with production postings, work queues and a job register. Its General ERP entry opens the business dashboard for the same company. Back to mill restores the industry workspace. The app remembers the account's selected company and checks its current permissions at sign-in. Opening a job shows its next permitted action, with eligible source documents and quantities. The [workflow audit](docs/coverage/knitting-workflow-audit.md) records 125 passing backend tests, 136 passing Flutter tests and an isolated job-to-invoice cycle with returns and cancellations. The [Mac frame timings](docs/coverage/workspace-frame-timings.json) cover both dashboards and a 200-job register. See the [original v1 evidence and release limits](docs/setup/KNITTING_V1.md) and [scope matrix](docs/coverage/knitting-scope.json).

## Flutter application

Double-click `scripts/erp-workspace.command` to start the local services and open the Mac app. The current native verification server is `http://localhost:8081`, with account **Administrator** / **admin**, company **ERP Native Verification**. Create/Edit now use native Flutter forms. See [native workflow status and remaining parity](docs/setup/NATIVE_WORKFLOWS.md).

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
| `apps/erp_extensions/` | Local authenticated native interface for Frappe |
| `docs/coverage/` | Source inventory, conditional/report metadata and scenario evidence |
| `tools/native_metadata/` | Syntax-only metadata extraction; no upstream script execution |
| `docs/design/` | Reference observations, image prompts, provenance and screenshots |
| `scripts/` | Named start and stop launchers |
| `docs/setup/` | Toolchain, licensing and verification records |
| `.local/` | Ignored verification project and reports |

The official source trees retain their own Git repositories and notices. Git history is shallow to conserve space; all tracked files at the selected releases are present. The root workspace does not vendor these repositories into another Git history. Use `upstream.lock.json` to identify the originals precisely.

## Development direction

Keep ERPNext/Frappe business logic and APIs as the starting server. Extend the approved visual style across all native routes while expanding industry workflows. The product name is provisional. Track general ERP parity, knitting scenarios and packaging separately; AI remains deferred.

See [license review](docs/setup/LICENSES.md) and [setup status](docs/setup/STATUS.md). Windows builds require a Windows host with Visual Studio's Desktop development with C++ workload. macOS cannot validate a native Windows build.

## License

Workspace-specific files use GNU GPL v3; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Upstream components retain their original licenses.
