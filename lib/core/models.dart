import 'dart:math' as math;
import 'dart:typed_data';

double number(Map<String, dynamic> m, String k, double fallback) =>
    m[k] is num && (m[k] as num).isFinite ? (m[k] as num).toDouble() : fallback;

class Settings {
  double intervalM = 3, strideM = .7, stableSeconds = 1.5, cooldownSeconds = 6;
  double gyroThreshold = .08, accelerationThreshold = .45, stepThreshold = 1.25;
  double gpsMaxAccuracy = 20, gpsMaxAge = 5;
  bool requireGps = true, forwardGps = true, voice = true, sound = true;
  int gpsTimeOffset = 8;
  Map<String, dynamic> toJson() => {
    'intervalM':intervalM,'strideM':strideM,'stableSeconds':stableSeconds,
    'cooldownSeconds':cooldownSeconds,'gyroThreshold':gyroThreshold,
    'accelerationThreshold':accelerationThreshold,'stepThreshold':stepThreshold,
    'gpsMaxAccuracy':gpsMaxAccuracy,'gpsMaxAge':gpsMaxAge,'requireGps':requireGps,
    'forwardGps':forwardGps,'voice':voice,'sound':sound,'gpsTimeOffset':gpsTimeOffset};
  static Settings fromJson(Map<String,dynamic> m) => Settings()
    ..intervalM = number(m,'intervalM',3).clamp(.5,100)
    ..strideM = number(m,'strideM',.7).clamp(.2,1.5)
    ..stableSeconds = number(m,'stableSeconds',1.5).clamp(.5,10)
    ..cooldownSeconds = number(m,'cooldownSeconds',6).clamp(1,60)
    ..gyroThreshold = number(m,'gyroThreshold',.08).clamp(.01,.5)
    ..accelerationThreshold = number(m,'accelerationThreshold',.45).clamp(.1,2)
    ..stepThreshold = number(m,'stepThreshold',1.25).clamp(.5,4)
    ..gpsMaxAccuracy = number(m,'gpsMaxAccuracy',20).clamp(3,100)
    ..gpsMaxAge = number(m,'gpsMaxAge',5).clamp(1,15)
    ..requireGps = m['requireGps'] != false
    ..forwardGps = m['forwardGps'] != false
    ..voice = m['voice'] != false
    ..sound = m['sound'] != false
    ..gpsTimeOffset = m['gpsTimeOffset'] == 0 ? 0 : 8;
}

class GeoFix {
  const GeoFix({required this.lat, required this.lon, required this.accuracy,
    required this.time, required this.receivedAt, this.altitude, this.verticalAccuracy,
    this.speed, this.heading, this.speedAccuracy, this.satellites = 0,
    this.altitudeReference = 'WGS84 ellipsoid'});
  final double lat, lon, accuracy;
  final double? altitude, verticalAccuracy, speed, heading, speedAccuracy;
  final DateTime time;
  final int receivedAt, satellites;
  final String altitudeReference;
  static GeoFix? fromJson(Map<String,dynamic> m, int now) {
    if (m['lat'] is! num || m['lon'] is! num || m['accuracy'] is! num || m['timestamp'] is! num) return null;
    final lat = number(m,'lat',999), lon = number(m,'lon',999), acc = number(m,'accuracy',-1);
    if (lat.abs()>90 || lon.abs()>180 || acc<0) return null;
    double? optional(String k) => m[k] is num && (m[k] as num).isFinite ? (m[k] as num).toDouble() : null;
    return GeoFix(lat:lat, lon:lon, accuracy:acc,
      time:DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num).toInt(),isUtc:true),
      receivedAt:now, altitude:optional('altitude'), verticalAccuracy:optional('verticalAccuracy'),
      speed:optional('speed'), heading:optional('heading'), speedAccuracy:optional('speedAccuracy'),
      satellites:(m['satellites'] as num?)?.toInt() ?? 0,
      altitudeReference:m['altitudeReference'] as String? ?? 'WGS84 ellipsoid');
  }
  bool usable(int now, DateTime utc, Settings s) {
    final age = utc.difference(time).inMilliseconds;
    return accuracy <= s.gpsMaxAccuracy && age >= -1000 && age <= s.gpsMaxAge*1000 &&
        now-receivedAt <= s.gpsMaxAge*1000;
  }
  Map<String,dynamic> toJson() => {'lat':lat,'lon':lon,'accuracy':accuracy,
    'timestamp':time.millisecondsSinceEpoch,'altitude':altitude,'verticalAccuracy':verticalAccuracy,
    'speed':speed,'heading':heading,'speedAccuracy':speedAccuracy,'satellites':satellites,
    'altitudeReference':altitudeReference};
  double distanceTo(GeoFix other) {
    const r = math.pi / 180;
    final a = math.pow(math.sin((other.lat-lat)*r/2),2) +
        math.cos(lat*r)*math.cos(other.lat*r)*math.pow(math.sin((other.lon-lon)*r/2),2);
    return 6371000*2*math.asin(math.sqrt(a.clamp(0,1)));
  }
}

