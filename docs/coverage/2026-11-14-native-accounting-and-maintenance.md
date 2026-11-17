# Native accounting, inspection and maintenance workflows

The following rehearsals used a registered synthetic owner in a dedicated company on `native-test.localhost` on 14 November 2026. Real ERPNext controllers posted the transactions. Financial documents and test-site credentials were never sent to an external service.

| Entry in Flutter | Connected result |
| --- | --- |
| Accounts → Reconciliation → Reconcile payments | A customer receipt and supplier payment each had ₹75 unallocated. Applying ₹25 to their respective ₹100 invoices left ₹50 on each payment and ₹75 outstanding on each invoice. The vouchers were `ACC-PAY-2026-00013` / `ACC-SINV-2026-00028` and `ACC-PAY-2026-00014` / `ACC-PINV-2026-00008`. |
| Accounts → Reconciliation → Match bank statements | A ₹75 deposit and ₹75 withdrawal, `ACC-BTN-2026-00003` and `ACC-BTN-2026-00004`, matched the two posted payments. The statement balances became zero and each payment acquired a clearance date. Matching the bank movement left the invoice allocations intact. |
| Purchase Receipt → Create / copy → Inspect receipt items | The owner selected the second of two receipt lines for the same item and sampled two units. The inspection opened as `MAT-QA-2026-00001` against `MAT-PRE-2026-00006`. Reopening that line returned the same draft. |
| Asset → Create / copy → Maintenance plan → Maintenance logs | Asset `ACC-ASS-2026-00001` opened its company maintenance plan and due calibration log `ACC-AML-2026-00001`. A real database regression completed a monthly log and verified the next draft log due one month later. |

Authorization comes from the signed-in user's company, role and individual source-record permissions. The accounting screen presents a confirmation before posting and rechecks both balances on the server. Targeted tests exercised over-allocation, stale confirmations, duplicate matches, wrong-company selection, duplicate receipt item rows, oversize samples and monthly rescheduling.

Invoice allocation covers submitted Payment Entries with free balances and outstanding customer or supplier invoices against the party's configured account. Bank matching covers existing submitted bank transactions against regular posted receipts and payments. ERPNext supplies the matching candidates and records the clearance. Journal and credit-note allocation, internal transfers and automatic reconciliation are outside these two native workflows. Both connected financial checks used INR.

The receipt handoff respects the site's post-submission inspection policy. It creates a draft for a selected purchase receipt item or opens an existing inspection. Owners use the native inspection form to enter measurements and submit. The asset handoff opens an existing plan or a new prefilled plan. Maintenance teams, task assignments and frequency follow ERPNext's native validation.

## Import a bank statement

Select the company bank account on **Match bank statements**, choose **Import bank statement**, then select a UTF-8 CSV file. Map the date, a deposit and/or withdrawal column, bank reference, narration and optional bank transaction ID. Choose the date format and preview all lines, including duplicates, before posting. The importer accepts up to 200 rows and 256 KB per file. Every row must have exactly one positive deposit or withdrawal, denominated in the selected bank account’s currency.

A real company-scoped test imported a ₹65 deposit and ₹70 withdrawal, matched both to posted Payment Entries and verified their clearance dates. Uploading the same file after reconciliation created zero additional transactions. The importer uses bank transaction IDs where supplied. Without IDs, it compares the account, date, amounts, reference and narration. Indistinguishable rows within one file require distinct transaction IDs. A changed amount under an existing ID stops the import for review.

In a connected Flutter rehearsal, the synthetic owner read a real local file through the mapping screen, confirmed two statement lines and reopened the file. Its second preview showed zero new rows and two duplicates. ERPNext returned exactly two posted entries for the bank reference. The rehearsal exercised the file reader and screens with a supplied local file path. Native operating-system file-picker dialogs were not exercised.
