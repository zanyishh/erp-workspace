"""Synthetic offline checks for saved history rows in a MariaDB text dump."""
import gzip
import json
from pathlib import Path
import tempfile
import unittest

from verify_knitpack_preservation import contracts, verify_dump


def sql_literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return str(int(value))
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"


class BackupHistoryTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.path = Path(scratch.name) / "fixture.sql.gz"
        self.scope = "scope-synthetic"
        self.record = dict(source_key="synthetic", company=None, source_company_id=None, source_book=None,
                           namespace="demo.master", native_id="19", family="master", original_reference="NULL",
                           original_date_raw=None, effective_date=None, date_basis="not_applicable",
                           shared_cash=False, shared_reference=True, title="Shared master",
                           summary="Owner's lot, size 2\nRack \\ A", business_data={"quantity": 2})
        self.checksum = contracts.sha(self.record)

    def write_dump(self, records, **overrides):
        columns = ["name", "source_scope", *[k for k in self.record if k != "business_data"], "record_data", "data_sha256"]
        table = "`tabHistorical Business Record`"
        with gzip.open(self.path, "wt", encoding="utf-8") as output:
            output.write(f"CREATE TABLE {table} (\n" + ",\n".join(f" `{key}` text" for key in columns) + "\n);\n")
            if records:
                output.write(f"INSERT INTO {table} VALUES\n")
            for index, record in enumerate(records):
                payload = {**record, "data_sha256": self.checksum}
                row = {**payload, "record_data": json.dumps(payload), "name": "history-synthetic",
                       "source_scope": self.scope, **overrides}
                output.write("(" + ",".join(sql_literal(row[k]) for k in columns) + ")"
                             + (";\n" if index + 1 == len(records) else ",\n"))

    def verify(self):
        return verify_dump(self.path, {"synthetic": self.checksum}, self.scope)

    def test_saved_business_values_are_rehashed_and_matched_to_package(self):
        self.write_dump([self.record])
        result = self.verify()
        self.assertEqual(result["matching_payloads"], 1)
        self.assertEqual(result["rows_with_projection_mismatches"], 0)
        with self.assertRaisesRegex(ValueError, "differs"):
            verify_dump(self.path, {"synthetic": "0" * 64}, self.scope)

    def test_changed_missing_and_repeated_backup_rows_fail(self):
        for rows in ([{**self.record, "business_data": {}}], [], [self.record, self.record]):
            with self.subTest(row_count=len(rows)):
                self.write_dump(rows)
                with self.assertRaises(ValueError):
                    self.verify()

    def test_register_columns_can_disagree_with_an_intact_payload(self):
        for column, changed in {"company": "Default Co", "original_reference": None,
                                "source_scope": "other-scope", "name": "unrelated"}.items():
            with self.subTest(column=column):
                self.write_dump([self.record], **{column: changed})
                result = self.verify()
                self.assertEqual(result["matching_payloads"], 1)
                self.assertEqual(result["rows_with_projection_mismatches"], 1)
                self.assertEqual(result["mismatches_by_field"], {column: 1})
                self.assertEqual(result["mismatched_rows_by_family"], {"master": 1})
