import {readFile,writeFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compileCondition} from './conditions.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const inventory=JSON.parse(await readFile(resolve(root,'docs/coverage/erpnext-source-inventory.json'),'utf8'));
const rules={};let uses=0;
for(const type of inventory.record_types){
  const doc=JSON.parse(await readFile(resolve(root,type.source),'utf8'));
  for(const field of doc.fields??[])for(const key of ['depends_on','mandatory_depends_on','read_only_depends_on'])if(field[key]){rules[field[key]]=compileCondition(field[key]);uses++;}
}
const reports=JSON.parse(await readFile(resolve(root,'apps/erp_extensions/erp_extensions/report_definitions.json'),'utf8'));
for(const report of Object.values(reports.reports))for(const field of report.fields)for(const key of ['depends_on','mandatory_depends_on','read_only_depends_on'])if(field[key])rules[field[key]]=compileCondition(field[key]);
await writeFile(resolve(root,'apps/erp_extensions/erp_extensions/condition_definitions.json'),JSON.stringify(rules)+'\n');
const coverage={uses,distinct:Object.keys(rules).length,supported:Object.values(rules).filter(v=>v.op!=='unsupported').length,unsupported:Object.keys(rules).filter(k=>rules[k].op==='unsupported')};
await writeFile(resolve(root,'docs/coverage/condition-extraction.json'),JSON.stringify(coverage,null,2)+'\n');
process.stdout.write(JSON.stringify({uses,distinct:coverage.distinct,supported:coverage.supported})+'\n');
