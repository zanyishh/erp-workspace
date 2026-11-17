// Run inside the isolated Linux arm64 candidate image after package replacement.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
assert.equal(process.platform,'linux');
assert.equal(process.arch,'arm64');
const root=path.resolve(process.argv[2] || '/home/frappe/frappe-bench/apps/erpnext/banking/node_modules/vite');
const manifest=JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8'));
assert.equal(manifest.version,'8.2.4');
const vite=await import(pathToFileURL(path.join(root,'dist/node/index.js')));
const req=createRequire(path.join(root,'package.json'));
const css=req('lightningcss').transform({filename:'fixture.css',code:Buffer.from('.order { color: red; }'),minify:true});
assert.equal(css.code.toString(),'.order{color:red}');
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'erp-vite-security-'));
try {
  const input=path.join(temp,'fixture.js');
  await fs.writeFile(input,'export const quantity = [1, 2, 3].reduce((sum, value) => sum + value, 0);\n');
  const bundle=await vite.build({configFile:false,root:temp,logLevel:'error',build:{write:false,minify:true,lib:{entry:input,formats:['es'],fileName:'fixture'}}});
  const outputs=(Array.isArray(bundle)?bundle:[bundle]).flatMap(item=>item.output);
  const chunk=outputs.find(item=>item.type==='chunk');
  assert(chunk);
  const executed=await import('data:text/javascript;base64,'+Buffer.from(chunk.code).toString('base64'));
  assert.equal(executed.quantity,6);
  const nativeAddons=[
    'node_modules/lightningcss/node_modules/lightningcss-linux-arm64-gnu/lightningcss.linux-arm64-gnu.node',
    'node_modules/rolldown/node_modules/@rolldown/binding-linux-arm64-gnu/rolldown-binding.linux-arm64-gnu.node'
  ].map(relative=>path.join(root,relative));
  for(const addon of nativeAddons) assert(req.cache[addon],`Reviewed GNU addon was not actually loaded: ${addon}`);
  console.log(JSON.stringify({passed:true,vite:manifest.version,platform:process.platform,arch:process.arch,quantity:executed.quantity,css:css.code.toString(),loadedGnuNativeAddons:nativeAddons}));
} finally { await fs.rm(temp,{recursive:true,force:true}); }
