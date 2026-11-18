# Knitting acceptance scenarios

Proposed tests for the first optional industry pack, dated 13 November 2026. Status is **planned**, not executed. Use only synthetic data on `native-test.localhost`. Never use the live customer's credentials, parties, transactions or software as a test target.

## Synthetic service job cycle

Use a dedicated test company, synthetic customer, owned godown, subcontract custodian, machine, operator, checker and accountant. Server fixtures must refuse every site except `native-test.localhost`. Financial-year/date fixtures are explicit; do not depend on the wall clock.

| Step | Action | Required assertion |
| --- | --- | --- |
| 1 | Company enables Knitting; assign scoped roles | General-only company retains its ordinary ERP; operator cannot invoice; accountant cannot alter QC without its role |
| 2 | Create service job and programme | Customer owns material; target fabric is 88.000 kg; kind Order is independent from ownership; programme line identity persists |
| 3 | Receive 100.000 kg customer yarn | Custody is 100.000 kg; bags retained as a physical measure; no invented purchase, revenue or owned-yarn asset posting |
| 4 | Allocate compatible machine/shift | Remaining programme and yarn display correctly; overlapping or incompatible plan rejected |
| 5 | Consume 90.000 kg into two 44.000 kg rolls plus 2.000 kg declared process loss | Source yarn remaining is 10.000 kg; fabric is 88.000 kg; roll IDs are unique; 90 = 88 + 2 under this deliberately specified synthetic conversion rule |
| 6 | Release first roll and hold second | Only 44.000 kg eligible; held roll cannot be delivered; checker/history retained |
| 7 | Release second after a linked reinspection | Two rolls/88.000 kg eligible; initial Hold is still in history |
| 8 | Deliver first roll then second | Partial delivery is 44.000 kg then total 88.000 kg; physical roll custody and source links agree; no duplicate stock event |
| 9 | Return 5.000 kg yarn | Customer custody remaining is 5.000 kg; receipt/consumption/return/remaining reconcile as 100 = 90 + 5 + 5 |
| 10 | Bill first 44.000 kg at synthetic service rate INR 100.00/kg | Invoice is INR 4,400.00 before a deliberately zero-tax test fixture; remaining billable is 44.000 kg; service only, no sale of customer yarn |
| 11 | Bill remaining 44.000 kg | Total billed is INR 8,800.00; no overbilling; posted General Ledger balances; source references survive reopen |
| 12 | Attempt close with 5.000 kg remaining | Closure blocks and names the unresolved material; it does not silently consume the balance |
| 13 | Return remaining 5.000 kg and close | Receipt 100 = consumed 90 + returned 10 + remaining 0; delivered/billed fabric both 88; no open SC custody; job closes with invoices still legitimately unpaid |
| 14 | Optional payment then reversal case | Payment uses standard ERP controller; receivable clears once. Cancellation/credit follows dependency rules and reverses only intended effects |

The numbers are synthetic acceptance fixtures. They are not recovered Fashion Suite formulas, normal process-loss assumptions or tax advice. Test permitted-loss boundaries separately. Lycra is zero in this first case so its effect is not hidden inside the mass balance.

## Additional required cases

