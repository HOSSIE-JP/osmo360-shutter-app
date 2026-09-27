import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';

const cyan = Color(0xff65e0db);

class TrackView extends StatefulWidget {
  const TrackView({
    super.key,
    required this.track,
    required this.shots,
    this.current,
    this.large = false,
  });
  final List<GeoFix> track;
  final List<Shot> shots;
  final GeoFix? current;
  final bool large;
  @override
  State<TrackView> createState() => _TrackViewState();
}

class _TrackViewState extends State<TrackView> {
  bool threeD = false;
  double yaw = -.6, pitch = .6, zoom = 1, startZoom = 1;
  Offset lastFocal = Offset.zero;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.route_rounded, color: cyan, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '移動と撮影ポイント',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('2D')),
              ButtonSegment(value: true, label: Text('3D')),
            ],
            selected: {threeD},
            onSelectionChanged: (s) => setState(() => threeD = s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: widget.large ? 370 : 240,
          color: const Color(0xff101923),
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                if (!threeD)
                  InteractiveViewer(
                    minScale: .5,
                    maxScale: 8,
                    child: CustomPaint(
                      size: Size(c.maxWidth, widget.large ? 370 : 240),
                      painter: RoutePainter(
                        widget.track.toList(),
                        widget.shots.toList(),
                        widget.current,
                        false,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onScaleStart: (d) {
                      startZoom = zoom;
                      lastFocal = d.localFocalPoint;
                    },
                    onScaleUpdate: (d) => setState(() {
                      zoom = (startZoom * d.scale).clamp(.3, 8);
                      if (d.pointerCount == 1) {
                        final delta = d.localFocalPoint - lastFocal;
                        yaw += delta.dx * .008;
                        pitch = (pitch + delta.dy * .008).clamp(-1.4, 1.4);
                      }
                      lastFocal = d.localFocalPoint;
                    }),
                    child: CustomPaint(
                      size: Size(c.maxWidth, widget.large ? 370 : 240),
                      painter: RoutePainter(
                        widget.track.toList(),
                        widget.shots.toList(),
                        widget.current,
                        true,
                        yaw: yaw,
                        pitch: pitch,
                        zoom: zoom,
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Text(
                    threeD ? '相対座標 · 高さ×1' : 'N ↑   相対座標',
                    style: const TextStyle(
                      color: Color(0xff8598a8),
                      fontSize: 11,
                    ),
                  ),
                ),
                if (widget.track.isEmpty && widget.current == null)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.explore_outlined,
                          size: 40,
                          color: Color(0xff42616c),
                        ),
                        SizedBox(height: 12),
                        Text('歩いた軌跡を、ここに。'),
                        SizedBox(height: 4),
                        Text(
                          'セッション開始後にGPS位置を表示',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xff8598a8),
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Text(
                    threeD ? 'ドラッグで回転 · ピンチで拡大' : 'ピンチで拡大・ドラッグで移動',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff8598a8),
                    ),
                  ),
                ),
                if (threeD)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Column(
                      children: [
                        IconButton(
                          tooltip: '拡大',
                          onPressed: () =>
                              setState(() => zoom = (zoom * 1.25).clamp(.3, 8)),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                        IconButton(
                          tooltip: '縮小',
                          onPressed: () =>
                              setState(() => zoom = (zoom / 1.25).clamp(.3, 8)),
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        IconButton(
                          tooltip: '視点をリセット',
                          onPressed: () => setState(() {
                            zoom = 1;
                            yaw = -.6;
                            pitch = .6;
                          }),
                          icon: const Icon(Icons.restart_alt, size: 18),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _Legend(cyan, '移動軌跡'),
          _Legend(Color(0xffd5f7a5), '撮影動作検知'),
          _Legend(Color(0xffffc77d), '要求・結果不明'),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        '撮影地点はアプリの要求ログです。GPS誤差を含みます。',
        style: TextStyle(fontSize: 11, color: Color(0xff8598a8)),
      ),
      if (threeD)
        const Text(
          '高さは開始点からの差分。高度がない点は基準平面に表示します。',
          style: TextStyle(fontSize: 11, color: Color(0xff8598a8)),
        ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xffa1b2bf)),
      ),
    ],
  );
}

