import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../platform/bridge_interface.dart';
import 'capture_engine.dart';
import 'models.dart';
import 'protocol.dart';

class AppController extends ChangeNotifier {
  AppController(this.bridge) : engine=CaptureEngine(Settings());
  final DeviceBridge bridge;
  final CaptureEngine engine;
  final clock=Stopwatch()..start();
  final decoder=FrameDecoder();
  final List<Map<String,dynamic>> logs=[];
  List<Map<String,dynamic>> sessions=[];
  List<Map<String,dynamic>> projects=[];
  String selectedProjectId='', mapsApiKey='';
  String get projectName=>projects.where((p)=>p['id']==selectedProjectId).map((p)=>p['name'].toString()).firstOrNull??'プロジェクトを作成';
  List<Map<String,dynamic>> get projectSessions=>sessions.where((s)=>s['projectId']==selectedProjectId).toList();
  Map<String,dynamic> capabilities={};
  List<int> identity=[];
  String cameraName='未接続', connectionLabel='カメラを接続', error='', modeDescription='';
  String sessionId='', storageError='';
  int verificationCode=0, _sequence=0, _generation=0, _lastGps=-10000, _lastSave=0;
  int cameraId=0xff66;
  bool connecting=false, demo=false, _gpsSending=false, _shutterSending=false;
  bool _disposed=false;
  Timer? _timer, _handshakeTimer;
  StreamSubscription? _subscription;
  Completer<void>? _authorized;
  Future<void> _writeTail=Future.value();
  Future<void> _persistTail=Future.value();
  final Map<int, Completer<Frame>> _pending={};
  CapturePhase? _lastPhase;
  Settings get settings=>engine.settings;
  int get now=>clock.elapsedMilliseconds;
  DateTime get utc=>DateTime.now().toUtc();
  Future<void> initialize() async {
    _subscription=bridge.events.listen(_event,onError:(Object e)=>fail(e.toString()));
    try {
      capabilities=Map<String,dynamic>.from(await bridge.call('capabilities')??{});
      final saved=await bridge.call('load',{'key':'settings'});
      if(saved is String) engine.settings=Settings.fromJson(Map<String,dynamic>.from(jsonDecode(saved)));
      final ident=await bridge.call('load',{'key':'identity'});
      if(ident is String) identity=List<int>.from(jsonDecode(ident));
      if(identity.length!=6) {
        identity=List.generate(6,(_)=>Random.secure().nextInt(256)); identity[0]=(identity[0]|2)&254;
        await bridge.call('save',{'key':'identity','value':jsonEncode(identity)});
      }
      final history=await bridge.call('load',{'key':'sessions'});
      if(history is String) sessions=(jsonDecode(history) as List).map((e)=>Map<String,dynamic>.from(e)).toList();
      final projectData=await bridge.call('load',{'key':'projects'});
      if(projectData is String) projects=(jsonDecode(projectData) as List).map((p)=>Map<String,dynamic>.from(p)).toList();
      selectedProjectId=(await bridge.call('load',{'key':'selectedProject'})) as String? ?? '';
      mapsApiKey=(await bridge.call('load',{'key':'mapsApiKey'})) as String? ?? '';
      if(projects.isEmpty) await createProject('はじめての撮影','');
      if(!projects.any((p)=>p['id']==selectedProjectId)) selectedProjectId=projects.first['id'];
      for(final s in sessions) { s['projectId'] ??= selectedProjectId; }
      // Active sessions are never automatically resumed after reload/crash.
      final current=await bridge.call('load',{'key':'current'});
      if(current is String) {
        final recovered=Map<String,dynamic>.from(jsonDecode(current));
        if(recovered['id']!=null && !sessions.any((s)=>s['id']==recovered['id'])) {
          recovered['interrupted']=true; recovered['projectId'] ??= selectedProjectId;
          for(final shot in (recovered['shots'] as List? ?? [])) {
            if(shot['result']=='requested') { shot['result']='unknown'; shot['note']='アプリ終了時に未確定'; }
          }
          sessions.insert(0,recovered);
          await _saveHistory();
        }
        await bridge.call('remove',{'key':'current'});
      }
    } catch(e) { storageError='保存データの読み込み: $e'; }
    _timer=Timer.periodic(const Duration(milliseconds:100),(_)=>_tick());
    notifyListeners();
  }
  void log(String kind,String message,[Map<String,dynamic> extra=const {}]) {
    logs.add({'time':utc.toIso8601String(),'elapsedMs':now,'kind':kind,'message':message,...extra});
    if(logs.length>1500) logs.removeAt(0);
  }
  void fail(String message) { error=message; log('error',message); notifyListeners(); }
  Future<void> feedback(String message) async {
    log('notice',message);
    try { await bridge.call('feedback',{'text':message,'voice':settings.voice,'sound':settings.sound,'vibrate':true}); }
    catch(e) { log('warning','通知できません: $e'); }
  }
  int nextSequence()=>_sequence=(_sequence+1)&0xffff;
  Future<void> _write(Frame frame,{bool Function()? allowed}) {
    final gen=_generation;
    final work=_writeTail.catchError((Object _){}).then((_) async {
      if(gen!=_generation || !engine.connected) throw StateError('送信前に切断されました');
      if(allowed!=null && !allowed())throw StateError('送信条件が変わったため中止しました');
      log('tx','${frame.set.toRadixString(16)}/${frame.id.toRadixString(16)}',
        {'sequence':frame.sequence,'type':frame.type,'hex':_hex(frame.encode())});
      try {
        await bridge.call('write',{'bytes':frame.encode().toList()}).timeout(const Duration(seconds:4));
      } on TimeoutException {
        _generation++;await bridge.call('disconnect').catchError((Object _){});rethrow;
      }
    });
    _writeTail=work;
    return work;
  }
  Future<Frame> _request(int set,int id,Uint8List payload) async {
    final seq=nextSequence(), c=Completer<Frame>();
    _pending[seq]=c;
    try {
      // Install timeout handling before writing; notifications can arrive during write.
      final response=c.future.timeout(const Duration(seconds:5));
      unawaited(_write(Frame(set,id,seq,2,payload)).catchError((Object e){ if(!c.isCompleted)c.completeError(e); }));
      final frame=await response;
      if(frame.set!=set || frame.id!=id) throw StateError('応答コマンドが一致しません');
      return frame;
    } finally { _pending.remove(seq); }
  }
  Future<void> connect({bool reconnect=false}) async {
    if(connecting) return;
    if(demo) { await stopSession(); demo=false; engine.disconnect(); }
    connecting=true; error=''; connectionLabel='Bluetooth接続中';
    engine.disconnect(); decoder.reset(); _generation++;
    notifyListeners();
    try {
      await bridge.call('connect',{'reconnect':reconnect}).timeout(const Duration(seconds:35));
      // connected event installs protocol handshake before this returns.
    } catch(e) { connecting=false; connectionLabel='接続できません'; fail('$e'); }
  }
  void _event(Map<String,dynamic> e) {
    if(_disposed) return;
    switch(e['type']) {
      case 'connected':
        engine.connected=true; cameraName=e['name']??'Osmo 360';
        unawaited(_handshake());
      case 'disconnected':
        _generation++; engine.disconnect(); decoder.reset(); connecting=false;
        connectionLabel='切断されました'; _handshakeTimer?.cancel();
        if(_authorized!=null && !_authorized!.isCompleted) _authorized!.completeError(StateError('接続切断'));
        for(final c in _pending.values) { if(!c.isCompleted)c.completeError(StateError('接続切断')); }
        _pending.clear(); unawaited(feedback('カメラが切断されました')); unawaited(persist());
      case 'bytes':
        if(!demo) for(final frame in decoder.add(List<int>.from(e['bytes']))) { _frame(frame); }
      case 'motion':
        if(!demo) engine.motion(now,number(e,'gyro',double.nan),number(e,'linear',double.nan));
      case 'step':
        if(!demo) engine.addStep(now);
      case 'location':
        if(!demo) { final f=GeoFix.fromJson(e,now); if(f!=null) engine.location(f,now,utc); }
      case 'visibility':
        engine.visibility(e['visible']==true);
        if(!engine.visible) unawaited(persist());
      case 'capabilities':
        capabilities={...capabilities,...e}; engine.nativeSteps=e['nativeSteps']==true;
      case 'error':
        if(e['source']=='gps') engine.gpsUnavailable=true;
        fail(e['message']??'端末エラー');
      case 'warning': log('warning',e['message']??'');
    }
    notifyListeners();
  }
  Future<void> _handshake() async {
    final gen=_generation;
    final approved=Completer<void>(); _authorized=approved;
    verificationCode=1000+Random.secure().nextInt(9000);
    connectionLabel='カメラ画面で $verificationCode を確認'; notifyListeners();
    final timeout=approved.future.timeout(const Duration(seconds:40));
    try {
      unawaited(_write(Frame(0,0x19,nextSequence(),2,connectionPayload(identity,verificationCode)))
        .catchError((Object e){if(!approved.isCompleted)approved.completeError(e);}));
      await timeout;
      if(gen!=_generation) return;
      engine.authorized=true; connecting=false; connectionLabel='接続済み';
      await _write(Frame(0x1d,5,nextSequence(),0,Uint8List.fromList([3,20,0,0,0,0])));
      await _write(Frame(0,0,nextSequence(),1,Uint8List(0)));
      log('connection','接続承認完了',{'cameraId':cameraId,'name':cameraName});
    } catch(e) {
      connecting=false; engine.authorized=false; fail('接続承認に失敗: $e');
      await bridge.call('disconnect').catchError((Object _){});
    }
    notifyListeners();
  }
  void _frame(Frame f) {
    log('rx','${f.set.toRadixString(16)}/${f.id.toRadixString(16)}',
      {'sequence':f.sequence,'type':f.type,'hex':_hex(f.encode())});
    if(f.isAck) {
      final c=_pending[f.sequence];
      if(c!=null && !c.isCompleted) c.complete(f);
      if(f.set==0 && f.id==0x11 && f.payload.isNotEmpty) engine.acknowledge(f.sequence,f.payload[0]==0);
      if(f.set==0 && f.id==0x19 && f.payload.length>=5 && f.payload[4]!=0) {
        if(_authorized!=null && !_authorized!.isCompleted) _authorized!.completeError(StateError('カメラが接続を拒否'));
      }
      if(f.set==0 && f.id==0) log('version','バージョン応答',{'payload':_hex(f.payload)});
      return;
    }
    if(f.set==0 && f.id==0x19 && f.payload.length>=29) {
      final d=ByteData.sublistView(f.payload);
      if(f.payload[26]!=2) return;
      if(d.getUint16(27,Endian.little)!=0) {
        if(_authorized!=null && !_authorized!.isCompleted) _authorized!.completeError(StateError('接続が拒否されました'));
        return;
      }
      cameraId=d.getUint32(0,Endian.little);
      unawaited(_write(Frame(0,0x19,f.sequence,0x20,connectionAckPayload())).then((_){
        if(_authorized!=null && !_authorized!.isCompleted) _authorized!.complete();
      }).catchError((Object e){if(_authorized!=null && !_authorized!.isCompleted)_authorized!.completeError(e);}));
    } else if(f.set==0x1d && f.id==2) {
      final state=CameraStatus.parse(f.payload,now);
      if(state!=null && engine.authorized) { engine.status(state); }
    } else if(f.set==0x1d && f.id==6 && f.payload.length>=46) {
      final name=f.payload.sublist(2,2+f.payload[1].clamp(0,20));
      final param=f.payload.sublist(25,25+f.payload[24].clamp(0,20));
      modeDescription='${ascii.decode(name,allowInvalid:true)} ${ascii.decode(param,allowInvalid:true)}';
    }
    if((f.type&31)>0 && !(f.set==0 && f.id==0x19)) {
      unawaited(_write(Frame(f.set,f.id,f.sequence,0x20,Uint8List.fromList([0])))
        .catchError((Object e)=>log('error','$e')));
    }
  }
  Future<void> photoMode() async {
    if(!engine.authorized || engine.pending!=null) return;
    try {
      final f=await _request(0x1d,4,photoModePayload(cameraId));
      if(f.payload.isEmpty || f.payload[0]!=0) throw StateError('モード切り替えが拒否されました');
      // ACK does not establish the mode: next status notification must confirm it.
      engine.camera=null; modeDescription='パノラマ写真モードの確認待ち';
    } catch(e) { fail('$e'); }
  }
  Future<void> startSession() async {
    if(engine.active) return;
    if(selectedProjectId.isEmpty){fail('プロジェクトを作成してください');return;}
    if(engine.shots.isNotEmpty || engine.track.isNotEmpty) { await _archive(); engine.resetSession(); }
    sessionId=utc.toIso8601String(); logs.clear(); engine.start(); error='';
    if(demo) _demoStatus();
    else {
      try { await bridge.call('startSensors'); }
      catch(e) { fail('センサー開始: $e'); }
    }
    await persist(); notifyListeners();
  }
  Future<void> stopSession() async {
    if(engine.pending!=null) engine.resolveUnknown('セッション停止時に状態が未確定');
    engine.stop();
    if(!demo) await bridge.call('stopSensors').catchError((Object e)=>log('warning','$e'));
    await _archive(); await _persistTail; await bridge.call('remove',{'key':'current'}).catchError((Object _){});
    notifyListeners();
  }
  Future<void> pauseOrResume() async {
    if(engine.paused) {
      engine.resume();
      if(!demo) await bridge.call('startSensors').catchError((Object e)=>log('warning','$e'));
    } else { engine.pause('手動で一時停止しました'); }
    await persist(); notifyListeners();
  }
  void _tick() {
    if(demo && engine.active && !engine.paused) _demoStatus();
    engine.tick(now,utc);
    if(engine.phase!=_lastPhase) {
      if(engine.phase==CapturePhase.settle) unawaited(feedback('停止してください'));
      if(engine.phase==CapturePhase.moving && _lastPhase==CapturePhase.cooldown) unawaited(feedback('次の移動を開始できます'));
      _lastPhase=engine.phase;
    }
    if(engine.phase==CapturePhase.ready) unawaited(shutter(manual:false));
    if(!demo && engine.active && !engine.paused && engine.visible && engine.authorized &&
      settings.forwardGps && engine.gpsValid(now,utc) && engine.fix!.altitude!=null && !_gpsSending &&
      !_shutterSending && now-_lastGps>=1000) {
      _gpsSending=true; _lastGps=now;
      unawaited(_write(Frame(0,0x17,nextSequence(),0,gpsPayload(engine.fix!,timeOffsetHours:settings.gpsTimeOffset)))
        .catchError((Object e)=>log('error','GPS送信: $e')).whenComplete(()=>_gpsSending=false));
    }
    if(engine.active && now-_lastSave>3000) { _lastSave=now; unawaited(persist()); }
    notifyListeners();
  }
  Future<void> shutter({bool manual=true}) async {
    if(_shutterSending) return;
    final shot=engine.reserve(now,utc,manual:manual);
    if(shot==null) return;
    _shutterSending=true;
    final gen=_generation;
    try {
      // Persist the reservation before device IO; crashes never cause replay.
      await persist(required:true);
      if(!engine.active || engine.pending!=shot || !engine.visible || engine.paused || gen!=_generation) throw StateError('送信前に中止');
      if(demo) {
        shot.acknowledged=true;
        engine.status(CameraStatus(mode:0x3f,state:3,battery:87,remainingPhotos:900,capacityMb:32768,
          temperature:0,power:0,countdownMs:0,receivedAt:now+1));
      } else {
        shot.sequence=nextSequence();
        await _write(Frame(0,0x11,shot.sequence!,2,Uint8List.fromList([1,1,0,0])),allowed:()=>
          engine.active && engine.pending==shot && engine.visible && !engine.paused &&
          engine.camera!=null && engine.camera!.ready && now-engine.camera!.receivedAt<=2500 &&
          (!settings.requireGps || engine.gpsValid(now,utc)) &&
          (manual || (engine.motionFresh(now) && engine.gyro<=settings.gyroThreshold && engine.acceleration<=settings.accelerationThreshold))); 
      }
      await feedback('撮影要求を送りました');
    } catch(e) { engine.resolveUnknown('撮影要求の結果不明: $e。再送していません'); fail('$e'); }
    finally { _shutterSending=false; await persist(); notifyListeners(); }
  }
  Map<String,dynamic> snapshot() => {'schema':2,'id':sessionId,'demo':demo,'projectId':selectedProjectId,'projectName':projectName,
    'savedAt':utc.toIso8601String(),'settings':settings.toJson(),'cameraName':cameraName,
    'modeDescription':modeDescription,'steps':engine.steps,'estimatedDistanceM':engine.totalDistance,
    'shots':engine.shots.map((s)=>s.toJson()).toList(),'track':engine.track.map((f)=>f.toJson()).toList(),
    'logs':logs.toList(),'savedFileVerified':false};
  Future<void> persist({bool required=false}) async {
    if(sessionId.isEmpty || !engine.active)return;
    final value=jsonEncode(snapshot());
    final write=_persistTail.catchError((Object _){}).then((_)=>bridge.call('save',{'key':'current','value':value}));
    _persistTail=write.then<void>((_){}).catchError((Object _){});
    try { await write; }
    catch(e) {
      storageError='端末への保存に失敗しました。履歴を書き出してください: $e';engine.pause('保存容量を確認してください');
      if(required)rethrow;
    }
  }
  Future<void> saveSettings() async {
    try { await bridge.call('save',{'key':'settings','value':jsonEncode(settings.toJson())}); }
    catch(e) { storageError='$e'; }
    notifyListeners();
  }
  Future<void> _saveHistory() async {
    await bridge.call('save',{'key':'sessions','value':jsonEncode(sessions)});
  }
  Future<void> _archive() async {
    if(sessionId.isEmpty) return;
    final data=snapshot();
    sessions.removeWhere((s)=>s['id']==sessionId); sessions.insert(0,data);
    try { await _saveHistory(); } catch(e) { storageError='履歴保存: $e'; }
  }
  Future<void> export({Map<String,dynamic>? data,String format='json'}) async {
    final s=data??snapshot();
    final stamp=(s['id']??utc.toIso8601String()).toString().replaceAll(RegExp('[^0-9A-Za-z]'),'-');
    String content, mime;
    if(format=='gpx') {
      final points=(s['track'] as List? ?? []);
      content='<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="Osmo360 Shutter" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Walk track</name><trkseg>'+
        points.map((p)=>'<trkpt lat="${p['lat']}" lon="${p['lon']}"><time>${DateTime.fromMillisecondsSinceEpoch((p['timestamp'] as num).toInt(),isUtc:true).toIso8601String()}</time></trkpt>').join()+
        '</trkseg></trk></gpx>';
      // GPX ele expects elevation; omit WGS84 ellipsoid altitude rather than relabel it.
      mime='application/gpx+xml';
    } else if(format=='csv') {
      content='number,time_utc,result,ack,latitude,longitude,horizontal_accuracy_m,ellipsoid_altitude_m\n'+
        (s['shots'] as List? ?? []).map((p){final f=p['fix'] as Map?;return [p['number'],p['at'],p['result'],p['acknowledged'],f?['lat'],f?['lon'],f?['accuracy'],f?['altitude']].map((v)=>'"${(v??'').toString().replaceAll('"','""')}"').join(',');}).join('\n');
      mime='text/csv';
    } else { content=const JsonEncoder.withIndent('  ').convert(s); mime='application/json'; }
    try { await bridge.call('export',{'name':'osmo360-$stamp.$format','content':content,'mime':mime}); }
    catch(e) { fail('書き出し: $e'); }
  }
  Future<void> _saveProjects() async {
    await bridge.call('save',{'key':'projects','value':jsonEncode(projects)});
    await bridge.call('save',{'key':'selectedProject','value':selectedProjectId});
  }
  Future<void> createProject(String name,String description) async {
    if(engine.active) {fail('セッションを終了してからプロジェクトを作成してください');return;}
    if(name.trim().isEmpty) return;
    selectedProjectId='p-${utc.microsecondsSinceEpoch}';
    projects.add({'id':selectedProjectId,'name':name.trim(),'description':description.trim(),'createdAt':utc.toIso8601String(),'updatedAt':utc.toIso8601String()});
    engine.resetSession();sessionId='';
    await _saveProjects();notifyListeners();
  }
  Future<void> editProject(String id,String name,String description) async {
    if(name.trim().isEmpty)return;
    final p=projects.firstWhere((p)=>p['id']==id);
    p['name']=name.trim();p['description']=description.trim();p['updatedAt']=utc.toIso8601String();
    await _saveProjects();notifyListeners();
  }
  Future<void> selectProject(String id) async {
    if(engine.active || !projects.any((p)=>p['id']==id)) return;
    if(sessionId.isNotEmpty) await _archive();
    selectedProjectId=id;sessionId='';engine.resetSession();
    await _saveProjects();notifyListeners();
  }
  Future<void> deleteProject(String id) async {
    if(engine.active){fail('セッションを終了してください');return;}
    sessions.removeWhere((s)=>s['projectId']==id);projects.removeWhere((p)=>p['id']==id);
    if(selectedProjectId==id){selectedProjectId=projects.isEmpty?'':projects.first['id'];sessionId='';engine.resetSession();}
    await _saveHistory();await _saveProjects();await bridge.call('remove',{'key':'current'});notifyListeners();
  }
  Future<void> saveMapKey(String key) async {
    mapsApiKey=key.trim();
    await bridge.call('save',{'key':'mapsApiKey','value':mapsApiKey});notifyListeners();
  }
  Future<void> exportProject() async {
    final project=projects.where((p)=>p['id']==selectedProjectId).firstOrNull;
    final data={'schema':2,'project':project,'sessions':projectSessions,
      if(engine.active)'currentSession':snapshot()};
    await bridge.call('export',{'name':'osmo360-project-$selectedProjectId.json','content':const JsonEncoder.withIndent('  ').convert(data),'mime':'application/json'});
  }
  Future<void> deleteSession(String id) async {
    if(engine.active && sessionId==id)return;
    sessions.removeWhere((s)=>s['id']==id);
    if(sessionId==id){sessionId='';engine.resetSession();}
    await _saveHistory();notifyListeners();
  }
  Future<void> install() async {
    try { final r=await bridge.call('install'); if(r is Map && r['hint']!=null) error=r['hint']; }
    catch(e) { fail('$e'); } notifyListeners();
  }
  Future<void> enableDemo() async {
    if(engine.active) await stopSession();
    await bridge.call('disconnect').catchError((Object _){});
    demo=true; engine.resetSession(); cameraName='デモカメラ'; connectionLabel='デモ / 実機へ送信しません';
    engine.connected=true; engine.authorized=true; engine.nativeSteps=false;
    _demoStatus(); notifyListeners();
  }
  void _demoStatus() {
    engine.status(CameraStatus(mode:0x3f,state:1,battery:87,remainingPhotos:900,capacityMb:32768,
      temperature:0,power:0,countdownMs:0,receivedAt:now));
    final steps=engine.steps;
    engine.location(GeoFix(lat:35.6812+steps*.000003,lon:139.7671+steps*.000006,
      accuracy:4,altitude:40+steps*.05,verticalAccuracy:8,time:utc,receivedAt:now),now,utc);
    engine.motion(now,.008,.04);
  }
  void demoStep() { if(!demo)return; engine.addStep(now); engine.motion(now,.3,2); notifyListeners(); }
  static String _hex(List<int> bytes)=>bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ');
  @override
  void dispose() { _disposed=true; _timer?.cancel(); _handshakeTimer?.cancel(); _subscription?.cancel(); super.dispose(); }
}
