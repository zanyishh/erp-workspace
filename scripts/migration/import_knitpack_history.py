#!/usr/bin/env python3
"""Validate every local original before a resumable, console-only target import."""
import argparse
from collections import Counter
from functools import lru_cache
import hashlib,json,os
from pathlib import Path
import subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'apps/erp_extensions'))
from erp_extensions.migration import contracts
from erp_extensions.migration.normalize import success
from history_correction import apply_overlay


def preflight(scope,inputs,manifests,repairs):
    counts=Counter();keys=set();verified=set();pointers=set();applied=set();supplement_records=0

    @lru_cache(maxsize=32)
    def evidence(file,digest):
        entry=manifests.get((file,digest))
        if not entry:raise ValueError('Unknown original evidence.')
        raw=entry['path'].read_bytes()
        if len(raw)!=entry['bytes'] or hashlib.sha256(raw).hexdigest()!=digest:
            raise ValueError('An original archive hash or size changed.')
        data=json.loads(raw)
        if isinstance(data,dict) and not success(data):raise ValueError('Explicit failed source response is not business evidence.')
        verified.add((file,digest));return data

    for item in inputs:
        if hashlib.sha256(item['path'].read_bytes()).hexdigest()!=item['sha256']:raise ValueError('The validated input hash changed.')
        with item['path'].open() as stream:
            for number,line in enumerate(stream,1):
                value,record=apply_overlay(scope,json.loads(line),repairs)
                key=record['source_key']
                if key in keys:raise ValueError(f'Duplicate source identity at line {number}')
                keys.add(key);counts[record['family']]+=1
                if key in repairs:applied.add(key)
                if item['supplement']:
                    if record['family']!='master':raise ValueError('The additive supplement may only contain original reference masters.')
                    supplement_records+=1
                for ref in record['provenance']:
                    pointer_key=(ref['file'],ref['sha256'],ref['pointer'])
                    if pointer_key in pointers:continue
                    node=evidence(ref['file'],ref['sha256'])
                    try:
                        for part in ref['pointer'].split('/')[1:]:
                            part=part.replace('~1','/').replace('~0','~')
                            if isinstance(node,list):
                                if not part.isdigit() or (len(part)>1 and part.startswith('0')):raise KeyError(part)
                                node=node[int(part)]
                            elif isinstance(node,dict):node=node[part]
                            else:raise KeyError(part)
                    except (KeyError,IndexError,TypeError,ValueError):raise ValueError('An original evidence JSON pointer does not resolve.') from None
                    pointers.add(pointer_key)
    if applied!=set(repairs):raise ValueError('A reviewed correction did not match the frozen original input.')
    return {'records':sum(counts.values()),'families':dict(counts),'verified_original_files':len(verified),
        'verified_original_pointers':len(pointers),'input_sha256':inputs[0]['sha256'],
        'supplement_records':supplement_records,'supplements':{i['path'].name:i['sha256'] for i in inputs if i['supplement']},
        'metadata_corrections':len(applied)}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true')
    parser.add_argument('--supplement',type=Path,action='append',default=[],help='Append a hash-bound original-master JSONL; default remains read-only.')
    args=parser.parse_args()
    os.umask(0o077)
    base=ROOT/'.local/knitpack-migration';destination=ROOT/'.local/customer-workspace'
    path=base/'destination/history-records.jsonl'
    scope=contracts.normalize_scope(json.loads((destination/'migration-scope.json').read_text()))
    correction_path=base/'destination/history-provenance-correction-plan.json'
    correction=json.loads(correction_path.read_text()) if correction_path.exists() else {'repairs':[]}
    repairs={r['source_key']:r for r in correction['repairs']}
    validation=json.loads((base/'destination/history-records-validation.json').read_text())
    coverage=json.loads((base/'destination/history-records-coverage.json').read_text())
    source_hash=validation['sha256']
    if repairs and correction.get('frozen_history_sha256')!=source_hash:raise ValueError('Correction proof belongs to a different frozen input.')
    inputs=[{'path':path,'sha256':source_hash,'supplement':False}]
    for supplement in args.supplement:
        supplement=supplement.resolve()
        if supplement.parent!=(base/'destination').resolve() or supplement.suffix!='.jsonl':raise ValueError('Use a reviewed private destination supplement.')
        report=json.loads(supplement.with_name(supplement.stem+'-validation.json').read_text())
        inputs.append({'path':supplement,'sha256':report['sha256'],'supplement':True})
    manifests={}
    for name in ('report','source'):
        manifest_path=base/f'verification/{name}-snapshot-final.manifest.jsonl'
        expected=scope['manifest_sha256'] if name=='report' else coverage['original_manifest_sha256']
        if hashlib.sha256(manifest_path.read_bytes()).hexdigest()!=expected:raise ValueError('A final source manifest hash changed.')
        for line in manifest_path.read_text().splitlines():
            entry=json.loads(line);key=(entry['file'],entry['sha256'])
            manifests[key]={'path':base/(name+'-snapshot')/entry['file'],'bytes':entry['bytes']}
    checked=preflight(scope,inputs,manifests,repairs)
    checked['correction_sha256']=hashlib.sha256(correction_path.read_bytes()).hexdigest() if repairs else None
    (destination/'history-import-preflight.json').write_text(json.dumps(checked,indent=2))
    print(json.dumps(checked),flush=True)
    if not args.apply:return
    for item in inputs:
        if hashlib.sha256(item['path'].read_bytes()).hexdigest()!=item['sha256']:raise ValueError('The validated input changed.')
    program="""import json,sys,os,frappe
from collections import Counter
os.chdir('/home/frappe/frappe-bench/sites');frappe.init(site='customer-migration.localhost',sites_path='.')
frappe.connect();frappe.set_user('Administrator')
if not frappe.conf.get('erp_customer_migration_enabled'):raise RuntimeError('Dedicated target is not enabled')
from erp_extensions.migration import service
scope=service.create_scope(json.loads(sys.stdin.readline()));counts=Counter();created=0;total=0
try:
 for line in sys.stdin:
  value=json.loads(line);result=service.store_record(scope,value)
  total+=1;created+=bool(result['created']);counts[value['family']]+=1
  if total%100==0:
   frappe.db.commit();print(json.dumps({'processed':total,'created':created}),flush=True)
 frappe.db.commit();print('RESULT='+json.dumps({'processed':total,'created':created,'families':dict(counts),'scope':scope}),flush=True)
except Exception:
 frappe.db.rollback();raise
finally:frappe.destroy()
"""
    command=['docker','--context','colima-erp','compose','-f',str(ROOT/'infrastructure/erpnext/compose.yaml'),
        'exec','-T','backend','/home/frappe/frappe-bench/env/bin/python','-c',program]
    with (destination/'history-import.log').open('wb') as log:
        process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT)
        try:
            process.stdin.write((json.dumps(scope)+'\n').encode())
            for item in inputs:
                with item['path'].open() as stream:
                    for line in stream:
                        value,_=apply_overlay(scope,json.loads(line),repairs)
                        process.stdin.write((json.dumps(value,ensure_ascii=False)+'\n').encode())
            process.stdin.close();code=process.wait()
        except BrokenPipeError:
            code=process.wait()
    if code:raise SystemExit('Target import stopped safely; see the private history-import.log before resuming.')
    result=json.loads(next(line[7:] for line in (destination/'history-import.log').read_text().splitlines() if line.startswith('RESULT=')))
    if result['processed']!=checked['records'] or result['families']!=checked['families']:raise ValueError('Target coverage does not match the validated input.')
    (destination/'history-import-result.json').write_text(json.dumps({**result,'input_sha256':source_hash,'supplements':checked['supplements']},indent=2))
    print(json.dumps({'imported_originals':result['processed'],'new_originals':result['created']}))


if __name__=='__main__':main()
