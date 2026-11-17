# Native financial migration

The financial authority is one submitted ERPNext Journal Entry for each nonzero, uncancelled native `accv2.voucher` or `accv2.opening`. Original invoice records remain immutable, nonposting source copies. The compiler rejects other namespaces even when they contain financial fields.

Amounts use exact decimal strings through compilation and verification. Original business dates remain unchanged. Only originally undated opening records use the scope's explicitly approved effective date. Each company and source book has one immutable Finance Book binding. A new document in a bound company defaults to source book 0; references inherit their book, and cross-book references are rejected.

Original invoice customer and native accounting party remain separate identities. A knitting invoice uses the job's explicit billing customer and Finance Book when supplied. The original material customer remains unchanged.

## Mapping and controls

`prepare_financial_authority.py` reads the frozen private header, invoice, master and reconciliation artifacts. It produces financial enrichment, required supplier identities, explicit account keys, and the conserved settlement application plan. With `--target-bindings`, `--account-bindings` and `--scope`, it streams the finalized history package through the real normalization and posting compiler and writes an account-bound dry run.

Single-role source parties retain that role. Dual-role purchases, payments and debit notes use Supplier; sales, receipts, TDS receipts and credit notes use Customer. Ambiguous dual-role openings and adjustments use the approved Customer/Receivable policy. Source controls compare the combined Customer and Supplier net for the original party, company and book.

Counterparts use explicitly named legacy control accounts. A source category with a declared expense or income classification retains it; an unclassified category remains a control account. Gross sales controls preserve the source amount without claiming a reconstructed statutory tax split. Original invoice tax fields remain in the immutable invoice. New native invoices use normal ERPNext accounting and taxes.

Source cash selectors describe shared categories. They do not establish bank or cash GL legs. Shared category openings and supplied debit/credit movements are preserved once, separately from company GL. Only independently corroborated source cash-register rows enter those shared controls.

The annual source reports project voucher amounts to whole units using an independently observed HALF_EVEN relationship. The private controls retain exact original amounts, exact report projections and every difference. No amount correction or rounding journal is created to imitate that display basis.

## Native execution

- `finance.configure_books(scope, bindings)` installs the twelve explicit company/book bindings.
- `finance.post_record(record_name, mapping)` compiles, submits through the native Journal Entry controller, verifies GL and party-ledger ownership and amounts, and binds one immutable financial authority in the same transaction. Retrying verifies the existing authority.
- `settlements.apply_component(scope, component_id, bindings, edges, graph_sha256)` accepts only complete, conserved current-state components. Each original adjusted amount must equal its incident saved edges. It uses native reconciliation for same-account references and current-dated native offset journals for proved Customer/Supplier offsets. Original posting dates and amounts remain unchanged. The binding records the actual application timestamp, not a claimed historical allocation date.
- `finance.verify_party_controls(scope, controls)` checks the complete authority count and exact native GL net for every source company/party/book group. Cross-role offsets have zero combined source-party effect.

Unresolved settlement evidence remains visible and unallocated. Native future Payment Entries can reference the historical Journal Entries; the account and book remain those of the referenced authority. Native GL and payment-ledger rows are never inserted or repaired directly by this extension.

Binding records require explicit scope membership, company access and financial administration permission. Their internal writes use context-local authorization rather than client document flags. Site execution and testing are separate: the native tests contain synthetic fixtures and refuse any site except `native-test.localhost`.
