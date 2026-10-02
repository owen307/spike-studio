import '../protocol/spike_codec.dart';

class DiscoveredHub {
  const DiscoveredHub({
    required this.id,
    required this.name,
    this.rssi,
    this.confirmed = false,
    this.likely = false,
    this.mock = false,
  });

  final String id;
  final String name;
  final int? rssi;
  final bool confirmed;
  final bool likely;
  final bool mock;
}

class HubLive {
  const HubLive({
    required this.connected,
    required this.mock,
    required this.status,
    this.hubName,
    this.firmware,
    this.battery,
    this.yaw,
    this.pitch,
    this.roll,
    this.face,
    this.matrix = const [],
    this.ports = const [],
    this.slot,
  });

  final bool connected;
  final bool mock;
  final String status;
  final String? hubName;
  final String? firmware;
  final int? battery;
  final int? yaw;
  final int? pitch;
  final int? roll;
  final String? face;
  final List<int> matrix;
  final List<PortReading> ports;
  final int? slot;

  factory HubLive.idle({bool mock = true}) {
    return HubLive(
      connected: false,
      mock: mock,
      status: mock ? 'Mock hub is standing by.' : 'Not connected.',
      ports: [for (final letter in portLetters) PortReading(letter: letter, kind: 'empty')],
    );
  }

  PortReading port(String letter) {
    return ports.firstWhere(
      (port) => port.letter == letter,
      orElse: () => PortReading(letter: letter, kind: 'empty'),
    );
  }

  HubLive copyWith({
    bool? connected,
    bool? mock,
    String? status,
    String? hubName,
    String? firmware,
    int? battery,
    int? yaw,
    int? pitch,
    int? roll,
    String? face,
    List<int>? matrix,
    List<PortReading>? ports,
    int? slot,
  }) {
    return HubLive(
      connected: connected ?? this.connected,
      mock: mock ?? this.mock,
      status: status ?? this.status,
      hubName: hubName ?? this.hubName,
      firmware: firmware ?? this.firmware,
      battery: battery ?? this.battery,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      face: face ?? this.face,
      matrix: matrix ?? this.matrix,
      ports: ports ?? this.ports,
      slot: slot ?? this.slot,
    );
  }

  HubLive mergeDevices(DeviceBatch batch) {
    final next = [...ports];
    for (final reading in batch.ports) {
      final index = next.indexWhere((port) => port.letter == reading.letter);
      if (index >= 0) {
        next[index] = reading;
      } else {
        next.add(reading);
      }
    }
    return copyWith(
      battery: batch.battery ?? battery,
      yaw: batch.yaw ?? yaw,
      pitch: batch.pitch ?? pitch,
      roll: batch.roll ?? roll,
      face: batch.faceUp == null ? face : (faceNames[batch.faceUp] ?? face),
      matrix: batch.matrix ?? matrix,
      ports: next,
    );
  }
}

abstract class HubLink {
  bool get isMock;
  HubLive get current;
  Stream<HubLive> get live;
  Stream<String> get console;
  Stream<List<DiscoveredHub>> get devices;
  Future<void> scan({Duration timeout = const Duration(seconds: 8)});
  Future<void> stopScan();
  Future<void> connect(DiscoveredHub hub);
  Future<void> disconnect();
  Future<void> setNotifyInterval(int ms);
  Future<void> uploadAndRun(String python, {required int slot});
  Future<void> stopProgram(int slot);
  Future<void> dispose();
}
