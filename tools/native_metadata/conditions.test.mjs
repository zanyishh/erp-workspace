import {test} from 'node:test';
import assert from 'node:assert/strict';
import {compileCondition} from './conditions.mjs';
test('conditions become data without executing calls or global access',()=>{
  assert.equal(compileCondition("eval:doc.status === 1 && ['Open', 'Closed'].includes(parent.status)").op,'&&');
  assert.equal(compileCondition('eval:!doc.__onload?.is_enabled;').op,'!');
  assert.equal(compileCondition('customer').op,'field');
  for(const unsafe of ['eval:fetch("https://example.com")','eval:doc.status = 1','eval:(()=>{throw Error()})()','eval:frappe.call("method")'])assert.equal(compileCondition(unsafe).op,'unsupported');
});
test('compiles upstream import, child-row and inventory rules as restricted data',()=>{
  for(const rule of [
    "doc.import_file.split('.').pop().toLowerCase() === 'csv'",
    "doc.items.every((item) => !item.pr_detail)", "doc.suppliers.some((item) => item.send_email)",
    "cint(erpnext.is_perpetual_inventory_enabled(parent.company))",
    "erpnext.stock.is_subcontracting_or_return_transfer(doc)",
  ]) assert.notEqual(compileCondition('eval:'+rule).op,'unsupported',rule);
  for (const rule of ['doc.items.every((row) => row.touch())', 'doc.items.some(x => window.other)', 'erpnext.stock.is_subcontracting_or_return_transfer(parent)']) {
    assert.equal(compileCondition('eval:'+rule).op,'unsupported',rule);
  }
});
