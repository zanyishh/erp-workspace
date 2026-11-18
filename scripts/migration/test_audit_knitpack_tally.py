"""Synthetic Tally-text evidence checks, including ambiguity and hostile XML."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("audit_knitpack_tally.py")


class TallyAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.text = "\nPRIVATE-PARTY;REF-10;2023-04-02;118.00;100.00;9.00;9.00;0.00;"
        self.add("voucher", "{URI}accv2/getprint/getdata/acc_entry/voucher_print/{PASS}", {"root": {
            "voucher": {"id": "10", "companymas_id": "1", "sec_acc": "0", "party_id": "8", "ref_no": "REF-10",
                        "v_date": "2023-04-02", "finyear": "1", "acc_type": "sales", "amt": "118.00", "taxable_value": "100.00",
                        "cgst_value": "9.00", "sgst_value": "9.00", "igst_value": "0.00"},
            "party": {"id": "8", "party_name": "PRIVATE-PARTY"}}})

    def add(self, name, route, payload, filters=None):
        raw = json.dumps({**payload, "currentUserinfo": {"token": "PRIVATE-TOKEN"}}).encode()
        (self.folder / (name + ".json")).write_bytes(raw)
        with (self.folder / "manifest.jsonl").open("a") as stream:
            stream.write(json.dumps({"path": route, "file": name + ".json", "filters": filters,
                                     "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}) + "\n")

    def export(self, text=None, company="1"):
        self.add("tally-export-all-years", "knitpack/reports/tallyExport", {"result": {"tally_txt": self.text if text is None else text}},
                 {"companymas_id": company, "from_date": "2000-01-01", "to_date": "2100-12-31"})

    def audit(self):
        self.assertTrue(SCRIPT.exists(), "The offline Tally evidence auditor must exist")
        spec = importlib.util.spec_from_file_location("tally_audit", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result, texts = module.audit(self.folder)
        encoded = json.dumps(result)
        self.assertNotIn("PRIVATE-PARTY", encoded)
        self.assertNotIn("PRIVATE-TOKEN", encoded)
        self.assertFalse(result["import_allowed"])
        return result, texts

    def test_exact_text_hash_and_tuple_match_preserve_original_date_and_unknown_scope(self):
        self.export()
        result, texts = self.audit()
        export = result["exports"][0]
        self.assertEqual(texts[export["derived_file"]], self.text.encode())
        self.assertEqual(export["derived_sha256"], hashlib.sha256(self.text.encode()).hexdigest())
        self.assertEqual(export["nonblank_records"], 1)
        self.assertEqual(export["original_dates"]["min"], "2023-04-02")
        self.assertEqual(export["exact_corroboration"]["unique_native_key_rows"], 1)
        self.assertEqual(export["exact_corroboration"]["matched_books"], ["0"])
        self.assertEqual(export["book_scope"], "not_declared_in_export")
        self.assertEqual(export["explicit_ledger_leg_records"], 0)

    def test_equal_tuple_in_two_books_is_ambiguous_not_a_deduplication_rule(self):
        self.add("secondbook", "native/voucher", {"root": {"voucher": {
            "id": "11", "companymas_id": "1", "sec_acc": "1", "party_id": "8", "ref_no": "REF-10", "v_date": "2023-04-02",
            "amt": "118", "taxable_value": "100", "cgst_value": "9", "sgst_value": "9", "igst_value": "0"},
            "party": {"id": "8", "party_name": "PRIVATE-PARTY"}}})
        self.export()
        result, _ = self.audit()
        match = result["exports"][0]["exact_corroboration"]
        self.assertEqual(match["ambiguous_native_key_rows"], 1)
        self.assertEqual(match["unique_native_key_rows"], 0)

    def test_date_reference_and_amount_must_all_match_exactly(self):
        self.export(self.text.replace("2023-04-02", "2023-04-03"))
        result, _ = self.audit()
        self.assertEqual(result["exports"][0]["exact_corroboration"]["unmatched_rows"], 1)

    def test_delimiter_in_name_is_an_invalid_record_not_silently_joined(self):
        self.export(self.text.replace("PRIVATE-PARTY", "PRIVATE;PARTY"))
        result, _ = self.audit()
        self.assertEqual(result["exports"][0]["invalid_record_rows"], 1)

    def test_empty_export_does_not_prove_empty_company(self):
        self.export("", company="4")
        result, texts = self.audit()
        export = result["exports"][0]
        self.assertEqual(export["format"], "empty_text")
        self.assertFalse(export["complete"])
        self.assertEqual(texts[export["derived_file"]], b"")

    def test_xml_entity_declarations_are_rejected_without_expansion(self):
        self.export('<!DOCTYPE x [<!ENTITY e SYSTEM "file:///private/secret">]><x>&e;</x>')
        result, _ = self.audit()
        self.assertEqual(result["exports"][0]["format"], "xml_rejected_declaration")
        self.assertFalse(result["exports"][0]["parsed"])

    def test_plain_xml_counts_voucher_and_leg_elements_without_posting(self):
        self.export('<ENVELOPE><VOUCHER><ALLLEDGERENTRIES.LIST/><LEDGERENTRIES.LIST/></VOUCHER></ENVELOPE>')
        result, _ = self.audit()
        export = result["exports"][0]
        self.assertEqual(export["xml_voucher_elements"], 1)
        self.assertEqual(export["explicit_ledger_leg_records"], 2)


if __name__ == "__main__":
    unittest.main()
