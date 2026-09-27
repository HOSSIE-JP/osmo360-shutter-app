abstract class DeviceBridge {
  Stream<Map<String, dynamic>> get events;
  Future<dynamic> call(String method, [Map<String, dynamic> args = const {}]);
}
