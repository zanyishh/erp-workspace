# Knitting workflow audit

13 November 2026. The backend scenarios use synthetic companies and real Frappe and ERPNext controllers on `native-test.localhost` in the local `colima-erp` Docker context. All 47 registered knitting commands returned a successful result during the run. The native request handler, database transactions, stock postings and General Ledger remained active throughout. The counter recorded a command only after the real handler returned.

**124 backend tests passed in 40.066 seconds.** The eight modules covered 85 knitting scenarios, 38 general ERP scenarios and one saved-company selection scenario. The final log is `.local/knitting-workflow-final-retry.log`. ERPNext emitted its stock-controller deprecation warning and Frappe emitted a notification-parser warning during attachment tests.

## Workflow evidence

| Area | Paths verified | Reconciliation or guard |
| --- | --- | --- |
| Jobs and commercial terms | Create, revise, quote, accept, convert, set rates, complete individually or in a batch, reopen | A quotation converts once under concurrent requests. Delivered quantities retain their agreed prices across revisions. Completed jobs reject operational postings until reopened. |
| Yarn and ownership | General and job receipts, allocation, inter-job and inter-godown transfer, repacking, adjustment, yarn return, owned auxiliary charges | Moving 3 kg and one unit out of a 5 kg owned lot leaves 2 kg and one unit at origin. Returning the full consumable issue restores the same 3 kg and unit at destination. Customer yarn stays in the custody ledger. |
| Purchasing | Yarn purchase order, receipt, bill, dependency rejection and ordered cancellation | A 20 kg, two-unit general purchase at INR 10/kg returns to zero stock, custody, units and net posted GL after cancelling bill, receipt and order. |
| Production and inspection | Planning, replan, single/bulk production, split, fabric transfer, multiple QC decisions, release, machine and component counters | Reverse-order corrections restore 88 kg of yarn and zero component/plan progress. Replanning preserves the active run's machine. Correcting a reopened job retains a previously released slot. |
| Subcontracting and maintenance | Customer/owned issue, receipt, surplus return, billing, completion, partial short-close, reopen, bill correction/rebill, component replacement/breakage, stoppage and consumable return | A 30 kg partial receipt against 88 kg can be short-closed, reopened, rebilled, reclosed and reversed. Native PO status follows the reviewed subcontract. The shortened target stays at 30 kg. |
| Delivery and accounting | Customer and owned delivery, partial/grouped invoice, preview, credit, physical return, redelivery, rebill, payment and linked cancellation | An active invoice continues to protect its delivery after a full credit. A prior return cannot be reversed after the same roll has completed another delivery/return cycle. |
| Reports and exports | Job reconciliation, yarn, fabric, production, quality, subcontract, financial reports, planning, transaction history, labels and exports | Period corrections carry the opposite quantity and money on their own date, including INR 8,800 of revenue and INR 900 of delivery cost. Filtered machine changeovers retain the previous job. GST/Tally review files preserve each posted invoice when the screen is grouped. |
| Permissions and recovery | Role and company scope, linked warehouse restrictions, source versions, transaction rollback, uncertain-request replay, concurrent consumption and fixture recovery | Stale bill/consumable selections reject changes. Source-only forms lock the source job and advance its version. Recovery compares original stock and GL rows and the replayed command result. |

## Full owned-stock reversal

The end-to-end scenario receives 90 kg of owned yarn in three units at INR 10/kg, produces one 88 kg roll with 2 kg of loss, releases it and invoices INR 8,800. It closes the job, reopens it, posts an INR 8,800 credit and returns the roll to stock. QC, redelivery and rebilling produce a new INR 8,800 invoice. Corrections then unwind the second invoice through the first receipt, preserving each source document.

The scenario checks 88 kg of returned fabric before redelivery, 90 kg and three units of yarn after cancelling production, zero final yarn and fabric in the ERPNext stock bins, zero custody and job balances, and zero net active GL balance **per account** across the eight linked vouchers. All eight original vouchers finish with cancelled document status.

## Reproduce

From the project root, with the isolated native test services running:

```sh
docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml exec -T native-test-backend \
  /home/frappe/frappe-bench/env/bin/python -m unittest discover \
  -s /home/frappe/frappe-bench/apps/erp_extensions/erp_extensions/tests -p 'test_*.py' -v
```

The baseline had 109 passing backend scenarios. The new tests found a receipt that could never be cancelled after otherwise fully reversed production, dependencies hidden by zero net billing or a repeated roll state, and machine counters that could not unwind after a later correction. Company-only purchase cancellation already worked and now has a positive full-chain regression.

## Native app check

On the isolated HTTP service, synthetic job `KN-NTEST-JOB-2026-00005` received 100 kg of customer yarn. Production consumed 90 kg and yielded two 44 kg rolls with 2 kg of declared loss. The remaining 10 kg of yarn went back to the customer. After inspection, delivery, invoicing and closure, the job was reopened. One returned roll produced a ₹4,400 credit and a 44 kg increase in fabric on hand. The return, credit and original invoice were then cancelled in dependency order. Replacement invoice `ACC-SINV-2026-00006` totalled ₹8,800. Job closure reconciled yarn, fabric, unbilled and subcontract balances to zero. The replacement invoice PDF opened through the client API.

Company setup offers General ERP and Knitting ERP, with the existing stock item, service item and godown checks applied at activation. A permitted knitting user opens directly in the mill job register on the next login. The signed-in account's selected company is saved separately from its ERPNext accounting defaults. Jobs, yarn, planning, production, quality, dispatch and billing appear according to that account's permissions. Shared records open from the mill navigation.

All 121 Flutter tests passed and static analysis reported no issues. The Mac release build passed strict local signature verification. A new native login opened the job register, and the actual new-job form opened with fabric imagery and grouped entry fields. Mac screenshots are in `.local/verification/knitting-native/industry-home.png` and `native-new-job.png`. The iPhone simulator and Android ARM64 debug builds succeeded. Physical device operation, Windows compilation, production volume and external provider submission were outside this local run.

## Guided job flow and dashboard verification

The follow-up run passed 125 backend tests and 136 Flutter tests. Static analysis reported no issues. Through the running local service, the Flutter client verified eligible actions and sources across programme entry, yarn receipt, roll inspection, dispatch and invoicing. Returning a 44 kg roll made it eligible for reinspection. Cancelling the credit, return and original invoice allowed a replacement invoice of ₹8,800 on job `KN-NTEST-JOB-2026-00006`. Yarn, fabric, unbilled and subcontract balances closed at zero. The replacement invoice PDF was readable.

The current build compiled for macOS release, the iPhone simulator and Android ARM64 debug. In the full-screen Mac app, opening a running job and selecting Receive yarn carried the selected job, customer and company into the form. The [Mac performance measurements](workspace-frame-timings.json) include first-open frame costs and two runs with 200 jobs and 500 production postings.
