(() => {
  const frames=new Map();
  window.osmoMapAttach=(id,frame,json)=>{
    frame.title='Googleマップ';frame.style.cssText='width:100%;height:100%;border:0;border-radius:16px';
    frame.referrerPolicy='strict-origin-when-cross-origin';
    const entry={frame,config:JSON.parse(json)};frames.set(id,entry);
    frame.addEventListener('load',()=>frame.contentWindow.postMessage({type:'osmo-map',config:entry.config},location.origin));
    frame.src=new URL('map.html',document.baseURI).href;
  };
  window.osmoMapUpdate=(id,json)=>{const e=frames.get(id);if(e){e.config=JSON.parse(json);e.frame.contentWindow.postMessage({type:'osmo-map',config:e.config},location.origin);}};
  window.osmoMapDispose=id=>frames.delete(id);
})();
