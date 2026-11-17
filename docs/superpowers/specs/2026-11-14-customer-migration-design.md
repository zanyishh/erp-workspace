# Four-company customer migration

The user authorized completing the migration and necessary fixes/testing, approved keeping cash books shared, and approved 1 April 2023 as the effective date for undated openings while retaining their original values. No further generic implementation approval is required. Knitpack receives no writes; this increment works from the verified local archive.

## Approach

Use one separate customer site with four Company records. Preserve source business documents as immutable, scoped history with their original identity, dates, quantities, parties and references. Bind each imported economic effect to at most one native posting authority. Use native Journal Entries for historical financial effects where a native invoice would change the source's accounting amount or party; the original invoice remains linked and printable without double posting. Current settlement references are applied only where independently proved; unresolved matching is visible, not manufactured.

Physical quantities retain the source's batch granularity. Original dated documents remain accessible; verified captured current quantities supply an explicit migration balance from which new operations can continue. Do not infer individual roll weights, undocumented historical consumption, source cancellation or a historical zero opening. Current-state initialization is labelled with its actual migration cutoff, never represented as an original source event. Unknown current records remain visibly unavailable rather than zero.

This is an implementation choice for preserving the full accessible source history and permitting verified ongoing work; it does not claim a replay of an undocumented historical stock engine. A raw archive alone would not meet the request. Replaying ordinary present-day commands would change original dates and risks duplicate stock/accounting effects.

## Data and access

- Immutable migration scope maps source companies 1–4 to distinct native Companies and explicitly authorized app users.
- Historical records have a unique full source key, business payload, original/effective date and date basis, review notes and hash-bound provenance. Identical retries are no-ops; changed content is rejected.
- Shared cash has one scope-level opening and consolidated balance. Company transaction associations remain separate from ownership. No fifth company or duplicated shared opening is inferred.
- Source session, authentication and report-user metadata remain only in the protected original archive, never in app payloads.
- History APIs apply company and financial permissions before filtering/paging. Shared records require explicit scope membership.
- Current native GL/party balances, source history and preserved source adjustment state must be distinguishable; passing software tests alone does not certify source matching.

## App and operations

The native Flutter app accepts a private versioned local launch profile for the customer site, retaining the two existing synthetic demos. Allowed companies come from authenticated server context. Relevant invoice, job and accounting navigation exposes original history with search, clear dates, review explanations and back navigation. Customer data is never seeded into native-test.

Local services remain loopback-only. A named customer launcher/provisioner preserves all existing databases. Take destination backups, verify idempotent retries and rollback behavior, and rehearse new work on isolated synthetic data before applying customer batches. No source rows are corrected to force agreement.

## Acceptance

All available records and source relationships are accounted for, identities/dates remain intact, shared cash is counted once, approved openings use the effective date with raw dates retained, and native financial/physical controls reconcile at supported scope. Test four-company permissions, book separation, duplicate prevention, aggregate batch operations, new payments and invoice/history presentation. Report any source ambiguity or unavailable original honestly; no claim of perfect historical matching, atomic backup, or public launch readiness follows merely from import completion.
