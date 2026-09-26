import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';

const cyan=Color(0xff65e0db);
class TrackView extends StatefulWidget {
  const TrackView({super.key,required this.track,required this.shots,this.current,this.large=false});
  final List<GeoFix> track;
  final List<Shot> shots;
  final GeoFix? current;
  final bool large;
  @override
  State<TrackView> createState()=>_TrackViewState();
}
class _TrackViewState extends State<TrackView> {
  bool threeD=false;
  @override
  Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[const Icon(Icons.route_rounded,color:cyan,size:20),const SizedBox(width:10),
      const Expanded(child:Text('移動と撮影ポイント',style:TextStyle(fontWeight:FontWeight.w600,fontSize:16))),
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('2D')),ButtonSegment(value:true,label:Text('3D'))],
        selected:{threeD},onSelectionChanged:(s)=>setState(()=>threeD=s.first),showSelectedIcon:false,
        style:const ButtonStyle(visualDensity:VisualDensity.compact))]),
    const SizedBox(height:16),
    ClipRRect(borderRadius:BorderRadius.circular(18),child:Container(
      height:widget.large?370:240,color:const Color(0xff101923),
      child:LayoutBuilder(builder:(context,c)=>Stack(children:[
        InteractiveViewer(minScale:.5,maxScale:8,child:CustomPaint(size:Size(c.maxWidth,widget.large?370:240),
          painter:RoutePainter(widget.track.toList(),widget.shots.toList(),widget.current,threeD))),
        Positioned(left:14,top:14,child:Text(threeD?'相対座標 · 高さ×1':'N ↑   相対座標',style:const TextStyle(color:Color(0xff8598a8),fontSize:11))),
        if(widget.track.isEmpty && widget.current==null) const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.explore_outlined,size:40,color:Color(0xff42616c)),SizedBox(height:12),Text('歩いた軌跡を、ここに。'),
          SizedBox(height:4),Text('セッション開始後にGPS位置を表示',style:TextStyle(fontSize:12,color:Color(0xff8598a8)))])),
        const Positioned(bottom:12,right:12,child:Text('ピンチで拡大・ドラッグで移動',style:TextStyle(fontSize:10,color:Color(0xff8598a8))))
      ])))),
    const SizedBox(height:12),const Wrap(spacing:16,runSpacing:6,children:[
      _Legend(cyan,'移動軌跡'),_Legend(Color(0xffd5f7a5),'撮影動作検知'),_Legend(Color(0xffffc77d),'要求・結果不明')]),
    const SizedBox(height:8),const Text('撮影地点はアプリの要求ログです。GPS誤差を含みます。',style:TextStyle(fontSize:11,color:Color(0xff8598a8))),
  ]);
}
class _Legend extends StatelessWidget {
  const _Legend(this.color,this.label); final Color color; final String label;
  @override
  Widget build(BuildContext context)=>Row(mainAxisSize:MainAxisSize.min,children:[Container(width:6,height:6,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),const SizedBox(width:6),Text(label,style:const TextStyle(fontSize:11,color:Color(0xffa1b2bf)))]);
}
class RoutePainter extends CustomPainter {
  RoutePainter(this.track,this.shots,this.current,this.threeD);
  final List<GeoFix> track; final List<Shot> shots; final GeoFix? current; final bool threeD;
  void text(Canvas c,String t,Offset p,{Color color=const Color(0xff90a4b4),double size=10}) {
    final painter=TextPainter(text:TextSpan(text:t,style:TextStyle(color:color,fontSize:size,fontWeight:FontWeight.w600)),textDirection:TextDirection.ltr)..layout(); painter.paint(c,p);
  }
  @override
  void paint(Canvas c,Size size) {
    final grid=Paint()..color=const Color(0xff1b2b37)..strokeWidth=1;
    for(double x=0;x<size.width;x+=32)c.drawLine(Offset(x,0),Offset(x,size.height),grid);
    for(double y=0;y<size.height;y+=32)c.drawLine(Offset(0,y),Offset(size.width,y),grid);
    final points=[...track,...shots.where((s)=>s.fix!=null).map((s)=>s.fix!),if(current!=null)current!];
    if(points.isEmpty)return;
    final origin=points.first;
    Offset local(GeoFix p) {
      final east=(p.lon-origin.lon)*111320*math.cos(origin.lat*math.pi/180);
      final north=(p.lat-origin.lat)*111320;
      final z=p.altitude!=null&&origin.altitude!=null?p.altitude!-origin.altitude!:0.0;
      return threeD?Offset(east*.85-north*.5,-north*.42-east*.24-z):Offset(east,-north);
    }
    final coords=points.map(local).toList();
    var minX=coords.map((p)=>p.dx).reduce(math.min), maxX=coords.map((p)=>p.dx).reduce(math.max);
    var minY=coords.map((p)=>p.dy).reduce(math.min), maxY=coords.map((p)=>p.dy).reduce(math.max);
    final width=math.max(20.0,maxX-minX),height=math.max(20.0,maxY-minY);
    final scale=math.min((size.width-90)/width,(size.height-90)/height);
    final center=Offset((minX+maxX)/2,(minY+maxY)/2);
    Offset project(GeoFix p)=>(local(p)-center)*scale+Offset(size.width/2,size.height/2);
    if(track.length>1) {
      final path=Path()..moveTo(project(track.first).dx,project(track.first).dy);
      for(final p in track.skip(1))path.lineTo(project(p).dx,project(p).dy);
      c.drawPath(path,Paint()..style=PaintingStyle.stroke..strokeWidth=12..strokeCap=StrokeCap.round..color=cyan.withValues(alpha:.06));
      c.drawPath(path,Paint()..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round..color=cyan);
    }
    for(final s in shots.where((s)=>s.fix!=null)) {
      final p=project(s.fix!), color=s.result==ShotResult.actionObserved?const Color(0xffd5f7a5):const Color(0xffffc77d);
      c.drawCircle(p,10,Paint()..color=color);
      text(c,'${s.number}',p-const Offset(3,6),color:const Color(0xff0b1017),size:10);
    }
    if(current!=null) {
      final p=project(current!);
      c.drawCircle(p,(current!.accuracy*scale).clamp(5,70),Paint()..color=cyan.withValues(alpha:.06));
      c.drawCircle(p,6,Paint()..color=cyan);c.drawCircle(p,3,Paint()..color=Colors.white);
    }
    final barMeters=math.pow(10,(math.log(60/scale)/math.ln10).floor()).toDouble();
    c.drawLine(Offset(16,size.height-23),Offset(16+barMeters*scale,size.height-23),Paint()..color=const Color(0xff90a4b4)..strokeWidth=2);
    text(c,'${barMeters<1?barMeters.toStringAsFixed(1):barMeters.toStringAsFixed(0)} m',Offset(16,size.height-40));
  }
  @override bool shouldRepaint(covariant RoutePainter old)=>true;
}

