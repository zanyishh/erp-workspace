"""Synthetic financial authority cases; never load customer archives or a site."""
import copy
import importlib.util
from pathlib import Path
import unittest


MODULE = Path(__file__).resolve().parents[2] / "apps/erp_extensions/erp_extensions/migration/finance.py"


class FinanceBridgeTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), "The native financial compiler is not implemented")
        spec = importlib.util.spec_from_file_location("migration_finance", MODULE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.record = {"name": "source-record", "source_key": "source-key", "source_scope": "scope",
            "source_company_id": "1", "source_book": "0", "native_id": "9", "namespace": "accv2.voucher", "family": "voucher",
            "company": "Synthetic Company", "original_date_raw": "2023-07-03", "effective_date": "2023-07-03",
            "date_basis": "original", "business_data": {"financial": {"amount": "123.45", "currency": "INR",
                "entry_type": "debit", "voucher_type": "sales", "accounting_party_id": "7", "invoice_party_id": "8",
                "source_reference": "0009", "invoice_namespace": "kpinvoice", "invoice_native_id": "4",
                "original_invoice_value": "123", "original_r_invoice_value": "123.45", "cancelled": False}}}
        self.mapping = {"company": "Synthetic Company", "source_company_id": "1", "source_book": "0",
            "finance_book": "Synthetic Company Book 0", "currency": "INR", "party_type": "Customer",
            "party": "Billing Customer", "accounting_party_id": "7", "party_account": "Receivable",
            "counter_account": "Historical Sales", "counter_basis": "native_document_type", "cost_center": "Main"}

    def compile(self, **kwargs):
        return self.module.build_journal_spec(self.record, self.mapping, **kwargs)

    def test_exact_posted_amount_and_both_party_roles_survive(self):
        before = copy.deepcopy(self.record)
        result = self.compile()
        self.assertEqual(result["journal"]["accounts"][0]["debit_in_account_currency"], "123.45")
        self.assertEqual(result["journal"]["accounts"][1]["credit_in_account_currency"], "123.45")
        self.assertEqual(result["journal"]["finance_book"], "Synthetic Company Book 0")
        self.assertEqual(result["source_parties"], {"accounting_party_id": "7", "invoice_party_id": "8"})
        self.assertEqual(result["journal"]["posting_date"], "2023-07-03")
        self.assertEqual(self.record, before)

    def test_blank_or_wrong_company_book_mapping_is_rejected(self):
        for field, value in (("finance_book", ""), ("source_book", "1"), ("company", "Other Company"), ("source_company_id", "2")):
            with self.subTest(field=field):
                original = self.mapping[field]
                self.mapping[field] = value
                with self.assertRaises(ValueError):
                    self.compile()
                self.mapping[field] = original

    def test_invoice_customer_cannot_replace_posted_bill_to(self):
        self.mapping["accounting_party_id"] = "8"
        with self.assertRaises(ValueError):
            self.compile()

    def test_approved_opening_date_retains_original_invalid_date(self):
        self.record.update(original_date_raw="0000-00-00", effective_date="2023-04-01", date_basis="approved_opening",
                           namespace="accv2.opening", family="opening")
        self.record["business_data"]["financial"]["voucher_type"] = "opening-balance"
        self.mapping["counter_basis"] = "approved_opening_equity"
        self.mapping["counter_account"] = "Temporary Opening"
        with self.assertRaises(ValueError):
            self.compile()
        result = self.compile(approved_opening_date="2023-04-01")
        self.assertEqual(result["journal"]["is_opening"], "Yes")
        self.assertEqual(result["journal"]["posting_date"], "2023-04-01")
        self.assertEqual(result["original_date_raw"], "0000-00-00")

    def test_ordinary_document_date_is_never_rewritten(self):
        self.record["effective_date"] = "2023-04-01"
        with self.assertRaises(ValueError):
            self.compile(approved_opening_date="2023-04-01")

    def test_original_invoice_cannot_become_a_second_posting_authority(self):
        for namespace, family in (("knitpack.invoice", "invoice"), ("accv2.voucher", "invoice"), ("unknown", "voucher")):
            self.record.update(namespace=namespace, family=family)
            with self.subTest(namespace=namespace, family=family), self.assertRaises(ValueError):
                self.compile()

    def test_zero_and_cancelled_native_records_do_not_fabricate_journals(self):
        self.record["business_data"]["financial"]["amount"] = "0"
        self.assertFalse(self.compile()["posting_required"])
        self.record["business_data"]["financial"].update(amount="123.45", cancelled=True)
        self.assertFalse(self.compile()["posting_required"])

    def test_source_credit_posts_supplier_payable_without_changing_sign(self):
        f = self.record["business_data"]["financial"]
        f.update(voucher_type="purchase", entry_type="credit", general_ledger_id="4")
        self.mapping.update(party_type="Supplier", party="Supplier", party_account="Payable",
                            counter_account="Historical Purchase", counter_basis="native_general_account", general_ledger_id="4")
        result = self.compile()
        self.assertEqual(result["journal"]["accounts"][0]["credit_in_account_currency"], "123.45")
        self.assertEqual(result["journal"]["accounts"][1]["debit_in_account_currency"], "123.45")

    def test_missing_amount_and_unrepresentable_precision_are_rejected(self):
        for value in (None, "", "NaN", "-1", "1.001"):
            self.record["business_data"]["financial"]["amount"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.compile()

    def test_shared_cash_reference_requires_the_approved_shared_policy(self):
        f = self.record["business_data"]["financial"]
        f.update(voucher_type="receipt", entry_type="credit", cash_ledger_id="3")
        self.mapping.update(counter_basis="native_cashbook_movement", counter_account="Shared Cash Movements", cash_ledger_id="3")
        with self.assertRaises(ValueError):
            self.compile()
        self.assertTrue(self.compile(shared_cash_approved=True)["posting_required"])

    def test_cash_category_selector_does_not_override_native_general_account(self):
        self.record["business_data"]["financial"].update(voucher_type="receipt", entry_type="credit", cash_ledger_id="3", general_ledger_id="1")
        self.mapping.update(counter_basis="native_general_account", general_ledger_id="1", counter_account="Legacy General")
        self.assertEqual(self.compile()["journal"]["accounts"][1]["account"], "Legacy General")

    def test_counter_components_must_equal_native_amount_exactly(self):
        self.mapping["counter_components"] = [{"account": "Income", "amount": "100"}, {"account": "Tax", "amount": "23.45"}]
        self.assertEqual(len(self.compile()["journal"]["accounts"]), 3)
        self.mapping["counter_components"][1]["amount"] = "23.44"
        with self.assertRaises(ValueError):
            self.compile()

    def test_bound_company_defaults_to_primary_book_and_inherits_reference(self):
        bindings = [{"source_book": str(i), "finance_book": f"Book {i}"} for i in range(3)]
        self.assertEqual(self.module.resolve_book(None, bindings, []), "Book 0")
        self.assertEqual(self.module.resolve_book(None, bindings, ["Book 2"]), "Book 2")
        self.assertEqual(self.module.resolve_book("Book 1", bindings, []), "Book 1")

    def test_mixed_or_unmapped_book_reference_is_rejected(self):
        bindings = [{"source_book": str(i), "finance_book": f"Book {i}"} for i in range(3)]
        for selected, refs in [("Book 0", ["Book 1"]), (None, ["Book 0", "Book 2"]), (None, [None]), ("Other", [])]:
            with self.subTest(selected=selected, refs=refs), self.assertRaises(ValueError):
                self.module.resolve_book(selected, bindings, refs)

    def test_ordinary_company_has_no_new_default_or_restriction(self):
        self.assertEqual(self.module.resolve_book("Existing book", [], []), "Existing book")
        self.assertIsNone(self.module.resolve_book(None, [], []))


if __name__ == "__main__":
    unittest.main()
