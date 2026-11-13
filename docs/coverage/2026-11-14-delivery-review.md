# ERP Workspace delivery review

14 November 2026 · Local working tree on `feature/knitting-industry-pack`, based on `6ecb89e65409`. The isolated Frappe site was `native-test.localhost`, reached at `localhost:8081` through the dedicated `colima-erp` context.

**Disposition.** The synthetic job-to-invoice and General ERP document cycles pass. Production replacement remains open pending the customer’s formula, report, print, reconciliation and deployment checks. A percentage would imply a denominator of agreed customer workflows that the evidence does not provide.

## Fashion Suite evidence

The 13 November [functional specification](../research/fashionsuite/2026-11-13/knitpack-functional-specification-and-erp-gap-analysis.docx) and [screen catalogue](../research/fashionsuite/2026-11-13/knitpack-screen-catalogue.json) cover 234 menu entries across 36 groups. The Word specification contains all 232 distinct screen IDs. Their ID/route pairs match the [scope matrix](knitting-scope.json). The files matched the SHA-256 values in the earlier layout review, which recorded 36 pages. The 14 November [workflow and delivery review](../research/fashionsuite/2026-11-14/knitpack-workflow-and-delivery-review.docx) updates the local product assessment.

The automatic browser approval review blocked a new visit to the live customer origin before sign-in. Current testing used synthetic data. The 227 previously opened screens establish visible screen structure. Three menu-only entries concern job deletion, automation testing and roll editing/deletion. The two unresolved links concern master configuration and holidays. Hidden transaction-editor rules, vendor formulas and customer-specific equivalence require separate, authorised test material.

## Findings verified in the working tree

| Workflow | Fault found and evidence of repair |
| --- | --- |
| First sign-in | A fresh form prefilled Administrator, reported invalid credentials as an expired session and allowed malformed addresses to reach the connection callback. Labels, field validation and credential errors now identify the next action. Verification-code, website-account and password-reset responses follow pinned Frappe. Initial login and renewal handle mistyped and leading-zero verification codes in synthetic tests. Actual email/SMS delivery and authenticator enrollment were outside the test. |
| Company and permissions | The server and app now return and display an unassigned state for a staff account without Company read access. The worker can check for assignment or sign out. Revocation and failed access refresh have recovery paths. General ERP shortcuts use effective read/create capabilities. New document opens the permitted creation list directly. |
| General documents and reports | Master types that prompt for a name can be created, edited and reopened. Required fields in child rows identify the row and field. A failed default lookup can be retried. Stale-document recovery offers to fetch the current version and preserves the draft when the fetch fails. Tests also cover date bounds, blank comments, hidden report columns, numeric filters, export and quantity/currency display. |
| Job identity and pricing | Changing the selected job clears dependent roll and programme references. Revisions load the existing programme and preserve agreed line rates. The backend regression changes a specification without replacing the agreed 112/126 rates with a newer 150 rate. Explicit repricing remains available. |
| Production and dispatch | Review catches a 0.001 kg mass discrepancy. Checking and dispatching a roll open the selected roll with the current job version. A stale source can be reloaded before the write. The register exposes a paginated job finder. A fixture opens job 201 beyond the recent-200 dashboard and starts production with its programme. |
| Custody and purchasing | The server rejects mismatched GSM/loop specification transfers, customer material posted by adjustment to an owned job, and a job-specific purchase order received into general stock. A pack cannot be deactivated while a consumed owned receipt still has an unbilled supplier quantity. |
| Accounting | A manual owned-yarn receipt and supplier bill could hit different offset accounts. New receipt/bill tests reconcile a ₹120 accrual to ₹72 after the first partial bill and zero after the last bill. New bills against older unbilled receipts clear the original account. Existing posted historical bills were not rewritten. A read-only check found zero linked submitted manual-receipt bills on the isolated site. |
| Filtered reports | A machine selection showed three rolls weighing 60 kg but a summary of 88 kg. Employee/gauge filters also returned unrelated breakage, and a financial filter could show ₹8,800 net and ₹900 cost with zero matching invoices or cost sources. Reports now apply the dimensions and compute totals on matching records before pagination. Split-parent weight is excluded from grouped stock weight. |
| Workstation usability | Search and empty states, action-specific icons, matched report export dates, job-picker pagination, and report and setup navigation have widget coverage. Short-phone reporting was exercised at 360 × 510. The sign-in view was rendered and inspected at widths of 390, 834 and 1440. A design inspection caught a collapsed desktop illustration and low-contrast field labels before the final render. |