/// No fabricated GNSS quality: unknown fields use 0 satellites / maximum error.
/// Height is required; fix time is preserved even when retransmitted.
Uint8List gpsPayload(GeoFix f, {int timeOffsetHours = 8}) {
  if (f.altitude == null) throw ArgumentError('Altitude unavailable; do not forward GPS');
  final t=f.time.toUtc().add(Duration(hours:timeOffsetHours));
  final b=Uint8List(48), d=ByteData(48);
  d.setInt32(0,t.year*10000+t.month*100+t.day,Endian.little);
  d.setInt32(4,t.hour*10000+t.minute*100+t.second,Endian.little);
  d.setInt32(8,(f.lon*1e7).round(),Endian.little);
  d.setInt32(12,(f.lat*1e7).round(),Endian.little);
  d.setInt32(16,(f.altitude!*1000).round().clamp(-2147483648,2147483647),Endian.little);
  final velocityKnown=f.speed!=null && f.speed!>=0 && f.heading!=null && f.heading!>=0;
  final speed=velocityKnown ? f.speed!*100 : 0.0, heading=(f.heading??0)*math.pi/180;
  d.setFloat32(20,speed*math.cos(heading),Endian.little);
  d.setFloat32(24,speed*math.sin(heading),Endian.little);
  d.setFloat32(28,0,Endian.little); // no vertical speed from browser geolocation
  int accuracy(double? v, double scale) => v!=null && v>=0 ? (v*scale).round().clamp(0,0xfffffffe) : 0xffffffff;
  d.setUint32(32,accuracy(f.verticalAccuracy,1000),Endian.little);
  d.setUint32(36,accuracy(f.accuracy,1000),Endian.little);
  d.setUint32(40,velocityKnown ? accuracy(f.speedAccuracy,100) : 0xffffffff,Endian.little);
  d.setUint32(44,f.satellites.clamp(0,255),Endian.little);
  b.setAll(0,d.buffer.asUint8List());
  return b;
}

enum ShotResult { requested, actionObserved, failed, unknown }
class Shot {
  Shot({required this.number, required this.at, required this.elapsedMs, required this.manual,
    this.fix, this.sequence, this.result=ShotResult.requested, this.note='', this.acknowledged=false});
  final int number, elapsedMs;
  final DateTime at;
  final bool manual;
  final GeoFix? fix;
  int? sequence;
  ShotResult result;
  String note;
  bool acknowledged;
  String get label => switch(result) {
    ShotResult.requested => '要求送信済み', ShotResult.actionObserved => '撮影動作を検知',
    ShotResult.failed => '要求失敗', ShotResult.unknown => '結果不明'};
  Map<String,dynamic> toJson() => {'number':number,'at':at.toIso8601String(),'elapsedMs':elapsedMs,
    'manual':manual,'fix':fix?.toJson(),'sequence':sequence,'result':result.name,'note':note,
    'acknowledged':acknowledged,'savedFileVerified':false};
  static Shot fromJson(Map<String,dynamic> m) => Shot(number:(m['number'] as num).toInt(),
    at:DateTime.parse(m['at']),elapsedMs:(m['elapsedMs'] as num).toInt(),manual:m['manual']==true,
    fix:m['fix'] is Map ? GeoFix.fromJson(Map<String,dynamic>.from(m['fix']),0) : null,
    sequence:(m['sequence'] as num?)?.toInt(),
    result:ShotResult.values.firstWhere((r)=>r.name==m['result'],orElse:()=>ShotResult.unknown),
    note:m['note'] as String? ?? '',acknowledged:m['acknowledged']==true);
}
