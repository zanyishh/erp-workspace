import copy
from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'apps/erp_extensions'))
from erp_extensions.migration import contracts
from history_correction import validate_repair,apply_overlay


class CorrectionTests(unittest.TestCase):
    def fixture(self):
        scope=contracts.normalize_scope({'source_instance':'synthetic','company_bindings':{str(i):f'Company {i}' for i in range(1,5)},
            'allowed_users':['fixture@example.invalid'],'opening_effective_date':'2023-04-01','manifest_sha256':'a'*64,'policy_evidence_sha256':'b'*64})
        values={'namespace':'knitpack.job','native_id':'1857','source_company_id':'1','source_book':'0','family':'job',
            'original_date_raw':'2026-11-04','business_data':{'fields':{'job_reference':'Original 4'},'original_business':{'yarn_context':None,'job':{'id':'1857'}}},
            'provenance':[{'file':'actual.json','sha256':'a'*64,'pointer':'/job'}, {'file':'job-yarn-context-1857.json','sha256':'b'*64,'pointer':'/result'}]}
        old=contracts.normalize_record(scope,values);new=copy.deepcopy(old)
        del new['business_data']['original_business']['yarn_context'];new['provenance']=new['provenance'][:1]
        new['data_sha256']=contracts.sha({k:v for k,v in new.items() if k!='data_sha256'})
        return scope,values,{'old_normalized_record':old,'new_normalized_record':new,
            'expected_old_data_sha256':old['data_sha256'],'new_data_sha256':new['data_sha256']}

    def test_only_unavailable_null_context_and_reference_are_removed(self):
        scope,values,r=self.fixture();self.assertEqual(validate_repair(r),r['new_normalized_record'])
        corrected,result=apply_overlay(scope,values,{r['old_normalized_record']['source_key']:r})
        self.assertEqual(result,r['new_normalized_record']);self.assertEqual(corrected['original_date_raw'],values['original_date_raw'])
        self.assertIn('yarn_context',values['business_data']['original_business'])

    def test_a_business_change_cannot_hide_in_metadata_repair(self):
        _,_,r=self.fixture();new=r['new_normalized_record'];new['original_date_raw']='2026-11-05'
        new['data_sha256']=contracts.sha({k:v for k,v in new.items() if k!='data_sha256'});r['new_data_sha256']=new['data_sha256']
        with self.assertRaises(ValueError):validate_repair(r)


if __name__=='__main__':unittest.main()
