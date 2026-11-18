# KnitPack workflow coverage

All 232 distinct route IDs in the preserved source catalogue match the local scope ledger on route, name, section and inspection status. Of the 234 menu entries, 227 distinct screens were inspected, three routes were recorded from the menu only and two links were unresolved. **Zero full source routes have certified parity.** The catalogue describes visible controls and read results. A recorded Save action supplies no transaction, reversal or accounting outcome to compare.

The catalogue includes 818 field-label occurrences, 114 tables and 315 action-label occurrences. The 67 configuration controls have 133 observed choices. Another 13 workflow selectors have 42 choices. All 175 choice values still need source-equivalence acceptance. These counts are distinct from the number of operable commands.

## Classification of the 232 routes

| Ledger implementation class | Routes | Meaning |
|---|---:|---|
| Independent shared capability or safe substitute | 179 | A knitting function or grouped report represents the business area. Exact source field, calculation and menu behavior remains open. |
| Shared ERP reuse | 45 | Uses ERPNext records or reports through the native client. Each workflow still needs a source-specific acceptance case. |
| External or sample-dependent | 6 | S044 automation hardware, S067 GST download, S068 Tally export, S193 e-invoice, S194 e-way bill and S226 payment gateway. The two review exports can be generated locally. Hardware, provider and consumer acceptance require separate evidence. |
| Audited correction substitute | 2 | S018 job deletion and S048 roll edit/deletion map to guarded corrections with history. Both routes were menu-only. |

The separate *disposition* field yields 179 independent knitting workflows, 48 shared ERP adapters, two audited corrections, two independent substitutes and one optional hardware requirement. The two unresolved links are S223 Config and S227 Holiday. The release-requirement tally is 225 required independent functions, three schema/golden-file checks, three provider/pilot checks and one hardware dependency. S066 GST Report has a schema acceptance requirement even though its implementation class is a shared capability.

## What users can do

The four knitting command registries provide **52 distinct server operations**. The Flutter form catalogue has 53 unique action IDs. Its rate-only action submits the existing version-checked `revise_job` command. Every other ID maps directly. The read API exposes 14 register collections and 19 report types. These counts describe implementations, irrespective of the current role's right to open them. A report type can support several source routes with different date, grouping or print requirements.

| Primary family | Routes | Local operation or entry point | Outstanding evidence |
|---|---:|---|---|
| K01 Company and access | 9 | Company selection, pack enablement and capability checks in `workspace.py` and `knitting/permissions.py`. | Actual operator permissions and source-specific configuration meanings. |
| K02 Jobs, rates and masters | 37 | Estimation register, guarded acceptance and conversion, job register by party, date and status, factory master entry, rate revision. See `knitting/registers.py`, `factory.py` and `domain.py`. | Imported full-programme replacement is blocked where original identifiers, zero values or targets cannot satisfy native validation. |
| K03 Yarn and general stock | 10 | `receive_yarn`, `return_yarn`, `allocate_yarn`, `transfer_yarn`, `move_yarn`, `repack_yarn`, `adjust_yarn` and yarn order/bill commands. | Source automatic consumption, excess, backdating, adjustment rules and exact location defaults. |
| K04 Machine planning | 10 | The planning command and `knitting/planning.py` cover machine compatibility, allocation, shortage and change projections. | Actual capacity, ownership, operating calendar and source planning formulas. |
| K05 Production and corrections | 9 | Measured rolls, bulk rolls and atomic aggregate rows, saved machine/employee attribution, split and reversal commands. | Owned/mixed aggregate valuation and legacy correction/posting dates. |
| K06 Quality | 3 | Per-roll QC and reinspection in `domain.py`, aggregate review in `batches.py` and delivery release checks. | Acceptance of original QC rules, unattended devices and staff procedures. |
| K07 Delivery, billing and closure | 29 | Source-linked invoice/credit and physical return, delivery, transfers, single/multi-job completion and reopening. | Source-specific debit/credit adjustments, printing and exceptions. |
| K08 Subcontracting | 10 | Subcontract orders, issue, receipt, surplus return, billing, close, short-close and reopen. | Vendor ledger/statement and adjustment variants, and customer acceptance of a complete sequence. |
| K09 Factory controls | 25 | Machine/component setup, stoppage, consumable issue/return, breakage and replacement, margin before overhead. | Exact needle/sinker life formulas, stoppage percentages and source P&L allocations. |
| K10 Registers and reports | 82 | Job, yarn, roll, batch, production, QC, subcontract, activity and billing reports plus scoped native ERP reports. Daily/hourly roll reporting is detailed below. | Full report formulas, filter defaults, variants, print layouts and source totals. |
| K11 Prints and integrations | 8 | Knitting exports, roll labels and operational prints in `knitting/exports.py`, ERP invoice PDFs and configurable review outputs. | Provider credentials and acceptance, Tally/GST golden files, approved legacy print samples. |

