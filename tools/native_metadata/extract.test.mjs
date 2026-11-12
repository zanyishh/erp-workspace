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
