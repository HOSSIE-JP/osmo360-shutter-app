import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:osmo360_shutter_app/core/controller.dart';
import 'package:osmo360_shutter_app/platform/bridge_interface.dart';
import 'package:osmo360_shutter_app/ui/app.dart';
import 'package:osmo360_shutter_app/ui/track_view.dart';

class FakeBridge implements DeviceBridge {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<dynamic> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async => null;
}

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 900)]) {
    testWidgets('Material layout fits $size and navigation works', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(FakeBridge());
      addTearDown(c.dispose);
      await tester.pumpWidget(ShutterApp(controller: c));
      expect(find.text('Walk. Stop. Capture.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('設定').last);
      await tester.pumpAndSettle();
      expect(find.text('Make it your rhythm.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('project form, saved session and 3D controls fit $size', (tester) async {
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final c=AppController(FakeBridge());addTearDown(c.dispose);
      await c.createProject('初期プロジェクト','');
      await tester.pumpWidget(ShutterApp(controller:c));
      await tester.tap(find.byTooltip('新規プロジェクト'));await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first,'画面確認プロジェクト');
      await tester.enterText(find.byType(TextField).last,'合成データ');
      await tester.tap(find.text('保存'));await tester.pumpAndSettle();
      expect(c.projectName,'画面確認プロジェクト');
      expect(tester.takeException(),isNull);
      await c.enableDemo();await c.startSession();await c.shutter();await c.stopSession();
      await tester.tap(find.text('プロジェクト').last);await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('撮影詳細・軌跡を見る'));
      await tester.tap(find.text('撮影詳細・軌跡を見る'));await tester.pumpAndSettle();
      await tester.tap(find.text('3D'));await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('拡大'));await tester.pump();
      await tester.drag(find.byType(TrackView),const Offset(35,-20));await tester.pump();
      expect(find.textContaining('撮影要求 1 回'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.tap(find.byTooltip('セッション詳細を閉じる'));await tester.pumpAndSettle();
      expect(find.text('セッション詳細'),findsNothing);
    });
  }
  testWidgets('project input stays usable above the mobile keyboard', (tester) async {
    tester.view.physicalSize=const Size(360,640);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final c=AppController(FakeBridge());addTearDown(c.dispose);
    await c.createProject('初期プロジェクト','');
    await tester.pumpWidget(ShutterApp(controller:c));
    await tester.tap(find.byTooltip('新規プロジェクト'));await tester.pumpAndSettle();
    tester.view.viewInsets=const FakeViewPadding(bottom:300);
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();
    expect(c.projects,hasLength(1));expect(tester.takeException(),isNull);
  });
}
