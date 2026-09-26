/* Browser hardware adapter. Protocol and capture decisions stay in Dart. */
(() => {
  'use strict';
  const SERVICE=0xfff0, RX=0xfff4, TX=0xfff5;
  let listener=null, device=null, rx=null, tx=null, connecting=false;
  let geoId=null, wake=null, motionOn=false, audio=null, installPrompt=null;
  let generation=0, writeTail=Promise.resolve();
  const emit=(type,data={}) => { if(listener) listener(JSON.stringify({type,...data})); };
  const motion=e => {
    const a=e.acceleration, g=e.rotationRate;
    if(!a || !g || ![a.x,a.y,a.z,g.alpha,g.beta,g.gamma].every(Number.isFinite)) return;
    emit('motion',{linear:Math.hypot(a.x,a.y,a.z),gyro:Math.hypot(g.alpha,g.beta,g.gamma)*Math.PI/180});
  };
  const notify=e => {
    const v=e.target.value;
    emit('bytes',{bytes:Array.from(new Uint8Array(v.buffer,v.byteOffset,v.byteLength))});
  };
  function disconnected() {
    generation++;
    rx?.removeEventListener('characteristicvaluechanged',notify);
    rx=null; tx=null;
    emit('disconnected');
  }
  async function connect(args) {
    if(connecting) throw Error('接続処理中です');
    connecting=true;
    try {
      if(!navigator.bluetooth) throw Error('Web Bluetooth非対応です。Android Chromeをご利用ください');
      if(!window.isSecureContext) throw Error('BluetoothにはHTTPSが必要です');
      if(device?.gatt?.connected) device.gatt.disconnect();
      if(!args.reconnect || !device) {
        device?.removeEventListener('gattserverdisconnected',disconnected);
        // Some Osmo advertisements omit FFF0. A user-selected chooser is intentional.
        device=await navigator.bluetooth.requestDevice({acceptAllDevices:true,optionalServices:[SERVICE]});
        device.addEventListener('gattserverdisconnected',disconnected);
      }
      const gatt=await device.gatt.connect();
      const service=await gatt.getPrimaryService(SERVICE);
      rx=await service.getCharacteristic(RX);
      tx=await service.getCharacteristic(TX);
      rx.addEventListener('characteristicvaluechanged',notify);
      await rx.startNotifications();
      generation++;
      emit('connected',{name:device.name||'Osmo 360'});
      return {name:device.name||'Osmo 360'};
    } catch(e) { device?.gatt?.disconnect(); throw e; }
    finally { connecting=false; }
  }
  async function write(args) {
    const bytes=Uint8Array.from(args.bytes), gen=generation, characteristic=tx;
    const work=writeTail.catch(()=>{}).then(async()=>{
      if(!characteristic || gen!==generation || !device?.gatt?.connected) throw Error('カメラ未接続');
      // Conservative 20-byte ATT payload works at the default MTU (23).
      for(let offset=0;offset<bytes.length;offset+=20) {
        if(gen!==generation) throw Error('送信中に切断されました');
        const chunk=bytes.slice(offset,offset+20);
        if(characteristic.properties.write) await characteristic.writeValueWithResponse(chunk);
        else if(characteristic.properties.writeWithoutResponse) await characteristic.writeValueWithoutResponse(chunk);
        else throw Error('書き込み可能なCharacteristicがありません');
      }
    });
    writeTail=work;
    return work;
  }
  async function startSensors() {
    audio ||= typeof AudioContext!=='undefined' ? new AudioContext() : null;
    await audio?.resume().catch(()=>{});
    if(typeof DeviceMotionEvent!=='undefined' && typeof DeviceMotionEvent.requestPermission==='function') {
      if(await DeviceMotionEvent.requestPermission()!=='granted') emit('error',{source:'motion',message:'動作センサーの許可が必要です'});
    }
    if(!motionOn) { window.addEventListener('devicemotion',motion); motionOn=true; }
    if(geoId===null && navigator.geolocation) {
      geoId=navigator.geolocation.watchPosition(p=>{
        const c=p.coords;
        emit('location',{lat:c.latitude,lon:c.longitude,accuracy:c.accuracy,
          altitude:c.altitude,verticalAccuracy:c.altitudeAccuracy,speed:c.speed,heading:c.heading,
          timestamp:p.timestamp,satellites:0,altitudeReference:'WGS84 ellipsoid (browser)'});
      },e=>emit('error',{source:'gps',message:`位置情報: ${e.message}`}),
      {enableHighAccuracy:true,maximumAge:0,timeout:10000});
    }
    if(!navigator.geolocation) emit('error',{source:'gps',message:'位置情報非対応'});
    try { wake=await navigator.wakeLock?.request('screen'); }
    catch(e) { emit('warning',{message:'画面消灯防止が使えません。画面を前面に保ってください'}); }
    emit('capabilities',capabilities());
  }
  async function stopSensors() {
    if(geoId!==null) navigator.geolocation?.clearWatch(geoId);
    geoId=null; window.removeEventListener('devicemotion',motion); motionOn=false;
    await wake?.release().catch(()=>{}); wake=null;
    window.speechSynthesis?.cancel();
  }
  function capabilities() {
    return {bluetooth:!!navigator.bluetooth,motion:'DeviceMotionEvent' in window,
      location:!!navigator.geolocation,wakeLock:!!navigator.wakeLock,install:!!installPrompt,
      nativeSteps:false,platform:'web',standalone:window.matchMedia?.('(display-mode: standalone)').matches||false};
  }
  function feedback(args) {
    if(args.sound && audio?.state==='running') {
      const oscillator=audio.createOscillator(),gain=audio.createGain();
      oscillator.frequency.value=880; gain.gain.value=.07;
      oscillator.connect(gain); gain.connect(audio.destination);
      oscillator.start(); oscillator.stop(audio.currentTime+.1);
    }
    if(args.voice && window.speechSynthesis) {
      window.speechSynthesis.cancel();
      const u=new SpeechSynthesisUtterance(args.text); u.lang='ja-JP'; u.rate=1.1;
      window.speechSynthesis.speak(u);
    }
    if(args.vibrate) navigator.vibrate?.(60);
  }
  let storageDb;
  async function storage(action,key,value) {
    if(typeof indexedDB==='undefined') {
      if(action==='get')return localStorage.getItem(`osmo360.${key}`);
      if(action==='delete')return localStorage.removeItem(`osmo360.${key}`);
      localStorage.setItem(`osmo360.${key}`,value);return;
    }
    if(!storageDb) storageDb=new Promise((resolve,reject)=>{
      const request=indexedDB.open('osmo360-shutter',1);
      request.onupgradeneeded=()=>request.result.createObjectStore('kv');
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error);
      request.onblocked=()=>reject(Error('別のタブを閉じて再度お試しください'));
    });
    const db=await storageDb;
    return new Promise((resolve,reject)=>{
      const t=db.transaction('kv',action==='get'?'readonly':'readwrite'),store=t.objectStore('kv');
      const r=action==='get'?store.get(key):action==='delete'?store.delete(key):store.put(value,key);
      t.oncomplete=()=>resolve(r.result??null);t.onerror=()=>reject(t.error);t.onabort=()=>reject(t.error||Error('保存を中断しました'));
    });
  }
  const methods={
    capabilities,connect,write,
    disconnect:()=>{ device?.gatt?.disconnect(); },
    startSensors,stopSensors,
    keepAwake:async()=>{ if(document.visibilityState==='visible' && !wake) wake=await navigator.wakeLock?.request('screen'); },
    feedback,
    load:({key})=>storage('get',key),
    save:({key,value})=>storage('put',key,value),
    remove:({key})=>storage('delete',key),
    export:({name,content,mime})=>{
      const url=URL.createObjectURL(new Blob([content],{type:mime||'application/json'}));
      const a=document.createElement('a'); a.href=url; a.download=name; a.click();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    },
    install:async()=>{
      if(!installPrompt) return {hint:'Chromeメニューから「アプリをインストール」または「ホーム画面に追加」を選んでください'};
      await installPrompt.prompt(); const choice=await installPrompt.userChoice;
      installPrompt=null; emit('capabilities',capabilities()); return choice;
    }
  };
  window.osmoListen=callback=>{ listener=callback; emit('visibility',{visible:document.visibilityState==='visible'}); };
  window.osmoInvoke=async(method,json)=>{
    try {
      if(!methods[method]) throw Error(`Unsupported method: ${method}`);
      return JSON.stringify({value:(await methods[method](JSON.parse(json)))??null});
    } catch(e) { return JSON.stringify({error:e.message||String(e)}); }
  };
  document.addEventListener('visibilitychange',()=>{
    const visible=document.visibilityState==='visible'; emit('visibility',{visible});
    if(!visible) { window.speechSynthesis?.cancel(); wake?.release().catch(()=>{}); wake=null; }
  });
  window.addEventListener('beforeinstallprompt',e=>{ e.preventDefault(); installPrompt=e; emit('capabilities',capabilities()); });
  window.addEventListener('appinstalled',()=>{ installPrompt=null; emit('capabilities',capabilities()); });
})();
