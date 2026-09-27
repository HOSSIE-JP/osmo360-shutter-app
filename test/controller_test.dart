import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:osmo360_shutter_app/core/controller.dart';
import 'package:osmo360_shutter_app/core/models.dart';
import 'package:osmo360_shutter_app/core/protocol.dart';
import 'package:osmo360_shutter_app/platform/bridge_interface.dart';

class MemoryBridge implements DeviceBridge {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final Map<String, String> saved = {};
  final List<Map<String, dynamic>> exports = [];
  int writes = 0;
  final List<List<int>> packets = [];
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  Completer<void>? saveGate;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    switch (method) {
      case 'load':
        return saved[args['key']];
      case 'save':
        if (args['key'] == 'current' && saveGate != null)
          await saveGate!.future;
        saved[args['key']] = args['value'];
      case 'remove':
        saved.remove(args['key']);
      case 'write':
        writes++;
        packets.add(List<int>.from(args['bytes']));
        if (writeStarted != null && !writeStarted!.isCompleted)
          writeStarted!.complete();
        if (writeGate != null) await writeGate!.future;
      case 'export':
        exports.add(Map.from(args));
      case 'capabilities':
        return <String, dynamic>{};
    }
    return null;
  }
}

void main() {
  Future<(AppController, MemoryBridge)> setup() async {
    final b = MemoryBridge();
    final controller = AppController(b);
    addTearDown(() {
      controller.dispose();
      b.stream.close();
    });
    await controller.initialize();
    return (controller, b);
  }

  test(
    'project CRUD isolates sessions and never exports the map key',
    () async {
      final (c, b) = await setup();
      final first = c.selectedProjectId;
      await c.saveMapKey('test-private-key');
      await c.enableDemo();
      await c.startSession();
      await c.shutter();
      await c.stopSession();
      expect(c.projectSessions.single['shots'], hasLength(1));
      await c.createProject('山道', '高低差のある撮影');
      final second = c.selectedProjectId;
      expect(c.projectSessions, isEmpty);
      await c.editProject(second, '山道 B', '編集済み');
      expect(c.projectName, '山道 B');
      await c.selectProject(first);
      await c.exportProject();
      final exported = b.exports.single['content'] as String;
      expect(exported, contains('shots'));
      expect(exported, isNot(contains('test-private-key')));
      await c.deleteProject(first);
      expect(c.sessions, isEmpty);
      expect(c.selectedProjectId, second);
    },
  );
  test(
    'stopped and deleted sessions do not reappear after persistence or reload',
    () async {
      final (c, b) = await setup();
      await c.enableDemo();
      await c.startSession();
      await c.shutter();
      await c.stopSession();
      expect(b.saved.containsKey('current'), isFalse);
      await c.persist();
      expect(b.saved.containsKey('current'), isFalse);
      await c.deleteSession(c.sessions.single['id']);
      await c.selectProject(c.selectedProjectId);
      expect(c.sessions, isEmpty);
      expect(jsonDecode(b.saved['sessions']!), isEmpty);
    },
  );
  test(
    'stop during durable reservation cancels IO and leaves no active record',
    () async {
      final (c, b) = await setup();
      await c.enableDemo();
      await c.startSession();
      b.saveGate = Completer<void>();
      final shot = c.shutter();
      await Future<void>.delayed(Duration.zero);
      final stop = c.stopSession();
      b.saveGate!.complete();
      await Future.wait([shot, stop]);
      expect(b.writes, 0);
      expect(c.engine.active, isFalse);
      expect(b.saved.containsKey('current'), isFalse);
      expect(c.sessions.single['shots'][0]['result'], 'unknown');
    },
  );
  test(
    'interrupted pending shots recover as unknown without camera writes',
    () async {
      final b = MemoryBridge();
      b.saved['current'] = jsonEncode({
        'id': 'interrupted',
        'shots': [
          {'result': 'requested', 'note': ''},
        ],
        'track': [],
      });
      final c = AppController(b);
      addTearDown(() {
        c.dispose();
        b.stream.close();
      });
      await c.initialize();
      expect(c.sessions.single['interrupted'], isTrue);
      expect(c.sessions.single['shots'][0]['result'], 'unknown');
      expect(c.engine.active, isFalse);
      expect(b.writes, 0);
      expect(b.saved.containsKey('current'), isFalse);
    },
  );
  test(
    'GPS queued behind a command is cancelled when the session pauses',
    () async {
      final (c, b) = await setup();
      c.engine.connected = true;
      c.engine.authorized = true;
      await c.startSession();
      b.writeStarted = Completer<void>();
      b.writeGate = Completer<void>();
      final modeChange = c.photoMode();
      await b.writeStarted!.future;
      c.engine.location(
        GeoFix(
          lat: 0,
          lon: 0,
          accuracy: 3,
          altitude: 10,
          time: c.utc,
          receivedAt: c.now,
        ),
        c.now,
        c.utc,
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
      c.engine.pause('test pause');
      b.writeGate!.complete();
      final request = FrameDecoder().add(b.packets.single).single;
      b.stream.add({
        'type': 'bytes',
        'bytes': Frame(
          0x1d,
          4,
          request.sequence,
          0x20,
          Uint8List.fromList([0]),
        ).encode().toList(),
      });
      await modeChange;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(b.writes, 1, reason: 'Only the mode command may reach the device');
      expect(c.gpsForwardingStatus, contains('一時停止'));
    },
  );
  test('demo and stopped sessions never claim GPS transmission', () async {
    final (c, _) = await setup();
    expect(c.gpsForwardingStatus, 'GPS送信停止中');
    await c.enableDemo();
    await c.startSession();
    expect(c.gpsForwardingStatus, contains('実機へのGPS送信なし'));
    await c.stopSession();
    expect(c.gpsForwardingStatus, isNot(contains('GPS送信中')));
  });
}