## Connected evidence

| Operation | Observed result |
| --- | --- |
| General ERP read | The native-test gateway returned data for all eight dashboard modules. Stock returned a page of 50 items. Empty module lists also completed. |
| Create, edit and reopen | The Dart client created synthetic record `0kpbosvj8o`, edited and reopened it with its child row, posted a comment, uploaded and read back identical attachment bytes, removed the verification attachment and generated a PDF. The account's catalogue listed 488 record types and 197 reports. These are catalogue counts. |
| Knitting operations | Synthetic job `KN-NTEST-JOB-2026-00007` received 100 kg, consumed 90 kg, produced 88 kg in two rolls with 2 kg loss, and returned 10 kg unused yarn. Both rolls passed inspection and were dispatched. |
| Correction and closure | A one-roll credit was −₹4,400 and the physical return restored 44 kg. Reversing the return, credit and original invoice allowed the replacement invoice `ACC-SINV-2026-00012` for ₹8,800. Its PDF was readable. Yarn, in-house fabric, unbilled and subcontract balances were all 0.000 kg on close. |

## Verification results

| Check | Result in this run |
| --- | --- |
| Real Frappe and MariaDB tests | 136 passed in 41.695 seconds. The suite includes 95 knitting scenarios, 39 General ERP native API scenarios and two workspace selection scenarios. |
| Flutter suite | 171 tests passed. The complete static analysis reported no issues. Four separate framework-metadata tests also passed. |
| Mac build | The ARM64 release compiled and passed deep/strict local code-signature verification. macOS reported a locked screen when the built app was opened for a fresh hands-on walkthrough. Current UI evidence consists of Flutter interactions and renders, plus the real local HTTP cycles above. The preceding audit records the earlier hands-on Mac walkthrough. |
| Other target builds | ARM64 iPhone simulator and Android ARM64 debug builds succeeded. Windows compilation, physical device execution, and distribution signing remain open. |
| Source and document checks | The three upstream checkouts were clean. Both Word files passed archive integrity checks. The new review was rendered as five pages and visually checked. |

The client content fingerprint was `d01cd92bb12fdf316c326dc082888a0fc7089232e0c958de571a03492ea0d072` and the server fingerprint was `209d364785adf3453d97bae734b1f35bce08a0d72d6c502d4413c9e9a371877a`, using the project’s launcher fingerprint tool. Local signature validation checks bundle integrity. The Mac build emitted an Xcode destination metadata diagnostic. The backend test log contains upstream deprecation warnings.

## Release gates

- Compare the mill’s signed examples for loss and excess, mixed input charges, rate changes, stock ownership, and numbering. Record exact print and export acceptance. GST/Tally files are review formats. E-Invoice, E-Way Bill, payment providers and factory hardware require their own configured test environments.
- Test the customer’s actual General ERP workflows. Existing gaps include custom/dynamic reports, form-specific scripts and actions, POS, bank reconciliation, advanced field types, and manufacturing/asset scenarios. The [original General ERP inventory](../setup/NATIVE_WORKFLOWS.md) distinguishes metadata, implemented controls and tested business cases.
- Exercise screen readers, physical phones, print/scan hardware, a Windows build on Windows, installation and distribution signing. Benchmark factory-scale data and concurrent operators. The mill snapshot is bounded to 200 recent jobs and up to 500 supporting records per list.
- Rehearse a full-site backup/restore and migration with authorised sample material. Run an uncoached first-use session with a clerk and a floor operator, including a validation error and correction. Usability with actual first-time operators remains unmeasured.

## Research and reproducibility

Flutter’s guidance covers accessible names, scaled text, actionable errors and native screen-reader checks. W3C describes inline errors and form-submission feedback. They informed the UI cases. ERPNext’s guides describe which document posts stock and which posts the receivable. Real database tests use the corresponding pinned controllers. [Flutter accessibility](https://docs.flutter.dev/ui/accessibility) · [W3C form notifications](https://www.w3.org/WAI/tutorials/forms/notifications/) · [ERPNext Delivery Note](https://docs.frappe.io/erpnext/delivery-note) · [ERPNext Sales Invoice](https://docs.frappe.io/erpnext/sales-invoice).

Test commands and site setup are documented in the [previous workflow audit](knitting-workflow-audit.md) and [native workflow guide](../setup/NATIVE_WORKFLOWS.md). This run’s raw logs and sign-in renders are under the ignored local directory `.local/verification/delivery-review/`. The upstream ERPNext, Frappe and deployment checkouts retained clean working trees.
