import {test} from 'node:test';
import assert from 'node:assert/strict';
import {extractReportFilters} from './extract.mjs';

test('extracts only report filters and never executes source scripts',()=>{
  const result=extractReportFilters(`
    frappe.query_reports["Example"] = {filters:[
      {fieldname:"company",label:__("Company"),fieldtype:"Link",options:"Company",reqd:1,default:frappe.defaults.get_user_default("Company")},
      {fieldname:"from_date",label:__("From Date"),fieldtype:"Date",default:frappe.datetime.add_months(frappe.datetime.get_today(),-1)},
      {fieldname:"group_by",label:__("Group By"),fieldtype:"Select",options:["Account","Party"],on_change:()=>sendSomething()}
    ]};
    const unrelated={fieldname:"private_config",fieldtype:"Data"};
    throw new Error("Source must never be executed");
  `);
  assert.deepEqual(result.fields.map(f=>f.fieldname),['company','from_date','group_by']);
  assert.equal(result.fields[0].label,'Company');
  assert.deepEqual(result.fields[0].default,{native_default:'user',key:'Company'});
  assert.deepEqual(result.fields[1].default,{native_default:'date_offset',unit:'months',value:-1});
  assert.equal(result.fields[2].options,'Account\nParty');
  assert.ok(result.requires_adapter);
});

test('dynamic filter builders are reported instead of claimed complete',()=>{
  const result=extractReportFilters('frappe.query_reports["Example"]={filters:buildCustomFilters()};');
  assert.equal(result.fields.length,0);
  assert.ok(result.requires_adapter);
});

test('reads literal filters returned by a local builder without running it',()=>{
  const result=extractReportFilters(`function get_filters(){let filters=[
    {fieldname:'period',fieldtype:'Select',options:[{value:'Monthly',label:__('Monthly')},{value:'Yearly',label:__('Yearly')}],default:['Yearly']}
  ]; forbiddenSideEffect(); return filters;} frappe.query_reports.Test={filters:get_filters()};`);
  assert.equal(result.fields[0]?.options,'Monthly\nYearly');
  assert.equal(result.fields[0]?.default,'Yearly');
  assert.ok(result.requires_adapter);
});

test('only the registered report contributes filter definitions, including explicit shared copies',()=>{
 const source=`erpnext.financial_statements={filters:[{fieldname:'from_fiscal_year'}]};
 const config={filters:[{fieldname:'unrelated'}]};
 frappe.query_reports.R={filters:[{fieldname:'item',get_query(){return {filters:[{fieldname:'disabled'}]};}}]};
 anotherRequest({filters:{archived:0}});`;
 const result=extractReportFilters(source);
 assert.deepEqual(result.fields.map(f=>f.fieldname),['item']);
 assert.equal(result.diagnostics.includes('dynamic_filters'),false);
 assert.equal(result.requires_adapter,true);
 const financial=extractReportFilters(`erpnext.financial_statements={filters:[{fieldname:'company'},{fieldname:'old'}]};
 frappe.query_reports.R=$.extend({},erpnext.financial_statements);frappe.query_reports.R.filters.splice(1,1);
 frappe.query_reports.R.filters.push({fieldname:'new'});`);
 assert.deepEqual(financial.fields.map(f=>f.fieldname),['company','new']);
});

test('date defaults and enabled currency options are restricted data primitives',()=>{
 const r=extractReportFilters(`frappe.query_reports.R={filters:[
 {fieldname:'from',default:erpnext.utils.get_fiscal_year(frappe.datetime.get_today(),true)[1]},
 {fieldname:'end',default:frappe.defaults.get_user_default('sales_end_date') || erpnext.utils.get_fiscal_year(frappe.datetime.nowdate(),true)[2]},
 {fieldname:'to',default:frappe.datetime.add_days(frappe.datetime.month_start(),-1)},
 {fieldname:'when',default:frappe.defaults.get_global_default("year_start_date")},
 {fieldname:'currency',fieldtype:'Select',options:erpnext.get_presentation_currency_list()},
 {fieldname:'untested',default:erpnext.utils.get_fiscal_year(getUntrustedDate(),true)[1]}]};`);
 assert.deepEqual(r.fields[0].default,{native_default:'fiscal_start'});
 assert.equal(r.fields[1].default.native_default,'fallback');
 assert.deepEqual(r.fields[2].default,{native_default:'date_offset',unit:'days',value:-1,base:'month_start'});
 assert.equal(r.fields[3].default.native_default,'global_date');
 assert.equal(r.fields[4].native_options,'enabled_currencies');
 assert.deepEqual(r.diagnostics,['untested.default']);
});

test('a known timezone conversion keeps a previous-month local clock as a system datetime',()=>{
 const result=extractReportFilters(`frappe.query_reports.R={filters:[{fieldname:"from_date", fieldtype:"Datetime",
   default:frappe.datetime.convert_to_system_tz(frappe.datetime.add_months(frappe.datetime.now_datetime(),-1))}]};`);
 assert.deepEqual(result.fields[0].default,{native_default:'system_month_offset',value:-1});
});
