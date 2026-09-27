const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const vm=require('node:vm');
function worker() {
  const source=fs.readFileSync('tool/build_pwa.py','utf8').split("script = r'''")[1].split("'''")[0]
    .replaceAll('__VERSION__','test').replaceAll('__FILES__',JSON.stringify(['index.html','map.html','main.dart.js']));
  const listeners={},matches=[];
  const base='https://example.test/osmo360-shutter-app/';
  vm.runInNewContext(source,{
    URL,
    self:{registration:{scope:base},addEventListener:(name,fn)=>listeners[name]=fn},
    caches:{open:async()=>({match:async(url)=>{matches.push(url);return 'cached:'+url;}})},
    fetch:async()=>{throw Error('offline');}
  });
  async function get(path,mode='navigate',method='GET') {
    let response;
    listeners.fetch({request:{url:new URL(path,base).href,mode,method},respondWith:p=>{response=p;}});
    return response;
  }
  return {get,base,matches};
}
test('offline map navigation uses map.html instead of the Flutter entry point',async()=>{
  const w=worker();assert.equal(await w.get('map.html'),'cached:'+w.base+'map.html');
});
test('app root and unknown navigation use the Flutter entry point',async()=>{
  const w=worker();assert.equal(await w.get('./'),'cached:'+w.base+'index.html');
  assert.equal(await w.get('project/123'),'cached:'+w.base+'index.html');
});
test('Flutter scripts stay available offline',async()=>{
  const w=worker();assert.equal(await w.get('main.dart.js','cors'),'cached:'+w.base+'main.dart.js');
});
test('external maps, other scopes and writes are never intercepted',async()=>{
  const w=worker();
  assert.equal(await w.get('https://maps.googleapis.com/api.js','cors'),undefined);
  assert.equal(await w.get('/another-app/','navigate'),undefined);
  assert.equal(await w.get('main.dart.js','cors','POST'),undefined);
});
test('precache excludes hidden release metadata omitted by deployment archives',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'osmo-pwa-'));
  try {
    const web=path.join(dir,'build','web');
    fs.mkdirSync(path.join(web,'assets'),{recursive:true});
    fs.writeFileSync(path.join(web,'index.html'),'app');
    fs.writeFileSync(path.join(web,'main.dart.js'),'bundle');
    fs.writeFileSync(path.join(web,'.last_build_id'),'build id');
    fs.writeFileSync(path.join(web,'assets','.internal'),'metadata');
    const result=spawnSync('python3',[path.join(process.cwd(),'tool/build_pwa.py')],{cwd:dir,encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    const source=fs.readFileSync(path.join(web,'sw.js'),'utf8');
    const files=JSON.parse(source.match(/const FILES = (\[.*?\]);/s)[1]);
    assert.deepEqual(files,['index.html','main.dart.js']);
  } finally {
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
