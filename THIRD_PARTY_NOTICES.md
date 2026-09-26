# Reference protocols and third-party components

- DJI R SDK / Osmo GPS Controller Demo: https://github.com/dji-sdk/Osmo-GPS-Controller-Demo
  - Wire protocol: `docs/protocol.md` and `docs/protocol_data_segment.md`.
  - Data structures and CRC reference: `protocol/dji_protocol_data_structures.h`, `utils/crc/custom_crc16.*`, `utils/crc/custom_crc32.*`.
  - Upstream LICENSE contains both DJI EULA notices and an MIT section. Refer to the upstream LICENSE and https://developer.dji.com/policies/eula/ for their terms. This repository does not redistribute upstream source or documentation. Its Dart wire implementation is separately written from the published specification.
- Flutter and Dart retain their respective upstream licenses. Standard Android wrapper files are generated from the installed Flutter SDK.
- Google Maps is loaded only when the user supplies a Maps JavaScript API key and enables the map view. Google Maps Platform terms, billing and attribution apply. No map data is stored by the service worker.
- M5Shutter (https://kotohibi.f5.si/M5/) inspired the movement→stillness→shutter workflow. No M5Shutter source or assets are copied.

This is an independent, unofficial project. DJI, Osmo and Google Maps are trademarks of their respective owners.
