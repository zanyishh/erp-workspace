# Original operational record printing

The user has directed continued application improvement before hosting, preserving the customer's knitting workflows and source data. This is a focused implementation of the approved knitting print requirement and the 15 November audit gap, within the existing continuous-implementation authorization.

## Approach

Add a printable, immutable source copy for original orders, yarn receipts, yarn returns, production, fabric deliveries and subcontracts. Reuse the existing authorized historical detail projection and existing Flutter PDF/printing libraries. Do not route operational records through the invoice renderer or invent legacy stationery, missing totals, roll identities, signatures or transactions. Exact source layout equivalence remains unverified; these copies preserve the facts the app can already show.

The server must recheck company/scope membership, family and native print permission whenever print data is requested. Existing financial-field masking applies unchanged. No original, posting authority, stock quantity or balance is changed. Source metadata, raw archived payloads, credentials and internal posting links are excluded from printed data.

## Contract and presentation

`erp_extensions.migration.printing.record_data(company, name)` returns version 1, company, source_record, source_copy=true, document_label, title, reference, original_date, effective_date, date_basis, review_status, fields, tables and review_notes. Supported families map to the existing Knitting Job or Knitting Event print permission. Invoice printing retains its existing dedicated contract. Missing original dates are labelled Not recorded; approved effective dates remain distinct.

The Flutter detail screen exposes **Print original record** only when the server says this operational copy is printable. A dedicated preview uses the established charcoal, off-white and peach style, A4 pages, clear source-copy labelling, repeated page headings and readable labelled lines when a source table is too wide for a normal table. Preserve zero, null and exact decimal-string distinctions. Long notes and tables must paginate without dropping rows or shrinking them into illegibility.

Preview and export re-fetch authorized data. A company/access change invalidates an in-flight response; export is blocked after access loss. Keep original invoice preview unchanged.

## Verification and limits

Use synthetic fixtures on native-test.localhost for allowed/denied print permissions, cross-company denial, unsupported families, unchanged record digests, financial masking and managed account route restrictions. Flutter checks cover visibility, server arguments, scope mismatch/access loss, preserved decimal strings and long multi-page content. Render synthetic PDFs and inspect them. Native Mac walkthrough remains unverified by user direction. Hosting is deferred; no customer or source business records are used for tests.
