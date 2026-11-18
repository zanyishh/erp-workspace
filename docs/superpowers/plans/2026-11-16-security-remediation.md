# API and security remediation implementation plan

> Execute under the user's explicit instruction to fix the API failure and all Critical/High findings, then rerun tests. Preserve the dirty workspace and official reference checkouts; do not commit unrelated work.

**Goal:** Remove verified security defects where compatible fixes exist, reproduce and fix the HTTP contract failure, and produce current test/scan evidence without hiding unresolved findings.

**Architecture:** Apply application authorization fixes in the extension, native-test-only proxy configuration, platform-specific Android policy, and reproducible dependency/image overlays. Keep original evidence and immutable upstream references. Never modify customer data or delete volumes. Stage large artifacts on infact and serialize resource-heavy checks.

**Tech stack:** Flutter/Dart, Frappe/Python, nginx/Compose, Android manifests, npm/Python tooling, Trivy/Syft/MobSF.

1. Reproduce `TRACE /api/method/ping` returning 405 without Allow. Add a connected regression that checks the actual allowed-method contract and preserves normal ping/security headers. Mount the smallest proxy correction only on native-test-frontend, validate configuration, and rerun the unmodified Schemathesis check.
2. Add missing scope/company authorization to migration writers with denial/authorized-path regression tests. Check every caller and preserve intended synthetic administration.
3. Separate Android debug cleartext from release policy and disable backup. Obtain the user's platform-support choice before raising minimum Android version; verify the resolved manifest rather than fabricating scanner inputs.
4. Pin patched compatible npm transitive dependencies and verify Bruno/Playwright use. Investigate a narrowly tested cryptography-based Checkov verifier if its unfixed signing library can be eliminated without damaging verification.
5. Stage patched Chromium and a current-Go gosu build, investigate runtime Python/Node/OS dependencies, and construct reproducible isolated image changes where compatibility can be verified. Retain findings with no vendor fix or unproven applicability; do not silently exclude them.
6. Rerun affected focused tests first, then all configured safe functional suites and security scans. Review new raw outputs, reconcile duplicates and confirmed applicability, and document remaining blockers explicitly.

Review focus: permission bypass for an unlisted System Manager; denied company memberships; existing permitted operations; malformed/invalid cryptographic signatures; TRACE header correctness without widening methods; Android release HTTP/device compatibility; native PDF behavior after Chromium replacement; installed dependency consistency; no change to baseline/customer services or data.
