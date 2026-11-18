const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const postcss=require(path.resolve(process.argv[2]));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'erp-map-security-'));
const marker='ERP_SYNTHETIC_MAP_SECRET_7654';
try{
  const uploads=path.join(temp,'uploads');fs.mkdirSync(uploads);
  const map={version:3,sources:['private.js'],names:[],mappings:'AAAA',sourcesContent:[marker]};
  for(const extension of ['map','txt'])fs.writeFileSync(path.join(temp,'private.'+extension),JSON.stringify(map));
  fs.symlinkSync(path.join(temp,'private.map'),path.join(uploads,'linked.map'));
  const vectors=[
    {name:'relative map traversal',annotation:'../private.map',from:path.join(uploads,'input.css')},
    {name:'arbitrary file extension',annotation:'../private.txt',from:path.join(uploads,'input.css')},
    {name:'absolute map without from',annotation:path.join(temp,'private.map')},
    {name:'symlink escapes CSS directory',annotation:'linked.map',from:path.join(uploads,'input.css')},
  ];
  for(const item of vectors){
    const result=postcss().process('a { color: red; }\n/*# sourceMappingURL='+item.annotation+' */',item.from?{from:item.from}:{from:undefined});
    const output=JSON.stringify({css:result.css,map:result.map&&result.map.toJSON()});
    assert(!output.includes(marker),item.name+' disclosed synthetic source-map content');
  }
  console.log(JSON.stringify({passed:true,checks:vectors.map(item=>item.name)}));
}finally{fs.rmSync(temp,{recursive:true,force:true});}
