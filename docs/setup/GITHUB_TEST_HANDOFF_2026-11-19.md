# GitHub tester handoff — 19 November 2026

The publication includes the Flutter client, server extension, synthetic test fixtures, locked package versions, licenses, existing source history and a Windows test guide. The official upstream working trees and customer research remain separate, as specified by the workspace conventions.

Fresh local verification passed 77 top-level Python script tests, 253 offline migration tests and the Flutter architecture check (231 source files). A scan of the publishable candidate found no matches to common GitHub/AWS token or private-key formats. This scoped scan is not an exhaustive credential audit; the earlier publication review records the source/history and customer-identifier review.

The selected external Flutter SDK drive is not mounted in this session. The globally installed SDK is older than the project pin and was not substituted. The dedicated Colima Docker socket is unavailable to this session. Terminal network access cannot resolve github.com. Consequently native builds, the Flutter suite and connected backend validation are delegated to repository workflows, and their actual run status is authoritative.

The Windows workflow compiles both editions on a Windows runner, runs Flutter analysis/tests, checks that each native executable opens a window and packages the executable with its DLLs, data, notices and source link. A separate Linux job exercises the same portable backend launcher on an empty isolated database, verifies scoped logins and sample invoices, and repeats after a stop/start. It uses the exact source rather than the author's local database.

The mobile workflow builds Android and unsigned iOS and runs synthetic emulator/simulator journeys. The architecture workflow runs formatting, analysis and Flutter regression tests. A successful platform build is distinct from manual business acceptance, printer/device acceptance and customer migration. See [Windows testing](WINDOWS_TESTING.md) for the tester checklist and the [delivery review](DELIVERY_2026-11-18.md) for unresolved customer delivery limits.
