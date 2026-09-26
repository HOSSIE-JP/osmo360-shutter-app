"""Generate deterministic, scope-local cache for the actual Flutter release."""
from pathlib import Path
import hashlib
import json

root = Path('build/web')
files = sorted(p.relative_to(root).as_posix() for p in root.rglob('*')
               if p.is_file() and p.name not in ('sw.js', 'flutter_service_worker.js')
               and not p.name.endswith('.map'))
version = hashlib.sha256(b''.join((root / p).read_bytes() for p in files)).hexdigest()[:16]
script = r'''
const CACHE = 'osmo360-__VERSION__';
const FILES = __FILES__;
const scope = new URL(self.registration.scope);
self.addEventListener('install', event => {
  // An incomplete cache never replaces the working app. New versions wait for all
  // old tabs to close; no skipWaiting during a live shooting session.
  event.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES.map(p=>new URL(p,scope).href))));
});
self.addEventListener('activate', event => event.waitUntil((async()=>{
  for(const key of await caches.keys()) if(key.startsWith('osmo360-')&&key!==CACHE) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
  const u=new URL(event.request.url);
  if(event.request.method!=='GET'||u.origin!==scope.origin||!u.pathname.startsWith(scope.pathname))return;
  const relative=u.pathname.slice(scope.pathname.length);
  if(event.request.mode==='navigate') {
    event.respondWith(caches.open(CACHE).then(async c=>(await c.match(new URL('index.html',scope).href))||fetch(event.request)));
    return;
  }
  if(!FILES.includes(relative))return;
  event.respondWith(caches.open(CACHE).then(async c=>(await c.match(new URL(relative,scope).href))||fetch(event.request)));
});
'''.replace('__VERSION__', version).replace('__FILES__', json.dumps(files))
(root / 'sw.js').write_text(script)
(root / '.nojekyll').touch()
print(f'PWA cache {version}: {len(files)} local assets')
