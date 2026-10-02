import 'dart:convert';
import 'dart:typed_data';

/// SPIKE App 3 framing, from the public protocol notes.
///
/// https://lego.github.io/spike-prime-docs/encoding.html
/// The COBS variant escapes 0x00, 0x01, and 0x02. Bytes are then XOR 0x03
/// and a trailing 0x02 closes the frame. This is a direct port of the
/// example in https://github.com/LEGO/spike-prime-docs/blob/main/examples/python/cobs.py

const spikeDelimiter = 0x02;
const _noDelimiter = 0xFF;
const _codeOffset = spikeDelimiter;
const _maxBlock = 84;
const _xor = 3;

List<int> spikeEncode(List<int> data) {
  final buffer = <int>[];
  var codeIndex = 0;
  var block = 0;

  void beginBlock() {
    codeIndex = buffer.length;
    buffer.add(_noDelimiter);
    block = 1;
  }

  beginBlock();
  for (final byte in data) {
    final value = byte & 0xFF;
    if (value > spikeDelimiter) {
      buffer.add(value);
      block += 1;
    }
    if (value <= spikeDelimiter || block > _maxBlock) {
      if (value <= spikeDelimiter) {
        final delimiterBase = value * _maxBlock;
        final blockOffset = block + _codeOffset;
        buffer[codeIndex] = delimiterBase + blockOffset;
      }
      beginBlock();
    }
  }
  buffer[codeIndex] = block + _codeOffset;
  return buffer;
}

List<int> spikeDecode(List<int> data) {
  if (data.isEmpty) {
    throw const FormatException('COBS frame was empty.');
  }
  final buffer = <int>[];

  (int?, int) unescape(int code) {
    if (code == 0xFF) return (null, _maxBlock + 1);
    var adjusted = code - _codeOffset;
    var value = adjusted ~/ _maxBlock;
    var block = adjusted % _maxBlock;
    if (block == 0) {
      block = _maxBlock;
      value -= 1;
    }
    return (value, block);
  }

  var (value, block) = unescape(data[0] & 0xFF);
  for (final raw in data.skip(1)) {
    final byte = raw & 0xFF;
    block -= 1;
    if (block > 0) {
      buffer.add(byte);
      continue;
    }
    if (value != null) buffer.add(value);
    final next = unescape(byte);
    value = next.$1;
    block = next.$2;
  }
  return buffer;
}

Uint8List spikePack(List<int> data) {
  final encoded = spikeEncode(data);
  final out = Uint8List(encoded.length + 1);
  for (var i = 0; i < encoded.length; i++) {
    out[i] = (encoded[i] ^ _xor) & 0xFF;
  }
  out[encoded.length] = spikeDelimiter;
  return out;
}

List<int> spikeUnpack(List<int> frame) {
  if (frame.isEmpty) {
    throw const FormatException('Hub frame was empty.');
  }
  var start = 0;
  if (frame[0] == 0x01) start = 1;
  if (frame.length - start <= 1) return const [];
  final unframed = <int>[];
  for (var i = start; i < frame.length - 1; i++) {
    unframed.add((frame[i] ^ _xor) & 0xFF);
  }
  return spikeDecode(unframed);
}

/// Reassembles GATT notifications into frames that end with 0x02.
class SpikeFramer {
  final _buf = <int>[];

  List<List<int>> add(List<int> chunk) {
    final frames = <List<int>>[];
    for (final byte in chunk) {
      final value = byte & 0xFF;
      _buf.add(value);
      if (value == spikeDelimiter && _buf.length > 1) {
        frames.add(List<int>.from(_buf));
        _buf.clear();
      } else if (value == spikeDelimiter) {
        _buf.clear();
      }
    }
    return frames;
  }
}

