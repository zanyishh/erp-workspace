import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import import_knitpack_history as importer


class HistoryImportPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.scope=importer.contracts.normalize_scope({'source_instance':'synthetic','company_bindings':{str(i):f'Company {i}' for i in range(1,5)},
            'allowed_users':['test@example.invalid'],'opening_effective_date':'2023-04-01','physical_posting_mode':'closing_initialization',
            'manifest_sha256':'a'*64,'policy_evidence_sha256':'b'*64})
        self.source=self.root/'original.json';self.source.write_text('{"result":{"id":"7"}}')
        self.hash=hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.manifests={('original.json',self.hash):{'path':self.source,'bytes':self.source.stat().st_size}}
        self.row={'namespace':'masters.company','source_company_id':'1','source_book':None,'native_id':'1','family':'master','original_date_raw':None,
            'business_data':{'fields':{'description':'Synthetic company'}},'provenance':[{'file':'original.json','sha256':self.hash,'pointer':'/result'}]}

    def file(self,name,rows,supplement=False):
        path=self.root/name;path.write_text(''.join(json.dumps(r)+'\n' for r in rows))
        return {'path':path,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'supplement':supplement}

    def test_additive_master_supplement_is_stable_and_does_not_change_inputs(self):
        supplement={**self.row,'namespace':'masters.party','source_company_id':None,'native_id':'7','shared_reference':True}
        inputs=[self.file('base.jsonl',[self.row]),self.file('supplement.jsonl',[supplement],True)]
        first=importer.preflight(self.scope,inputs,self.manifests,{})
        self.assertEqual(first['records'],2);self.assertEqual(first['supplement_records'],1)
        self.assertEqual(first,importer.preflight(self.scope,inputs,self.manifests,{}))
        for entry in inputs:self.assertEqual(hashlib.sha256(entry['path'].read_bytes()).hexdigest(),entry['sha256'])

    def test_same_native_identity_cannot_be_replaced_by_supplement(self):
        inputs=[self.file('base.jsonl',[self.row]),self.file('supplement.jsonl',[self.row],True)]
        with self.assertRaisesRegex(ValueError,'Duplicate source identity'):importer.preflight(self.scope,inputs,self.manifests,{})

    def test_missing_pointer_failed_envelope_and_changed_hash_fail_closed(self):
        for payload,pointer in [('{"result":{}}','/absent'),('{"rc_error":true,"result":{}}','/result')]:
            with self.subTest(payload=payload):
                self.source.write_text(payload);digest=hashlib.sha256(self.source.read_bytes()).hexdigest()
                row=copy.deepcopy(self.row);row['provenance'][0].update(sha256=digest,pointer=pointer)
                with self.assertRaises(ValueError):importer.preflight(self.scope,[self.file('base.jsonl',[row])],{('original.json',digest):{'path':self.source,'bytes':len(payload)}},{})
        inputs=[self.file('base.jsonl',[self.row])];inputs[0]['path'].write_text('{}\n')
        with self.assertRaisesRegex(ValueError,'input hash'):importer.preflight(self.scope,inputs,self.manifests,{})

    def test_array_root_evidence_is_resolved_as_an_actual_json_pointer(self):
        self.source.write_text('[{"id":"7"}]');digest=hashlib.sha256(self.source.read_bytes()).hexdigest()
        row=copy.deepcopy(self.row);row['provenance'][0].update(sha256=digest,pointer='/0/id')
        result=importer.preflight(self.scope,[self.file('base.jsonl',[row])],{('original.json',digest):{'path':self.source,'bytes':self.source.stat().st_size}},{})
        self.assertEqual(result['verified_original_files'],1)

