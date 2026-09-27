import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GoogleMapPanel extends StatefulWidget {
  const GoogleMapPanel({super.key, required this.config});
  final Map<String, dynamic> config;
  @override
  State<GoogleMapPanel> createState() => _GoogleMapPanelState();
}

class _GoogleMapPanelState extends State<GoogleMapPanel> {
  MethodChannel? channel;
  @override
  void didUpdateWidget(covariant GoogleMapPanel old) {
    super.didUpdateWidget(old);
    channel?.invokeMethod('update', widget.config);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 350,
    child: AndroidView(
      viewType: 'osmo360/map',
      creationParams: widget.config,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        channel = MethodChannel('osmo360/map/$id');
      },
    ),
  );
}
