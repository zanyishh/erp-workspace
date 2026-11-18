// GPL-3.0. Generated metadata derives from the pinned, preserved GPL/MIT source.
import {readFile,writeFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {extractReportFilters} from './extract.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const inventory=JSON.parse(await readFile(resolve(root,'docs/coverage/erpnext-source-inventory.json'),'utf8'));
const reports={};const errors=[];
for(const report of inventory.reports){
  const path=resolve(root,report.source.replace(/\.json$/,'.js'));
  let source='';try{source=await readFile(path,'utf8');}catch{}
  for(const shared of ['financial_statements','sales_trends_filters','purchase_trends_filters']){
    if(source.includes(`erpnext.${shared}`)){
      source=(await readFile(resolve(root,`upstream/erpnext/erpnext/public/js/${shared}.js`),'utf8'))+'\n'+source;
    }
  }
  try{
    const definition=source?extractReportFilters(source,report.name):{fields:[],requires_adapter:true,diagnostics:['no_script_filter_schema']};
    reports[report.name]={...definition,source:report.source,reference:report.reference,type:report.type};
  }catch(error){errors.push({report:report.name,error:error.message});reports[report.name]={fields:[],requires_adapter:true,diagnostics:['parse_error'],source:report.source};}
}
await writeFile(resolve(root,'apps/erp_extensions/erp_extensions/report_definitions.json'),JSON.stringify({version:1,reports},null,2)+'\n');
await writeFile(resolve(root,'docs/coverage/report-extraction.json'),JSON.stringify({total:inventory.reports.length,
  with_fields:Object.values(reports).filter(r=>r.fields.length).length,
  requires_adapters:Object.values(reports).filter(r=>r.requires_adapter).length,errors},null,2)+'\n');
process.stdout.write(JSON.stringify({reports:Object.keys(reports).length,withFields:Object.values(reports).filter(r=>r.fields.length).length,parseErrors:errors.length})+'\n');
