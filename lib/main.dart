import 'package:flutter/material.dart';
import 'core/controller.dart';
import 'platform/device_bridge.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(createBridge());
  runApp(ShutterApp(controller: controller));
  controller.initialize();
}