class RoutePainter extends CustomPainter {
  RoutePainter(
    this.track,
    this.shots,
    this.current,
    this.threeD, {
    this.yaw = -.6,
    this.pitch = .6,
    this.zoom = 1,
  });
  final double yaw, pitch, zoom;
  final List<GeoFix> track;
  final List<Shot> shots;
  final GeoFix? current;
  final bool threeD;
  void text(
    Canvas c,
    String t,
    Offset p, {
    Color color = const Color(0xff90a4b4),
    double size = 10,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    final grid = Paint()
      ..color = const Color(0xff1b2b37)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32)
      c.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    for (double y = 0; y < size.height; y += 32)
      c.drawLine(Offset(0, y), Offset(size.width, y), grid);
    final points = [
      ...track,
      ...shots.where((s) => s.fix != null).map((s) => s.fix!),
      if (current != null) current!,
    ];
    if (points.isEmpty) return;
    final origin = points.first;
    List<double> meters(GeoFix p) {
      final east =
          (p.lon - origin.lon) * 111320 * math.cos(origin.lat * math.pi / 180);
      final north = (p.lat - origin.lat) * 111320;
      final z = p.altitude != null && origin.altitude != null
          ? p.altitude! - origin.altitude!
          : 0.0;
      return [east, north, z];
    }

    Offset rotate(double east, double north, double z) {
      final rotatedX = east * math.cos(yaw) - north * math.sin(yaw);
      final rotatedY = east * math.sin(yaw) + north * math.cos(yaw);
      return threeD
          ? Offset(rotatedX, -rotatedY * math.sin(pitch) - z * math.cos(pitch))
          : Offset(east, -north);
    }

    Offset local(GeoFix p) {
      final v = meters(p);
      return rotate(v[0], v[1], v[2]);
    }

    final coords = points.map(local).toList();
    var minX = coords.map((p) => p.dx).reduce(math.min),
        maxX = coords.map((p) => p.dx).reduce(math.max);
    var minY = coords.map((p) => p.dy).reduce(math.min),
        maxY = coords.map((p) => p.dy).reduce(math.max);
    final width = math.max(20.0, maxX - minX),
        height = math.max(20.0, maxY - minY);
    var scale = math.min(
      (size.width - 90) / width,
      (size.height - 90) / height,
    );
    var center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    if (threeD) {
      // Keep a stable world-space centre and scale while rotating the view.
      final xyz = points.map(meters).toList();
      final midpoint = List.generate(
        3,
        (axis) =>
            (xyz.map((v) => v[axis]).reduce(math.min) +
                xyz.map((v) => v[axis]).reduce(math.max)) /
            2,
      );
      final radius = math.max(
        10.0,
        xyz
            .map(
              (v) => math.sqrt(
                List.generate(
                  3,
                  (axis) => math.pow(v[axis] - midpoint[axis], 2),
                ).reduce((a, b) => a + b),
              ),
            )
            .reduce(math.max),
      );
      scale = math.min(size.width - 90, size.height - 90) / (radius * 2) * zoom;
      center = rotate(midpoint[0], midpoint[1], midpoint[2]);
    }
    Offset project(GeoFix p) =>
        (local(p) - center) * scale + Offset(size.width / 2, size.height / 2);
    if (track.length > 1) {
      final path = Path()
        ..moveTo(project(track.first).dx, project(track.first).dy);
      for (final p in track.skip(1)) path.lineTo(project(p).dx, project(p).dy);
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = cyan.withValues(alpha: .06),
      );
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = cyan,
      );
    }
    for (final s in shots.where((s) => s.fix != null)) {
      final p = project(s.fix!),
          color = s.result == ShotResult.actionObserved
              ? const Color(0xffd5f7a5)
              : const Color(0xffffc77d);
      c.drawCircle(p, 10, Paint()..color = color);
      text(
        c,
        '${s.number}',
        p - const Offset(3, 6),
        color: const Color(0xff0b1017),
        size: 10,
      );
    }
    if (current != null) {
      final p = project(current!);
      c.drawCircle(
        p,
        (current!.accuracy * scale).clamp(5, 70),
        Paint()..color = cyan.withValues(alpha: .06),
      );
      c.drawCircle(p, 6, Paint()..color = cyan);
      c.drawCircle(p, 3, Paint()..color = Colors.white);
    }
    final barMeters = math
        .pow(10, (math.log(60 / scale) / math.ln10).floor())
        .toDouble();
    c.drawLine(
      Offset(16, size.height - 23),
      Offset(16 + barMeters * scale, size.height - 23),
      Paint()
        ..color = const Color(0xff90a4b4)
        ..strokeWidth = 2,
    );
    text(
      c,
      '${barMeters < 1 ? barMeters.toStringAsFixed(1) : barMeters.toStringAsFixed(0)} m',
      Offset(16, size.height - 40),
    );
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) => true;
}

class AltitudeChart extends StatelessWidget {
  const AltitudeChart({super.key, required this.track});
  final List<GeoFix> track;
  @override
  Widget build(BuildContext context) {
    final values = track
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '高度の変化',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          '楕円体高 / GPS測位誤差を含む・海抜とは異なります',
          style: TextStyle(fontSize: 11, color: Color(0xff8598a8)),
        ),
        SizedBox(
          height: 130,
          width: double.infinity,
          child: values.length < 2
              ? const Center(
                  child: Text(
                    '移動後に高度グラフを表示',
                    style: TextStyle(color: Color(0xff8598a8)),
                  ),
                )
              : CustomPaint(painter: _AltitudePainter(values)),
        ),
      ],
    );
  }
}

class _AltitudePainter extends CustomPainter {
  _AltitudePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas c, Size s) {
    final lo = values.reduce(math.min),
        hi = values.reduce(math.max),
        range = math.max(5.0, hi - lo);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = 10 + i * (s.width - 20) / (values.length - 1),
          y = s.height - 20 - (values[i] - lo) * (s.height - 40) / range;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    c.drawPath(
      path,
      Paint()
        ..color = const Color(0xffb6a7ed)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final label = TextPainter(
      text: TextSpan(
        text: '${lo.toStringAsFixed(1)} – ${hi.toStringAsFixed(1)} m',
        style: const TextStyle(fontSize: 11, color: Color(0xffb6a7ed)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(c, const Offset(10, 8));
  }

  @override
  bool shouldRepaint(covariant _AltitudePainter old) => true;
}
