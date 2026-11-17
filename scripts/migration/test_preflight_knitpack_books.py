"""Synthetic historical-book contract checks; no Frappe/site/customer data."""
import copy
import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("preflight_knitpack_books.py")


class BookPreflightTests(unittest.TestCase):
    def setUp(self):
        self.evidence = {"file": "native.json", "sha256": "a" * 64, "pointer": "/result"}
        self.plan = {"mappings": [self.mapping(c, b) for c, b in [(1, 0), (1, 1), (2, 0), (3, 0), (4, 0)]],
                     "documents": [self.document(0, "10"), self.document(1, "10")], "shared_cash_ownership": []}

    def mapping(self, company, book):
        return {"instance": "synthetic", "company_id": str(company), "book_id": str(book),
                "target_company": f"Company {company}", "finance_book": f"C{company}-B{book}"}

    def identity(self, book=0, record="10"):
        return {"instance": "synthetic", "module": "accv2", "company_id": "1", "book_id": str(book),
                "record_type": "voucher", "native_id": record}

    def document(self, book, record):
        return {"source": self.identity(book, record), "source_date": "2023-04-10", "posting_date": "2023-04-10",
                "source_book_evidence": self.evidence, "target_company": "Company 1", "finance_book": f"C1-B{book}",
                "target_doctype": "Journal Entry", "target_name": f"C1-B{book}-V{record}", "posting_authority": "native_document",
                "account_references": [{"namespace": "ledger", "native_id": "5", "ownership_basis": "native_company", "owner_company_id": "1",
                                        "evidence": self.evidence}], "references": []}

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "The offline book preflight must exist")
        spec = importlib.util.spec_from_file_location("book_preflight", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.audit(self.plan)
        self.assertFalse(result["import_allowed"])
        self.assertFalse(result["balances_verified"])
        return result

    def codes(self):
        return {item["code"] for item in self.audit()["issues"]}

    def test_same_numeric_id_in_two_books_is_two_distinct_native_keys(self):
        result = self.audit()
        self.assertTrue(result["contract_valid"])
        self.assertEqual(result["distinct_document_keys"], 2)

    def test_third_native_book_keeps_its_own_identity_mapping_and_references(self):
        self.plan["mappings"].append(self.mapping(1, 2))
        self.plan["documents"].append(self.document(2, "10"))
        result = self.audit()
        self.assertTrue(result["contract_valid"])
        self.assertEqual(result["distinct_document_keys"], 3)
        self.plan["documents"][-1]["references"] = [{"source": self.identity(0),
            "relation": "against_voucher", "evidence": self.evidence}]
        self.assertIn("reference_cross_company_or_book", self.codes())

    def test_unvalidated_additional_book_is_not_implicitly_accepted(self):
        self.plan["mappings"].append(self.mapping(1, 3))
        self.plan["documents"].append(self.document(3, "10"))
        self.assertTrue({"mapping_incomplete", "source_identity_incomplete"} <= self.codes())

    def test_integer_zero_book_is_preserved_but_missing_book_is_rejected(self):
        self.plan["documents"][0]["source"]["book_id"] = 0
        self.assertTrue(self.audit()["contract_valid"])
        self.plan["documents"][0]["source"].pop("book_id")
        self.assertIn("source_identity_incomplete", self.codes())

    def test_four_companies_cannot_share_a_target_company(self):
        self.plan["mappings"][2]["target_company"] = "Company 1"
        self.assertIn("target_company_shared", self.codes())

    def test_books_cannot_share_finance_book_and_book_cannot_be_blank(self):
        self.plan["mappings"][1]["finance_book"] = "C1-B0"
        self.assertIn("finance_book_shared", self.codes())
        self.plan["mappings"][1]["finance_book"] = ""
        self.assertIn("mapping_incomplete", self.codes())

    def test_original_date_and_native_book_evidence_are_required(self):
        self.plan["documents"][0]["posting_date"] = "2026-11-14"
        self.plan["documents"][0]["source_book_evidence"] = {"basis": "request_echo"}
        self.assertTrue({"original_date_not_preserved", "native_book_evidence_missing"} <= self.codes())

    def test_duplicate_source_or_target_and_direct_gl_authority_are_rejected(self):
        self.plan["documents"].append(copy.deepcopy(self.plan["documents"][0]))
        self.plan["documents"][1]["posting_authority"] = "direct_gl"
        self.assertTrue({"duplicate_source_key", "duplicate_target_key", "posting_authority_unsupported"} <= self.codes())

    def test_cross_book_reference_is_rejected_even_when_native_id_matches(self):
        self.plan["documents"][0]["references"] = [{"source": self.identity(1), "relation": "against_voucher"}]
        self.assertIn("reference_cross_company_or_book", self.codes())

    def test_unknown_target_and_candidate_allocation_cannot_become_saved_edge(self):
        self.plan["documents"][0]["references"] = [{"source": self.identity(0, "99"), "relation": "allocation",
                                                   "evidence_kind": "candidate", "amount": "10"}]
        self.assertTrue({"reference_target_missing", "saved_allocation_evidence_missing"} <= self.codes())

    def test_shared_cash_company_query_echo_does_not_establish_ownership(self):
        self.plan["documents"][0]["account_references"] = [{"namespace": "cash_ledger", "native_id": "3",
                "ownership_basis": "request_echo", "evidence": self.evidence}]
        self.assertIn("account_ownership_unresolved", self.codes())
        self.plan["documents"][0]["account_references"][0]["ownership_basis"] = "approved_shared_cash"
        self.assertIn("shared_cash_ownership_unresolved", self.codes())

    def test_saved_allocation_requires_original_effective_date_and_stable_edge_key(self):
        self.plan["documents"].append(self.document(0, "11"))
        edge = {"source": self.identity(0, "11"), "relation": "allocation", "evidence_kind": "saved_native_edge",
                "native_edge_key": "allocation:7", "effective_date": "2023-04-10", "evidence": self.evidence}
        self.plan["documents"][0]["references"] = [edge]
        self.assertTrue(self.audit()["contract_valid"])
        edge.pop("effective_date")
        self.assertIn("saved_allocation_evidence_missing", self.codes())

    def test_native_account_owner_and_native_reference_evidence_cannot_be_omitted(self):
        self.plan["documents"][0]["account_references"][0]["owner_company_id"] = "2"
        self.plan["documents"].append(self.document(0, "11"))
        self.plan["documents"][0]["references"] = [{"source": self.identity(0, "11"), "relation": "against_voucher"}]
        self.assertTrue({"account_ownership_unresolved", "native_reference_evidence_missing"} <= self.codes())

    def test_current_state_reference_requires_conservation_evidence_not_invented_history(self):
        self.plan["documents"].append(self.document(0, "11"))
        edge = {"source": self.identity(0, "11"), "relation": "allocation", "evidence_kind": "conserved_current_state",
                "evidence": self.evidence, "component_conservation_evidence": self.evidence}
        self.plan["documents"][0]["references"] = [edge]
        self.assertTrue(self.audit()["contract_valid"])
        edge.pop("component_conservation_evidence")
        self.assertIn("saved_allocation_evidence_missing", self.codes())


if __name__ == "__main__":
    unittest.main()
