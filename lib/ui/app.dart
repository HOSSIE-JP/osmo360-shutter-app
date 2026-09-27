import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/capture_engine.dart';
import '../core/models.dart';
import 'track_view.dart';
import 'map_widget.dart';

const muted = Color(0xff8e9eaf),
    surface = Color(0xff141d27),
    border = Color(0xff26323e);

class ShutterApp extends StatelessWidget {
  const ShutterApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Osmo 360 Shutter',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: cyan,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: const Color(0xff0b1119),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff0b1119),
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xff101923),
        indicatorColor: cyan.withValues(alpha: .15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: const Color(0xff082323),
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.onlyForDiscrete,
      ),
      dividerColor: border,
    ),
    home: Home(controller: controller),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.controller});
  final AppController controller;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int page = 0;
  bool showMap = true;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c.engine.visibility(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) c.persist();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 940;
      final body = SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              Container(
                width: 94,
                height: double.infinity,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: border)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.camera_rounded, color: cyan, size: 32),
                    const SizedBox(height: 36),
                    Expanded(
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        selectedIndex: page,
                        onDestinationSelected: (v) => setState(() => page = v),
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.radio_button_checked),
                            label: Text('撮影'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.route_outlined),
                            label: Text('軌跡'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history_rounded),
                            label: Text('プロジェクト'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.tune_rounded),
                            label: Text('設定'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 32 : 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(wide),
                        const SizedBox(height: 24),
                        if (c.error.isNotEmpty)
                          _banner(
                            c.error,
                            Icons.info_outline,
                            () => setState(() => c.error = ''),
                          ),
                        if (c.storageError.isNotEmpty)
                          _banner(c.storageError, Icons.storage_rounded, null),
                        if (c.demo)
                          _banner(
                            'デモモード · カメラには送信しません',
                            Icons.science_outlined,
                            null,
                          ),
                        switch (page) {
                          0 => _capture(wide),
                          1 => _route(),
                          2 => _history(),
                          _ => _settings(),
                        },
                        const SizedBox(height: 24),
                        const Center(
                          child: Text(
                            'OSMO 360 SHUTTER  /  v0.1  ·  FOREGROUND',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.8,
                              color: Color(0xff516577),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return Scaffold(
        body: body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (v) => setState(() => page = v),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.radio_button_checked),
                    label: '撮影',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.route_outlined),
                    label: '軌跡',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    label: 'プロジェクト',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_rounded),
                    label: '設定',
                  ),
                ],
              ),
      );
    },
  );
  Widget _header(bool wide) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OSMO 360',
              style: TextStyle(
                color: cyan,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              [
                'Walk. Stop. Capture.',
                'Your walk, mapped.',
                'Your projects.',
                'Make it your rhythm.',
              ][page],
              style: TextStyle(
                fontSize: wide ? 30 : 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              [
                '歩いて、止まって、360°を残す。',
                '撮影ポイントと移動の軌跡。',
                'プロジェクトごとに、撮影を記録。',
                '撮影の間隔と静止判定を調整。',
              ][page],
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (wide) const _StatusPill(Icons.circle, '前面利用', cyan),
      const SizedBox(width: 10),
      IconButton(
        tooltip: 'アプリをインストール',
        onPressed: c.install,
        icon: const Icon(Icons.install_mobile_outlined, color: muted),
      ),
    ],
  );
  Widget _banner(String text, IconData icon, VoidCallback? close) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff322a21),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xffffc77d), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xffffd9a9)),
            ),
          ),
          if (close != null)
            IconButton(
              onPressed: close,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    ),
  );
  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      Card(
        child: Padding(padding: padding, child: child),
      );
  Widget _capture(bool wide) {
    final left = Column(
      children: [
        _projectSelector(),
        const SizedBox(height: 18),
        _cameraCard(),
        const SizedBox(height: 18),
        _captureCard(),
        const SizedBox(height: 18),
        _metrics(),
      ],
    );
    final right = Column(
      children: [
        panel(
          TrackView(
            track: c.engine.track,
            shots: c.engine.shots,
            current: c.engine.fix,
          ),
        ),
        const SizedBox(height: 18),
        _sensorCard(),
        const SizedBox(height: 18),
        _recent(),
      ],
    );
    if (wide)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: left),
          const SizedBox(width: 22),
          Expanded(flex: 5, child: right),
        ],
      );
    return Column(children: [left, const SizedBox(height: 18), right]);
  }

  Widget _cameraCard() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cyan.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.link_rounded, color: cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.cameraName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.connectionLabel,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            if (c.engine.camera != null)
              Text(
                '${c.engine.camera!.battery}%',
                style: const TextStyle(color: cyan, fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: c.connecting
                    ? null
                    : () => c.connect(reconnect: true),
                icon: const Icon(Icons.bluetooth_rounded, size: 18),
                label: Text(
                  c.connecting
                      ? '接続中…'
                      : c.engine.authorized
                      ? '再接続'
                      : 'カメラを接続',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: c.engine.authorized && !c.demo ? c.photoMode : null,
                icon: const Icon(Icons.panorama_photosphere_outlined, size: 18),
                label: const Text('写真モード'),
              ),
            ),
          ],
        ),
        if (c.modeDescription.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.modeDescription,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
        if (c.engine.camera != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '残り ${c.engine.camera!.remainingPhotos} 枚',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                Text(
                  '${(c.engine.camera!.capacityMb / 1024).toStringAsFixed(1)} GB 空き',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                Text(
                  c.engine.camera!.temperature == 0
                      ? '温度 正常'
                      : '温度警告 ${c.engine.camera!.temperature}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  String get stateTitle => switch (c.engine.phase) {
    CapturePhase.idle => '撮影をはじめよう',
    CapturePhase.paused => '一時停止中',
    CapturePhase.moving => '次のポイントへ',
    CapturePhase.settle => '止まってください',
    CapturePhase.ready => 'シャッター準備',
    CapturePhase.cooldown => 'クールダウン',
    CapturePhase.cameraWait => 'カメラの処理待ち',
    CapturePhase.blocked => '準備を待っています',
  };
  String get stateDetail => switch (c.engine.phase) {
    CapturePhase.idle => 'カメラと接続し、セッションを開始',
    CapturePhase.paused => c.engine.pauseReason,
    CapturePhase.moving => '移動を検知してから、静止時に1枚撮影します',
    CapturePhase.settle => 'スマホとカメラを静止させてください',
    CapturePhase.ready => '撮影要求を送信します',
    CapturePhase.cooldown => '最小間隔とカメラ状態を確認しています',
    CapturePhase.cameraWait => '撮影動作と待機状態への復帰を確認中',
    CapturePhase.blocked => c.engine.blockReason,
  };
  Widget _captureCard() {
    final e = c.engine,
        cool = e.cooldownRemaining(c.now),
        progress = e.phase == CapturePhase.cooldown
            ? 1 - cool / c.settings.cooldownSeconds
            : e.stableProgress(c.now);
    final display = e.phase == CapturePhase.cooldown
        ? cool.toStringAsFixed(1)
        : e.phase == CapturePhase.settle
        ? '${(e.stableProgress(c.now) * 100).round()}'
        : e.distanceRemaining.toStringAsFixed(1);
    final unit = e.phase == CapturePhase.cooldown
        ? '秒'
        : e.phase == CapturePhase.settle
        ? '% 静止'
        : 'm 次の撮影まで';
    return panel(
      Column(
        children: [
          Row(
            children: [
              const Text(
                'CAPTURE SESSION',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: muted),
              ),
              const Spacer(),
              _StatusPill(
                Icons.circle,
                e.active ? (e.paused ? 'PAUSED' : 'LIVE') : 'STANDBY',
                e.active && !e.paused ? cyan : muted,
              ),
            ],
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: 216,
            height: 216,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 216,
                  height: 216,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    backgroundColor: const Color(0xff263743),
                    color: cyan,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        cyan.withValues(alpha: .08),
                        cyan.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      e.phase == CapturePhase.cooldown
                          ? Icons.timelapse_rounded
                          : Icons.directions_walk_rounded,
                      color: cyan,
                      size: 22,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      e.active ? display : '360°',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.active ? unit : 'READY TO EXPLORE',
                      style: const TextStyle(
                        fontSize: 11,
                        color: muted,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            stateTitle,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: Text(
              stateDetail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
            ),
          ),
          const SizedBox(height: 20),
          if (!e.active)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.engine.authorized ? c.startSession : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('セッションを開始'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: e.shutterBlock(c.now, c.utc) == null
                        ? () => c.shutter()
                        : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('手動シャッター'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: e.paused ? '再開' : '一時停止',
                  onPressed: c.pauseOrResume,
                  icon: Icon(
                    e.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'セッションを終了',
                  onPressed: c.stopSession,
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
            ),
          if (c.demo && e.active)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: c.demoStep,
                icon: const Icon(Icons.directions_walk),
                label: const Text('デモ：1歩進む'),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            '撮影間隔 ${c.settings.intervalM.toStringAsFixed(1)} m  ·  静止 ${c.settings.stableSeconds.toStringAsFixed(1)} 秒',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _metrics() => Row(
    children: [
      Expanded(
        child: _metric(
          '撮影要求',
          '${c.engine.shots.length}',
          '回',
          Icons.camera_alt_outlined,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _metric(
          '推定移動',
          c.engine.totalDistance.toStringAsFixed(1),
          'm',
          Icons.route,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _metric(
          c.engine.nativeSteps ? '歩数' : '推定歩数',
          '${c.engine.steps}',
          '歩',
          Icons.directions_walk_rounded,
        ),
      ),
    ],
  );
  Widget _metric(String label, String value, String unit, IconData icon) =>
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: muted, size: 18),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 4,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(unit, style: const TextStyle(color: muted, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ),
        padding: const EdgeInsets.all(16),
      );
  Widget _sensorCard() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'センサーと測位',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 20),
        _sensorLine(
          Icons.location_on_outlined,
          'GPS',
          c.engine.gpsValid(c.now, c.utc)
              ? '±${c.engine.fix!.accuracy.toStringAsFixed(1)} m'
              : '位置情報待ち',
          c.engine.gpsValid(c.now, c.utc),
        ),
        const SizedBox(height: 16),
        _sensorLine(
          Icons.sensors_rounded,
          '静止判定',
          c.engine.motionFresh(c.now)
              ? '${c.engine.gyro.toStringAsFixed(3)} rad/s'
              : 'センサー待ち',
          c.engine.motionFresh(c.now),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: c.engine.stableProgress(c.now),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
          backgroundColor: border,
          color: cyan,
        ),
        const SizedBox(height: 10),
        Text(
          '加速度 ${c.engine.acceleration.toStringAsFixed(2)} m/s²  ·  静止を ${c.settings.stableSeconds.toStringAsFixed(1)} 秒継続',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        if (c.engine.fix != null) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          SelectableText(
            '${c.engine.fix!.lat.toStringAsFixed(6)}, ${c.engine.fix!.lon.toStringAsFixed(6)}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '高度 ${c.engine.fix!.altitude?.toStringAsFixed(1) ?? '—'} m  ·  ${c.gpsForwardingStatus}',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ],
    ),
  );
  Widget _sensorLine(IconData icon, String name, String value, bool good) =>
      Row(
        children: [
          Icon(icon, color: muted, size: 20),
          const SizedBox(width: 10),
          Text(name, style: const TextStyle(fontSize: 12)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: good ? cyan : muted),
          ),
        ],
      );
  Widget _recent() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '最近の撮影',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => page = 2),
              child: const Text('すべて'),
            ),
          ],
        ),
        if (c.engine.shots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              '最初の1枚を待っています。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          )
        else
          ...c.engine.shots.reversed.take(3).map(_shotRow),
      ],
    ),
  );
  Widget _shotRow(Shot s) => InkWell(
    onTap: () => _shotDetails(s),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cyan.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${s.number.toString().padLeft(2, '0')}',
              style: const TextStyle(color: cyan, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  '${_time(s.at)} · ${s.manual ? '手動' : '自動'} · ${s.fix == null ? 'GPSなし' : '±${s.fix!.accuracy.toStringAsFixed(0)} m'}',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Icon(
            s.result == ShotResult.actionObserved
                ? Icons.check_circle_outline
                : Icons.pending_outlined,
            size: 18,
            color: s.result == ShotResult.actionObserved
                ? const Color(0xffd5f7a5)
                : const Color(0xffffc77d),
          ),
        ],
      ),
    ),
  );
  String _time(DateTime t) =>
      '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}:${t.toLocal().second.toString().padLeft(2, '0')}';
  Widget _route() => Column(
    children: [
      if (c.mapsApiKey.isNotEmpty) ...[
        _mapCard(c.engine.track, c.engine.shots, c.engine.fix),
        const SizedBox(height: 18),
      ],
      panel(
        TrackView(
          track: c.engine.track,
          shots: c.engine.shots,
          current: c.engine.fix,
          large: true,
        ),
      ),
      const SizedBox(height: 18),
      panel(AltitudeChart(track: c.engine.track)),
      const SizedBox(height: 18),
      _exports(null),
      const SizedBox(height: 10),
      const Text(
        'APIキー未設定時は相対座標表示のみ。地図の表示時はGoogleへ表示位置を送ります。',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ],
  );
  Widget _exports(Map<String, dynamic>? data) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final format in ['json', 'csv', 'gpx'])
        OutlinedButton.icon(
          onPressed: () => c.export(data: data, format: format),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text('${format.toUpperCase()} 書き出し'),
        ),
    ],
  );
  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _projectSelector(manage: true),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.engine.active ? '現在のセッション' : '直前のセッション',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '「撮影動作を検知」は保存完了の保証ではありません。',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            _exports(null),
            const SizedBox(height: 12),
            if (c.engine.shots.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('まだ撮影要求はありません。', style: TextStyle(color: muted)),
              )
            else
              ...c.engine.shots.reversed.take(100).map(_shotRow),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        '保存したセッション',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 6),
      const Text(
        '選択中のプロジェクト内のセッション。詳細から撮影地点・時刻・GPSを確認できます。',
        style: TextStyle(color: muted, fontSize: 11),
      ),
      const SizedBox(height: 14),
      if (c.projectSessions.isEmpty)
        panel(
          const SizedBox(
            width: double.infinity,
            child: Text('セッション終了後にここへ保存されます。', style: TextStyle(color: muted)),
          ),
        )
      else
        ...c.projectSessions.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s['demo'] == true ? 'DEMO · ' : ''}${s['id']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '履歴を削除',
                        onPressed: () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('この履歴を削除しますか？'),
                              content: const Text('書き出していない記録は復元できません。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('キャンセル'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('削除'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) await c.deleteSession(s['id']);
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(s['shots'] as List?)?.length ?? 0} 回の要求 · ${s['steps'] ?? 0} 歩${s['interrupted'] == true ? ' · 中断から復元' : ''}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _sessionDetails(s),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('撮影詳細・軌跡を見る'),
                  ),
                  const SizedBox(height: 12),
                  _exports(s),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 20),
      panel(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('通信・動作ログ', style: TextStyle(fontSize: 16)),
          subtitle: Text(
            'CRCエラー ${c.decoder.rejected} · 最新 ${c.logs.length} 件',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          children: [
            SizedBox(
              height: 280,
              child: ListView.builder(
                itemCount: math.min(100, c.logs.length),
                itemBuilder: (context, index) {
                  final item = c.logs[c.logs.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: SelectableText(
                      '${item['elapsedMs']}  ${item['kind']}  ${item['message']}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ],
  );
  void _change(void Function() action) {
    if (c.engine.active && !c.engine.paused)
      c.engine.pause('設定を変更しました。再開してください');
    action();
    c.saveSettings();
    setState(() {});
  }

  Widget _slider(
    String title,
    String help,
    double value,
    double min,
    double max,
    int divisions,
    String unit,
    void Function(double) setter,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
            Text(
              '${value.toStringAsFixed(2)} $unit',
              style: const TextStyle(
                color: cyan,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(help, style: const TextStyle(fontSize: 11, color: muted)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          semanticFormatterCallback: (v) => '$title ${v.toStringAsFixed(2)} $unit',
          onChanged: (v) => _change(() => setter(v)),
        ),
      ],
    ),
  );

  Widget _projectSelector({bool manage = false}) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_outlined, color: cyan, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '撮影プロジェクト',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '新規プロジェクト',
              onPressed: c.engine.active ? null : () => _projectDialog(),
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(c.selectedProjectId),
          initialValue: c.selectedProjectId.isEmpty
              ? null
              : c.selectedProjectId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          hint: const Text('プロジェクトを作成してください'),
          items: c.projects
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p['id'],
                  child: Text(p['name'], overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: c.engine.active
              ? null
              : (id) {
                  if (id != null) c.selectProject(id);
                },
        ),
        if (manage && c.selectedProjectId.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            c.projects.firstWhere(
                  (p) => p['id'] == c.selectedProjectId,
                )['description'] ??
                '',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            '${c.projectSessions.length} セッション · ${c.projectSessions.fold<int>(0, (sum, s) => sum + ((s['shots'] as List?)?.length ?? 0))} 撮影要求',
            style: const TextStyle(color: cyan, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _projectDialog(edit: true),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('編集'),
              ),
              OutlinedButton.icon(
                onPressed: c.exportProject,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('全体を書き出し'),
              ),
              OutlinedButton.icon(
                onPressed: c.engine.active ? null : _deleteProject,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('削除'),
              ),
            ],
          ),
        ],
        if (c.engine.active)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'プロジェクトの切り替えはセッション終了後に行えます。',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ),
      ],
    ),
  );
  Future<void> _projectDialog({bool edit = false}) async {
    final project = edit
        ? c.projects.firstWhere((p) => p['id'] == c.selectedProjectId)
        : null;
    final name = TextEditingController(text: project?['name'] ?? ''),
        description = TextEditingController(
          text: project?['description'] ?? '',
        );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(edit ? 'プロジェクトを編集' : '新規プロジェクト'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'プロジェクト名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '説明・メモ'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      if (edit) {
        await c.editProject(c.selectedProjectId, name.text, description.text);
      } else {
        await c.createProject(name.text, description.text);
      }
    }
    name.dispose();
    description.dispose();
  }

  Future<void> _deleteProject() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${c.projectName}」を削除？'),
        content: const Text(
          'このプロジェクト内の全セッションと撮影・GPS履歴を削除します。必要な場合は先に書き出してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('プロジェクトを削除'),
          ),
        ],
      ),
    );
    if (accepted == true) await c.deleteProject(c.selectedProjectId);
  }

  Future<void> _mapKeyDialog() async {
    final keyController = TextEditingController(text: c.mapsApiKey);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Maps APIキー'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: keyController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Maps JavaScript API key',
              helperText: '空欄で保存すると地図を無効化します',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted == true) await c.saveMapKey(keyController.text);
    keyController.dispose();
  }

  Widget _mapCard(List<GeoFix> track, List<Shot> shots, GeoFix? current) =>
      panel(
        Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Googleマップ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '通信・APIキーが必要です',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              value: showMap,
              onChanged: (v) => setState(() => showMap = v),
            ),
            if (showMap)
              GoogleMapPanel(
                key: ValueKey(c.mapsApiKey),
                config: {
                  'key': c.mapsApiKey,
                  'track': track.map((p) => p.toJson()).toList(),
                  'shots': shots.map((p) => p.toJson()).toList(),
                  'current': current?.toJson(),
                },
              ),
          ],
        ),
      );
  Future<void> _shotDetails(Shot shot) async {
    final f = shot.fix;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('撮影 #${shot.number}'),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              '状態: ${shot.label}',
              '要求時刻: ${shot.at.toLocal()}',
              'UTC: ${shot.at.toIso8601String()}',
              '操作: ${shot.manual ? '手動' : '自動'}',
              'カメラ応答: ${shot.acknowledged ? '要求を受理' : '未確認'}',
              '緯度: ${f?.lat.toStringAsFixed(7) ?? '—'}',
              '経度: ${f?.lon.toStringAsFixed(7) ?? '—'}',
              '水平精度: ${f?.accuracy.toStringAsFixed(1) ?? '—'} m',
              '高度: ${f?.altitude?.toStringAsFixed(1) ?? '—'} m',
              '垂直精度: ${f?.verticalAccuracy?.toStringAsFixed(1) ?? '—'} m',
              '高度基準: ${f?.altitudeReference ?? '—'}',
              '測位時刻: ${f?.time.toIso8601String() ?? '—'}',
              if (shot.note.isNotEmpty) '注記: ${shot.note}',
              '画像ファイルの保存・GPS埋め込みは実画像で確認してください。',
            ].join('\n'),
            style: const TextStyle(fontSize: 13, height: 1.9),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _sessionDetails(Map<String, dynamic> data) async {
    final shots = (data['shots'] as List? ?? [])
        .map((s) => Shot.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    final track = (data['track'] as List? ?? [])
        .map((p) => GeoFix.fromJson(Map<String, dynamic>.from(p), 0))
        .whereType<GeoFix>()
        .toList();
    final observed = shots
        .where((s) => s.result == ShotResult.actionObserved)
        .length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'セッション詳細',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'セッション詳細を閉じる',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  data['id'] ?? '',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 12),
                Text(
                  '撮影要求 ${shots.length} 回 · 撮影動作検知 $observed 回 · ${data['steps'] ?? 0} 歩',
                  style: const TextStyle(fontSize: 13, color: cyan),
                ),
                const SizedBox(height: 20),
                TrackView(track: track, shots: shots, large: true),
                const SizedBox(height: 20),
                AltitudeChart(track: track),
                const SizedBox(height: 16),
                _exports(data),
                const SizedBox(height: 16),
                ...shots.map(_shotRow),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settings() => Column(
    children: [
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '地図APIキー',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              'Google Maps JavaScript APIのキーを設定すると地図を表示できます。未入力でも2D／3Dの相対座標・撮影履歴は利用できます。',
              style: TextStyle(fontSize: 12, color: muted, height: 1.7),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.mapsApiKey.isEmpty ? 'APIキー未設定' : 'APIキー設定済み',
                    style: const TextStyle(color: cyan, fontSize: 13),
                  ),
                ),
                OutlinedButton(
                  onPressed: _mapKeyDialog,
                  child: const Text('キーを設定'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'キーは端末内に保存し、ログ・プロジェクト書き出しには含めません。Google Cloudで課金・Maps JavaScript APIを有効にし、使用元を hossie-jp.github.io に制限してください。',
              style: TextStyle(fontSize: 11, color: muted, height: 1.7),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '撮影のリズム',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _slider(
              '撮影間隔',
              '歩数 × 歩幅で推定します',
              c.settings.intervalM,
              .5,
              20,
              39,
              'm',
              (v) => c.settings.intervalM = v,
            ),
            _slider(
              '最小クールダウン',
              'カメラの処理待ちは別に確認します',
              c.settings.cooldownSeconds,
              1,
              30,
              58,
              '秒',
              (v) => c.settings.cooldownSeconds = v,
            ),
            _slider(
              '静止する時間',
              '連続して揺れが小さくなったら撮影',
              c.settings.stableSeconds,
              .5,
              5,
              18,
              '秒',
              (v) => c.settings.stableSeconds = v,
            ),
            _slider(
              '1歩あたりの歩幅',
              '例：10 mを15歩で歩いた場合は0.67 m',
              c.settings.strideM,
              .2,
              1.2,
              100,
              'm',
              (v) => c.settings.strideM = v,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPSと通知',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('撮影にGPSを必須とする', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '古い位置・精度不足では撮影を保留',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              value: c.settings.requireGps,
              onChanged: (v) => _change(() => c.settings.requireGps = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('カメラへGPSを送信', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '有効な位置と高度を1秒ごとに送信',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              value: c.settings.forwardGps,
              onChanged: (v) => _change(() => c.settings.forwardGps = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('音声ガイド', style: TextStyle(fontSize: 14)),
              value: c.settings.voice,
              onChanged: (v) => _change(() => c.settings.voice = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('通知音', style: TextStyle(fontSize: 14)),
              value: c.settings.sound,
              onChanged: (v) => _change(() => c.settings.sound = v),
            ),
            OutlinedButton.icon(
              onPressed: () => c.feedback('停止してください。撮影の準備ができました'),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('通知をテスト'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      panel(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('詳細な判定・GPS設定', style: TextStyle(fontSize: 16)),
          children: [
            _slider(
              'ジャイロ閾値',
              'スマホをカメラと同じポールに固定して調整',
              c.settings.gyroThreshold,
              .01,
              .3,
              29,
              'rad/s',
              (v) => c.settings.gyroThreshold = v,
            ),
            _slider(
              '加速度の静止閾値',
              '小さい値ほど静止判定が厳しくなります',
              c.settings.accelerationThreshold,
              .1,
              1.5,
              28,
              'm/s²',
              (v) => c.settings.accelerationThreshold = v,
            ),
            _slider(
              '推定歩数のピーク閾値',
              'PWA / 歩数センサー非搭載端末用',
              c.settings.stepThreshold,
              .5,
              3,
              25,
              'm/s²',
              (v) => c.settings.stepThreshold = v,
            ),
            _slider(
              'GPSの最大水平誤差',
              'この値を超える測位は撮影判定に使いません',
              c.settings.gpsMaxAccuracy,
              3,
              50,
              47,
              'm',
              (v) => c.settings.gpsMaxAccuracy = v,
            ),
            _slider(
              'GPSの最大経過時間',
              '取得時刻と受信後の経過時間の両方を確認',
              c.settings.gpsMaxAge,
              1,
              10,
              18,
              '秒',
              (v) => c.settings.gpsMaxAge = v,
            ),
            DropdownButtonFormField<int>(
              initialValue: c.settings.gpsTimeOffset,
              decoration: const InputDecoration(labelText: 'カメラ送信時刻の基準'),
              items: const [
                DropdownMenuItem(value: 8, child: Text('公式例：UTC+8（日付繰り上げ対応）')),
                DropdownMenuItem(value: 0, child: Text('UTC（実機検証用）')),
              ],
              onChanged: (v) {
                if (v != null) _change(() => c.settings.gpsTimeOffset = v);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              '衛星数・速度精度の不明値は実機ログで確認が必要です。画像へのGPS保存と時刻は元画像で検証してください。',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '接続前の確認',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. カメラの電源とBluetoothをON\n2. スマホをカメラと同じポールへ固定\n3. Bluetooth・位置情報・センサーを許可\n4. 接続後、カメラ画面の確認コードを承認\n5. パノラマ写真モードと写真設定を確認',
              style: TextStyle(fontSize: 12, color: muted, height: 1.9),
            ),
            const SizedBox(height: 18),
            const Text(
              'アプリは前面のまま使用します。非表示・切断時は一時停止し、未確定のシャッターを自動再送しません。',
              style: TextStyle(fontSize: 11, color: muted, height: 1.7),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: c.enableDemo,
              icon: const Icon(Icons.science_outlined),
              label: const Text('カメラなしでデモを試す'),
            ),
            const SizedBox(height: 10),
            Text(
              'BLE: ${c.capabilities['bluetooth'] == true ? '利用可能' : '非対応 / 要確認'}  ·  ${c.capabilities['platform'] ?? '確認中'}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .14)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 7),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
      ],
    ),
  );
}
