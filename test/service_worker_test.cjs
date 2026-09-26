const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
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
