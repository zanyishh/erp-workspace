# Git publication and native test readiness

Review date 18 November 2026, local time. The working branch is `feature/knitting-industry-pack`. It has no configured Git remote. The delivery bundle carries a local candidate commit prepared in an isolated Git directory. The working branch remains on its original HEAD.

The source-publication review covered the tracked and non-ignored untracked files. Customer research is excluded, the backend package includes its test fixtures and current package notices are present. Customer release still depends on the connected, data and platform checks in the [delivery review](DELIVERY_2026-11-18.md).

## Git content review

- Ignored the customer screen catalogue, three private research documents, two account-specific coverage reports, their verification JSON, and three planning or specification files containing identifiable operational observations. The files remain on disk. Public guides refer to the private reviews in prose.
- Checked tracked and non-ignored untracked filenames for signing keys, environment files, archives, databases and generated application packages. Local runtime, Flutter build and credential directories are excluded. The synthetic 15-page invoice lookbook and its previews remain intentional design material.
- Inspected pending text for provider token formats, private key markers, credential-bearing URLs, email domains and password-like assignments. The assignments flagged by this check were synthetic test values and test doubles. No customer credential was identified. This was a scoped working-tree review. The historical Gitleaks scan and its dispositions remain separate evidence.
- Converted links targeting the author's checkout to relative repository links. Three security lockfiles now describe staging and provenance paths relative to the repository or quality storage. The pyexpat builder resolves inputs from its own checkout and the configured quality directory. The storage configuration, `ERP_QUALITY_HOME` and its `--quality-home` override are supported. All previous lock bytes remain with the private historical evidence. Current recipe identity checks continue to use the complete lockfile SHA-256. Old build receipts certify the earlier inputs only.
- All three official upstream checkouts match the exact locked commits and have clean worktrees. All ten copied upstream notice files match the recorded checksums. The package inventory covers all **89 hosted package versions** in `pubspec.lock`. The two additional packages were verified with local package archive checksums. For six upgraded packages, the version-specific pub.dev metadata matched the archive checksum in the lockfile and the published notice was preserved. The newer vector_math notice differs from the historical copy. Both versions remain attributed. All inventoried notice files passed SHA-256 verification. Each of the six new notice records contains its public source URL in [the inventory](../../licenses/flutter-packages/inventory.json).
- A synthetic relocated checkout test exercised the actual pyexpat preflight from a different working directory, with separate external storage. It accepted the correct bytes, rejected a same-size changed source, and performed no container operations. All **23** selected path, XML, image preparation and source-mount checks passed.

## Clean-checkout rehearsal

The review copied the Git candidate into an empty directory without existing caches, customer files or upstream checkouts. The app architecture check passed there. The build initially omitted the two synthetic fixtures used to verify knitting GST and Tally review exports. The corrected backend wheel contains both fixtures, all three runtime metadata files and the extension license. Their packaged inputs matched the candidate files byte for byte.

The standalone runs passed 253 offline migration tests, 70 script tests, 113 quality-runner tests, four Android configuration tests and eight JavaScript metadata tests. The metadata tests ran after installing their four locked development packages with `npm ci --offline --ignore-scripts`. These results cover the local test environment and synthetic cases.

The identified customer company names, party names, tax identifiers and contact values produced zero matches in a scan of candidate text using 359 captured values. A separate scan of common provider-key, private-key and credential-URL patterns found only a synthetic URL test. This check covered readable text and Office XML. The package inventory covers all 89 current hosted dependencies, and all 95 retained notice files match their digests. Each upstream checkout still matches its locked commit and all ten copied upstream notices match their originals. The source review also replaced 27 broken local documentation links and verified relative document and image links against the candidate.

Private capture evidence, prior-app Swift sources, rehearsal screenshots and the quality volume are separate inputs for repeating their historical comparisons. They are unnecessary for the standalone tests above. To regenerate upstream metadata, obtain the three official checkouts at the tags in [upstream.lock.json](../../upstream.lock.json) under `upstream/<repository key>` and verify each HEAD against its recorded commit.

## Native verification

The dedicated Colima status reported the `erp` profile unavailable. Docker could not access the `colima-erp` socket, and the native loopback service did not respond. The named `scripts/setup-native-test.command` stopped during Colima’s attempt to write the profile configuration outside the managed workspace. It exited before Compose or Frappe ran.

| Fresh check | Result |
| --- | --- |
| Offline migration tests against synthetic archives | 253 passed |
| Offline invoice print, knitting permission batching, history capability and workspace scope checks | 23 passed |
| Frappe/ERPNext database tests on `native-test.localhost` | Blocked before site startup |
| Native knitting posting, invoice issuance and database readback | Awaiting the isolated site |
| Original evaluation site, customer site and database volumes | No live reads or writes during this review |

Run the offline checks from the repository root. A separate ignored Python bytecode prefix avoids reusing stale mutation-test bytecode from earlier runs.

```sh
export PYTHONPATH=apps/erp_extensions:scripts/migration
export PYTHONPYCACHEPREFIX="$PWD/.local/push-readiness-pycache"
export PYTHONDONTWRITEBYTECODE=1
python3 -m unittest discover -s scripts/migration -p 'test_*.py'
python3 -m unittest scripts.test_original_invoice_print scripts.test_knitting_permission_batches scripts.test_history_capabilities scripts.test_customer_workspace_scope
```

The initial compatibility run found a compact register overflow and a settings action obscured by a prior confirmation. The current release assessment uses the subsequently recovered pinned Flutter 3.47.9 toolchain. The [mobile verification record](MOBILE_RUN_2026-11-18.md) identifies the compiler, architecture targets, test outcomes and outstanding device checks.

The connected release check requires the dedicated Colima profile, the pinned Flutter SDK and synthetic accounts on `native-test.localhost` at loopback port 8081. Windows compilation still requires a Windows host.

## Publication candidate and parent history

The local bundle uses the existing branch name and includes its parent history so that it can be cloned independently. The history review covered all 18 commits reachable from the pre-delivery HEAD, 671 distinct blobs, 457 paths and 66 unique historical images. The text, commit-metadata and image-text comparisons found zero matches to 359 known customer identifiers. The credential review identified the synthetic offline fixture in the startup profiler. This review is scoped to the candidate and its reachable history.

The handoff includes a local Git bundle. From a separate directory, `git clone --branch feature/knitting-industry-pack /path/to/ERP-delivery.bundle ERP-delivery` creates a clean checkout at the reviewed commit. No GitHub destination has been configured or contacted.
