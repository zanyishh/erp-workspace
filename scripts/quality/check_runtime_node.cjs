/* Local, synthetic compatibility checks for the replacement runtime packages. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const root = path.resolve(process.argv[2] || '.');
let req = createRequire(path.join(root, 'package.json'));
if(process.env.ERP_NODE_TARGETS_JSON){
  const manifest=JSON.parse(fs.readFileSync(process.env.ERP_NODE_TARGETS_JSON,'utf8'));
  const resolveTarget=name=>{
    const packageName=name==='brace-expansion-v5'?'brace-expansion':name;
    const target=manifest.replacements.find(item=>item.package===packageName&&(name!=='brace-expansion-v5'||item.replacement_version.startsWith('5.'))&&(name!=='brace-expansion'||item.replacement_version.startsWith('1.')));
    assert(target,`Missing smoke target: ${name}`);
    const local=createRequire(path.join(path.dirname(target.target_path),'erp-smoke-fixture.js'));
    return {local,name:packageName};
  };
  req=name=>{const target=resolveTarget(name);return target.local(target.name);};
  req.resolve=name=>{const target=resolveTarget(name);return target.local.resolve(target.name);};
}
const results = [];
async function check(name, fn) { await fn(); results.push({ name, passed: true }); }
async function listen(server) { await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); return server.address().port; }
async function close(server) { await new Promise((resolve,reject) => server.close(e => e ? reject(e) : resolve())); }
async function main() {
  await check('axios URL and JSON request compatibility', () => {
    const axios = req('axios');
    assert.equal(axios.getUri({baseURL:'https://example.invalid', url:'/orders', params:{id:7}}), 'https://example.invalid/orders?id=7');
    assert.equal(axios.VERSION, '1.21.1');
    assert.equal(axios.defaults.transformRequest[0].call({}, {value:2}, new axios.AxiosHeaders()), '{"value":2}');
  });
  for (const name of ['brace-expansion','brace-expansion-v5']) await check(name + ' ranges and literals', () => {
    const module = req(name); const expand = typeof module === 'function' ? module : module.expand;
    assert.deepEqual(expand('a{1..3}b'), ['a1b','a2b','a3b']);
    assert.deepEqual(expand('a{red,blue}b'), ['aredb','ablueb']);
    assert.deepEqual(expand('plain'), ['plain']);
  });
  await check('browserslist explicit target', () => assert.deepEqual(req('browserslist')('chrome 120'), ['chrome 120']));
  await check('follow-redirects local redirect', async () => {
    const server=http.createServer((request,response) => { if(request.url==='/first'){response.writeHead(302,{location:'/last'}); response.end();} else response.end('fixture'); });
    const port=await listen(server);
    try { const response=await new Promise((resolve,reject) => req('follow-redirects').http.get(`http://127.0.0.1:${port}/first`,res=>{ let text=''; res.on('data',x=>text+=x); res.on('end',()=>resolve(text)); }).on('error',reject)); assert.equal(response,'fixture'); }
    finally { await close(server); }
  });
  await check('immutable persistent update', () => {
    const {fromJS}=req('immutable'); const first=fromJS({order:{quantity:3}}); const next=first.setIn(['order','quantity'],4);
    assert.equal(first.getIn(['order','quantity']),3); assert.deepEqual(next.toJS(),{order:{quantity:4}});
  });
  await check('launch-editor public function loads', () => assert.equal(typeof req('launch-editor'),'function'));
  await check('lodash merge and prototype rejection', () => {
    const _=req('lodash'); assert.deepEqual(_.merge({x:{a:1}},{x:{b:2}}),{x:{a:1,b:2}});
    _.merge({},JSON.parse('{"__proto__":{"erpPolluted":true},"constructor":{"prototype":{"erpPolluted":true}}}'));
    assert.equal({}.erpPolluted,undefined); assert.equal(_.VERSION,'4.18.1');
  });
  await check('lodash-es ESM import and merge', async () => {
    const _=await import(pathToFileURL(req.resolve('lodash-es')).href);
    assert.deepEqual(_.merge({x:{a:1}},{x:{b:2}}),{x:{a:1,b:2}});
  });
  await check('minimatch and picomatch patterns', () => {
    assert(req('minimatch')('src/order.js','src/*.js')); assert(!req('minimatch')('src/order.ts','src/*.js'));
    const match=req('picomatch')('src/{a,b}.js'); assert(match('src/a.js')); assert(!match('src/c.js'));
  });
  await check('nanoid randomness and alphabet', () => {
    const {nanoid,customAlphabet}=req('nanoid'); const ids=new Set(Array.from({length:100},()=>nanoid())); assert.equal(ids.size,100);
    for(const id of ids) assert.equal(id.length,21); assert.match(customAlphabet('abc',20)(),/^[abc]{20}$/);
  });
  await check('postcss parse, transform, map', async () => {
    const postcss=req('postcss'); const result=await postcss([{postcssPlugin:'fixture',Declaration(decl){if(decl.prop==='color')decl.value='blue';}}]).process('.order { color: red; }',{from:'fixture.css',to:'out.css',map:{inline:false}});
    assert.match(result.css,/color: blue/); assert(result.map); assert.throws(()=>postcss.parse('a { color: red'));
  });
  await check('socket parser text and binary round trip', () => {
    const {Encoder,Decoder}=req('socket.io-parser');
    for(const packet of [{type:2,nsp:'/',id:4,data:['order',{quantity:2}]},{type:2,nsp:'/fixture',data:['bytes',Buffer.from([1,2,3])]}]){
      const encoder=new Encoder(),decoder=new Decoder(); let actual; decoder.on('decoded',value=>actual=value);
      for(const encoded of encoder.encode(packet))decoder.add(encoded); assert.deepEqual(actual,packet); decoder.destroy();
    }
    assert.throws(()=>new Decoder().add('9invalid'));
  });
  await check('source-map-js generated mapping', () => {
    const {SourceMapGenerator,SourceMapConsumer}=req('source-map-js'); const gen=new SourceMapGenerator({file:'out.js'});
    gen.addMapping({generated:{line:1,column:0},original:{line:2,column:3},source:'in.js'});
    const consumer=new SourceMapConsumer(gen.toJSON()); assert.deepEqual(consumer.originalPositionFor({line:1,column:0}),{source:'in.js',line:2,column:3,name:null});
  });
  await check('svgo valid SVG optimize and malformed rejection', () => {
    const {optimize}=req('svgo'); const result=optimize('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="10" height="10" fill="red"/></svg>');
    assert(!result.error); assert.match(result.data,/<svg/); assert.match(result.data,/(red|#f00)/); assert(optimize('<svg><broken></svg>').error);
  });
  await check('tmp safe allocation and cleanup', () => {
    const tmp=req('tmp'); const file=tmp.fileSync({prefix:'erp-node-smoke-'}); assert(fs.existsSync(file.name)); fs.writeSync(file.fd,'fixture'); file.removeCallback(); assert(!fs.existsSync(file.name));
    for (const option of ['prefix','postfix','template']) assert.throws(()=>tmp.tmpNameSync({[option]:['invalid-type']}));
  });
  await check('undici mock HTTP response', async () => {
    const {MockAgent}=req('undici'); const agent=new MockAgent(); agent.disableNetConnect(); agent.get('https://example.invalid').intercept({path:'/order',method:'GET'}).reply(200,{quantity:2});
    try { const response=await agent.request({origin:'https://example.invalid',path:'/order',method:'GET'}); assert.equal(response.statusCode,200); assert.deepEqual(await response.body.json(),{quantity:2}); agent.assertNoPendingInterceptors(); } finally { await agent.close(); }
  });
  await check('ws loopback echo', async () => {
    const {WebSocket,WebSocketServer}=req('ws'); const server=new WebSocketServer({host:'127.0.0.1',port:0}); await new Promise(resolve=>server.on('listening',resolve));
    server.on('connection',socket=>socket.on('message',data=>socket.send(data)));
    try { await new Promise((resolve,reject)=>{const client=new WebSocket(`ws://127.0.0.1:${server.address().port}`); client.on('open',()=>client.send('fixture')); client.on('error',reject); client.on('message',data=>{try{assert.equal(data.toString(),'fixture'); client.close();}catch(e){reject(e);}}); client.on('close',resolve);}); }
    finally { await close(server); }
  });
  if(process.platform==='linux'&&!process.env.ERP_NODE_TARGETS_JSON) await check('vite actual Linux native production bundle', async () => {
    const vite=await import(pathToFileURL(req.resolve('vite')).href);
    const build=await vite.build({configFile:false,logLevel:'error',build:{write:false,minify:true,lib:{entry:path.join(root,'vite-fixture.js'),formats:['es'],fileName:'fixture'}}});
    const result=Array.isArray(build)?build[0]:build; assert(result.output.some(item=>item.type==='chunk'&&item.code.includes('quantity')));
  });
  else results.push({name:'vite actual Linux native production bundle',skipped:'run standalone tool-runtime-node-vite-check.mjs for the actual image target'});
  console.log(JSON.stringify({platform:process.platform,arch:process.arch,results},null,2));
}
main().catch(error=>{console.error(JSON.stringify({results,error:String(error),stack:error.stack},null,2));process.exitCode=1;});