class AltitudeChart extends StatelessWidget {
  const AltitudeChart({super.key,required this.track}); final List<GeoFix> track;
  @override Widget build(BuildContext context) {
    final values=track.where((p)=>p.altitude!=null).map((p)=>p.altitude!).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('高度の変化',style:TextStyle(fontSize:16,fontWeight:FontWeight.w600)),const SizedBox(height:4),
      const Text('楕円体高 / GPS測位誤差を含む・海抜とは異なります',style:TextStyle(fontSize:11,color:Color(0xff8598a8))),
      SizedBox(height:130,width:double.infinity,child:values.length<2?const Center(child:Text('移動後に高度グラフを表示',style:TextStyle(color:Color(0xff8598a8)))):CustomPaint(painter:_AltitudePainter(values))),
    ]);
  }
}
class _AltitudePainter extends CustomPainter {
  _AltitudePainter(this.values);final List<double> values;
  @override void paint(Canvas c,Size s) {
    final lo=values.reduce(math.min),hi=values.reduce(math.max),range=math.max(5.0,hi-lo);
    final path=Path();
    for(var i=0;i<values.length;i++) {
      final x=10+i*(s.width-20)/(values.length-1),y=s.height-20-(values[i]-lo)*(s.height-40)/range;
      i==0?path.moveTo(x,y):path.lineTo(x,y);
    }
    c.drawPath(path,Paint()..color=const Color(0xffb6a7ed)..style=PaintingStyle.stroke..strokeWidth=2);
    final label=TextPainter(text:TextSpan(text:'${lo.toStringAsFixed(1)} – ${hi.toStringAsFixed(1)} m',style:const TextStyle(fontSize:11,color:Color(0xffb6a7ed))),textDirection:TextDirection.ltr)..layout();label.paint(c,const Offset(10,8));
  }
  @override bool shouldRepaint(covariant _AltitudePainter old)=>true;
}
