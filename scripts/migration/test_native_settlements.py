"""Synthetic component proof rules; no sites or customer fixtures."""
import importlib.util
from pathlib import Path
import unittest


class NativeSettlementProofTests(unittest.TestCase):
    def setUp(self):
        p = Path(__file__).resolve().parents[2] / "apps/erp_extensions/erp_extensions/migration/settlements.py"
        self.assertTrue(p.exists(), "Native settlement bridge is not implemented")
        spec = importlib.util.spec_from_file_location("native_settlements", p)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.nodes = {"sale": {"company": "Company", "source_book": "1", "finance_book": "Book1", "accounting_party_id": "7",
            "amount": "100", "adjusted": "60", "entry_type": "debit", "party_type": "Customer", "party_account": "AR"},
            "receipt": {"company": "Company", "source_book": "1", "finance_book": "Book1", "accounting_party_id": "7",
            "amount": "60", "adjusted": "60", "entry_type": "credit", "party_type": "Customer", "party_account": "AR"}}
        self.edges = [{"first": "sale", "second": "receipt", "amount": "60"}]

    def test_exact_component_can_apply_without_changing_amounts(self):
        plan = self.module.validate_component(self.nodes, self.edges)
        self.assertEqual(plan["same_account_edges"], 1)
        self.assertEqual(plan["cross_role_edges"], 0)

    def test_partial_or_overallocated_component_is_rejected(self):
        for amount in ("59", "61"):
            self.edges[0]["amount"] = amount
            with self.assertRaises(ValueError): self.module.validate_component(self.nodes, self.edges)

    def test_cross_company_book_party_or_direction_is_rejected(self):
        for field, value in (("company", "Other"), ("source_book", "2"), ("accounting_party_id", "8"), ("entry_type", "debit")):
            old = self.nodes["receipt"][field]
            self.nodes["receipt"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.module.validate_component(self.nodes, self.edges)
            self.nodes["receipt"][field] = old

    def test_cross_role_is_explicit_current_offset_not_same_account_allocation(self):
        self.nodes["receipt"].update(party_type="Supplier", party_account="AP")
        plan = self.module.validate_component(self.nodes, self.edges)
        self.assertEqual(plan["cross_role_edges"], 1)

    def test_duplicate_or_self_edge_is_rejected(self):
        with self.assertRaises(ValueError): self.module.validate_component(self.nodes, self.edges * 2)
        self.edges[0]["second"] = "sale"
        with self.assertRaises(ValueError): self.module.validate_component(self.nodes, self.edges)

