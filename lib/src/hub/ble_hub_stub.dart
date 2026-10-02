import 'dart:async';

import 'hub_models.dart';

class BleHubLink implements HubLink {
  final _live = StreamController<HubLive>.broadcast();
  final _console = StreamController<String>.broadcast();
  final _devices = StreamController<List<DiscoveredHub>>.broadcast();
  var _current = HubLive.idle(mock: false);

  @override
  bool get isMock => false;

  @override
  HubLive get current => _current;

  @override
  Stream<HubLive> get live => _live.stream;

  @override
  Stream<String> get console => _console.stream;

  @override
  Stream<List<DiscoveredHub>> get devices => _devices.stream;

  @override
  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    throw StateError(
      'This browser build cannot open the hub radio. Use the Android app or the desktop build, or stay on the mock hub.',
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(DiscoveredHub hub) async {
    throw StateError('Bluetooth is not available in this browser build.');
  }

  @override
  Future<void> disconnect() async {
    _current = HubLive.idle(mock: false);
    _live.add(_current);
  }

  @override
  Future<void> setNotifyInterval(int ms) async {}

  @override
  Future<void> uploadAndRun(String python, {required int slot}) async {
    throw StateError('Connect from the Android or desktop build to download a program.');
  }

  @override
  Future<void> stopProgram(int slot) async {}

  @override
  Future<void> dispose() async {
    await _live.close();
    await _console.close();
    await _devices.close();
  }
}
