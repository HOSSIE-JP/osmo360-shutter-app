const test=require('node:test');const assert=require('node:assert/strict');
const vm=require('node:vm');const fs=require('node:fs');
function harness(){
  const events=[],writes=[],listeners={},windowListeners={};let geoSuccess;let gen=0;
  const rx={addEventListener:(k,f)=>listeners[k]=f,removeEventListener:()=>{},startNotifications:async()=>{}};
  const tx={properties:{write:true},writeValueWithResponse:async b=>{writes.push([...b]);}};
  const device={name:'Osmo test',addEventListener:(k,f)=>listeners[k]=f,removeEventListener:()=>{},gatt:{connected:false,connect:async()=>{device.gatt.connected=true;return{getPrimaryService:async()=>({getCharacteristic:async id=>id===0xfff4?rx:tx})}},disconnect:()=>{device.gatt.connected=false;listeners.gattserverdisconnected?.()}}};
  const doc={visibilityState:'visible',addEventListener:(k,f)=>listeners[k]=f};
  const nav={bluetooth:{requestDevice:async()=>device},geolocation:{watchPosition:(success)=>{geoSuccess=success;return 0},clearWatch:()=>gen++},wakeLock:{request:async()=>({release:async()=>{}})}};
  const win={isSecureContext:true,addEventListener:(k,f)=>windowListeners[k]=f,removeEventListener:k=>delete windowListeners[k],matchMedia:()=>({matches:false})};
  const context={window:win,document:doc,navigator:nav,localStorage:{getItem:()=>null,setItem:()=>{}},Uint8Array,Array,Math,Number,JSON,Promise,Error,setTimeout,console};
  vm.runInNewContext(fs.readFileSync('web/device_bridge.js','utf8'),context);win.osmoListen(x=>events.push(JSON.parse(x)));
  const call=async(m,a={})=>JSON.parse(await win.osmoInvoke(m,JSON.stringify(a)));
  return{events,writes,listeners,windowListeners,doc,device,call,geo:()=>geoSuccess,cleared:()=>gen};
}
test('connect enables notification then emits connected',async()=>{const h=harness();await h.call('connect');assert.equal(h.events.at(-1).type,'connected');});
test('writes are serialized and fragmented at MTU 23',async()=>{const h=harness();await h.call('connect');await Promise.all([h.call('write',{bytes:Array(48).fill(1)}),h.call('write',{bytes:[9,9]})]);assert.deepEqual(h.writes.map(x=>x.length),[20,20,8,2]);assert.equal(h.writes[3][0],9);});
test('disconnected link rejects writes rather than replaying',async()=>{const h=harness();await h.call('connect');await h.call('disconnect');assert.ok((await h.call('write',{bytes:[1]})).error);assert.equal(h.writes.length,0);});
test('notification respects DataView byteOffset and byteLength',async()=>{const h=harness();await h.call('connect');h.listeners.characteristicvaluechanged({target:{value:new DataView(Uint8Array.from([0,1,2,3]).buffer,1,2)}});assert.deepEqual(h.events.at(-1).bytes,[1,2]);});
test('null motion values do not emit a stationary sample',async()=>{const h=harness();await h.call('startSensors');h.windowListeners.devicemotion({acceleration:{x:null,y:null,z:null},rotationRate:{alpha:0,beta:0,gamma:0}});assert.equal(h.events.filter(e=>e.type==='motion').length,0);});
test('gyro degrees convert to rad/s, GPS preserves fix time',async()=>{const h=harness();await h.call('startSensors');h.windowListeners.devicemotion({acceleration:{x:0,y:0,z:0},rotationRate:{alpha:180,beta:0,gamma:0}});assert.equal(h.events.at(-1).gyro,Math.PI);h.geo()({timestamp:123,coords:{latitude:35,longitude:139,accuracy:4,altitude:null}});assert.equal(h.events.at(-1).timestamp,123);assert.equal(h.events.at(-1).altitude,null);});
test('visibility emits pause signal and sensor cleanup handles watch ID zero',async()=>{const h=harness();await h.call('startSensors');h.doc.visibilityState='hidden';h.listeners.visibilitychange();assert.equal(h.events.at(-1).visible,false);await h.call('stopSensors');assert.equal(h.cleared(),1);});
