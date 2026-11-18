# ERP workspace

This workspace holds the preserved ERPNext backend and the native Flutter client, **ERP Workspace**, with an optional company-enabled knitting industry pack. General ERP remains available; knitting adds its own scoped factory workflow and records. AI is deferred.

New customers select **Create a company** and choose **General ERP** or **Knitting**. Owners can invite staff by role from **Account and settings → Team access**. Staff choose **Join with invitation** and enter the workspace set up by their owner. The local Mac launcher supplies the service address automatically. A knitting company opens its mill dashboard, with a pinned **General ERP** entry and shortcuts to the business areas its user can read. A knitting company can return to its mill from the company selector. Back from a General module returns to the business overview. The app remembers a returning account’s selected company and checks its current permissions at sign-in. Opening a job shows its next permitted action, with eligible source documents and quantities. The [14 November verification](docs/coverage/2026-11-14-owner-signup.md) records 147 passing backend tests, 197 passing Flutter tests and a local job-to-invoice cycle with returns and cancellations. The [Mac frame timings](docs/coverage/workspace-frame-timings.json) cover both dashboards and a 200-job register. See the [original v1 evidence and release limits](docs/setup/KNITTING_V1.md) and [scope matrix](docs/coverage/knitting-scope.json).

The [owner and staff rehearsal](docs/coverage/2026-11-14-owner-signup.md) covers new company registration, role-based invitations, first transactions and Mac startup. The [connected staff pilot](docs/coverage/2026-11-14-connected-pilot.md) records the full knitting, purchasing and selling rehearsals with fresh accounts, navigation regressions and recovery evidence. The [14 November delivery review](docs/coverage/2026-11-14-delivery-review.md) records the latest workflow fixes, connected checks and customer-pilot gates. The private Fashion Suite functional specification contains the original screen-by-screen evidence.

The [General ERP workflow verification](docs/coverage/2026-11-14-general-workflow-parity.md) records the latest work on purchasing, stock, manufacturing, cash sales, accounting and company setup. The [product research and first-use trial](docs/research/2026-11-14-erp-product-research.md) describe what to measure with owners and staff.

## Flutter application

**Windows testers:** follow [Windows testing](docs/setup/WINDOWS_TESTING.md) to download both app editions, start your own local ERPNext backend and test General ERP, Knitting and shared invoicing. Repository access requires an accepted GitHub collaborator invitation.

Double-click `scripts/erp-workspace.command` to start the isolated local service and install **ERP Workspace Local**. The app opens directly to **Meridian Trading**, the General ERP demo with its own invoices and customers. Choose **Kaveri Loomworks** in the company selector to open the separate Knitting demo. Each demo uses its own permission-scoped account and company invoice settings. After setup, open the app from your Applications folder. See the [native workflow guide](docs/setup/NATIVE_WORKFLOWS.md) for launch and recovery details.

The separate customer copy uses `scripts/erp-customer.command` and **ERP Workspace Customer** with normal password sign-in and knitting-only customer navigation. Its supporting masters, accounting tools and original history remain available. Read the private KnitPack parity and delivery audit before a customer switch; matching captured balances does not establish identical everyday workflows. This customer build remains local to this Mac.

Current handoff and remaining delivery gaps are in the [18 November delivery review](docs/setup/DELIVERY_2026-11-18.md).

Architecture and maintainability: [architecture guide](ARCHITECTURE.md), [ranked Flutter audit](docs/architecture/AUDIT_2026-11-16.md), and [migration progress](docs/architecture/MIGRATION_PROGRESS.md).

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
