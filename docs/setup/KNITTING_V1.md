# ERP Workspace 0.2 — first knitting version

13 November 2026. The independently implemented first knitting version is built and verified locally. This is a synthetic local validation of the defined v1 workflow; it is not certification of every vendor screen, customer formula, device or production deployment.

## Product and workflow

General ERP stays available. The selected permitted company, server-side pack state and account capabilities determine whether Knitting appears. Future industries can add their own records and workspace without replacing general ERP; hospital/book workflows are not offered as working features yet. AI remains deferred.

The native workflow is: estimate/job and fabric programme → yarn receipt/allocation → compatible machine allocation → actual consumption and roll weights → QC/reinspection → released-roll delivery → reviewed source invoice → original ERP payment and optional credit/return → reconciled completion/reopening. Bulk production and batch completion are atomic. The server checks company, ownership, source versions and request identity and uses original ERP controllers for valued stock, purchase/sales documents and GL.

The UI uses Manrope, Barlow Condensed, neutral light surfaces, charcoal panels and restrained peach highlights throughout the native routes. Main task actions precede long record lists. Selection, navigation, expansion and confirmed results use meaningful motion; editable fields and quantities do not animate or reset to decorate a refresh. Reduced motion uses immediate changes. Unsaved entries and setup edits have discard protection; uncertain saves require a receipt/status check before retry.

## Local exploration

Run `scripts/erp-workspace.command`. It starts only the local native test runtime, installs/migrates the independent schemas, preserves demo choices and rebuilds/reloads changed source. It preserves all database volumes. The server is `http://localhost:8081`, site `native-test.localhost`; the development account is the one documented in the root README. Choose **ERP Native Verification** and open **Knitting**. Demo Knitting Mills and DEMO-KNIT items are synthetic. **ERP Knitting Verification** is for rolled-back automated scenarios; it is separate from exploration records.

The original evaluation UI remains at port 8080. No customer Fashion Suite host, credentials or live records are used for implementation or verification. Source and font/dependency notices remain under `licenses/`, `NOTICE.md` and the app's Licenses page.

## Verification basis

109 real backend checks, 112 Flutter checks and 4 metadata checks pass. Flutter analysis and repository whitespace checks pass. One fresh whole-branch review identified 18 material findings; the source, access, accounting and native workflow fixes are recorded in `docs/coverage/knitting-review-resolution.md`. No second review was requested.

- Synthetic service cycle: 100.000 kg received; 90.000 consumed → 88.000 fabric + 2.000 declared loss; 10.000 returned; 88.000 delivered/billed; INR 8,800.00 under an explicit zero-tax fixture. Closure leaves zero yarn/fabric/unbilled balances while an unpaid receivable may remain.
- Owned/mixed stock: original stock controllers, no second invoice stock issue; separate auxiliary charges and delivered rates remain frozen; owned subcontract fixture includes raw material plus the agreed service in INR 5,300.00 fabric inventory value.
- Corrections: source cancellation/partial credit/physical return preserve dependency checks and GL/stock history. Domain writes through generic CRUD are blocked; native source drilldowns keep permitted payment actions.
- Concurrency: independent database connections resolve duplicate requests to one event and cannot consume an unavailable yarn balance. Company writes currently serialize; this proves correctness for the fixture, not large-factory throughput.
- Recovery: compressed backup/restore of disposable knitting records and stable source replay preserve exact balances and compare untouched original stock/GL. Full-site restore and real customer migration need a separate rehearsal with approved samples.
- Reports/exports: canonical quantities, explicit as-of/period basis, grouped registers, current planning outlook, permissions, CSV/QR-label PDF and independent review-format golden files. See `docs/coverage/knitting-integration-contracts.md`.

## External and release gates

Windows compilation needs a Windows host. Generated project files are not proof of a Windows build. Physical iPhone/Android execution, iPhone signing, customer printer/scanner settings and any hardware automation remain separate checks. Final Mac, iOS simulator and Android builds are recorded below against product code `75e01a8`.

E-Invoice, E-Way Bill and payment gateway are **Not configured**; no external filing or charge occurs. GST/Tally review files are independent schemas, not verified portal/import formats. Exact customer parity needs approved examples and provider/schema checks. General ERP native metadata coverage, individual vendor-route equivalence, automated scenarios and native interactions are tracked separately in the scope matrix; none implies the others.

## Implementation decisions

- Keep the dedicated feature branch in the existing directory so launchers and mounts retain their paths. Integration still needs branch review.
- Frappe masks restricted fields with null; protected content stays hidden while a field name may remain visible.
- Serialize domain writes on a company row plus source-version checks. Measure throughput before a large factory rollout.
- Seed safe exploration records early to verify the real Dart HTTP cycle; separate them from the automated company so repeated tests cannot disturb a demo job.
- Recovery verification restores disposable pack records without overwriting a whole ERP site. Full-site restore/customer migration is not established by that test.

## Final evidence

Product code: `75e01a8` on `feature/knitting-industry-pack`; final evidence/tests documentation follows in the same branch. No merge, push or publication was performed.

- Mac ARM64 release build: passed, 28.6 MB. Strict deep code-signature verification passed. Native executable: `apps/erp_client/build/macos/Build/Products/Release/ERP Workspace.app`.
- iPhone simulator debug build: passed. `apps/erp_client/build/ios/iphonesimulator/Runner.app`.
- Android ARM64 debug APK: passed. `apps/erp_client/build/app/outputs/flutter-apk/app-debug.apk`.
- Current real Dart HTTP cycle: job `KN-NTEST-JOB-2026-00003`, invoice `ACC-SINV-2026-00002`, INR 8,800.00; exact zero remaining operational balances; receipt lookup and actual invoice PDF passed.
- Actual native Mac cycle: job `KN-NTEST-JOB-2026-00004`; receipt event 00022/lot 00003 received 100.000 kg and 2 physical units; production event 00023 consumed 90.000 kg into rolls 00005/00006 at 44.000 kg each plus 2.000 kg loss; QC events 00024/00025 released both; delivery event 00026 retained the destination/transport; invoice `ACC-SINV-2026-00003`/event 00027 was reviewed and posted for INR 8,800.00 under the explicit zero-tax fixture; event 00028 returned 10.000 kg with the remaining 2 units; event 00029 completed the reconciled job. The final binary also passed a reasoned reopen/completion check with the concise saved-result UI.
- Native checks and screenshots also cover the general overview, knitting workbench, exact job reconciliation and source billing (88.000 kg / INR 8,800.00), the submitted original invoice editor and its actual in-app PDF. The final binary's reasoned reopening and completion generated events 00030/00031. The app is left full screen on completed job 00004. Only the recorded interactions are native-verified. The original running demo job 00001 remains available for exploration.
- `docs/coverage/knitting-scope.json` gives every one of the 232 observed routes an explicit disposition. Shared capability tests and safe substitutes are separated from route parity, individual native interaction and external gates. Individual vendor routes certified: **0**. This prevents a shared report engine from being presented as 232 independently verified vendor screens.
- Frame timings were not profiled. Motion behavior and reduced-motion state are covered by Flutter checks; native interaction was visually inspected. Physical devices, release signing/distribution, Windows, large-factory throughput and full-site restore remain explicit gates.
- Local evidence and screenshots are retained under `.local/verification/`; no customer data or live provider calls were used.

Detailed execution decisions and their costs are in `docs/setup/KNITTING_DECISIONS.md`.

Machine-readable evidence: `docs/coverage/knitting-native-verification.json`. Final logs are retained locally in `.local/verification/knitting-release-2026-11-13/`; screenshots are in `.local/verification/knitting-native/`.
