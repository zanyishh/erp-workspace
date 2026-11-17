# Quality and security coverage inventory

Prepared 15 November 2026 from source files and the user's requested testing stack.
**Historical preparation inventory. No tests, scans, load tests, service launches or customer-data inspections were
performed while creating this inventory. The user subsequently authorized testing on 15 November 2026; see the [completed execution report](QUALITY_RUN_2026-11-15.md) for current results, unresolved findings and coverage gaps.** A named test below is evidence that a scenario is
implemented, not evidence that it currently passes. Earlier reports are historical
evidence and do not certify the current working tree.

## Execution boundary

- The only permitted connected target for the general quality runner is
  `http://127.0.0.1:8081`, site `native-test.localhost`, using synthetic records.
- The preserved original ERPNext baseline is port `8080`. The separate local
  customer migration copy is port `8082`, site `customer-migration.localhost`.
  Neither belongs in this synthetic test target set. The live Fashion Suite
  account is excluded entirely.
- Use Docker context `colima-erp`, Compose project `erp-baseline`, and the named
  launchers. `scripts/setup-native-test.command` starts services, creates the
  test site if needed, installs extensions and seeds demo records. It is a
  mutation, not a preparation-only or inventory command.
- `scripts/stop-erpnext.command` stops services and the dedicated Colima profile
  while retaining data. Never remove database/application volumes as cleanup.
- Keep workloads sequential on this 8 GB Mac. Large scanner databases, container
  images, Android/iOS builds, browser downloads and observability services need
  disk and memory capacity checks before later installation or execution.
- Windows build verification requires a Windows host. A generated project folder
  is not a successful Windows build.

## Existing tests and recommended future commands

These are reference commands for a later explicit run request. They have **not**
been executed for this preparation. The default Flutter suite is `test/`; it must
not automatically include `tool/`.

