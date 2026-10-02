import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'spike_codec.dart';

abstract class BytePipe {
  Stream<List<int>> get inbound;
  Future<void> write(List<int> data);
}

/// App 3 session steps, in the order of the official example client:
/// InfoRequest, device notifications, clear slot, file upload, ProgramFlow start.
///
/// https://github.com/LEGO/spike-prime-docs/blob/main/examples/python/app.py
class SpikeRpc {
  SpikeRpc(this.pipe, {this.onLog});

  final BytePipe pipe;
  final void Function(String line)? onLog;
  final _framer = SpikeFramer();
  final _messages = StreamController<HubMessage>.broadcast();
  StreamSubscription<List<int>>? _sub;
  Completer<HubMessage>? _pending;
  int? _pendingType;
  InfoMessage? info;

  Stream<HubMessage> get messages => _messages.stream;

  void start() {
    _sub ??= pipe.inbound.listen(_onBytes, onError: (Object error) {
      onLog?.call('Radio read failed: $error');
    });
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.completeError(StateError('Hub link closed.'));
    }
  }

  Future<void> uploadAndStart(
    List<int> program, {
    required int slot,
    int notifyMs = 200,
    String filename = 'program.py',
  }) async {
    if (program.isEmpty) {
      throw StateError('Refusing to upload an empty program.');
    }
    final infoResponse = await request(infoRequest(), 0x01);
    if (infoResponse is! InfoHubMessage) {
      throw StateError('Hub did not return an InfoResponse.');
    }
    info = infoResponse.info;
    onLog?.call(
      'Hub firmware ${info!.firmwareLabel}, RPC ${info!.rpcMajor}.${info!.rpcMinor}.${info!.rpcBuild}, '
      'packet ${info!.maxPacketSize}, chunk ${info!.maxChunkSize}.',
    );
    if (info!.productGroup != 0) {
      onLog?.call(
        'Product group ${info!.productGroup} is not the documented SPIKE Prime value 0. Continuing anyway.',
      );
    }

    final notify = await request(deviceNotificationRequest(notifyMs), 0x29);
    if (notify is StatusHubMessage && !notify.status.ok) {
      throw StateError('Hub refused device notifications.');
    }

    try {
      final name = await request(hubNameRequest(), 0x19);
      if (name is HubNameHubMessage && name.name.name.isNotEmpty) {
        onLog?.call('Hub name: ${name.name.name}');
      }
    } catch (error) {
      onLog?.call('Hub name was not returned ($error).');
    }

    final clear = await request(clearSlotRequest(slot), 0x47);
    if (clear is StatusHubMessage && !clear.status.ok) {
      onLog?.call('Clear slot $slot was not acknowledged. The slot may already be empty. Continuing.');
    }

    final fileCrc = spikeCrc(program);
    final start = await request(startFileUploadRequest(filename, slot, fileCrc), 0x0D);
    if (start is! StatusHubMessage || !start.status.ok) {
      throw StateError('Hub refused the program.py upload.');
    }

    final chunkSize = info!.maxChunkSize <= 0 ? 64 : info!.maxChunkSize;
    var running = 0;
    for (var offset = 0; offset < program.length; offset += chunkSize) {
      final end = offset + chunkSize > program.length ? program.length : offset + chunkSize;
      final chunk = program.sublist(offset, end);
      running = spikeCrc(chunk, seed: running);
      final chunkResponse = await request(transferChunkRequest(running, chunk), 0x11);
      if (chunkResponse is! StatusHubMessage || !chunkResponse.status.ok) {
        throw StateError('Hub rejected a program chunk at byte $offset.');
      }
    }

    final flow = await request(programFlowRequest(stop: false, slot: slot), 0x1F);
    if (flow is! StatusHubMessage || !flow.status.ok) {
      throw StateError('Hub did not start slot $slot.');
    }
    onLog?.call('Program started in slot $slot.');
  }

  Future<void> stopSlot(int slot) async {
    final flow = await request(programFlowRequest(stop: true, slot: slot), 0x1F);
    if (flow is StatusHubMessage && !flow.status.ok) {
      throw StateError('Hub did not acknowledge stop.');
    }
  }

  Future<void> setNotifyInterval(int intervalMs) async {
    final response = await request(deviceNotificationRequest(intervalMs), 0x29);
    if (response is StatusHubMessage && !response.status.ok) {
      throw StateError('Hub refused the notification interval.');
    }
  }

  Future<HubMessage> request(
    List<int> payload,
    int responseType, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_pending != null && !_pending!.isCompleted) {
      throw StateError('Another hub request is still waiting.');
    }
    final waiter = Completer<HubMessage>();
    _pending = waiter;
    _pendingType = responseType;
    try {
      await send(payload);
      return await waiter.future.timeout(timeout);
    } finally {
      if (identical(_pending, waiter)) {
        _pending = null;
        _pendingType = null;
      }
    }
  }

  Future<void> send(List<int> payload) async {
    final frame = spikePack(payload);
    final packetSize = (info == null || info!.maxPacketSize <= 0) ? frame.length : info!.maxPacketSize;
    onLog?.call('TX ${messageName(payload.isEmpty ? -1 : payload[0])} (${frame.length} frame bytes)');
    for (var offset = 0; offset < frame.length; offset += packetSize) {
      final end = offset + packetSize > frame.length ? frame.length : offset + packetSize;
      await pipe.write(frame.sublist(offset, end));
    }
  }

  void _onBytes(List<int> chunk) {
    for (final frame in _framer.add(chunk)) {
      List<int> payload;
      try {
        payload = spikeUnpack(frame);
      } catch (error) {
        onLog?.call('Could not unpack a hub frame: $error');
        continue;
      }
      if (payload.isEmpty) continue;
      HubMessage message;
      try {
        message = parseHubMessage(payload);
      } catch (error) {
        onLog?.call('Could not parse a hub message: $error');
        continue;
      }
      onLog?.call('RX ${describe(message)}');
      if (!_messages.isClosed) _messages.add(message);
      final waiter = _pending;
      if (waiter != null && !waiter.isCompleted && payload[0] == _pendingType) {
        waiter.complete(message);
      }
    }
  }
}

