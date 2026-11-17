# Knitpack data preservation

All **28,370 frozen responses** passed byte-size and SHA-256 checks. All **26,764 packaged historical records** matched the saved backup by source identity and recomputed content hash. The register audit found **1,272 stored company links that disagree with those records**. Six historical jobs lack a usable transaction history, and the sequential capture leaves the current source population unknown.

The review ran on 18 November 2026 in India using local archives and a compressed database backup. No requests went to the customer account and no customer records were changed.

## Archive and backup checks

| Frozen evidence | Verified responses | Bytes | Manifest SHA-256 |
| --- | ---: | ---: | --- |
| Original capture | 286 | 4,148,856 | `a02f11c36ff0221a88a947690fd76423c25b6086819d55d319edb7a681a93468` |
| Report and saved-document capture | 28,084 | 421,197,301 | `b5b5525d45c59d870c83dd65591c7a31ddb42abb67c366579bbb7202662bf631` |
| **Total** | **28,370** | **425,346,157** | |

Both current manifests match the frozen copies and the previously recorded digests. Every response is a private regular file with matching bytes and digest. There were zero missing, duplicate or extra response paths. The one decoded logo (20,886 bytes) matches both its source field and the saved asset digest.

The provenance preflight verified 24,974 distinct referenced files and 39,782 distinct JSON pointers. It checked identity uniqueness, the base package and the 177 additional reference masters, including one previously reviewed correction to an absent source context. The result matches the saved import receipt. The final dump contains exactly the same source keys and normalized business-content hashes. Verification decompressed the dump and read historical rows as text. No SQL ran.

| Historical family | Package and backup |
| --- | ---: |
| Jobs | 1,657 |
| Production records | 11,601 |
| Yarn receipts | 2,036 |
| Yarn returns | 639 |
| Fabric deliveries | 4,192 |
| Invoices | 1,976 |
| Vouchers | 3,320 |
| Party openings | 51 |
| Shared cash movements | 272 |
| Shared cash openings | 2 |
| Adjustments | 13 |
| Subcontract documents | 3 |
| Master histories, including the supplement | 1,002 |
| **Total** | **26,764** |

## Shared-record company index

The full dump comparison now checks the document name, migration scope, separately stored register fields and content hash against the authenticated original. In **25,492 rows** every field matched. In **1,272 rows**, only the company link differed. The 998 shared reference masters, 272 shared cash movements and two shared cash openings each had a company in the register column. Their authenticated payloads correctly had no owning company and their shared flags matched. The dedicated history screens use those flags for shared visibility. Company-filtered queries that rely on the link alone can attribute these records to the wrong company.

Frappe fills a missing company link from the operator's default during insert. The importer now excludes original register fields from default filling. An authorized replay of the same verified input can clear the legacy shared-company link under the existing scope lock. That correction requires matching payload, identity, scope, visibility flags and a currently bound company. It leaves original values, dates and postings intact. Applying the correction to an authorized destination and verifying a fresh backup are outstanding. The stricter verifier exits with status 1 on the saved backup.

## Outstanding evidence

| Population or question | Evidence and remaining limit |
| --- | --- |
| Job transaction history | The first index contains 1,657 distinct jobs. The later capture contains 1,656. The same-job transaction-history response was usable for 1,651 of 1,657 requested identities. The ledger response contains a matching saved header for 1,656 distinct jobs. A header cannot establish missing child activity. The reason for the missing later job remains unknown. |
| Changes since capture | Reads span several hours on 14 November. Only a separately authorized delta or point-in-time source export can establish subsequent inserts, edits and deletions or reconcile an authoritative cutoff. |
| Attachments, cancellations and audit events | The logo has verified bytes. A complete source attachment inventory, deleted-record history, and underlying audit trail are unavailable. Raw response hashes authenticate the bytes against the saved manifests. |
| Roll and stock history | The saved production data identifies aggregate batches. Individual roll identities, weights, consumption by lot and historical stock valuation lack sufficient evidence. |
| Financial settlements | Recalculation from the 3,320 voucher and 51 opening headers found 262 company/party/book scopes. Debit and credit adjusted totals differed in 48. Nine contained an adjusted amount above its voucher amount, including four additional scopes, giving 52 unresolved scopes. Rechecking 2,907 saved allocation views found three differences against their adjusted totals. There were 1,591 supported references in 320 balanced components. No postings were replayed. The full historical allocation graph, effective dates and source journal legs remain unproved. |
| Master ownership and compliance | Earlier analysis found no company binding for 39 machine and 49 employee originals, missing machine capacities and necessary HR dates. External tax submissions and service-provider history were outside the capture. |

Earlier destination checks cover 262 party/book balance groups and 9,904 stock comparisons. Those figures describe their recorded stage. This review compares the saved backup's historical-record table only. Runtime permissions, printing, posting, warehouse controls and current destination state require separate evidence. The private 14 November migration review retains the earlier results.

## Reproduce

From the ERP repository root, with the authorized offline files in their existing locations, run the verifier and the synthetic regression suite.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/migration/verify_knitpack_preservation.py \
  .local/knitpack-migration .local/customer-workspace \
  .local/customer-workspace/backups/20261115_003357*database.sql.gz
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/migration -p 'test_*.py'
```

The offline migration suite passed **253 tests**. The register regression includes a borrowed company, changed scope/name, SQL null versus literal text, and escaped or multiline field values. An in-memory exercise of the real import method reproduced the operator default before the repair and passed after it for shared masters and cash, including replay and changed-input refusal. The native integration case could not run because the dedicated Docker socket denied access. These tests do not certify on-site behavior.
