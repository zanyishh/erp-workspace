const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const base=path.resolve(process.argv[2] || '/home/frappe/frappe-bench/apps/frappe/node_modules/decode-uri-component');
const fixed=require(base);
async function main(){
  assert.equal(typeof fixed,'function');
  const esm=(await import(pathToFileURL(path.join(base,'index.js')))).default;
  let comparisons=0;
  const raw=['','plain','hello world','a+b','a%20b','ERP / # ? & =','Tamil தமிழ்','🧶 knitting','£ € ¥','$ + % /','file+name.js','\0\n\r'];
  for(let i=0;i<512;i++)raw.push(String.fromCodePoint(0x20+(i*127)%0xd700)+' ERP '+String.fromCodePoint(0x10000+i));
  for(const value of raw){
    const encoded=encodeURIComponent(value);assert.equal(fixed(encoded),decodeURIComponent(encoded));assert.equal(esm(encoded),decodeURIComponent(encoded));comparisons++;
  }
  assert.equal(fixed('a+b'),'a b');assert.equal(esm('a+b'),'a+b');
  for(const value of [null,undefined,3,{},['a']])assert.throws(()=>fixed(value),TypeError);
  for(const value of ['%','%zz','%C2','%FE%FF','%E0%A4%A','%C0%AF','%ED%A0%80','%F4%90%80%80'])assert.equal(fixed(value),esm(value));
  let payload='';for(let i=0;i<32000;i++)payload+='%'+Math.floor(i/256).toString(16).padStart(2,'0')+'%'+(i%256).toString(16).padStart(2,'0')+'x';payload+='%zz';
  const start=performance.now();const result=fixed(payload);const elapsed=performance.now()-start;
  assert.equal(result,esm(payload));assert(elapsed<1500,`linear decoder exceeded time bound: ${elapsed}ms`);
  console.log(JSON.stringify({passed:true,valid_compatibility_vectors:comparisons,malformed_vectors:8,type_rejections:5,adversarial_bytes:payload.length,adversarial_ms:elapsed}));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