String messageName(int type) {
  return switch (type) {
    0x00 => 'InfoRequest',
    0x01 => 'InfoResponse',
    0x0C => 'StartFileUpload',
    0x0D => 'StartFileUploadResponse',
    0x10 => 'TransferChunk',
    0x11 => 'TransferChunkResponse',
    0x18 => 'GetHubName',
    0x19 => 'HubName',
    0x1E => 'ProgramFlow',
    0x1F => 'ProgramFlowResponse',
    0x20 => 'ProgramFlowNotification',
    0x21 => 'Console',
    0x28 => 'DeviceNotificationRequest',
    0x29 => 'DeviceNotificationResponse',
    0x3C => 'DeviceNotification',
    0x46 => 'ClearSlot',
    0x47 => 'ClearSlotResponse',
    _ => 'Message 0x${type.toRadixString(16)}',
  };
}

String describe(HubMessage message) {
  return switch (message) {
    InfoHubMessage(:final info) => 'InfoResponse ${info.firmwareLabel}',
    StatusHubMessage(:final status) => '${messageName(status.type)} ${status.ok ? 'ack' : 'nack'}',
    ConsoleHubMessage(:final console) => 'Console ${console.text}',
    HubNameHubMessage(:final name) => 'HubName ${name.name}',
    ProgramFlowHubMessage(:final note) => note.stop ? 'Program stopped' : 'Program started',
    DeviceHubMessage(:final batch) => 'Devices battery=${batch.battery ?? '-'} ports=${batch.ports.length}',
    UnknownHubMessage(:final unknown) => 'Unknown 0x${unknown.type.toRadixString(16)}',
  };
}

Uint8List asBytes(String text) => Uint8List.fromList(utf8.encode(text));
