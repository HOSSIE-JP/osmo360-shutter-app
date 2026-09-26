# Architecture

## Ownership

- `lib/core/protocol.dart`: bounded streaming frame decoder, LE framing, CRC16/32, connection payload, camera status.
- `lib/core/capture_engine.dart`: deterministic capture decisions, movement token, sensor freshness, cooldown, pending shot outcome.
- `lib/core/controller.dart`: serialized device IO, request correlation, handshake, GPS forwarding, persistence and project/session lifecycle.
- `lib/core/models.dart`: settings, timestamped geolocation, quality-preserving GPS encoding, shot evidence.
- `lib/ui`: Material 3 UI, project CRUD, detail views, map-free 3D projection and optional Google map platform views.
- `web/device_bridge.js`: Web Bluetooth, DeviceMotion, geolocation, feedback, IndexedDB, download and installation.
- `android_src`: Kotlin GATT, runtime permissions, sensors, GNSS, TTS, atomic persistence, document export, map WebView.

The Dart capture state machine owns shutter decisions. UI, service worker, map HTML and native/web adapters never issue shutter commands independently. No foreground service is required because background capture is explicitly out of scope.

## Capture rules

Every shot needs an active visible session, an approved camera connection, a fresh status (≤2.5s), panorama photo mode `0x3f`, idle state, available storage, acceptable temperature and completed shared cooldown. GPS-required mode also requires original fix timestamp freshness, arrival freshness and horizontal accuracy.

Automatic capture additionally requires new movement since the previous request and uninterrupted gyro/linear-acceleration stability. A sensor gap over400ms resets the stable interval. One shot reservation synchronously consumes the movement token before any asynchronous IO, preventing duplicate requests. Manual shots use the same pending-operation lock and cooldown.

ACK correlates by sequence and only records request acceptance. Busy state after request records `actionObserved`; return to ready releases camera wait. Missing evidence times out to an explicit paused state. Disconnection and reload never replay a pending command. Post-shot records never claim that a file was saved.

## Coordinates and GPS

All original timestamps and available quality fields are retained. GNSS coordinates use 1e7 degrees, altitude/position accuracy mm, velocity cm/s; unknown satellite count remains 0. Missing altitude inhibits forwarding. The protocol's unknown quality handling and +8 hour convention require camera verification.

Near-distance capture spacing uses steps×stride, not noisy GPS displacement. Track filtering rejects gross jumps and does not add stationary jitter as distance. 3D view projects local east/north/up at the initial fix using a yaw/pitch camera; rotation and zoom do not change original points. Vertical exaggeration is1×. Height reference and accuracy remain visible in details.

## Project data

Projects have IDs, names, descriptions and timestamps. Each session has a project ID, start ID, settings snapshot, camera identity, shot evidence, track and a bounded diagnostic ring. Current session snapshots recover as interrupted history after reload. API keys are stored separately from projects and never included in exports.

Switching or deleting projects requires the session to end. Deleting a project explicitly deletes its sessions; the UI asks confirmation. Individual session deletion is also explicit. API-key-free operation makes no map-provider request; opt-in Google map views send display positions to Google.

## PWA lifecycle

Foreground only. Page visibility and Flutter lifecycle events pause capture. Screen Wake Lock is a best-effort convenience. Resume requires user interaction, reacquires sensor resources and requires new movement. The service worker caches only same-origin app assets and has no access to capture logic, BLE or geolocation.
