const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {createRequire}=require('node:module');
const modules=path.resolve(process.argv[2]);
const req=createRequire(path.join(modules,'fixture.js'));
const vue=req('vue');
const renderer=req('@vue/server-renderer');
const compiler=req('@vue/compiler-sfc');
async function main(){
  const originalWarn=console.warn,originalError=console.error;
  try{
    console.warn=()=>{};console.error=()=>{};
    assert.equal(renderer.ssrRenderAttrs({'x\rautofocus\ronfocus':'ERP_SYNTHETIC_VALUE'}),'','unsafe CR in attribute name must be rejected');
  }finally{console.warn=originalWarn;console.error=originalError;}
  assert.equal(vue.version,'3.5.42');
  for(const name of ['shared','reactivity','runtime-core','runtime-dom','compiler-core','compiler-dom','compiler-sfc','compiler-ssr','server-renderer'])assert.equal(req('@vue/'+name+'/package.json').version,'3.5.42');
  const fromVue=createRequire(req.resolve('vue/package.json'));
  const fromRenderer=createRequire(req.resolve('@vue/server-renderer/package.json'));
  assert.equal(fromVue.resolve('@vue/runtime-dom'),fromRenderer.resolve('@vue/runtime-dom'),'Vue and renderer must share the same runtime instance');
  const Child={setup(){const quantity=vue.ref(2);const doubled=vue.computed(()=>quantity.value*2);const context=vue.inject('context');return()=>vue.h('div',{title:'A&B','data-context':context},String(doubled.value));}};
  const app=vue.createSSRApp({setup(){vue.provide('context','order');return()=>vue.h(Child);}});
  assert.equal(await renderer.renderToString(app),'<div title="A&amp;B" data-context="order">4</div>');
  const source='<script setup>import { ref } from "vue"; const quantity=ref(2);</script><template><div class="order">{{ quantity }}</div></template><style scoped>.order { color: red; }</style>';
  const {descriptor,errors}=compiler.parse(source,{filename:'Fixture.vue'});assert.deepEqual(errors,[]);
  const script=compiler.compileScript(descriptor,{id:'erp-fixture'});
  const template=compiler.compileTemplate({source:descriptor.template.content,filename:'Fixture.vue',id:'erp-fixture',compilerOptions:{bindingMetadata:script.bindings}});assert.deepEqual(template.errors,[]);
  const style=compiler.compileStyle({source:descriptor.styles[0].content,filename:'Fixture.vue',id:'data-v-erp-fixture',scoped:true});assert.deepEqual(style.errors,[]);assert.match(style.code,/data-v-erp-fixture/);
  console.log(JSON.stringify({passed:true,version:vue.version,checks:['CR attribute injection rejected','10package family aligned','shared runtime singleton','SSR provide/inject/reactivity/escaping','script setup compile','template compile','scoped CSS compile']}));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
