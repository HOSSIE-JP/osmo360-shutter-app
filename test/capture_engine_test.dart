import 'package:flutter_test/flutter_test.dart';
import 'package:osmo360_shutter_app/core/capture_engine.dart';
import 'package:osmo360_shutter_app/core/models.dart';
import 'package:osmo360_shutter_app/core/protocol.dart';

final utc = DateTime.utc(2026, 9, 27);
CameraStatus status(int now, {int mode = 0x3f, int state = 1, int temp = 0}) =>
    CameraStatus(
      mode: mode,
      state: state,
      battery: 90,
      remainingPhotos: 100,
      capacityMb: 1024,
      temperature: temp,
      power: 0,
      countdownMs: 0,
      receivedAt: now,
    );
CaptureEngine ready() =>
    CaptureEngine(
        Settings()
          ..requireGps = false
          ..intervalM = 1.4,
      )
      ..connected = true
      ..authorized = true
      ..start()
      ..status(status(0));
void walkAndSettle(CaptureEngine e, {int from = 0}) {
  e.addStep(from + 300);
  e.addStep(from + 600);
  for (var t = from + 700; t <= from + 2300; t += 100) e.motion(t, .01, .03);
  e.status(status(from + 2300));
}

void main() {
  test('walk-stop takes one photo; staying still cannot trigger another', () {
    final e = ready();
    walkAndSettle(e);
    final shot = e.reserve(2300, utc, manual: false);
    expect(shot, isNotNull);
    shot!.sequence = 7;
    e.acknowledge(7, true);
    expect(shot.result, ShotResult.requested); // ACK is not save confirmation
    e.status(status(2400, state: 3));
    e.status(status(2700));
    expect(shot.result, ShotResult.actionObserved);
    for (var t = 3000; t <= 10000; t += 100) e.motion(t, .01, .03);
    e.status(status(10000));
    expect(e.reserve(10000, utc, manual: false), isNull);
    walkAndSettle(e, from: 10000);
    expect(e.reserve(12300, utc, manual: false), isNotNull);
  });
  test('manual and automatic share one cooldown and pending command', () {
    final e = ready();
    walkAndSettle(e);
    expect(e.reserve(2300, utc, manual: true), isNotNull);
    expect(e.reserve(2301, utc, manual: true), isNull);
    e.status(status(2400, state: 3));
    e.status(status(2500));
    expect(e.reserve(2501, utc, manual: true), isNull);
    e.status(status(8400));
    expect(e.reserve(8400, utc, manual: true), isNotNull);
  });
  test('wrong mode, expired state and overtemperature block shutter', () {
    final e = ready();
    e.status(status(0, mode: 1));
    expect(e.reserve(1, utc, manual: true), isNull);
    e.status(status(0));
    expect(e.reserve(2600, utc, manual: true), isNull);
    e.status(status(2700, temp: 2));
    expect(e.reserve(2701, utc, manual: true), isNull);
  });
  test('sensor gaps and permission loss never count as stationary', () {
    final e = ready();
    walkAndSettle(e);
    e.status(status(3000));
    expect(e.reserve(3000, utc, manual: false), isNull);
    e.motion(3000, .01, .03);
    expect(e.stable(3000), isFalse);
  });
  test('hidden page pauses and does not auto-resume or replay', () {
    final e = ready();
    walkAndSettle(e);
    e.visibility(false);
    e.visibility(true);
    expect(e.paused, isTrue);
    expect(e.reserve(2400, utc, manual: true), isNull);
    e.resume();
    expect(e.hasMovement, isFalse);
  });
  test('disconnect leaves uncertain request without automatic retry', () {
    final e = ready();
    final shot = e.reserve(1, utc, manual: true)!;
    e.disconnect();
    expect(shot.result, ShotResult.unknown);
    expect(e.paused, isTrue);
    expect(e.pending, isNull);
  });
  test('missing post-shot evidence times out and requires explicit resume', () {
    final e = ready();
    final shot = e.reserve(1, utc, manual: true)!;
    e.tick(16000, utc);
    expect(shot.result, ShotResult.unknown);
    expect(e.paused, isTrue);
  });
  test('GPS requires a fresh original timestamp, not just a new callback', () {
    final e = ready();
    e.settings.requireGps = true;
    e.location(
      GeoFix(
        lat: 35,
        lon: 139,
        accuracy: 3,
        time: utc.subtract(const Duration(seconds: 30)),
        receivedAt: 0,
      ),
      0,
      utc,
    );
    expect(e.reserve(1, utc, manual: true), isNull);
    e.location(
      GeoFix(lat: 35, lon: 139, accuracy: 3, time: utc, receivedAt: 2),
      2,
      utc,
    );
    expect(e.reserve(3, utc, manual: true), isNotNull);
  });
  test('stationary GPS drift cannot satisfy movement spacing', () {
    final e = ready();
    for (var i = 0; i < 10; i++)
      e.location(
        GeoFix(
          lat: 35 + i * .00002,
          lon: 139,
          accuracy: 4,
          time: utc.add(Duration(seconds: i)),
          receivedAt: i * 1000,
        ),
        i * 1000,
        utc.add(Duration(seconds: i)),
      );
    expect(e.steps, 0);
    expect(e.hasMovement, isFalse);
    expect(e.track.length, 1);
  });
}
