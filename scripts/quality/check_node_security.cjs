#!/usr/bin/env node
// Run against an explicitly selected tool directory, before activating its lock.
const assert = require('node:assert/strict');
const path = require('node:path');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const requireTool = createRequire(path.join(path.resolve(process.argv[2]), 'package.json'));

(async () => {
  const { faker } = requireTool('@faker-js/faker');
  faker.rawDefinitions.test = (() => () => {});
  try { faker.helpers.fake('{{test.constructor(globalThis.__erp_faker_probe=1)}}'); } catch (_) {}
  assert.equal(globalThis.__erp_faker_probe, undefined, 'Faker must not execute template code');

  const FormData = requireTool('form-data');
  const form = new FormData();
  form.append('name"\r\nX-Injected: owned', 'synthetic');
  assert.equal(form.getBuffer().includes(Buffer.from('\r\nX-Injected: owned')), false, 'Multipart field names must not inject headers');

  const yaml = requireTool('js-yaml');
  assert.deepEqual(yaml.load('request:\n  method: GET\n  retry: false\n'), { request: { method: 'GET', retry: false } });

  const grpcFile = path.join(path.resolve(process.argv[2]), 'node_modules/@usebruno/requests/src/grpc/grpcMessageGenerator.js');
  const { generateGrpcSampleMessage } = await import(pathToFileURL(grpcFile));
  const sample = generateGrpcSampleMessage({ requestType: { field: [
    { name: 'amount', type: 'TYPE_FLOAT' }, { name: 'count', type: 'TYPE_INT32' },
    { name: 'enabled', type: 'TYPE_BOOL' }, { name: 'title', type: 'TYPE_STRING' },
    { name: 'data', type: 'TYPE_BYTES' }, { name: 'entries', type: 'TYPE_STRING', label: 'LABEL_REPEATED' },
  ] } }, { arraySize: 2 });
  assert.equal(typeof sample.amount, 'number');
  assert.equal(Number.isInteger(sample.count), true);
  assert.equal(typeof sample.enabled, 'boolean');
  assert.equal(typeof sample.title, 'string');
  assert.equal(Buffer.from(sample.data, 'base64').length >= 5, true);
  assert.equal(sample.entries.length, 2);

  const axios = requireTool('axios');
  assert.equal(axios.getUri({ url: 'http://127.0.0.1:8081/api/method/ping', params: { check: 'a b' } }), 'http://127.0.0.1:8081/api/method/ping?check=a+b');
  console.log('Passed Faker code-execution guard, multipart injection guard, YAML parsing, Bruno/Faker compatibility and Axios request construction.');
})().catch(error => { console.error(error); process.exitCode = 1; });
