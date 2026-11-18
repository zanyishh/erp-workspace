# Knitting report and original-history filters

Continue the user-authorized application improvement before hosting. Reuse supported report dimensions and add reliable filters for preserved original records; do not reconstruct unknown vendor calculations or mutate source history.

## Operational reports

Expose existing server-supported customer/material owner, order, machine, operator/user, employee, shift, fabric, dia and gauge dimensions only on report families whose rows provide them. Keep job fixed when the screen is embedded for one job. Use permission-filtered existing pickers with an exact-value fallback for historical/inactive IDs; never imply active-only choices are a complete history list. Employee and operator are distinct. Keep company scope and existing aggregate source-permission guards.

Keep draft controls separate from applied filters. Run resets the page; subsequent pages and exports use the applied parameters until another run. Show the applied selection clearly. Report/company/access changes remove inapplicable controls and invalidate stale responses. Existing backend filtering already precedes summaries, grouping, counts and pagination; preserve that contract.

## Original history

Add optional `filters` to records/shared_cash and a bounded `filter_options(company, family, field, query='', start=0, filters=None)` endpoint. Fixed allowed keys: from_date, to_date, date_basis, source_book, party, job, status. Reject unknown keys, invalid/reversed ISO dates, unbounded strings and unsupported combinations. All predicates are parameterized and applied in SQL before rows/count/paging; options use the same scope and applicable predicates with a fixed JSON-path allowlist.

Party is an exact visible normalized original party name; duplicate labels remain included. Job is the exact family-specific normalized displayed order value, not a universal source/destination identity. Status uses only the existing normalized status. Do not inspect opaque raw fields or infer missing/cancelled states. Show these controls only when scoped normalized values exist. Options are paged with has_more; no first-page-only choice list.

With no filters, preserve existing results including undated records. Date ranges default to original-date semantics (date_basis=original). Effective-date mode explicitly includes approved openings. No-original-date mode includes records whose basis is not original, including approved undated openings, and cannot be combined with a date range. Do not invent or change original dates. Source book filters use exact recorded values; distinguish an omitted filter from explicit null if a No source book choice is exposed.

Return filtered row_count without relabelling the summary's unfiltered family totals. Shared-cash filters change only displayed rows/count; validated balances remain the full shared-book controls and are labelled accordingly.

## Verification

Synthetic SQL tests cover matches beyond the first page, combined predicates, quote/wildcard values, identical references in different books, null/original/approved-opening dates, duplicate party names, absent job/status, denied company/member/financial scope for options and counts, and unchanged shared cash controls. Flutter checks cover exact parameter values, reset/clear, stale responses, applied-export consistency and 360px/desktop layouts. No customer/source writes or deployment; native Mac walkthrough remains unverified by user direction.
