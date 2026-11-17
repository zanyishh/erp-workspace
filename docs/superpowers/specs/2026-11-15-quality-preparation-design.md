# Testing and security preparation

The user supplied an enterprise testing/security stack and explicitly requested installation and preparation before a later command starts any tests. This is the authority for preparation; it does not authorize test, scan, load, fuzz, restore, or migration execution now.

## Design

Keep development tools out of the shipped Flutter and Frappe applications. Install into ignored `.local/quality/` where practical. Keep reproducible manifests and scanner/API/load configurations in `infrastructure/erpnext/quality/`, named launchers in `scripts/`, and readiness evidence in `docs/setup/`. Preserve existing edits and upstream sources. Existing Flutter, Dart, Xcode, Android, Docker and Colima tools are reused.

Only the synthetic `native-test.localhost` site, exposed at `http://127.0.0.1:8081`, is a permitted dynamic target. Original baseline port 8080, customer port 8082, external hosts and customer migration tooling are excluded. Every execution command requires an explicit `--execute`; default commands only describe plans or inventory installation. Downloads/installations do not run app tests. Keep resource-intensive tools sequential on the 8 GB Mac.

## Approaches

- Selected implementation: local tools, isolated Python environments, pinned Node packages, dormant container definitions. Fits the existing launchers and gives visible installation evidence.
- An always-running scanner/monitoring cluster would consume too much memory and start work the user has deferred.
- Hosted scanning would introduce accounts and source uploads that are outside the request.

## Preparation constraints

Initial free disk space is approximately 1.4 GB. Do not fill the disk, remove user data, delete Docker volumes, or clean existing customer/migration outputs. Install small tools where safe; stage remaining downloads and record blockers honestly. User was asked to free 15–20 GB or provide an external location. Mobile execution requires compatible Patrol native harnesses and a selected device; Windows requires a Windows host. A scanner installation does not establish complete coverage or release approval. AI remains deferred. Monitoring is postrelease scope, documented separately.

## Verification

Permitted now: inspect files and versions, parse new configuration, check launcher syntax, inspect install metadata, review preparation code. No application tests, security scans, network probes of ERP, benchmarks, containers starting, or test-site provisioning. Tests for the new launcher can be authored now and run only after the user's start command.
