import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'bridge_interface.dart';

@JS('osmoInvoke')
external JSPromise<JSString> _invoke(JSString method, JSString args);
@JS('osmoListen')
external void _listen(JSFunction callback);
DeviceBridge createBridge() => WebBridge();

class WebBridge implements DeviceBridge {
  WebBridge() {
    _listen(
      ((JSString value) {
        _events.add(Map<String, dynamic>.from(jsonDecode(value.toDart)));
      }).toJS,
    );
  }
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await _invoke(method.toJS, jsonEncode(args).toJS).toDart;
    final decoded = jsonDecode(result.toDart) as Map<String, dynamic>;
    if (decoded['error'] != null) throw StateError(decoded['error'].toString());
    return decoded['value'];
  }
}
