import 'dart:convert';
import 'package:flutter/services.dart';
import 'bridge_interface.dart';

DeviceBridge createBridge() => NativeBridge();

class NativeBridge implements DeviceBridge {
  static const _methods = MethodChannel('osmo360/device');
  static const _events = EventChannel('osmo360/events');
  @override
  late final events = _events.receiveBroadcastStream().map(
    (event) =>
        Map<String, dynamic>.from(event is String ? jsonDecode(event) : event),
  );
  @override
  Future<dynamic> call(String method, [Map<String, dynamic> args = const {}]) =>
      _methods.invokeMethod(method, args);
}
