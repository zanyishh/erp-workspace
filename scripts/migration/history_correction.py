"""A reviewed null-context provenance correction; original business facts stay fixed."""
import copy
from erp_extensions.migration import contracts


def validate_repair(repair):
    old=repair['old_normalized_record'];new=repair['new_normalized_record']
    if old['namespace']!='knitpack.job' or old['native_id']!='1857' or old['source_company_id']!='1':
        raise ValueError('This narrowly reviewed correction does not cover another original.')
    for record,key in ((old,'expected_old_data_sha256'),(new,'new_data_sha256')):
        clean={k:v for k,v in record.items() if k!='data_sha256'}
        if contracts.sha(clean)!=record['data_sha256'] or record['data_sha256']!=repair[key]:
            raise ValueError('The correction evidence hash changed.')
    expected=copy.deepcopy(old)
    original=expected['business_data']['original_business']
    if original.get('yarn_context','not present') is not None:raise ValueError('A real source context must never be removed.')
    del original['yarn_context']
    removed=[r for r in expected['provenance'] if r['file']=='job-yarn-context-1857.json' and r['pointer']=='/result']
    if len(removed)!=1:raise ValueError('Only the one unavailable context reference may be corrected.')
    expected['provenance']=[r for r in expected['provenance'] if r not in removed]
    expected['data_sha256']=new['data_sha256']
    if expected!=new:raise ValueError('The proposed correction alters actual original business facts.')
    return new


def apply_overlay(scope,values,repairs):
    old=contracts.normalize_record(scope,values)
    repair=repairs.get(old['source_key'])
    if not repair:return values,old
    new=validate_repair(repair)
    if old['data_sha256']!=repair['expected_old_data_sha256']:raise ValueError('The frozen original does not match its correction proof.')
    values={**values,'business_data':new['business_data'],'provenance':new['provenance']}
    checked=contracts.normalize_record(scope,values)
    if checked!=new:raise ValueError('The corrected import no longer matches its reviewed metadata.')
    return values,checked