K00 covers the whole app experience and K12 covers migration and packaging. Neither is the primary family for a source route. The 232 individual route decisions and exact route strings are available in the [scope ledger](knitting-scope.json). The corresponding screens and their controls are in the private source catalogue.

## Roll traceability repair

S055 Hourly Roll Register, S056 Employe Roll Register and S057 Employe Hourly Roll Register all expose a date and production shift. The roll report already supported a period, shift and grouping. Its hourly and daily groups read an event timestamp absent from individual roll rows. Two rolls produced on different dates were consequently grouped as one “Unspecified” row.

The report now uses the roll's recorded production timestamp to form its day and hour. Production at 23:59 and 00:01 on successive days falls into different day and hour groups. Split children retain their original production timestamp and the report excludes the split parent's weight when summing. The screen also offers the verified original employee and machine filters/groupings already available in Production and Fabric. Saved identity distinguishes equal names, while labels and numbers are displayed to the operator. The report continues to distinguish the authenticated user from the production employee. It reports individual roll history. Source-defined hourly efficiency or pay calculations remain open.

## Yarn receipt and return

S004 lists the goods receipt number, date, job, party, party challan number, physical count and received weight. S104 offers a separate inward register with party, job, godown and lot filters. S110 offers a return register with party, job and dates. The preserved receipt field inventory also identifies the party challan date separately from the receipt date.

Both the job and general receipt forms now accept the party challan number, challan date and supplier/customer lot. The operator reviews the entered values before posting. A leading zero in a challan number or lot remains significant. The receipt event retains the challan particulars independently of the stock posting timestamp.

**Yarn Inward Register** and **Yarn Return Register** now read the recorded custody movements. Each row exposes the event reference, movement date, job where recorded, party, item, lot, godown, kg and recorded units. The inward register also shows the party challan reference and date. Operators can filter by period, party, job, godown and supplier/customer lot and can search by the exact inward challan number. Grouping and CSV/PDF exports operate on the same selected rows and units. The return register displays the quantity returned as a positive magnitude. Voided receipts are excluded when the reversal is known by the selected end date.

Original history remains the source for historical KnitPack entries. Missing challan details on older native receipts stay blank. KnitPack order-type, count, colour, mill, DC-origin selector semantics and legacy edit/delete behaviour still need acceptance evidence.

## Delivery, roll time and stoppage

