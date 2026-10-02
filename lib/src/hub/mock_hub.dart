import 'dart:async';

import '../protocol/spike_codec.dart';
import '../protocol/spike_rpc.dart';
import 'hub_models.dart';

class MockHubLink implements HubLink {
  final _live = StreamController<HubLive>.broadcast();
  final _console = StreamController<String>.broadcast();
  final _devices = StreamController<List<DiscoveredHub>>.broadcast();
  var _current = HubLive.idle();
  var _interval = 100;
  Timer? _timer;
  final _motors = <String, int>{'A': 0, 'B': 0};
  int _distance = 420;
  int _force = 0;
  bool _pressed = false;
  int _color = 0;
  final int _battery = 86;

  @override
  bool get isMock => true;

  @override
  HubLive get current => _current;

  @override
  Stream<HubLive> get live => _live.stream;

  @override
  Stream<String> get console => _console.stream;

  @override
  Stream<List<DiscoveredHub>> get devices => _devices.stream;

  static const discovered = DiscoveredHub(
    id: 'mock-hub',
    name: 'Mock hub (no radio)',
    rssi: -42,
    confirmed: true,
    mock: true,
  );

  @override
  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    _say('Scanning for a mock hub. This does not use Bluetooth.');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _devices.add(const [discovered]);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(DiscoveredHub hub) async {
    _current = _snapshot('Mock hub connected. Nothing is on the radio.');
    _emit();
    _say('Mock hub connected. Teach and playback stay on this computer.');
    _restartTimer();
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _current = HubLive.idle();
    _emit();
    _say('Mock hub disconnected.');
  }

  @override
  Future<void> setNotifyInterval(int ms) async {
    _interval = ms.clamp(50, 2000);
    if (_current.connected) _restartTimer();
  }

  @override
  Future<void> uploadAndRun(String python, {required int slot}) async {
    final crc = spikeCrc(asBytes(python));
    _say('Mock: InfoRequest, clear slot $slot, upload program.py (${python.length} bytes, crc $crc).');
    _say('Mock: ProgramFlow start. No bytes were sent to a hub.');
    _say('Mock playback only follows simple motor.run_for_degrees and motor_pair lines.');
    _current = _current.copyWith(status: 'Mock is playing the program locally.', slot: slot);
    _emit();
    await _simulate(python);
  }

  @override
  Future<void> stopProgram(int slot) async {
    _say('Mock: ProgramFlow stop on slot $slot.');
    _current = _current.copyWith(status: 'Mock program stopped.');
    _emit();
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _live.close();
    await _console.close();
    await _devices.close();
  }

  void setMotor(String letter, int position) {
    _motors[letter] = position;
    _emit();
  }

  void setDistance(int mm) {
    _distance = mm;
    _emit();
  }

  void setForce(int force, {bool? pressed}) {
    _force = force.clamp(0, 100);
    _pressed = pressed ?? _force > 30;
    _emit();
  }

  void setColor(int color) {
    _color = color;
    _emit();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _interval), (_) => _emit());
  }

  void _emit() {
    _current = _snapshot(_current.status);
    if (!_live.isClosed) _live.add(_current);
  }

  HubLive _snapshot(String status) {
    final ports = <PortReading>[
      for (final letter in portLetters)
        if (_motors.containsKey(letter))
          PortReading(
            letter: letter,
            kind: 'motor',
            deviceType: 0x31,
            position: _motors[letter],
            absPosition: wrapAbs(_motors[letter]!),
            speed: 0,
            power: 0,
          )
        else if (letter == 'C')
          PortReading(letter: letter, kind: 'distance', distanceMm: _distance)
        else if (letter == 'D')
          PortReading(
            letter: letter,
            kind: 'color',
            color: _color,
            red: _color == 9 ? 800 : 20,
            green: _color == 6 ? 800 : 20,
            blue: _color == 3 ? 800 : 20,
          )
        else if (letter == 'E')
          PortReading(letter: letter, kind: 'force', force: _force, pressed: _pressed)
        else
          PortReading(letter: letter, kind: 'empty'),
    ];
    return HubLive(
      connected: true,
      mock: true,
      status: status,
      hubName: 'Mock hub',
      firmware: 'mock App 3 shape',
      battery: _battery,
      yaw: 0,
      pitch: 0,
      roll: 0,
      face: 'top',
      ports: ports,
      matrix: List<int>.filled(25, 0),
      slot: _current.slot,
    );
  }

  Future<void> _simulate(String python) async {
    final moves = <(String, int)>[];
    final motor = RegExp(r'motor\.run_for_degrees\(port\.([A-F]),\s*(-?\d+)');
    for (final match in motor.allMatches(python)) {
      moves.add((match.group(1)!, int.parse(match.group(2)!)));
    }
    final pair = RegExp(
      r'motor_pair\.pair\(motor_pair\.PAIR_1,\s*port\.([A-F]),\s*port\.([A-F])\)\s*'
      r'(?:await\s+)?(?:_m\d+\s*=\s*)?motor_pair\.move_for_degrees\(motor_pair\.PAIR_1,\s*(-?\d+)',
    );
    for (final match in pair.allMatches(python.replaceAll('\n', ' '))) {
      final degrees = int.parse(match.group(3)!);
      moves.add((match.group(1)!, degrees));
      moves.add((match.group(2)!, degrees));
    }
    if (moves.isEmpty) return;
    final origins = {for (final entry in _motors.entries) entry.key: entry.value};
    final totals = <String, int>{};
    for (final (letter, degrees) in moves) {
      totals[letter] = (totals[letter] ?? 0) + degrees;
    }
    const steps = 12;
    for (var step = 1; step <= steps; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      for (final entry in totals.entries) {
        final origin = origins[entry.key] ?? 0;
        _motors[entry.key] = origin + (entry.value * step / steps).round();
      }
      _emit();
    }
  }

  void _say(String line) {
    if (!_console.isClosed) _console.add(line);
  }
}

int wrapAbs(int position) {
  var angle = position % 360;
  if (angle > 179) angle -= 360;
  if (angle < -180) angle += 360;
  return angle;
}
