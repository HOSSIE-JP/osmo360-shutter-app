import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osmo360_shutter_app/core/controller.dart';
import 'package:osmo360_shutter_app/platform/bridge_interface.dart';
import 'package:osmo360_shutter_app/ui/app.dart';
class FakeBridge implements DeviceBridge {
  @override Stream<Map<String,dynamic>> get events=>const Stream.empty();
  @override Future<dynamic> call(String method,[Map<String,dynamic> args=const {}])async=>null;
}
void main(){
  for(final size in [const Size(390,844),const Size(1366,900)]) {
    testWidgets('Material layout fits $size and navigation works',(tester)async{
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final c=AppController(FakeBridge());addTearDown(c.dispose);
      await tester.pumpWidget(ShutterApp(controller:c));
      expect(find.text('Walk. Stop. Capture.'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.tap(find.text('設定').last);await tester.pumpAndSettle();
      expect(find.text('Make it your rhythm.'),findsOneWidget);expect(tester.takeException(),isNull);
    });
  }
}
