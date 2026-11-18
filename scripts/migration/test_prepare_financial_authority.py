import unittest
from prepare_financial_authority import financial_record, compare_party_controls, party_role, mapping_plan, settlement_plan


class FinancialAuthorityPreparationTests(unittest.TestCase):
    def header(self, **updates):
        return {"id": "9", "companymas_id": "1", "sec_acc": "2", "acc_type": "sales", "party_id": "7",
                "amt": "12.50", "entry_type": "debit", "v_date": "2024-04-03", "v_no": "0009", "cancelled": "0", **updates}

    def test_explicit_invoice_link_preserves_accounting_and_original_parties(self):
        h = self.header(acc_ref_type="kpinvoice", acc_ref_code="8")
        link = {"voucher_key": ["1", "9", "2"], "invoice_key": ["regular", "1", "8", "2"],
                "original_invoice_party_id": "6", "original_invoice_value": "13", "original_r_invoice_value": "12.50"}
        r = financial_record(h, link)
        self.assertEqual(r["financial"]["amount"], "12.50")
        self.assertEqual(r["financial"]["accounting_party_id"], "7")
        self.assertEqual(r["financial"]["invoice_party_id"], "6")
        self.assertEqual(r["namespace"], "accv2.voucher")

    def test_sales_missing_or_cross_company_invoice_link_is_rejected(self):
        h = self.header(acc_ref_type="kpinvoice", acc_ref_code="8")
        with self.assertRaises(ValueError): financial_record(h, None)
        link = {"voucher_key": ["2", "9", "2"], "invoice_key": ["regular", "2", "8", "2"]}
        with self.assertRaises(ValueError): financial_record(h, link)

    def test_legacy_projection_is_separate_from_exact_posting_amount(self):
        headers = [self.header(), self.header(id="10", acc_type="opening-balance", amt="1.25", v_date="0000-00-00")]
        controls = [{"kind": "party", "source_company_id": "1", "source_ledger_id": "7", "requested_book": "2",
            "from_date": "2024-04-01", "to_date": "2025-03-31", "opening_net": "1.25", "closing_net": "13.25", "path": "synthetic"}]
        result = compare_party_controls(headers, controls, "2023-04-01")
        closing = result["partitions"][0]["comparisons"]["closing"]
        self.assertEqual(closing["native_signed_amount"], "13.75")
        self.assertEqual(closing["legacy_projection"], "13.25")
        self.assertTrue(closing["projection_equal"])
        self.assertFalse(closing["native_equal"])

    def test_missing_control_stays_unknown(self):
        control = {"kind": "party", "source_company_id": "1", "source_ledger_id": "7", "requested_book": "2",
            "from_date": "2024-04-01", "to_date": "2025-03-31", "opening_net": None, "closing_net": "12", "path": "synthetic"}
        result = compare_party_controls([self.header()], [control], "2023-04-01")
        self.assertIsNone(result["partitions"][0]["comparisons"]["opening"]["projection_equal"])

    def test_unified_party_policy_retains_single_roles_and_explicit_dual_opening_basis(self):
        self.assertEqual(party_role("supplier", "receipt")[0], "Supplier")
        self.assertEqual(party_role("party", "debitnote")[0], "Customer")
        self.assertEqual(party_role("party,supplier", "purchase")[0], "Supplier")
        self.assertEqual(party_role("party,subcontractor", "payment")[0], "Supplier")
        self.assertEqual(party_role("party,supplier", "opening-balance"), ("Customer", "approved_unified_party_fallback"))

    def test_mapping_keeps_cash_pool_separate_and_source_party_explicit(self):
        h = self.header(acc_type="payment", cash_ledger="3", acc_code1="1")
        r = financial_record(h)
        plan = mapping_plan([r], {"7": {"customer_type": "party,supplier"}}, [{"id": "1", "ledger_name": "Source expense", "ledger_type": "Expenses"}], [{"id": "3", "ledger_name": "Shared pool"}])
        p = plan["postings"][0]
        self.assertEqual(p["mapping"]["party"], "KP-SUPPLIER-7")
        self.assertEqual(p["mapping"]["counter_basis"], "native_general_account")
        self.assertEqual(p["counter_account_key"], "general:1")
        self.assertEqual(p["source_cash_category_id"], "3")
        self.assertEqual(plan["required_supplier_ids"], ["7"])
        self.assertFalse(plan["shared_cash_opening_in_company_gl"])

    def test_settlement_plan_excludes_unresolved_components(self):
        records = [financial_record(self.header(acc_type="debitadj", acc_code1="1", adj_val="12.50")),
                   financial_record(self.header(id="10", acc_type="receipt", acc_code1="1", adj_val="12.50", entry_type="credit"))]
        plan = mapping_plan(records, {"7": {"customer_type": "party"}}, [{"id": "1", "ledger_type": "Expenses"}], [])
        graph = {"integrity_issues": [], "components": [{"status": "conserved_current_state", "nodes": [["1", "9", "2"], ["1", "10", "2"]], "edge_indices": [0]},
            {"status": "unresolved", "nodes": [], "edge_indices": [1]}], "edges": [
            {"status": "conserved_current_state", "first": ["1", "9", "2"], "second": ["1", "10", "2"], "amount": "12.50"},
            {"status": "unresolved", "first": ["1", "9", "2"], "second": ["1", "10", "2"], "amount": "99"}]}
        result = settlement_plan(graph, plan, records)
        self.assertEqual(result["counts"], {"components": 1, "edges": 1, "same_account_edges": 1, "cross_role_edges": 0})

