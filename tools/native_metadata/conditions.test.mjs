import {test} from 'node:test';
import assert from 'node:assert/strict';
import {compileCondition} from './conditions.mjs';
test('conditions become data without executing calls or global access',()=>{
  assert.equal(compileCondition("eval:doc.status === 1 && ['Open', 'Closed'].includes(parent.status)").op,'&&');
  assert.equal(compileCondition('eval:!doc.__onload?.is_enabled;').op,'!');
  assert.equal(compileCondition('customer').op,'field');
  for(const unsafe of ['eval:fetch("https://example.com")','eval:doc.status = 1','eval:(()=>{throw Error()})()','eval:frappe.call("method")'])assert.equal(compileCondition(unsafe).op,'unsupported');
});
