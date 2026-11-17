"""Synthetic identity-only preparation; never creates destination records."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("prepare_knitpack_masters.py")


class MasterPreparationTests(unittest.TestCase):
    def module(self):
        self.assertTrue(SCRIPT.exists())
        spec = importlib.util.spec_from_file_location("master_preparation", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def observation(self, namespace="masters.party", native_id="7", scope=(), **fields):
        return {"namespace": namespace, "native_id": native_id, "scope": list(scope),
                "kind": "party", "fields": fields or {"party_name": "Synthetic"},
                "evidence": {"file": "master.json", "sha256": "a" * 64, "pointer": "/result"}}

    def test_repeated_generation_is_stable_and_company_use_does_not_split_party(self):
        m = self.module(); row = self.observation()
        uses = [{"namespace": "masters.party", "native_id": "7", "scope": [], "company": c,
                 "role": "accounting_party", "evidence": row["evidence"]} for c in ("1", "2")]
        first = m.build("synthetic", [row, copy.deepcopy(row)], uses)
        self.assertEqual(first, m.build("synthetic", [row], list(reversed(uses))))
        self.assertEqual(len(first["entities"]), 1)
        self.assertEqual(len(first["company_use"]), 2)
        self.assertFalse(first["import_allowed"])
        self.assertEqual(first["entities"][0]["ownership"], "not_inferred_from_use")

    def test_namespaces_and_job_contexts_never_merge_equal_numeric_ids(self):
        m = self.module()
        rows = [self.observation(), self.observation("masters.company"),
                self.observation("knitpack.job_yarn_material", scope=("1", "10")),
                self.observation("knitpack.job_yarn_material", scope=("1", "11"))]
        result = m.build("synthetic", rows, [])
        self.assertEqual(len({r["proposed_registry_key"] for r in result["entities"]}), 4)

    def test_complementary_fields_are_retained_but_conflicting_originals_are_quarantined(self):
        m = self.module(); a = self.observation(status="1"); b = self.observation(created_time="2020-01-02 03:04:05")
        result = m.build("synthetic", [a, b], [])
        self.assertEqual(result["entities"][0]["status"], "prepared_identity_only")
        b["fields"]["status"] = "0"
        self.assertIn("conflicting_source_field_versions", m.build("synthetic", [a, b], [])["entities"][0]["quarantine_reasons"])

    def test_target_collisions_are_detected_instead_of_renaming_originals(self):
        m = self.module()
        with patch.object(m, "target_key", return_value="forced-collision"):
            result = m.build("synthetic", [self.observation(native_id="7"), self.observation(native_id="8")], [])
        self.assertEqual(sum("target_key_collision" in r["quarantine_reasons"] for r in result["entities"]), 2)

    def test_original_zero_date_remains_hashed_source_evidence_not_a_target_date(self):
        m = self.module(); row = self.observation(created_time="0000-00-00"); before = copy.deepcopy(row)
        entity = m.build("synthetic", [row], [])["entities"][0]
        self.assertEqual(row, before)
        evidence = entity["original_date_evidence"][0]
        self.assertEqual(evidence["pointer"], "/result/created_time")
        self.assertEqual(evidence["value_sha256"], hashlib.sha256(b'"0000-00-00"').hexdigest())
        self.assertNotIn("posting_date", entity)

    def test_audit_actor_ids_are_preserved_but_not_classified_as_dates(self):
        m = self.module()
        row = self.observation(updated_by="17", created_by="18", jobdate="0000-00-00",
                               created_time="2020-01-02 03:04:05", updated_at="2020-02-03T04:05:06")
        entity = m.build("synthetic", [row], [])["entities"][0]
        self.assertEqual({r['field'] for r in entity['original_date_evidence']}, {'jobdate', 'created_time', 'updated_at'})
        self.assertIn('updated_by', entity['field_evidence'])
        self.assertIn('created_by', entity['field_evidence'])

    def test_unresolved_ownership_and_contextual_items_stay_nonposting(self):
        m = self.module(); row = self.observation("masters.godown"); row["quarantine_reasons"] = ["shared_owner_unresolved"]
        result = m.build("synthetic", [row], [])
        self.assertEqual(result["entities"][0]["status"], "quarantined")
        self.assertIsNone(result["entities"][0]["target_item_equivalence"])

    def test_unknown_company_use_is_rejected_and_missing_master_is_explicit(self):
        m = self.module(); row = self.observation()
        uses = [{"namespace": "masters.party", "native_id": "8", "scope": [], "company": "1",
                 "role": "accounting_party", "evidence": row["evidence"]},
                {"namespace": "masters.party", "native_id": "7", "scope": [], "company": "9",
                 "role": "accounting_party", "evidence": row["evidence"]}]
        result = m.build("synthetic", [row], uses)
        self.assertEqual({r["code"] for r in result["issues"]}, {"use_master_missing", "use_company_unknown"})

    def test_missing_identity_or_unbound_source_evidence_cannot_prepare_a_record(self):
        m = self.module(); a = self.observation(native_id=None); b = self.observation()
        b['evidence']['sha256'] = 'not-a-hash'
        result = m.build('synthetic', [a, b], [])
        self.assertEqual(result['entities'], [])
        self.assertEqual({r['code'] for r in result['issues']}, {'source_identity_invalid', 'source_evidence_invalid'})


if __name__ == "__main__":
    unittest.main()
