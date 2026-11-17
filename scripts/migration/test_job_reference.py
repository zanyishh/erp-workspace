"""Verified original job labels; no database or source access."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'apps/erp_extensions'))
from erp_extensions.migration import references


class JobReferenceTests(unittest.TestCase):
    def record(self):
        return {'namespace': 'knitpack.job', 'family': 'job', 'native_id': '123', 'source_company_id': '1',
            'business_data': {'original_business': {'original_saved_job': {'id': '123', 'companymas_id': '1'},
                'job_ledger': {'pjobno': '456/26', 'job': {'id': '123', 'companymas_id': '1'}}}}}

    def test_exact_original_label_without_mutation_or_suffix_inference(self):
        record = self.record()
        before = copy.deepcopy(record)
        self.assertEqual(references.verified_job_reference(record), '456/26')
        self.assertEqual(record, before)
        record['business_data']['original_business'].pop('original_saved_job')
        self.assertEqual(references.verified_job_reference(record), '456/26')
        record['business_data']['original_business']['job_ledger'].pop('pjobno')
        self.assertIsNone(references.verified_job_reference(record))

    def test_wrong_header_identity_company_namespace_and_unbounded_label_fail_closed(self):
        for header in ('original_saved_job', 'job_ledger'):
            for key in ('id', 'companymas_id'):
                record = self.record()
                value = record['business_data']['original_business'][header]
                if header == 'job_ledger':value = value['job']
                value[key] = 'other'
                self.assertIsNone(references.verified_job_reference(record))
        for key, value in (('namespace', 'knitpack.production'), ('family', 'production')):
            record = self.record()
            record[key] = value
            self.assertIsNone(references.verified_job_reference(record))
        for label in (None, '', 123, ['456/26'], 'x' * 4097, '456\x00/26'):
            record = self.record()
            record['business_data']['original_business']['job_ledger']['pjobno'] = label
            self.assertIsNone(references.verified_job_reference(record))


if __name__ == '__main__':
    unittest.main()
