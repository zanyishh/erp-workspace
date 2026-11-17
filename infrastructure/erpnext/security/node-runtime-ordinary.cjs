// Ordinary candidate-runtime checks; synthetic loopback traffic and files only.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const https = require('node:https');
const http2 = require('node:http2');
const zlib = require('node:zlib');
const {spawnSync} = require('node:child_process');
const {once} = require('node:events');

async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

async function close(server) {
  if (!server.listening) return;
  if (server.closeAllConnections) server.closeAllConnections();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

function request(client, options, body = '') {
  return new Promise((resolve, reject) => {
    const outgoing = client.request({...options, agent: false}, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => resolve({status: response.statusCode, body: Buffer.concat(chunks).toString()}));
    });
    outgoing.setTimeout(5000, () => outgoing.destroy(new Error('Loopback request timed out')));
    outgoing.on('error', reject);
    outgoing.end(body);
  });
}

async function main() {
  assert.equal(process.platform, 'linux');
  assert.equal(process.arch, 'arm64');
  assert.notEqual(process.getuid(), 0, 'Run the normal checks as frappe');
  assert.equal(process.version, 'v24.22.3');
  assert.equal(process.execPath, '/home/frappe/.nvm/versions/node/v24.22.2/bin/node');
  assert.equal(process.versions.modules, '137');
  assert.equal(process.versions.sqlite, '3.54.1');
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'erp-node-runtime-'));
  const checks = [];
  const servers = [];
  let session;
  try {
    const handler = (incoming, response) => {
      const chunks = [];
      incoming.on('data', chunk => chunks.push(chunk));
      incoming.on('end', () => {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify({method: incoming.method, body: Buffer.concat(chunks).toString()}));
      });
    };
    const plain = http.createServer(handler); servers.push(plain);
    const port = await listen(plain);
    const payload = JSON.stringify({invoice: 'synthetic', amount: 125.5});
    const reply = await request(http, {host: '127.0.0.1', port, path: '/invoice', method: 'POST'}, payload);
    assert.equal(reply.status, 200);
    assert.deepEqual(JSON.parse(reply.body), {method: 'POST', body: payload});
    const fetched = await fetch(`http://127.0.0.1:${port}/invoice`, {signal: AbortSignal.timeout(5000)});
    assert.equal(fetched.status, 200);
    assert.deepEqual(await fetched.json(), {method: 'GET', body: ''});
    checks.push('HTTP request/body roundtrip', 'built-in fetch');

    const keyPath = path.join(temporary, 'synthetic.key');
    const certificatePath = path.join(temporary, 'synthetic.crt');
    const generated = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
      '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      '-keyout', keyPath, '-out', certificatePath], {encoding: 'utf8', timeout: 20000});
    assert.equal(generated.status, 0, generated.stderr);
    fs.chmodSync(keyPath, 0o600);
    const key = fs.readFileSync(keyPath), certificate = fs.readFileSync(certificatePath);
    const secure = https.createServer({key, cert: certificate, minVersion: 'TLSv1.2'}, handler);
    servers.push(secure);
    const securePort = await listen(secure);
    const trusted = await request(https, {host: '127.0.0.1', port: securePort, servername: 'localhost',
      method: 'POST', ca: certificate, rejectUnauthorized: true}, payload);
    assert.equal(trusted.status, 200);
    assert.equal(JSON.parse(trusted.body).body, payload);
    await assert.rejects(request(https, {host: '127.0.0.1', port: securePort, servername: 'localhost',
      rejectUnauthorized: true}), error => ['DEPTH_ZERO_SELF_SIGNED_CERT', 'SELF_SIGNED_CERT_IN_CHAIN',
        'UNABLE_TO_VERIFY_LEAF_SIGNATURE'].includes(error.code));
    checks.push('verified TLS request', 'untrusted certificate rejected');

    const multiplexed = http2.createSecureServer({key, cert: certificate}); servers.push(multiplexed);
    multiplexed.on('stream', stream => {
      stream.respond({':status': 200, 'content-type': 'text/plain'});
      stream.end('Synthetic HTTP/2 invoice');
    });
    const http2Port = await listen(multiplexed);
    session = http2.connect(`https://127.0.0.1:${http2Port}`, {ca: certificate, servername: 'localhost',
      rejectUnauthorized: true});
    session.setTimeout(5000, () => session.destroy(new Error('HTTP/2 loopback timed out')));
    await once(session, 'connect');
    const h2Reply = await new Promise((resolve, reject) => {
      const stream = session.request({':path': '/invoice'});
      let status, body = '';
      stream.on('response', headers => { status = headers[':status']; });
      stream.setEncoding('utf8'); stream.on('data', chunk => { body += chunk; });
      stream.on('error', reject); stream.on('end', () => resolve({status, body})); stream.end();
    });
    assert.deepEqual(h2Reply, {status: 200, body: 'Synthetic HTTP/2 invoice'});
    session.destroy(); session = null;
    checks.push('verified TLS HTTP/2 stream');

    const {DatabaseSync} = require('node:sqlite');
    const database = new DatabaseSync(':memory:');
    try {
      assert.equal(database.prepare('select sqlite_version() as version').get().version, '3.54.1');
      database.exec('CREATE TABLE invoice(id INTEGER PRIMARY KEY, amount INTEGER NOT NULL) STRICT');
      database.prepare('INSERT INTO invoice(amount) VALUES (?)').run(12550);
      database.exec('BEGIN; INSERT INTO invoice(amount) VALUES(99); ROLLBACK;');
      assert.equal(database.prepare('SELECT sum(amount) AS total FROM invoice').get().total, 12550);
      assert.equal(database.prepare("SELECT json_extract('{\"quantity\":3}', '$.quantity') AS quantity").get().quantity, 3);
      database.exec("CREATE VIRTUAL TABLE search USING fts5(body); INSERT INTO search VALUES('synthetic invoice')");
      assert.equal(database.prepare("SELECT count(*) AS found FROM search WHERE search MATCH 'invoice'").get().found, 1);
      assert.equal(database.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
    } finally { database.close(); }
    checks.push('built-in SQLite version/transactions/JSON/FTS5/integrity');

    const content = Buffer.from('Synthetic invoice 125.50\n'.repeat(250));
    const dictionary = Buffer.from('Synthetic invoice amount quantity');
    assert.deepEqual(zlib.gunzipSync(zlib.gzipSync(content)), content);
    assert.deepEqual(zlib.inflateSync(zlib.deflateSync(content, {dictionary}), {dictionary}), content);
    assert.deepEqual(zlib.brotliDecompressSync(zlib.brotliCompressSync(content)), content);
    checks.push('gzip/deflate with dictionary/Brotli roundtrips');
    console.log(JSON.stringify({status: 'passed', uid: process.getuid(), executable: process.execPath,
      versions: process.versions, checks, network_scope: '127.0.0.1 ephemeral ports only',
      limitation: 'Ordinary compatibility checks, not a claim that every bundled native library has been patched.'}));
  } finally {
    if (session) session.destroy();
    for (const server of servers.reverse()) await close(server);
    fs.rmSync(temporary, {recursive: true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
