"""Synthetic source tax settings only; no site or customer fixtures."""
import importlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps/erp_extensions"))


class ServiceTaxTemplateTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.import_module("erp_extensions.migration.tax_templates")
        self.hsn = {"id": "7", "hsn_type": "service", "hsn": "999999", "status": "1",
                    "percentage": "5.00", "cgst": "2.50", "sgst": "2.50", "igst": "5.00"}
        self.companies = {str(i): {"id": str(i), "country": "India", "gstin": "33ABCDE1234F1Z5"} for i in range(1, 5)}
        self.bindings = {str(i): f"Synthetic company {i}" for i in range(1, 5)}

    def compile(self, **changes):
        return self.module.compile_options(**{"scope": "synthetic", "manifest_sha256": "a" * 64,
            "hsns": [self.hsn], "companies": self.companies, "company_bindings": self.bindings,
            "evidence": [{"file": "synthetic.json", "sha256": "b" * 64}], **changes})

    def test_explicit_service_definition_creates_eight_choices_without_a_default(self):
        result = self.compile()
        self.assertEqual(len(result["companies"]), 4)
        self.assertEqual(sum(len(row["templates"]) for row in result["companies"]), 8)
        for row in result["companies"]:
            self.assertEqual([t["is_default"] for t in row["templates"]], [0, 0])
            self.assertEqual(row["templates"][0]["rates"], {"CGST": "2.50", "SGST": "2.50"})
            self.assertEqual(row["templates"][1]["rates"], {"IGST": "5.00"})
            self.assertTrue(all("999999" in t["title"] for t in row["templates"]))
        self.assertFalse(result["changes_historical_postings"])
        self.assertFalse(result["changes_items"])

    def test_ambiguous_missing_or_conflicting_source_definitions_are_rejected(self):
        for hsns in ([], [self.hsn, dict(self.hsn, id="8")], [dict(self.hsn, percentage="6")],
                     [dict(self.hsn, cgst="NaN")], [dict(self.hsn, status="0")]):
            with self.assertRaises(ValueError):
                self.compile(hsns=hsns)

    def test_exact_four_indian_company_identities_and_gst_are_required(self):
        for field, value in (("id", "99"), ("country", "Other"), ("gstin", "")):
            companies = {k: dict(v) for k, v in self.companies.items()}
            companies["1"][field] = value
            with self.assertRaises(ValueError):
                self.compile(companies=companies)
        with self.assertRaises(ValueError):
            self.compile(company_bindings={**self.bindings, "4": self.bindings["1"]})

    def test_source_placeholder_is_unchanged_and_flagged_without_certifying_registration(self):
        self.companies["2"]["gstin"] = "ORIGINAL-PLACEHOLDER"
        row = self.compile()["companies"][1]
        self.assertEqual(row["source_gstin"], "ORIGINAL-PLACEHOLDER")
        self.assertTrue(row["review_issues"])
        self.assertTrue(all(t["is_default"] == 0 for t in row["templates"]))

    def test_package_proof_detects_a_changed_rate(self):
        result = self.compile()
        self.assertEqual(result["proof_hash"], self.module.proof_hash(result))
        result["companies"][0]["templates"][0]["rates"]["CGST"] = "9"
        self.assertNotEqual(result["proof_hash"], self.module.proof_hash(result))


if __name__ == "__main__":
    unittest.main()
