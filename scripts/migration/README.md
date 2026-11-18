# Offline Knitpack archive check

This standard-library tool reads an already acquired archive. It never connects
to Knitpack, changes the archive, or imports customer data into the product.

```sh
python3 scripts/migration/check_knitpack_snapshot.py /private/archive/source-snapshot --report /private/audit/report.json
python3 -m unittest discover -s scripts/migration -p 'test_*.py'
```

The checker writes private JSON and Markdown reports with owner-only permissions.
It verifies manifest file sizes and SHA-256 hashes, excludes failed responses,
deduplicates historical job selectors, reconciles full job records, and checks
source IDs, company identity, and fiscal-year dates. Indian April-to-March fiscal
years are inferred from the source fiscal labels; this assumption is stated in
every report. No customer rows, session values, or raw API messages are emitted.

Exit `0` means the checked files and identities passed, **not** that migration is
complete. Exit `2` indicates damaged or inconsistent evidence. An empty selector
does not establish an empty company. Job-level checks do not establish complete
transaction, accounting, stock, attachment, or audit history. Synthetic tests
use temporary generated records and do not read a customer archive.

## Offline report completeness and identity inventory

```sh
python3 scripts/migration/inventory_knitpack_reports.py /private/archive/source-snapshot /private/archive/report-snapshot --report /private/audit/report-inventory.json
```

This helper captures both manifests beside the private output before reading the
captured response files. It verifies their sizes and hashes, inventories field
types and original date ranges, compares job-history/header coverage with the
original company/job index, and reports candidate-ID repetition, embedded
masters, warehouse/company evidence and attachment-reference fields. It handles
both object report roots and grouped ledger roots. Template variables and
authentication material are excluded.

Row counts, repeated row fingerprints, and candidate IDs are observations, not
certified transaction counts or permission to deduplicate joined report rows.
An unbound godown is not assigned to a company from transaction context alone.
Empty arrays do not certify empty businesses; a job-ledger header does not fill
a failed job transaction history. Every one of the twelve destination evidence
domains remains incomplete until its independent requirements are reconciled.
The helper performs no accounting arithmetic, source request, import or site
operation. Exit `0` means no captured integrity/identity issue was detected,
**not** migration completeness; import is always disabled in its output.

## Captured Tally text

```sh
python3 scripts/migration/audit_knitpack_tally.py /private/archive/report-snapshot --output-dir /private/audit/tally
```

This preserves each `result.tally_txt` string exactly as UTF-8 text with its
source-response hash, captures the manifest, and writes a private structural
audit. Semicolon records are corroborated only by exact party/reference/date
and five-value tuples against native voucher headers; ambiguous matches remain
unresolved. Unnamed columns are an explicit candidate mapping, not an official
export schema. Repeated records are never silently removed. XML, if present,
is parsed without external resolution and DTD/entity declarations are rejected.
No export is executed or imported, and no GL or settlement balance is certified.

## Native voucher children and allocation candidates

```sh
python3 scripts/migration/audit_knitpack_voucher_children.py /private/archive/report-snapshot --report /private/audit/voucher-child-audit.json
```

The auditor captures the manifest and validates saved tax-child IDs and their
`voucher_id` links before comparing raw saved child-field sums with headers.
It preserves discrepancies without invoking source tax calculations or choosing
rounding rules. It also checks allocation candidate IDs/dates against native
company/book/party voucher identities and distinguishes explicit endpoint
candidates, unresolved positive rows, zero rows and later-dated candidates.
Candidate `id` can identify the current voucher, a different voucher, or an
unresolved obligation; a native allocation-row ID and effective date remain
unproved. Display sums matching `adj_val` or `pend_amt` are diagnostic
only: the public client does not persist those fields from its display sum.
No candidate is promoted to a historical allocation event or posted into a
destination. See the separate current-state auditor below.

## Conserved current settlement state

```sh
python3 scripts/migration/audit_knitpack_current_settlements.py /private/archive/report-snapshot --ui-asset /private/public/5264.32b10518d6d432f0.js --report /private/audit/current-settlements.json
```

This auditor pins the independently reviewed public edit screen by hash, captures
the archive manifest, and checks native headers, exact reference identities,
opposite entry types, amounts and connected-component conservation. Positive self
rows are summaries, not self-allocations. Unknown targets, repeated rows,
conflicting reciprocal amounts, missing scopes and overallocations stay unresolved.
Reciprocal views of one pair are one current reference, not two historical events.
Identical recaptures remain evidence for one current view; changed versions are
unresolved and are not silently replaced by a convenient snapshot.
Explicit adjustment-row company, party or book values must match the native
target. An opening response with no record and a different returned book remains
a scope diagnostic, not proof of an opening or of absence in the requested book.

A conserved current reference can receive a new destination child ID; it does not
require an invented source child ID or effective timestamp. Original voucher dates
are retained separately. Native pending-field comparisons remain diagnostics.
This evidence cannot authorize import or replace the remaining accounting,
ownership, invoice-link and completeness controls.

## Historical company/book plan preflight

```sh
python3 scripts/migration/preflight_knitpack_books.py /private/explicit-plan.json --report /private/audit/book-preflight.json
```

This pure offline contract check requires separate mappings for all four source
companies, nonblank Finance Books, source identities including the original book,
unchanged posting dates, native evidence locators and exact same-book references.
Recognized source books are `0`, `1` and `2`, each corroborated by native records;
this does not assert complete historical coverage in each company/book scope.
Shared cash ownership needs an explicit recorded decision; request echoes and
allocation candidates cannot supply it. Historical settlement events require a
stable edge key and original effective date; a current-state reference instead
requires an independently verified component-conservation evidence locator. The private design describes native
ERPNext extension points and the runtime tests still required; no hook is installed.

`contract_valid` checks only the submitted plan's book-scope structure. Evidence
locators and ownership assertions must be independently verified. This check does
not validate amounts, complete business history or target runtime behavior.
`import_allowed` and `balances_verified` are always false, including on exit `0`.

## Offline master identity preparation

`prepare_knitpack_masters.build(instance, observations, uses)` is a pure offline
library. It binds source namespaces and native IDs, including company/job/parent
scope where required, to deterministic proposed registry keys. Original fields
and dates remain in hash-bound source files referenced by JSON pointers; the
package does not copy master values into a destination or assign posting dates.

Repeated evidence is deduplicated. Conflicting source fields and target-key
collisions are quarantined. Company-use references remain separate from ownership,
and contextual yarn/fabric identities do not imply a global ERPNext Item. The
library validates evidence-locator shape; the archive selection/verification step
must verify the actual file hashes. It has no CLI, database client or import path,
and both `import_allowed` and `operational_migration_complete` remain false.
