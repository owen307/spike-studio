import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/spike_codec.dart';
import '../protocol/spike_rpc.dart';
import 'hub_models.dart';

const spikeServiceUuid = '0000fd02-0000-1000-8000-00805f9b34fb';
const spikeRxUuid = '0000fd02-0001-1000-8000-00805f9b34fb';
const spikeTxUuid = '0000fd02-0002-1000-8000-00805f9b34fb';

class _BlePipe implements BytePipe {
  _BlePipe(this.writeChar);
  final BluetoothCharacteristic writeChar;
  final _inbound = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _sub;

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  void listen(BluetoothCharacteristic notifyChar) {
    _sub = notifyChar.onValueReceived.listen(_inbound.add);
  }

  @override
  Future<void> write(List<int> data) {
    return writeChar.write(data, withoutResponse: true);
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _inbound.close();
  }
}

class BleHubLink implements HubLink {
  final _live = StreamController<HubLive>.broadcast();
  final _console = StreamController<String>.broadcast();
  final _devices = StreamController<List<DiscoveredHub>>.broadcast();
  var _current = HubLive.idle(mock: false);
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<HubMessage>? _rpcSub;
  BluetoothDevice? _device;
  _BlePipe? _pipe;
  SpikeRpc? _rpc;
  final _seen = <String, DiscoveredHub>{};

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
    _seen.clear();
    _publishDevices();
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('This computer has no Bluetooth LE stack this build can use.');
    }
    await _ensurePermissions();
    final adapter = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 4));
    if (adapter != BluetoothAdapterState.on) {
      throw StateError('Bluetooth is off. Turn it on, then scan again.');
    }
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        final advName = result.advertisementData.advName;
        final platformName = result.device.platformName;
        final name = advName.isNotEmpty ? advName : (platformName.isNotEmpty ? platformName : 'Unnamed');
        final uuids = result.advertisementData.serviceUuids.map((guid) => guid.str.toLowerCase());
        final confirmed = uuids.any((uuid) => uuid.contains('fd02'));
        final lower = name.toLowerCase();
        final likely = confirmed || lower.contains('spike') || lower.contains('lego') || lower.contains('hub');
        if (!likely) continue;
        _seen[id] = DiscoveredHub(
          id: id,
          name: name,
          rssi: result.rssi,
          confirmed: confirmed,
          likely: likely,
        );
      }
      _publishDevices();
    });
    _say('Scanning for hubs advertising service $spikeServiceUuid.');
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
      withServices: const [],
    );
    _say('Scan finished. ${ _seen.length} possible hub${_seen.length == 1 ? '' : 's'}.');
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<void> connect(DiscoveredHub hub) async {
    await disconnect();
    final device = BluetoothDevice.fromId(hub.id);
    _device = device;
    _set(status: 'Connecting to ${hub.name}...');
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
        mtu: 512,
      );
      final services = await device.discoverServices();
      final service = services.cast<BluetoothService?>().firstWhere(
        (item) => item!.uuid.str.toLowerCase() == spikeServiceUuid,
        orElse: () => null,
      );
      if (service == null) {
        throw StateError(
          'This device does not expose the SPIKE App 3 service $spikeServiceUuid. '
          'Pybricks and older LWP3 hubs use a different radio protocol. '
          'Power a hub running the SPIKE 3 app firmware and disconnect it from other apps.',
        );
      }
      final rx = _char(service, spikeRxUuid);
      final tx = _char(service, spikeTxUuid);
      if (rx == null || tx == null) {
        throw StateError('The hub service is missing the RX or TX characteristic.');
      }
      await tx.setNotifyValue(true);
      final pipe = _BlePipe(rx);
      pipe.listen(tx);
      final rpc = SpikeRpc(pipe, onLog: _say);
      rpc.start();
      _pipe = pipe;
      _rpc = rpc;
      await _rpcSub?.cancel();
      _rpcSub = rpc.messages.listen(_onMessage);
      _set(
        connected: true,
        status: 'Connected. Asking the hub for its info.',
        hubName: hub.name,
      );
      final info = await rpc.request(infoRequest(), 0x01);
      if (info is! InfoHubMessage) {
        throw StateError('The hub did not answer InfoRequest.');
      }
      rpc.info = info.info;
      _set(
        connected: true,
        firmware: info.info.firmwareLabel,
        status: 'Connected. Firmware ${info.info.firmwareLabel}.',
      );
      try {
        final name = await rpc.request(hubNameRequest(), 0x19);
        if (name is HubNameHubMessage && name.name.name.isNotEmpty) {
          _set(hubName: name.name.name);
        }
      } catch (_) {}
      await rpc.setNotifyInterval(200);
      _say('Live readings are on, about every 200 ms.');
    } catch (error) {
      _say('Connect failed: $error');
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _rpcSub?.cancel();
    _rpcSub = null;
    await _rpc?.close();
    _rpc = null;
    await _pipe?.close();
    _pipe = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _current = HubLive.idle(mock: false);
    _emit();
  }

  @override
  Future<void> setNotifyInterval(int ms) async {
    final rpc = _rpc;
    if (rpc == null) throw StateError('Connect a hub first.');
    await rpc.setNotifyInterval(ms);
  }

  @override
  Future<void> uploadAndRun(String python, {required int slot}) async {
    final rpc = _rpc;
    if (rpc == null) throw StateError('Connect a hub before downloading.');
    if (slot < 0 || slot > 19) throw StateError('Program slot must be 0 through 19.');
    _say('Uploading program.py to slot $slot. This replaces whatever is in that slot.');
    await rpc.uploadAndStart(asBytes(python), slot: slot, notifyMs: 200);
    _set(slot: slot, status: 'Program running in slot $slot.');
  }

  @override
  Future<void> stopProgram(int slot) async {
    final rpc = _rpc;
    if (rpc == null) throw StateError('Connect a hub first.');
    await rpc.stopSlot(slot);
    _set(status: 'Stop sent to slot $slot.');
  }

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();
    await disconnect();
    await _live.close();
    await _console.close();
    await _devices.close();
  }

  void _onMessage(HubMessage message) {
    if (message is DeviceHubMessage) {
      _current = _current.mergeDevices(message.batch);
      _emit();
    } else if (message is ConsoleHubMessage) {
      _say('Hub: ${message.console.text}');
    } else if (message is ProgramFlowHubMessage) {
      _set(status: message.note.stop ? 'Hub stopped the program.' : 'Hub started the program.');
    }
  }

  BluetoothCharacteristic? _char(BluetoothService service, String uuid) {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid.str.toLowerCase() == uuid) return characteristic;
    }
    return null;
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final legacy = await Permission.bluetooth.request();
    final location = await Permission.locationWhenInUse.request();
    final scanOk = scan.isGranted || scan.isLimited || legacy.isGranted;
    final connectOk = connect.isGranted || connect.isLimited || legacy.isGranted;
    if (!scanOk || !connectOk) {
      throw StateError(
        'Bluetooth permission was denied. Allow Nearby devices for Spike Prime Studio. '
        'On Android 11 and older, Location must also be allowed so the system will return scan results. '
        'This app does not track where you are.',
      );
    }
    if (!location.isGranted && !location.isLimited) {
      _say('Location permission was not granted. Android 12 and newer can still scan. Older Android may show no hubs.');
    }
  }

  void _publishDevices() {
    final list = _seen.values.toList()
      ..sort((a, b) {
        if (a.confirmed != b.confirmed) return a.confirmed ? -1 : 1;
        return (b.rssi ?? -999).compareTo(a.rssi ?? -999);
      });
    if (!_devices.isClosed) _devices.add(list);
  }

  void _set({
    bool? connected,
    String? status,
    String? hubName,
    String? firmware,
    int? slot,
  }) {
    _current = _current.copyWith(
      connected: connected,
      mock: false,
      status: status,
      hubName: hubName,
      firmware: firmware,
      slot: slot,
    );
    _emit();
  }

  void _emit() {
    if (!_live.isClosed) _live.add(_current);
  }

  void _say(String line) {
    if (!_console.isClosed) _console.add(line);
  }
}