| ID | Scenario | Evidence required |
| --- | --- | --- |
| A01 | General ERP company without knitting | No knitting workspaces; normal core create/save/report remains available |
| A02 | Pack disabled or permission revoked during a session | New write denied on server; direct generic/API/print/file/report paths obey scope; history retained; no cross-company cache leak |
| A03 | Two-company and two-site identities | No cross-company references, reports or file access; no cross-site session reuse; shared permitted master behavior explicit |
| A04 | Setup incomplete and enable/close/disable/reactivate | Capabilities reflect prerequisites; active obligations block Inactive; setup change recorded; reactivation preserves records |
| A05 | Own yarn and owned-fabric sale | Real owned-stock consumption/output/delivery and valuation reconcile; invoice/GL post once; service fixture never accidentally invokes this path |
| A06 | Own and customer lycra | Different owner inputs/custody/cost; all allowed/excess bases explicit; no assumed one-percentage rule |
| A07 | Partial bags/cones, multi-size and roll split | Physical units and kg conserved separately; child roll split linked; fractional invalid counts rejected |
| A08 | Sample/order and specification/rate revisions | Classification separate from lifecycle/owner; existing posted rows preserve source revision/rate |
| A09 | Repeated production/delivery/invoice request | Same request and payload returns same result; changed payload rejected; one canonical movement/GL effect |
| A10 | Two operators consume/deliver the last balance | Real concurrent database test; one succeeds and other receives a useful conflict; balance never negative |
| A11 | Injected failure between event and stock/roll/invoice posting | Whole action rolls back; retry does not leave orphan roll, source link or accounting row |
| A12 | Uncertain network result and session expiry | Check status resolves the request; working form survives; no automatic write replay |
| A13 | QC hold/reject/rework and exception | Ineligible delivery blocked; reinspection history and any authorised exception recorded |
| A14 | SC round trip | Issue known lot, receive fabric, return surplus, settle bill; SC and original job quantities reconcile independently |
| A15 | Planning queue/split/stoppage | Compatible capacity, overlap, due horizon, 24-hour change and 72-hour shortage have explicit fixture outputs |
| A16 | Needle/sinker/consumable issue/return | Boundary/run/remaining kg and replacement history reconcile; each report grouping agrees with source events |
| A17 | Partial invoice, overbill, return, credit and cancellation | Source allocations conserved, stale mappings denied and standard GL balanced; downstream dependencies enforced |
| A18 | Completion/reopen thresholds | Below/exact/above each policy boundary; operational/billing/payment states independent; reason and role recorded |
| A19 | Decimal, rounding and numbering | Nonfinite/negative/overflow rejected; 3-decimal kg and configured money precision; fiscal boundary and duplicate/manual sequences tested |
| A20 | Job/stock/report reconciliation | Job ledger with/without SC, fabric/roll/yarn and as-of/period views match immutable source fixtures and permission scope |
| A21 | Prints and exports | Approved fields/units/totals/source links, roll-label tokens and fiscal tokens; valid native PDF; export permission denied when absent |
| A22 | GST/Tally/provider contracts | Known fixtures only; pending/failure/retry/reconciliation and duplicate suppression; no real tax submission, email or charge |
| A23 | Synthetic migration and restore | Stable source crosswalk; trial import repeatable; company/owner/lot/roll/GL totals reconcile; backup restores exact state |
| A24 | General ERP regression and cross-platform UX | Existing suite plus core/knitting screen-state matrix at 390/834/1440, large text, reduced motion; native Mac walkthrough and supported builds |
| A25 | Estimation to job | Draft Quotation has no stock/GL effects; accepted source specification/rate lines map once; stale/cross-company and denied conversion rejected |
| A26 | Yarn processing and repack | Same-owner input 100.000 kg becomes output yarn 99.000 kg plus declared loss 1.000 kg; input/output cones independent; no fabricated fabric output; source lot chain and owned/custody adapters reconcile |
| A27 | Mixed ownership and charge policy | Customer yarn 90.000 kg plus own lycra 2.000 kg becomes customer-owned fabric 90.000 kg plus declared customer-yarn loss 2.000 kg. Own lycra is issued once; included-rate case bills 90 × INR 100 = INR 9,000; separate-charge case adds 2 × INR 50 = INR 100 without a second stock issue. Both ledgers balance; wrong-party inputs blocked |
| A28 | Holidays master setup and safe correction substitutes | Holiday removes machine capacity; reviewed company/master settings affect only their company; job/roll correction preserves source history and rejects invalid downstream dependencies; no copied destructive delete |

## Run evidence

Each result records: app/server revision, fixture version, site, account role, action/request references, expected and actual balances, GL/stock source documents, report/PDF assertions, test command/run log, native screenshot or walkthrough, failure list and remaining external checks. No real credentials or customer data in logs.

Completion means all required work packages and cases have passed their defined gates, with no known blocking defects. Report compilation, widget, real-database, native interaction and external provider/device checks separately. A browser design preview and an isolated happy-path invoice test cannot establish industry-wide completeness.

The initial release excludes unspecified device automation (S044). Live provider adapters may remain Not configured; they are mandatory customer-pilot gates when that customer needs them. GST/Tally formats require documented schemas and golden-file tests, with customer samples needed before claiming their exact format parity. Independent substitutes for unresolved/deletion routes are required and tested in A28. See the design's release-scope section; do not leave these as an impossible all-vendor-menus completion promise.
