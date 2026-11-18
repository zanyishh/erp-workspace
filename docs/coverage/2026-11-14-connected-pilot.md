# Connected staff pilot on the isolated ERP site

14 November 2026. Newly provisioned mill and trade staff signed in from the Flutter sign-in screen against `native-test.localhost` on port 8081. One ran mill operations and the other ran buying, selling and payments in **ERP Native Verification**. Both were restricted to that company. Neither held the System Manager role. Administrator provisioned synthetic staff and masters. The commercial transactions were posted by the staff accounts.

## Operators and results

| Journey through the Flutter screens | Checks against ERPNext |
| --- | --- |
| Mill staff created a programme, received 15 kg in one bag, attempted to consume 16 kg, corrected the same entry to 13 kg, produced a 12 kg roll with 1 kg declared loss, put it on hold, reinspected and released it, dispatched and invoiced it, returned the remaining 2 kg and one bag, then closed the job. | Job `KN-NTEST-JOB-2026-00011`, roll `KN-NTEST-ROLL-2026-00016`, invoice `ACC-SINV-2026-00018`. One successful production event, two inspection decisions on the same roll, and ₹1,200 on each side of the invoice ledger. Yarn, fabric, subcontract and unbilled balances ended at 0.000 kg. No physical units remained. |
| The trade clerk selected a supplier, entered five cartons at ₹30 each, submitted a purchase order, opened the linked receipt, received stock, booked the supplier invoice and paid it. | `PUR-ORD-2026-00003` → `MAT-PRE-2026-00003` → `ACC-PINV-2026-00003` → `ACC-PAY-2026-00005`. Stock increased by five units and ₹150. The reopened supplier invoice had zero outstanding. |
| The same clerk sold two of those cartons at ₹50 each, submitted the sales order, dispatched the goods, raised an invoice and received payment. | `SAL-ORD-2026-00003` → `MAT-DN-2026-00003` → `ACC-SINV-2026-00019` → `ACC-PAY-2026-00006`. Stock decreased by two units and ₹60. The ₹100 invoice had zero outstanding. Three cartons remained at ₹90. For all six stock, invoice and payment vouchers, the per-voucher debits equalled credits. |

The operator rehearsals used actual Flutter widgets, field validation, confirmation dialogs, linked-document menus and the HTTP service. A separate native Mac profile build signed in at 1404 × 754, opened General ERP without scrolling the mill navigation, reselected the company, opened submitted sales order `SAL-ORD-2026-00003`, returned to Selling and then General, and signed out. Separate readbacks checked submitted vouchers, stock and ledger postings. No customer account or data was used. These are automated first-use rehearsals with synthetic company data. They do not measure how an uncoached person performs.

## Factory planning and subcontracting

A separate factory staff account with Manufacturing User and Purchase User permissions exercised the connected ERP methods for a new synthetic job, `KN-NTEST-JOB-2026-00012`. This extension used the HTTP service. The mill and trading journeys above used Flutter screens.

The factory user allocated 4 kg to a new machine and posted 4 kg of production. Maintenance recorded two broken needles, a 20-minute stop and a replacement. The subcontractor received 10 kg of yarn, returned 8 kg of fabric and 1 kg of surplus yarn, and recorded 1 kg of loss. The ₹400 supplier bill posted as `ACC-PINV-2026-00004`. After inspection, dispatch and billing, the subcontract and job closed with zero open balances. Filtered job, machine and gauge reports were checked against the posted events. Across in-house and subcontract production the job received 15 kg of yarn, consumed 14 kg, produced and delivered 12 kg, recorded 2 kg of loss, and returned 1 kg.

## Navigation faults reproduced and fixed

- A General ERP module had no visible way back to its overview. In a knitting company, the nearby mill switch could be mistaken for Back. A module now has an explicit **Back to business overview** control. System Back does the same thing. The deliberate switch is labelled **Knitting workspace** on the General overview.
- Selecting a company from General could unexpectedly open knitting. Reselecting the active company could also complete late and reset an already-open module. The selection now preserves General mode. Reselecting the current company leaves navigation in place.
- A return animation could rebuild the outgoing module with a cleared selection and throw a null error. The outgoing subtree keeps its identity and reads its own captured module and filter until it leaves.
- A staff account with both sets of permissions verified mill → General → reselect company → Selling → saved order. Back returned to Selling and then to General. The same account opened a saved order through All modules, and Back returned to its record list, catalogue and General in order.
- At the native Mac window height, the mill’s General ERP switch had scrolled out of view underneath the work areas. It now stays pinned above the company controls. The mill remembers the previously visited page, job, search and filter. On phones, Back closes an open drawer first. Leaving edited setup asks once whether to discard or keep editing.

## Other defects found during entry

