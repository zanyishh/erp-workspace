// Run against the original tree to save expected output, then the candidate tree.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {createRequire}=require('node:module');
const root=path.resolve(process.argv[2]||'/home/frappe/frappe-bench/apps/frappe/node_modules');
const req=createRequire(path.join(root,'fixture.js'));
const postcss=req('postcss');
const modulePlugin=req('postcss-modules-sync').default;
const {compileStyle,compileStyleAsync}=req('@vue/component-compiler-utils');
const cssCases=[
  '.order { color: red; margin: 0 2px; }',
  '.order:hover, .order.active { color: blue; }',
  '@media (max-width: 700px) { .order { display: block; } }',
  '.order > .item + .label { padding: calc(1em + 2px); }',
  '@keyframes pulse { from { opacity: 0; } to { opacity: 1; } } .order { animation: pulse 1s; }',
  '.order { --erp-color: red; color: var(--erp-color); }',
  ':global(.external) .local { color: #fff; }',
  '.base { color: red; } .derived { composes: base; display: flex; }',
  '/* fixture */\n.order[data-state="open"]::before { content: "ERP"; }',
];
const results=[];
async function main(){
  for(let i=0;i<cssCases.length;i++){
    const source=cssCases[i],filename=`/fixtures/fixture-${i}.css`;
    for(const scoped of [false,true]){
      const result=compileStyle({source,filename,id:'data-v-erp',scoped});
      assert.deepEqual(result.errors,[]);
      const asyncResult=await compileStyleAsync({source,filename,id:'data-v-erp',scoped});
      assert.deepEqual(asyncResult.errors,[]); assert.equal(asyncResult.code,result.code);
      results.push({kind:'vue-style',case:i,scoped,css:result.code});
    }
    let tokens;
    const output=postcss([modulePlugin({generateScopedName:'[name]__[local]__[hash:base64:5]',getJSON:value=>tokens=value})]).process(source,{from:filename,map:false});
    results.push({kind:'css-modules',case:i,css:output.css,tokens});
  }
  const resolver=req('source-map-resolve');
  const map={version:3,file:'bundle.js',sources:['file%20name.js'],names:[],mappings:'AAAA'};
  const reads=[];
  const resolved=resolver.resolveSync('//# sourceMappingURL=bundle%20file.js.map','/fixtures/bundle.js',name=>{reads.push(name);if(name.endsWith('.map'))return JSON.stringify(map);return 'export const quantity=2;';});
  assert.deepEqual(reads,['/fixtures/bundle file.js.map','/fixtures/file name.js']);
  results.push({kind:'source-map-resolve',resolved,reads});
  if(process.argv[3]){
    const expected=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
    assert.deepEqual(results,expected.results);
  }
  console.log(JSON.stringify({passed:true,checks:results.length,results},null,2));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
