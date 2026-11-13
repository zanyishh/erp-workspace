# Knitting output and integration contracts

Version 1, 13 November 2026. All verification uses synthetic companies on `native-test.localhost`. Nothing connects to the customer’s Fashion Suite, a bank, a tax portal, email or a payment service.

## Connected business records

The Flutter client talks to the installed Frappe extension over its authenticated session. Each reviewed command uses a company-scoped request identity and source version. Owned stock posts through original Stock Entry and Delivery Note controllers; service and fabric billing posts through original Sales Invoice; subcontract procurement uses Purchase Order and Purchase Invoice. These remain normal ERPNext records with source links and native PDF, files and accounting access. Knitting roles control industry tasks; standard Stock User, Accounts User/Manager and purchase permissions must also be assigned where a role needs those original controllers. An industry role does not grant itself general accounting write access.

## Reports and time basis

Reports accept a fixed report name, company, optional permitted job, As of/Period, dates and page. Pages contain at most 100 rows. Exports require export permission and a maximum of 10,000 rows; large event histories must be narrowed before processing more than 100,000 events. Decimal quantities cross the boundary as strings with three decimal places, money with two. Only declared report columns are returned. Billing and margin require financial access.

As of reconstructs event/roll state through the end date, including correction timing. Period limits movement events to the selected dates; custody columns in the job reconciliation are closing balances. Production/roll activity uses production dates. Outstanding receivables are explicitly current, not historical aging. Margin uses company-currency invoice net revenue less posted expenses from linked stock, delivery and subcontract financial documents, before unallocated overhead. It is not a prediction of profit, tax or a substitute for ERPNext’s full ledger reports.

## Local files

- CSV: UTF-8 with BOM, CRLF rows, declared column keys, standard CSV quoting; formula-leading text is escaped. No background sharing.
- PDF: original ERPNext invoice/document printing; operational report PDFs; independent roll-label PDF with source job, programme line, actual kg, machine, time, state and readable identity token.
- Fiscal reference: the label helper uses April–March India fiscal-year notation; it does not change the server’s configured fiscal year or original ERPNext document numbering.
- Roll token: `job|programme_line|44.000kg`. This is an identity/reference token, not a claim of compatibility with a customer’s scanner or label stock.

## Review formats and provider boundary

`gst_review` emits `erp-workspace.gst-review.v1`: company, review-only purpose and invoice/posting-date/currency/net/tax/grand-total fields. `tally_review` emits an `ERPWorkspaceReview` XML with the same explicit fields. Checked-in synthetic golden files define these independent contracts. They are **review files**, not GST portal upload schemas or Tally import-compatible vouchers. Customer-approved samples and official provider/schema validation are required before implementing those outbound formats. Existing general ERP reports remain accessible.

E-Invoice, E-Way Bill and payment gateway show **Not configured**. Their controls explain the missing provider rather than fabricate submission, payment or reconciliation success. A later adapter must retain the originating company, document and request identity, provider reference, pending/failure/confirmed state, retry policy and reconciliation evidence. No provider secrets belong in these source files or exports. Device automation, scanners, printer margins and real provider submissions require separate device/provider testing.
