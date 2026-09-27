import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:osmo360_shutter_app/core/protocol.dart';
import 'package:osmo360_shutter_app/core/models.dart';

void main() {
  final golden = Uint8List.fromList([
    0xaa,
    0x1b,
    0,
    1,
    0,
    0,
    0,
    0,
    5,
    0,
    0x57,
    0xee,
    0x1d,
    4,
    0,
    0,
    0x33,
    0xff,
    0x0a,
    1,
    0x47,
    0x39,
    0x36,
    0xf4,
    0xfa,
    0xe1,
    0xd0,
  ]);
  test('matches the independently published DJI mode-switch vector', () {
    final f = Frame(
      0x1d,
      4,
      5,
      1,
      Uint8List.fromList([0, 0, 0x33, 0xff, 0x0a, 1, 0x47, 0x39, 0x36]),
    );
    expect(f.encode(), golden);
  });
  test('accepts every possible ATT split and coalesced frames', () {
    for (var cut = 1; cut < golden.length; cut++) {
      final decoder = FrameDecoder();
      expect(decoder.add(golden.sublist(0, cut)), isEmpty);
      expect(decoder.add(golden.sublist(cut)).single.id, 4);
    }
    expect(FrameDecoder().add([...golden, ...golden]).length, 2);
  });
  test('recovers after garbage, invalid length, header CRC and body CRC', () {
    final corrupt = Uint8List.fromList(golden)..[18] = 1;
    final d = FrameDecoder();
    expect(
      d.add([0, 0xaa, 0xff, 0xff, ...golden, ...corrupt, ...golden]).length,
      2,
    );
    expect(d.rejected, greaterThan(0));
  });
  test('GPS preserves signed coordinates, mm and UTC+8 date rollover', () {
    final f = GeoFix(
      lat: -33.86,
      lon: 151.2,
      accuracy: 6,
      altitude: 23.4,
      verticalAccuracy: 9,
      speed: 2,
      heading: 90,
      time: DateTime.utc(2026, 9, 26, 23, 59, 58),
      receivedAt: 0,
    );
    final d = ByteData.sublistView(gpsPayload(f));
    expect(d.getInt32(0, Endian.little), 20260927);
    expect(d.getInt32(4, Endian.little), 75958);
    expect(d.getInt32(12, Endian.little), -338600000);
    expect(d.getInt32(16, Endian.little), 23400);
    expect(d.getFloat32(24, Endian.little), closeTo(200, .001));
    expect(d.getUint32(40, Endian.little), 0xffffffff);
    expect(d.getUint32(44, Endian.little), 0);
  });
  test('missing altitude is never silently encoded as sea level', () {
    expect(
      () => gpsPayload(
        GeoFix(
          lat: 0,
          lon: 0,
          accuracy: 1,
          time: DateTime.utc(2026),
          receivedAt: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
  test('short status cannot become a ready camera', () {
    expect(CameraStatus.parse(Uint8List(37), 0), isNull);
  });
}
