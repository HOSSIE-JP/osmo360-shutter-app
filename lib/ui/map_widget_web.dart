import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
@JS('osmoMapUpdate') external void mapUpdate(JSNumber id,JSString json);
@JS('osmoMapAttach') external void mapAttach(JSNumber id,JSObject element,JSString json);
@JS('osmoMapDispose') external void mapDispose(JSNumber id);
class GoogleMapPanel extends StatefulWidget {
  const GoogleMapPanel({super.key,required this.config});final Map<String,dynamic> config;
  @override State<GoogleMapPanel> createState()=>_GoogleMapPanelState();
}
class _GoogleMapPanelState extends State<GoogleMapPanel> {
  static int nextId=0;late final int id=nextId++;bool attached=false;String last='';
  @override void didUpdateWidget(covariant GoogleMapPanel old){super.didUpdateWidget(old);_update();}
  void _update(){final s=jsonEncode(widget.config);if(attached&&s!=last){last=s;mapUpdate(id.toJS,s.toJS);}}
  @override Widget build(BuildContext context)=>SizedBox(height:350,child:HtmlElementView.fromTagName(tagName:'iframe',onElementCreated:(element){attached=true;last=jsonEncode(widget.config);mapAttach(id.toJS,element as JSObject,last.toJS);}));
  @override void dispose(){if(attached)mapDispose(id.toJS);super.dispose();}
}
