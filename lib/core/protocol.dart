import 'dart:typed_data';

/// Independent implementation of the published DJI R SDK wire format.
/// Reflected CRCs use DJI's 0x3aa3 seed and no final xor.
int crc16(Iterable<int> bytes) => _crc(bytes, 0xa001, 0xffff);
int crc32(Iterable<int> bytes) => _crc(bytes, 0xedb88320, 0xffffffff);
int _crc(Iterable<int> bytes, int polynomial, int mask) {
  var crc = 0x3aa3;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? polynomial : 0);
    }
  }
  return crc & mask;
}

class Frame {
  const Frame(this.set, this.id, this.sequence, this.type, this.payload);
  final int set, id, sequence, type;
  final Uint8List payload;
  bool get isAck => (type & 0x20) != 0;
  Uint8List encode() {
    final size = payload.length + 18;
    if (size > 1023) throw ArgumentError('Frame too large');
    final bytes = Uint8List(size);
    final data = ByteData.sublistView(bytes);
    bytes[0] = 0xaa;
    data.setUint16(1, size, Endian.little);
    bytes[3] = type;
    data.setUint16(8, sequence, Endian.little);
    data.setUint16(10, crc16(bytes.take(10)), Endian.little);
    bytes[12] = set;
    bytes[13] = id;
    bytes.setRange(14, size - 4, payload);
    data.setUint32(size - 4, crc32(bytes.take(size - 4)), Endian.little);
    return bytes;
  }
}

/// Notification boundaries need not coincide with frame boundaries.
/// Invalid lengths/CRC resynchronise one byte at a time; memory is bounded.
class FrameDecoder {
  final List<int> _buffer = [];
  int rejected = 0;
  void reset() => _buffer.clear();
  List<Frame> add(List<int> chunk) {
    final frames = <Frame>[];
    for (final byte in chunk) {
      _buffer.add(byte & 255);
      while (_buffer.isNotEmpty) {
        if (_buffer.first != 0xaa) { _buffer.removeAt(0); continue; }
        if (_buffer.length < 12) break;
        final length = _buffer[1] | (_buffer[2] << 8);
        final headerCrc = _buffer[10] | (_buffer[11] << 8);
        if (length < 18 || length > 1023 || _buffer[4] != 0 ||
            crc16(_buffer.take(10)) != headerCrc) {
          rejected++; _buffer.removeAt(0); continue;
        }
        if (_buffer.length < length) break;
        final bytes = Uint8List.fromList(_buffer.take(length).toList());
        final d = ByteData.sublistView(bytes);
        if (crc32(bytes.take(length - 4)) != d.getUint32(length - 4, Endian.little)) {
          rejected++; _buffer.removeAt(0); continue;
        }
        frames.add(Frame(bytes[12], bytes[13], d.getUint16(8, Endian.little),
            bytes[3], Uint8List.sublistView(bytes, 14, length - 4)));
        _buffer.removeRange(0, length);
      }
    }
    return frames;
  }
}

Uint8List connectionPayload(List<int> identity, int code, {bool paired = false}) {
  if (identity.length != 6) throw ArgumentError('6-byte identity required');
  final b = Uint8List(33);
  final d = ByteData.sublistView(b);
  d.setUint32(0, 0x12345678, Endian.little);
  b[4] = 6;
  b.setRange(5, 11, identity);
  b[26] = paired ? 0 : 1;
  d.setUint16(27, code, Endian.little);
  return b;
}

Uint8List connectionAckPayload() {
  final b = Uint8List(9);
  ByteData.sublistView(b).setUint32(0, 0x12345678, Endian.little);
  return b;
}

Uint8List photoModePayload(int cameraId) {
  final b = Uint8List(9);
  ByteData.sublistView(b).setUint32(0, cameraId, Endian.little);
  b[4] = 0x3f;
  return b;
}

class CameraStatus {
  const CameraStatus({required this.mode, required this.state, required this.battery,
    required this.remainingPhotos, required this.capacityMb, required this.temperature,
    required this.power, required this.countdownMs, required this.receivedAt});
  final int mode, state, battery, remainingPhotos, capacityMb, temperature, power, countdownMs;
  final int receivedAt;
  bool get busy => state == 3 || countdownMs > 0;
  bool get ready => mode == 0x3f && state == 1 && power == 0 &&
      temperature < 2 && remainingPhotos > 0 && capacityMb > 0 && countdownMs == 0;
  static CameraStatus? parse(Uint8List b, int now) {
    if (b.length < 38) return null;
    final d = ByteData.sublistView(b);
    return CameraStatus(mode:b[0], state:b[1], battery:b[37],
      capacityMb:d.getUint32(15, Endian.little), remainingPhotos:d.getUint32(19, Endian.little),
      power:b[28], temperature:b[30], countdownMs:d.getUint32(31, Endian.little), receivedAt:now);
  }
}