From the repository root, the two offline Python groups use generated fixtures
and mocked dependencies. Migration test names do not imply customer-data use:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
PYTHONPATH=apps/erp_extensions python3 -m unittest discover -s scripts/migration -p 'test_*.py' -v
```

From `apps/erp_client`, with already resolved Flutter dependencies:

```sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test
```

The direct Flutter command above omits coverage. The quality runner's `flutter`
group includes `--coverage` when explicitly executed. The execution-stage runner
now places coverage in its external per-run report directory. No coverage run, percentage or target is
established here. Flutter may also update its SDK cache outside the workspace
even with `--no-pub`; external tool storage does not redirect every SDK output.
Do not invoke Flutter merely to inventory its version during preparation.

With the named synthetic runtime already provisioned and running, execute the
project's native `unittest` suite in the Frappe environment:

```sh
docker --context colima-erp compose -p erp-baseline -f infrastructure/erpnext/compose.yaml exec -T -e NATIVE_TEST_SITE=native-test.localhost native-test-backend /home/frappe/frappe-bench/env/bin/python -m unittest discover -s /home/frappe/frappe-bench/apps/erp_extensions/erp_extensions/tests -p 'test_*.py' -v
```

This is the existing suite's direct Python entry point, rather than a claim that
it has been converted to `bench run-tests` or pytest. Its fixtures explicitly
initialize `native-test.localhost`; core fixtures create synthetic schema,
companies, users and setup items, and some setup steps commit. Most business
scenarios roll back afterward. Treat the whole suite as a synthetic database
write workload, not as read-only or globally rollback-only.

### Excluded from automatic test discovery

| Path or group | Reason |
| --- | --- |
| `apps/erp_client/tool/pilot_customer_migration_test.dart` | Explicit customer workspace, original records, private profile, and optional customer input/output files. Its environment opt-in is not authorization for the synthetic suite. |
| All `apps/erp_client/tool/pilot_*.dart` | Connected/manual rehearsals need individual fixture, credential and endpoint review before opt-in. Some create transactions or change branding. |
| `pilot_local_launch_test.dart`, `pilot_company_invoice_settings_test.dart`, `pilot_invoice_gallery_test.dart` | They open the app's real saved local profile. `LocalWorkspace._configured()` follows `selected_workspace` and its loopback origin, which can select the customer copy before a later assertion. Do not infer safety from the word “local.” |
| `apps/erp_client/tool/verify_connection.dart` | Defaults to original baseline port 8080 and accepts `ERP_URL`; it is not confined to the synthetic target. |
| Other `tool/verify_*.dart` and connected profiling tools | Some enforce native-test host/site checks, but require explicit credentials and can write records. Keep separate from offline/default discovery. |
| `scripts/provision-customer-site.py`, `scripts/provision-customer-profile.py`, `scripts/setup-customer-workspace.command`, `scripts/erp-customer.command` | Customer-copy provisioning or launch, outside synthetic scope. |
| Migration acquisition/import/preparation/audit commands invoked on private archives | Actual archive processing and import require separately authorized material and scope. Synthetic `test_*.py` fixtures are a different execution group. |
| `.local/`, upstream checkouts, build outputs and private app profile files | Disposable/private/generated material or immutable reference source; do not include by broad recursive discovery. Scanner-specific dependency manifest inputs require explicit scope. |

No customer fixture contents were read to prepare this document. The customer
test classification comes from source code, not from private data inspection.

## Requested tool stack and current evidence

This inventory describes integration needs, not tool installation status. Use the
separate tooling manifest/status and installation receipts for installed versions.
Package or CLI installation is separate from browser downloads, native device
setup and a successful application run. Playwright's selected Chromium headless
shell requires its own download evidence; headed debugging needs a full browser.

| Tool or capability | Source evidence / intended role | Remaining work before claiming coverage |
| --- | --- | --- |
| Flutter Test and Dart Analyzer | `apps/erp_client/pubspec.yaml` declares `flutter_test` and Flutter lints; unit/widget scenarios are in `test/`. | Run only after user instruction; capture current results. |
| Flutter coverage | Flutter can instrument the existing suite. | Collect report, review meaningful uncovered behavior, agree thresholds. |
| Patrol | Native Android/iOS automation requested. | Add device journeys, test build configuration and appropriate host/device setup; existing widget pilots are not Patrol coverage. |
| Playwright | A login-only browser smoke example is prepared. Package installation and the separate Chromium headless-shell download have distinct installation evidence. | Define supported browser surface and authenticated synthetic journeys; it does not replace native Flutter UI testing. |
| Native Python / pytest | Existing server tests use `unittest` and real Frappe; offline tests use standard-library fixtures/mocks. | Preserve supported native runner; add pytest only for a concrete testing need rather than treating installation as coverage. |
| Schemathesis | API schema-based generated edge cases. | A reviewed OpenAPI contract and synthetic auth/target restrictions are required; no completed contract/fuzz campaign is asserted. |
| Testcontainers | Disposable database/service fixtures. | Design compatible Frappe/MariaDB/Redis lifecycle; existing Compose test site is the current integration substrate. Check resource capacity. |
| Bruno | Repeatable API request collections. | Create sanitized synthetic collections and environment configuration; no customer tokens or examples. |
| Hypothesis | Property-based backend validation. | Add meaningful generators and invariants for money, quantities, state transitions and isolation; no property campaign is claimed. |
| tox | Explicit supported Python environment matrix. | Decide supported versions and define environments; the Frappe container remains authoritative for native integration. |
| k6 | API load, stress, spike and endurance tests. | Choose expected load, p95/error objectives and maximum safe local load; restrict to synthetic target and run only by explicit request. |
| Flutter DevTools | Native startup, frame and memory profiling. | `tool/profile_startup.dart`, `tool/profile_workspace.dart` and existing coverage reports provide starting workloads; current production/device budgets remain unverified. |
| Community maintainability analysis | Optional code-smell review. | Select useful Dart/Python rules; avoid duplicating analyzer or security findings. |
| Semgrep Community Edition | Source pattern checks. | Scope first-party source, pin reviewed rules and triage findings; scanner support does not establish full Dart coverage. |
| Trivy | Filesystem/dependency/container/configuration vulnerability checks. | Pin inputs and database version, account for offline database size, triage direct and inherited findings. |
| OWASP ZAP | Web/API dynamic security testing and automation. | Supply authenticated synthetic scope and reviewed automation plan; passive and active workloads both remain unexecuted. |
| Gitleaks | Exposed secret detection. | Review current source and intended history scope with redacted output; no “secret-free” assertion before a run and triage. |
| MobSF | Mobile artifact security analysis. | Requires built APK/IPA or supported source workflow and significant runtime resources; build, signing and dynamic-device analysis remain separate gates. |
| Checkov | Infrastructure configuration checks. | Review relevant Compose/deployment support and findings; default evaluation passwords must be assessed in their localhost-only context. |
| ffuf | Authorized endpoint/input discovery. | Requires exact allowlisted origin, conservative request budget and explicit run instruction; broad host discovery is excluded. |
| ScanCode Toolkit | File-level license/copyright inventory. | Version 32.5.0 is installed and version-verified through existing Rosetta/Intel Python, with external caches. No scan has run. Include relevant shipped files/assets and preserve notices; legal obligation review remains independent. |
| Syft | Software bill of materials. | Produce separate first-party/dependency and shipped-image inventories with provenance; no SBOM yet certified by this inventory. |
| Grype | Vulnerability evaluation of SBOM/artifacts. | Require matching SBOM and current database; deduplicate against Trivy and review unresolved findings. |
| OSS Review Toolkit (ORT) | Dependency license policy and compliance workflow. | Version 99.0.0 native CLI and isolated Temurin Java 25.0.5+8 are installed and version-verified. Upstream recommends 8 GiB JVM memory and 4 CPU cores for full work; plan analysis on a larger host. Configure distribution obligations, package managers and policy review; no policy evaluation has run. |
| OpenSSF Scorecard | Upstream project security-practice assessment. | Define public upstream repositories and token scope; scores do not prove product security or justify changing immutable upstream references. |
| Prometheus and Grafana | Postrelease metrics, dashboards and alerts. | Separate deployment, retention, alert ownership and capacity plan; not required to start during local preparation. |
| OpenTelemetry | Traces/metrics instrumentation and correlation. | Define data minimization, collector/exporter configuration and performance cost before deployment. |
| GlitchTip or equivalent self-hosted error tracking | Postrelease error monitoring. | Define redaction, access, retention and incident ownership; no service deployment is claimed. |

## ERP risk requirements mapped to source evidence

Paths in this table are relative to `apps/erp_extensions/erp_extensions/tests/`
unless explicitly prefixed. This is an inventory of scenario intent, not an audit
of every assertion or a complete attack-surface review.

| Requirement | Existing source evidence | Gap / unverified boundary |
| --- | --- | --- |
| Multi-company isolation | `test_migration_store.py` includes cross-company record/page/detail denial; `test_workspace_selection.py`, `test_knitting.py` and `test_migration_finance.py` exercise company/book scope. | Full endpoint/role/field matrix and adversarial cross-tenant enumeration remain pending. |
| Authentication and session recovery | `test_native_api.py` includes guest denial and public session status; Flutter `test/session_recovery_test.dart`, `test/access_refresh_test.dart`, `test/native_session_test.dart`. | Real expired, revoked and stolen-session scenarios, rotation/replay and device persistence need explicit verification. |
| Permission enforcement | `test_native_api.py` includes read-only field injection, foreign child IDs, stale saves/workflow versions and financial report denial; `scripts/test_knitting_permission_batches.py`, `scripts/test_customer_workspace_scope.py` use mocks. | Complete privilege escalation and direct API tampering matrix remains pending. Mocked scope tests do not authorize customer access. |
| Financial correctness | `test_native_api.py`, `test_invoice_hub.py`, `test_knitting.py`, `test_payment_reconciliation.py`, `test_migration_finance.py`; Flutter invoice/PDF tests. | Agreed GST, rounding, discount, credit-note and multi-currency boundary matrix plus independent expected values remain pending; tests do not certify legal/tax correctness. |
| Payment and request idempotency | `test_knitting_concurrency.py`, `test_knitting_recovery.py`, native journal idempotency in `test_migration_finance.py`, reconciliation scenarios. | External payment provider duplicate/out-of-order webhooks and reconciliation failure recovery require a defined integration and synthetic provider fixtures. |
| Transactions and concurrency | `test_knitting_concurrency.py` uses separate connections; recovery and workflow tests exercise replay and dependency behavior. | Process/database crash injection, deadlocks, sustained concurrent workloads and recovery time remain unverified. |
| Upload safety | `test_native_api.py` covers private attachments, file ownership and exact bytes; Flutter specialized field/import tests. | Malicious MIME/content, traversal, oversized/decompression attacks and malware policy require explicit cases. |
| Audit history | `test_native_api.py` activity scenarios; `test_migration_store.py` rejects generic mutation of source records; knitting event tests. | Tamper resistance, privileged administrative paths, retention and monitoring have not been independently verified. |
| Backups and restoration | Data-preserving stop launcher and named volumes are configured. | No encrypted backup/restore drill, off-host copy, recovery point or recovery time is established here. |
| Infrastructure exposure | Compose declares loopback frontends on 8080/8081/8082 and separate site routing. | Source configuration is not runtime port verification; production hardening, TLS, secrets, network isolation and rollback remain pending. |
| Secrets in Flutter artifacts | Permission-scoped local profile design is in `local_workspace.dart`; `test/local_workspace_test.dart` uses synthetic temporary profiles. | Source/history and actual release binary scans plus credential lifecycle review remain pending. Do not read private profiles into reports. |
| Migration integrity | Offline `scripts/migration/test_*.py` and native `test_migration_*.py` use synthetic records for identity, original dates, source proof, books and scope. | Customer reconciliation/completeness is separate authorized work and is not implied by synthetic tests. |
| Native UX and performance | Flutter widget suites cover forms, reports, navigation, permissions and confirmation behavior; dedicated profiling tools exist. | Accessibility, reduced motion, device/platform matrix, sustained performance and Windows build verification remain pending. |
| AI authorization/security | AI remains deferred by project direction. | Do not implement agents, GenAI tests or access bypasses as part of this setup. Revisit OWASP GenAI guidance only when an AI feature is authorized. |

## Standards and release gates

The requested standards are planning baselines: OWASP ASVS 5.0 Level 2 for
web/backend verification, MASVS for mobile, and NIST SSDF for secure development.
No conformance claim is made. A requirement-by-requirement applicability and
evidence matrix is still needed. OWASP GenAI requirements are deferred with AI.

| Gate | Status as of this preparation | Evidence needed to close |
| --- | --- | --- |
| Current tests/analyzer | Pending explicit run instruction | Current revision, exact command, environment, result and triaged failures. |
| Critical security vulnerabilities | Not evaluated | Zero unresolved findings in agreed scope after scan and manual review. |
| High-severity vulnerabilities | Not evaluated | Remediation or a documented, reviewed exception with owner/expiry. |
| Cross-tenant leakage | Not evaluated for current revision | Agreed isolation matrix passes; no unresolved known failures. |
| Critical business workflows | Definition and execution pending | Enumerated launch workflows with complete current passing evidence. |
| Financial calculations | Definition and execution pending | Reviewed financial boundary cases and exact expected results. |
| Production-secret exposure | Not evaluated | Source/history/artifact review and rotation of any exposed production credentials. |
| Required license obligations | Inventory and qualified review pending | Third-party software/assets, attribution and redistribution/source obligations resolved for the chosen distribution. |
| Backup restoration | Pending | Successful encrypted backup and restore drill with defined RPO/RTO. |
| Staging deployment and rollback | Pending | Isolated staging evidence, rollback rehearsal and deployment ownership. |
| Performance and reliability | Objectives and execution pending | Agreed p95 latency, load, error rate, availability, memory and recovery targets with measured results. |
| macOS, iOS, Android, Windows | Current release verification pending | Platform builds and supported device journeys; Windows host required. |
| Terms, privacy, data processing and compliance | Qualified review pending | Final terms/subscriptions/refunds, privacy/retention/deletion, processor agreements, vendor list, applicable GST/DPDP and international obligations. Current legal applicability must be checked at review time. |
| Monitoring and incident response | Postrelease design pending | Metrics/errors/traces, redaction, alert owners, vulnerability response and incident/restore playbooks. |
| Deployment approval | Not granted by this inventory | All applicable gates resolved and explicit release decision. Passing scanners alone are insufficient. |

Potential future cadence is per-change fast checks, per-PR integration/dependency
checks, explicitly scheduled broader testing, and release-specific load/security/
restore/legal review. No automatic schedule or CI execution is authorized or
activated by this document. The later explicit start instruction authorizes the current local test run.
