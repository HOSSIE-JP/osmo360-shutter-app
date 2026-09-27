# Project instructions

- Flutter UI and Dart capture/protocol core are shared by Android and web.
- Foreground only. Hidden/inactive/disconnected sessions pause and need explicit resume.
- Never automatically resend a shutter command. ACK is not photo-save confirmation.
- Require a fresh confirmed panorama photo mode (0x3f) before any shutter.
- Missing or stale sensors must never be interpreted as stationary.
- Preserve fix timestamps, horizontal/vertical accuracy and altitude reference.
- Session logs and location history stay local. No analytics or server uploads.
- Do not commit device logs, locations, credentials, signing keys or upstream SDK source.
- Run flutter analyze, flutter test and node --test test/web_bridge_test.cjs.
- Deploy the Flutter web release from osmo360-shutter-app via GitHub Pages Actions.
- Hardware validation is performed by the owner; never report simulated results as hardware-tested.
