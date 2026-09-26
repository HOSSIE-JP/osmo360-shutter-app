import 'dart:math' as math;
import 'models.dart';
import 'protocol.dart';

enum CapturePhase { idle, paused, moving, settle, blocked, cooldown, cameraWait, ready }

/// Deterministic state machine. All durations use monotonic elapsed milliseconds.
/// IO belongs to the controller; reserving a shot synchronously consumes its movement token.
class CaptureEngine {
  CaptureEngine(this.settings);
  Settings settings;
  bool active=false, paused=false, visible=true, connected=false, authorized=false;
  bool gpsUnavailable=false, nativeSteps=false;
  int steps=0, _stepBase=0, _lastStep=-10000;
  int? _lastMotion, _stillSince, _lastShotAt;
  bool _peak=false, _sawBusy=false;
  double gyro=0, acceleration=0;
  String pauseReason='', blockReason='';
  CameraStatus? camera;
  GeoFix? fix;
  Shot? pending;
  CapturePhase phase=CapturePhase.idle;
  final List<Shot> shots=[];
  final List<GeoFix> track=[];
  double get distanceSinceShot => math.max(0,steps-_stepBase)*settings.strideM;
  double get totalDistance => steps*settings.strideM;
  double get distanceRemaining => math.max(0,settings.intervalM-distanceSinceShot);
  bool get hasMovement => steps>_stepBase && distanceSinceShot>=settings.intervalM;
  bool motionFresh(int now) => _lastMotion!=null && now-_lastMotion!<=400;
  bool stable(int now) => motionFresh(now) && _stillSince!=null && now-_stillSince!>=settings.stableSeconds*1000;
  double stableProgress(int now) => !motionFresh(now)||_stillSince==null ? 0 :
      ((now-_stillSince!)/(settings.stableSeconds*1000)).clamp(0,1);
  double cooldownRemaining(int now) => _lastShotAt==null ? 0 :
      math.max(0,settings.cooldownSeconds-(now-_lastShotAt!)/1000);
  bool gpsValid(int now,DateTime utc) => !gpsUnavailable && fix!=null && fix!.usable(now,utc,settings);
  void start() {
    active=true; paused=false; pauseReason=''; _stepBase=steps; _stillSince=null;
  }
  void pause(String reason) { paused=true; pauseReason=reason; _stillSince=null; }
  void resume() {
    if(!visible || !connected || !authorized || pending!=null) return;
    paused=false; pauseReason=''; _stillSince=null; _stepBase=steps;
  }
  void stop() { active=false; paused=false; _stillSince=null; }
  void resetSession() {
    if(pending!=null) throw StateError('撮影結果の確認中です');
    stop(); shots.clear(); track.clear(); steps=0; _stepBase=0;
    _lastShotAt=null; _lastMotion=null; fix=null; camera=null;
  }
  void visibility(bool value) {
    visible=value;
    if(!value && active) pause('画面が非表示になりました。前面に戻して再開してください');
    _stillSince=null; _lastMotion=null;
  }
  void disconnect() {
    connected=false; authorized=false; camera=null;
    if(pending!=null) resolveUnknown('通信切断。再送していません');
    if(active) pause('カメラが切断されました');
  }
  void addStep(int now) {
    if(!active || paused || !visible || now-_lastStep<250) return;
    steps++; _lastStep=now; _stillSince=null;
  }
  void motion(int now,double angular,double linear) {
    if(!angular.isFinite || !linear.isFinite) return;
    if(_lastMotion==null || now-_lastMotion!>400) _stillSince=null;
    _lastMotion=now; gyro=angular.abs(); acceleration=linear.abs();
    if(gyro<=settings.gyroThreshold && acceleration<=settings.accelerationThreshold) {
      _stillSince ??= now;
    } else { _stillSince=null; }
    if(!nativeSteps) {
      if(acceleration>settings.stepThreshold && !_peak) { _peak=true; addStep(now); }
      if(acceleration<settings.stepThreshold*.45) _peak=false;
    }
  }
  void location(GeoFix next,int now,DateTime utc) {
    if(fix!=null && !next.time.isAfter(fix!.time)) return;
    fix=next; gpsUnavailable=false;
    if(!active || paused || !visible || !next.usable(now,utc,settings)) return;
    // Stationary jitter never contributes to the shot-spacing counter.
    if(track.isEmpty) { track.add(next); return; }
    final previous=track.last, seconds=next.time.difference(previous.time).inMilliseconds/1000;
    if(seconds<=0 || next.distanceTo(previous)>math.max(25,seconds*5+next.accuracy+previous.accuracy)) return;
    if(now-_lastStep<3000 && seconds>=1) {
      track.add(next);
      if(track.length>12000) track.removeAt(0);
    }
  }
  void status(CameraStatus next) {
    camera=next;
    final p=pending;
    if(p==null || next.receivedAt<=p.elapsedMs) return;
    if(next.busy) {
      _sawBusy=true; p.result=ShotResult.actionObserved;
      p.note='撮影状態への遷移を検知。画像保存の保証ではありません';
    } else if(_sawBusy && next.ready) { pending=null; }
  }
  void acknowledge(int sequence,bool accepted) {
    final p=pending;
    if(p==null || p.sequence!=sequence) return;
    if(accepted) { p.acknowledged=true; }
    else { p.result=ShotResult.failed; p.note='カメラが要求を拒否'; pending=null; pause('撮影要求が拒否されました'); }
  }
  void resolveUnknown(String note) {
    if(pending!=null) {
      // Keep observed evidence, even if idle/recovery is missing.
      if(pending!.result!=ShotResult.actionObserved) pending!.result=ShotResult.unknown;
      pending!.note=note;
    }
    pending=null; pause(note);
  }
  String? shutterBlock(int now,DateTime utc) {
    if(!active) return 'セッションを開始してください';
    if(!visible || paused) return pauseReason.isEmpty ? '一時停止中' : pauseReason;
    if(!connected || !authorized) return 'カメラの接続承認待ち';
    if(pending!=null) return 'カメラの撮影動作を確認中';
    if(cooldownRemaining(now)>0) return 'クールダウン中';
    if(camera==null || now-camera!.receivedAt>2500) return '新しいカメラ状態を待っています';
    if(camera!.mode!=0x3f) return 'パノラマ写真モードに切り替えてください';
    if(!camera!.ready) return 'カメラ待ち（処理・容量・温度・電源を確認）';
    if(settings.requireGps && !gpsValid(now,utc)) return '新しいGPS位置を待っています';
    return null;
  }
  void tick(int now,DateTime utc) {
    if(pending!=null && now-pending!.elapsedMs>math.max(15000,settings.cooldownSeconds*1000+5000)) {
      resolveUnknown('撮影後の状態を確認できません。カメラを確認して再開してください');
    }
    if(!active) { phase=CapturePhase.idle; return; }
    if(paused) { phase=CapturePhase.paused; return; }
    if(cooldownRemaining(now)>0) { phase=CapturePhase.cooldown; return; }
    if(pending!=null) { phase=CapturePhase.cameraWait; return; }
    final block=shutterBlock(now,utc);
    if(block!=null) { blockReason=block; phase=CapturePhase.blocked; return; }
    if(!motionFresh(now)) { blockReason='センサー待ち。手動撮影は利用できます'; phase=CapturePhase.blocked; return; }
    if(!hasMovement) { phase=CapturePhase.moving; return; }
    phase=stable(now) ? CapturePhase.ready : CapturePhase.settle;
  }
  Shot? reserve(int now,DateTime utc,{required bool manual}) {
    if(shutterBlock(now,utc)!=null) return null;
    if(!manual && (!hasMovement || !stable(now))) return null;
    final shot=Shot(number:shots.length+1,at:utc,elapsedMs:now,manual:manual,
      fix:gpsValid(now,utc) ? fix : null);
    shots.add(shot); pending=shot; _lastShotAt=now; _sawBusy=false;
    _stepBase=steps; _stillSince=null;
    return shot;
  }
}