/// CRC-32 used by the hub file transfer.
///
/// Matches `binascii.crc32` after padding to a multiple of 4 with 0x00,
/// as in https://github.com/LEGO/spike-prime-docs/blob/main/examples/python/crc.py
int spikeCrc(List<int> data, {int seed = 0, int align = 4}) {
  final padded = List<int>.from(data);
  final remainder = padded.length % align;
  if (remainder != 0) {
    padded.addAll(List<int>.filled(align - remainder, 0));
  }
  var crc = (seed ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  for (final byte in padded) {
    crc ^= byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
      crc &= 0xFFFFFFFF;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class InfoMessage {
  InfoMessage({
    required this.rpcMajor,
    required this.rpcMinor,
    required this.rpcBuild,
    required this.fwMajor,
    required this.fwMinor,
    required this.fwBuild,
    required this.maxPacketSize,
    required this.maxMessageSize,
    required this.maxChunkSize,
    required this.productGroup,
  });

  final int rpcMajor;
  final int rpcMinor;
  final int rpcBuild;
  final int fwMajor;
  final int fwMinor;
  final int fwBuild;
  final int maxPacketSize;
  final int maxMessageSize;
  final int maxChunkSize;
  final int productGroup;

  String get firmwareLabel => '$fwMajor.$fwMinor+$fwBuild';
}

class StatusMessage {
  StatusMessage(this.type, this.ok);
  final int type;
  final bool ok;
}

class ConsoleMessage {
  ConsoleMessage(this.text);
  final String text;
}

class HubNameMessage {
  HubNameMessage(this.name);
  final String name;
}

class ProgramFlowNote {
  ProgramFlowNote(this.stop);
  final bool stop;
}

class PortReading {
  PortReading({
    required this.letter,
    required this.kind,
    this.deviceType,
    this.absPosition,
    this.power,
    this.speed,
    this.position,
    this.force,
    this.pressed,
    this.color,
    this.red,
    this.green,
    this.blue,
    this.distanceMm,
  });

  final String letter;
  final String kind;
  final int? deviceType;
  final int? absPosition;
  final int? power;
  final int? speed;
  final int? position;
  final int? force;
  final bool? pressed;
  final int? color;
  final int? red;
  final int? green;
  final int? blue;
  final int? distanceMm;
}

class DeviceBatch {
  DeviceBatch({
    this.battery,
    this.faceUp,
    this.yawFace,
    this.yaw,
    this.pitch,
    this.roll,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.matrix,
    this.ports = const [],
  });

  final int? battery;
  final int? faceUp;
  final int? yawFace;
  final int? yaw;
  final int? pitch;
  final int? roll;
  final int? accelX;
  final int? accelY;
  final int? accelZ;
  final int? gyroX;
  final int? gyroY;
  final int? gyroZ;
  final List<int>? matrix;
  final List<PortReading> ports;
}

class UnknownMessage {
  UnknownMessage(this.type, this.bytes);
  final int type;
  final List<int> bytes;
}

sealed class HubMessage {}

class InfoHubMessage extends HubMessage {
  InfoHubMessage(this.info);
  final InfoMessage info;
}

class StatusHubMessage extends HubMessage {
  StatusHubMessage(this.status);
  final StatusMessage status;
}

class ConsoleHubMessage extends HubMessage {
  ConsoleHubMessage(this.console);
  final ConsoleMessage console;
}

class HubNameHubMessage extends HubMessage {
  HubNameHubMessage(this.name);
  final HubNameMessage name;
}

class ProgramFlowHubMessage extends HubMessage {
  ProgramFlowHubMessage(this.note);
  final ProgramFlowNote note;
}

class DeviceHubMessage extends HubMessage {
  DeviceHubMessage(this.batch);
  final DeviceBatch batch;
}

class UnknownHubMessage extends HubMessage {
  UnknownHubMessage(this.unknown);
  final UnknownMessage unknown;
}

const portLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

String portLetter(int index) {
  if (index >= 0 && index < portLetters.length) return portLetters[index];
  return '?';
}

String motorTypeName(int type) {
  return switch (type) {
    0x30 => 'Medium motor',
    0x31 => 'Large motor',
    0x41 => 'Small motor',
    _ => 'Motor 0x${type.toRadixString(16)}',
  };
}

const colorNames = {
  0x00: 'black',
  0x01: 'magenta',
  0x02: 'purple',
  0x03: 'blue',
  0x04: 'azure',
  0x05: 'turquoise',
  0x06: 'green',
  0x07: 'yellow',
  0x08: 'orange',
  0x09: 'red',
  0x0A: 'white',
  0xFF: 'none',
};

const faceNames = {
  0: 'top',
  1: 'front',
  2: 'right',
  3: 'bottom',
  4: 'back',
  5: 'left',
};

Uint8List infoRequest() => Uint8List.fromList([0x00]);

Uint8List clearSlotRequest(int slot) => Uint8List.fromList([0x46, slot & 0xFF]);

Uint8List programFlowRequest({required bool stop, required int slot}) {
  return Uint8List.fromList([0x1E, stop ? 1 : 0, slot & 0xFF]);
}

Uint8List deviceNotificationRequest(int intervalMs) {
  final out = Uint8List(3);
  final data = ByteData.sublistView(out);
  data.setUint8(0, 0x28);
  data.setUint16(1, intervalMs & 0xFFFF, Endian.little);
  return out;
}

Uint8List hubNameRequest() => Uint8List.fromList([0x18]);

Uint8List startFileUploadRequest(String name, int slot, int crc) {
  final encoded = _utf8(name);
  if (encoded.length > 31) {
    throw ArgumentError('File name is longer than 31 bytes.');
  }
  final out = BytesBuilder();
  out.addByte(0x0C);
  out.add(encoded);
  out.addByte(0);
  out.addByte(slot & 0xFF);
  out.add(_u32(crc));
  return out.toBytes();
}

Uint8List transferChunkRequest(int runningCrc, List<int> chunk) {
  final out = BytesBuilder();
  out.addByte(0x10);
  out.add(_u32(runningCrc));
  out.add(_u16(chunk.length));
  out.add(chunk);
  return out.toBytes();
}

HubMessage parseHubMessage(List<int> data) {
  if (data.isEmpty) {
    throw const FormatException('Empty hub message.');
  }
  final type = data[0] & 0xFF;
  switch (type) {
    case 0x01:
      return InfoHubMessage(_parseInfo(data));
    case 0x0D:
    case 0x11:
    case 0x1F:
    case 0x29:
    case 0x47:
    case 0x17:
    case 0x0B:
    case 0x15:
      final ok = data.length > 1 && data[1] == 0x00;
      return StatusHubMessage(StatusMessage(type, ok));
    case 0x19:
      return HubNameHubMessage(HubNameMessage(_cString(data.sublist(1))));
    case 0x21:
      return ConsoleHubMessage(ConsoleMessage(_cString(data.sublist(1))));
    case 0x20:
      return ProgramFlowHubMessage(ProgramFlowNote(data.length > 1 && data[1] != 0));
    case 0x3C:
      return DeviceHubMessage(_parseDevices(data));
    default:
      return UnknownHubMessage(UnknownMessage(type, data));
  }
}

InfoMessage _parseInfo(List<int> data) {
  if (data.length < 17) {
    throw FormatException('InfoResponse is ${data.length} bytes, expected 17.');
  }
  final view = ByteData.sublistView(Uint8List.fromList(data));
  return InfoMessage(
    rpcMajor: view.getUint8(1),
    rpcMinor: view.getUint8(2),
    rpcBuild: view.getUint16(3, Endian.little),
    fwMajor: view.getUint8(5),
    fwMinor: view.getUint8(6),
    fwBuild: view.getUint16(7, Endian.little),
    maxPacketSize: view.getUint16(9, Endian.little),
    maxMessageSize: view.getUint16(11, Endian.little),
    maxChunkSize: view.getUint16(13, Endian.little),
    productGroup: view.getUint16(15, Endian.little),
  );
}

DeviceBatch _parseDevices(List<int> data) {
  if (data.length < 3) {
    throw const FormatException('Device notification is too short.');
  }
  final view = ByteData.sublistView(Uint8List.fromList(data));
  final size = view.getUint16(1, Endian.little);
  final payload = data.sublist(3, 3 + (size < data.length - 3 ? size : data.length - 3));
  var offset = 0;
  int? battery;
  int? faceUp;
  int? yawFace;
  int? yaw;
  int? pitch;
  int? roll;
  int? ax;
  int? ay;
  int? az;
  int? gx;
  int? gy;
  int? gz;
  List<int>? matrix;
  final ports = <PortReading>[];
  final bytes = ByteData.sublistView(Uint8List.fromList(payload));
  DeviceBatch truncated() => DeviceBatch(battery: battery, ports: ports);

  while (offset < payload.length) {
    final kind = payload[offset] & 0xFF;
    switch (kind) {
      case 0x00:
        if (offset + 2 > payload.length) return truncated();
        battery = payload[offset + 1] & 0xFF;
        offset += 2;
      case 0x01:
        if (offset + 21 > payload.length) return truncated();
        faceUp = bytes.getUint8(offset + 1);
        yawFace = bytes.getUint8(offset + 2);
        yaw = bytes.getInt16(offset + 3, Endian.little);
        pitch = bytes.getInt16(offset + 5, Endian.little);
        roll = bytes.getInt16(offset + 7, Endian.little);
        ax = bytes.getInt16(offset + 9, Endian.little);
        ay = bytes.getInt16(offset + 11, Endian.little);
        az = bytes.getInt16(offset + 13, Endian.little);
        gx = bytes.getInt16(offset + 15, Endian.little);
        gy = bytes.getInt16(offset + 17, Endian.little);
        gz = bytes.getInt16(offset + 19, Endian.little);
        offset += 21;
      case 0x02:
        if (offset + 26 > payload.length) return truncated();
        matrix = payload.sublist(offset + 1, offset + 26);
        offset += 26;
      case 0x0A:
        if (offset + 12 > payload.length) return truncated();
        ports.add(
          PortReading(
            letter: portLetter(payload[offset + 1] & 0xFF),
            kind: 'motor',
            deviceType: payload[offset + 2] & 0xFF,
            absPosition: bytes.getInt16(offset + 3, Endian.little),
            power: bytes.getInt16(offset + 5, Endian.little),
            speed: bytes.getInt8(offset + 7),
            position: bytes.getInt32(offset + 8, Endian.little),
          ),
        );
        offset += 12;
      case 0x0B:
        if (offset + 4 > payload.length) return truncated();
        ports.add(
          PortReading(
            letter: portLetter(payload[offset + 1] & 0xFF),
            kind: 'force',
            force: payload[offset + 2] & 0xFF,
            pressed: payload[offset + 3] == 0x01,
          ),
        );
        offset += 4;
      case 0x0C:
        if (offset + 9 > payload.length) return truncated();
        ports.add(
          PortReading(
            letter: portLetter(payload[offset + 1] & 0xFF),
            kind: 'color',
            color: bytes.getInt8(offset + 2),
            red: bytes.getUint16(offset + 3, Endian.little),
            green: bytes.getUint16(offset + 5, Endian.little),
            blue: bytes.getUint16(offset + 7, Endian.little),
          ),
        );
        offset += 9;
      case 0x0D:
        if (offset + 4 > payload.length) return truncated();
        ports.add(
          PortReading(
            letter: portLetter(payload[offset + 1] & 0xFF),
            kind: 'distance',
            distanceMm: bytes.getInt16(offset + 2, Endian.little),
          ),
        );
        offset += 4;
      case 0x0E:
        if (offset + 11 > payload.length) return truncated();
        ports.add(
          PortReading(
            letter: portLetter(payload[offset + 1] & 0xFF),
            kind: 'matrix',
          ),
        );
        offset += 11;
      default:
        offset = payload.length;
    }
  }

  return DeviceBatch(
    battery: battery,
    faceUp: faceUp,
    yawFace: yawFace,
    yaw: yaw,
    pitch: pitch,
    roll: roll,
    accelX: ax,
    accelY: ay,
    accelZ: az,
    gyroX: gx,
    gyroY: gy,
    gyroZ: gz,
    matrix: matrix,
    ports: ports,
  );
}

String _cString(List<int> bytes) {
  final end = bytes.indexOf(0);
  final slice = end >= 0 ? bytes.sublist(0, end) : bytes;
  return utf8.decode(slice, allowMalformed: true);
}

List<int> _utf8(String text) => utf8.encode(text);

List<int> _u16(int value) {
  final v = value & 0xFFFF;
  return [v & 0xFF, (v >> 8) & 0xFF];
}

List<int> _u32(int value) {
  final v = value & 0xFFFFFFFF;
  return [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
}

String bytesHex(List<int> bytes) {
  return bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
}

List<int> hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final out = <int>[];
  for (var i = 0; i < clean.length; i += 2) {
    out.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return out;
}