| Source route | Repaired native behaviour | Verification |
| --- | --- | --- |
| S007 Fabric Delivery | The existing challan selector offered both measured-roll and batch deliveries. The print handler previously rejected every batch. It now prints the source batch reference, programme, recorded roll/piece count, aggregate kg and transport details after the same permission and active-delivery checks as a measured roll. | A synthetic 21.300 kg, two-piece batch printed one source line. The output retained the aggregate measurement and excluded commercial rates. The test inspects the actual HTML sent to the PDF renderer. A persisted-site test also checks the generated PDF bytes when the bench is available. |
| S053–S057 roll registers | Roll Time Register opens a chronological detail list. Production time and roll reference lead each row. The employee-hour register groups by both saved employee identity and production hour. | Two rolls whose references sort in the opposite order to their timestamps displayed chronologically. Across midnight, 3.500 kg in each hour produced a 7.000 kg total. |
| S147 Stoppage Entry, S148 Shiftwise Stoppage, S150 Machinewise Stoppage | Entry accepts an optional godown and configured machine shift. Named reports group by shift or machine and support dates, godown and machine filters. Period results count only the portion of the recorded downtime that overlaps the chosen dates, including intervals entered after the machine resumed. | An overnight interval from 23:00 to 01:00, entered the following day, contributed 60 minutes to the selected day. An interval ending at midnight contributed zero to that day. Historic entries without a recorded shift stay unspecified. The percentage denominator in S149 remains open. |

The reports screen also provides the named daily production, employee production and hourly/employee roll reports. At phone widths, the result summary and labelled records share a vertical scroll surface. The first three fields are visible and additional fields expand inside the record. The page controls, linked documents and applied-filter export all remain available.

## Verification

The local catalogue and ledger matched on all 232 IDs, names, routes, sections and inspection statuses. The four command registries were compared with the 53 distinct Flutter form action IDs. Eight direct Python cases passed using the actual command/projection/export code with synthetic inputs and isolated dependencies. The Flutter 3.47.9 software renderer passed 26 knitting report cases, four employee/machine report cases, 17 entry cases and 41 workspace cases. These include phone register selection, scrolling and expansion, review of challan details under both platform themes, invalidation, pagination and export. Replacing the client while a print was pending previously surfaced the old result in the replacement workspace. The workspace now refreshes from the new client and checks the API, access revision, company, page and selected job before showing the PDF or its error. Signed builds and physical device results are tracked separately in the mobile delivery record. Persisted Frappe tests for the new workflows still need the isolated bench.

## Reproduce the audit

Run from the repository root. This comparison uses only the catalogue and ledger files.

```sh
python3 - <<'PY'
import collections, json
from pathlib import Path

catalogue = json.loads(Path('docs/research/fashionsuite/2026-11-13/knitpack-screen-catalogue.json').read_text())
ledger = json.loads(Path('docs/coverage/knitting-scope.json').read_text())
sources, targets = catalogue['screens'], ledger['requirements']
by_id = {row['id']: row for row in targets}
assert len(by_id) == len(targets) == len(sources) == len({s['id'] for s in sources})
assert len({s['route'] for s in sources}) == len(sources)
for source in sources:
    target = by_id[source['id']]
    for key, mapped in [('name', 'observed_name'), ('route', 'observed_route'),
                        ('section', 'observed_section'), ('status', 'audit_status')]:
        assert source[key] == target[mapped], (source['id'], key)
for key in ['implementation_status', 'disposition', 'release_requirement', 'work_package', 'audit_status']:
    print(key, dict(collections.Counter(row[key] for row in targets)))
print('Field occurrences, tables, action occurrences:',
      [sum(len(s[key]) for s in sources) for key in ['fields', 'tables', 'actions']])
other_choices = [e for screen in catalogue['workflow_choices'] for e in screen['enums']]
for selectors in [catalogue['configuration_choices'], other_choices]:
    print('Controls and options:', len(selectors), sum(len(s['options']) for s in selectors))
PY
```

Run the offline report checks with the standard library. For the integration tests, use the project-selected Flutter SDK and the synthetic site in the existing ERP bench.

```sh
python3 scripts/test_knitting_roll_reports.py
(cd apps/erp_client && python3 ../../scripts/flutter_toolchain.py test --no-pub test/knitting_production_operator_report_test.dart)
bench --site native-test.localhost run-tests --module erp_extensions.tests.test_knitting_reports
bench --site native-test.localhost run-tests --module erp_extensions.tests.test_knitting_production_operator_reports
```
