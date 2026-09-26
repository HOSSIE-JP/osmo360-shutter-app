"""Read-only deployment check of actual public PWA assets; no browser/device claims."""
import json
import os
import struct
import time
from urllib.request import urlopen, Request
from urllib.parse import urljoin

base = os.environ['PAGES_URL']
assert base.startswith('https://hossie-jp.github.io/osmo360-shutter-app/')
def get(path):
    url = urljoin(base, path)
    for attempt in range(4):
        try:
            with urlopen(Request(url, headers={'Cache-Control': 'no-cache'}), timeout=15) as response:
                assert response.status == 200, (url, response.status)
                return response.read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(3)
index = get('').decode()
assert '<title>Osmo 360 Shutter</title>' in index
assert '<base href="/osmo360-shutter-app/">' in index
manifest = json.loads(get('manifest.json'))
assert manifest['display'] == 'standalone'
assert manifest['start_url'] == './' and manifest['scope'] == './'
for icon in manifest['icons']:
    data = get(icon['src'])
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == tuple(map(int, icon['sizes'].split('x')))
worker = get('sw.js').decode()
assert "const entry=FILES.includes(relative)" in worker
assert 'map.html' in worker and 'main.dart.js' in worker
assert len(get('main.dart.js')) > 10000
assert b'flutter' in get('flutter_bootstrap.js')
assert b'maps.googleapis.com/maps/api/js' in get('map.html')
print('PASS: public HTTPS entry, manifest, all PWA icons, worker, Flutter bundle and map page')