- After factory and subcontract records were present, an unrelated purchase-order reference could prevent a quality checker from listing permitted mill activity. Linked-source visibility now filters out unreadable records while preserving the user’s normal access to other events. A regression case includes both a forbidden source and an accessible job.
- Yarn pickers now show eligible stock items. A definite posting rejection keeps the entry editable, with its quantities intact. An uncertain network outcome retains the status-check flow.
- Opening an inspection previously selected **Released**. The checker now explicitly chooses a decision. Both the hold and subsequent release were recorded before dispatch.
- Add machine had been offered to a mill manager who lacked permission to create its underlying ERPNext workstation. Machine creation and purchasing or billing actions now use effective ERP document permissions. A fresh HTTP check after reloading the service confirmed the original mill manager lacked machine, subcontract order and yarn order creation, while a separately authorised factory account could perform them.
- Six empty knitting references could appear at the top of ordinary ERP forms. Linked knitting sources remain visible on documents that actually have them.
- Returning from a linked voucher now fetches current source data. A settled invoice stops offering another payment entry. The dashboard’s Unpaid invoices action filters the current company and period to submitted invoices with an outstanding balance. Clearing the filter returns to all invoices. The clerk checked a real paid invoice in both views.

## Visual and motion checks

The catalogue now distinguishes everyday records such as customers, sales orders, delivery notes, supplier receipts, invoices, bank accounts, journal entries and payments by silhouette. General ERP status chips pair text with a state-specific symbol. The 47 knitting business commands have explicit symbols. Repeated instances of the same operation use the same symbol. Desktop mill navigation exposes the permitted destinations, and work queues appear above the chart on phones.

The mill entry strip advances from entry to review to posted. The final confirmation follows server acknowledgement. Page transitions, selected navigation and document feedback use short state changes and honour reduced motion. The rehearsal includes tests for intermediate and settled states, retained search and focus, Back behavior and reduced motion. Local comparison renders cover phone, tablet and desktop.

A native ARM64 Mac profile run used a 1404 × 754 window at 2× scale on a 60 Hz display, with 200 synthetic jobs and 500 production postings. None of the 302 measured register-scroll frames, 216 production-selection frames, or 189 sales-selection frames exceeded 16.67 ms in either build or raster. The first mill open included a 266.851 ms raster frame. The first General open included a 37.485 ms build and a 22.919 ms raster peak. First-open latency remains visible even though steady interactions met this run’s frame budget. Profile fixtures were in memory and timing does not include server response time.

## Backup rehearsal

The test site’s database, configuration, public files and private files were backed up. A new MariaDB instance with networking disabled imported the compressed SQL into temporary storage. It restored 784 tables. At the backup checkpoint the restored closed job `KN-NTEST-JOB-2026-00010`, the two invoices from the second trade run (`ACC-SINV-2026-00016` and `ACC-PINV-2026-00002`), and four corresponding ledger voucher totals matched their source rows. The sole backed-up file matched its source SHA-256 after extraction. The source database was never the restore target. This exercised SQL and file recovery. Starting the complete application against a restored deployment and rehearsing customer cutover remain separate checks.

## Build and regression evidence

All 140 real backend tests passed in 49.942 seconds, including the restricted checker regression. A new checker also read a permitted job over HTTP while direct access to the restricted purchase order and its event returned 403. All 184 Flutter tests and four metadata tests passed. Full Flutter static analysis reported no issues. The ARM64 Mac release passed deep/strict code-signature verification. The ARM64 iPhone simulator build and Android ARM64 debug APK compiled. The Mac build emitted an Xcode destination metadata diagnostic. These local builds do not establish Windows or physical-device behavior.

## Reproduce

From the project root, run the existing `scripts/setup-native-test.command` launcher. From `apps/erp_client`, use a new directory inside the ignored project `.local` tree for each rehearsal. The commands below use a fresh generated directory under that tree. The local fixtures generate passwords and restrict their credential files to the current user.

```sh
export PILOT_DIR="$(mktemp -d "$PWD/../../.local/staff-pilot.XXXXXX")"
python3 tool/pilot_mill_fixture.py "$PILOT_DIR"
flutter test --no-pub tool/pilot_mill_test.dart
python3 tool/pilot_trade_fixture.py provision "$PILOT_DIR"
PILOT_FLOW=Purchase flutter test --no-pub tool/pilot_trade_test.dart
PILOT_FLOW=Sales flutter test --no-pub tool/pilot_trade_test.dart
python3 tool/pilot_trade_fixture.py verify "$PILOT_DIR"
```

Local evidence is under `.local/pilot-20261114/`. The mill’s `mill-release/mill-result.json` and `posted-ledger.json` contain the job and accounting readbacks. The trade run’s `trade-portable/trade-ledgers.json` contains all eight linked vouchers. The connected factory results are in `factory/result.json`. Navigation, screenshots, frame timings and isolated restore evidence are recorded separately. Credentials are excluded from the report.

For coverage limits beyond these sample workflows, see the [delivery review](2026-11-14-delivery-review.md). Customer-specific formulas, tax submissions, external providers, printer/scanner behavior, live migration, production-scale throughput, assisted-technology testing and physical target devices require separate evidence.
