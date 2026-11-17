'use strict';

// Usage: node test_runtime_node.cjs BASELINE_NODE_MODULES CANDIDATE_NODE_MODULES
// The baseline is a verified unpacking of the exact affected image packages.
const assert = require('node:assert/strict');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const [beforePath, afterPath] = process.argv.slice(2).map((p) => path.resolve(p));
const before = (name) => require(path.join(beforePath, name));
const after = (name) => require(path.join(afterPath, name));

// CVE-2022-37601: a query key must not mutate the result's prototype.
const attack = '?__proto__[]=polluted&valid=true';
assert.deepEqual(Object.getPrototypeOf(before('loader-utils').parseQuery(attack)), ['polluted']);
const safeQuery = after('loader-utils').parseQuery(attack);
assert.equal(Object.getPrototypeOf(safeQuery), null);
assert.deepEqual(safeQuery.__proto__, ['polluted']);
assert.equal(safeQuery.valid, true);
assert.equal({}.polluted, undefined);

// The image uses loader-utils through generic-names for CSS module names.
// Check both symbolic and content-hashed names, nested paths and Unicode.
let nameCases = 0;
for (const pattern of ['[name]__[local]___[hash:base64:5]', '[hash:base64:8]', '[path][name]__[local]', '[local]__[hash:hex:6]']) {
  for (const file of ['/bench/apps/frappe/public/css/form.css', '/bench/apps/frappe/public/css/nested/print.scss']) {
    for (const localName of ['button', 'field-label', 'தமிழ்', '9column']) {
      const options = { context: '/bench', hashPrefix: 'frappe' };
      assert.equal(after('generic-names')(pattern, options)(localName, file), before('generic-names')(pattern, options)(localName, file));
      nameCases++;
    }
  }
}

// CVE-2026-9277: reject attacker-controlled operator objects, including the
// documented parse(envFn) route, before any string reaches a shell.
for (const separator of ['\n', '\r', '\u2028', '\u2029']) {
  const operator = { op: ';' + separator + 'printf injected' };
  assert.ok(before('shell-quote').quote([operator]).includes(separator));
  assert.throws(() => after('shell-quote').quote([operator]), TypeError);
  if (separator === '\n' || separator === '\r') {
    assert.throws(() => after('shell-quote').quote(after('shell-quote').parse('echo $X', () => operator)), TypeError);
  }
}

// Normal string arguments used by launch-editor keep their exact bytes.
const args = ['', 'plain', 'path with spaces', 'Tamil-தமிழ்', 'quote\'double"', '$HOME;$(printf wrong)', 'line\nbreak', 'back\\slash'];
const quoted = after('shell-quote').quote(args);
assert.deepEqual(after('shell-quote').parse(quoted), args);
const roundTrip = execFileSync('/bin/sh', ['-c', "printf '%s\\0' " + quoted]);
assert.deepEqual(roundTrip, Buffer.from(args.join('\0') + '\0'));
console.log(JSON.stringify({ status: 'passed', cssNameCompatibilityCases: nameCases, operatorInjectionCases: 6, shellArgumentRoundTripCases: args.length }));
