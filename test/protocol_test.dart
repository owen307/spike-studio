import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spike_prime_studio/src/protocol/spike_codec.dart';
import 'package:spike_prime_studio/src/protocol/spike_rpc.dart';

void main() {
  test('crc matches the official binascii helper', () {
    expect(spikeCrc('hello'.codeUnits), 4279481629);
    expect(spikeCrc([0x61]), 2732478330);
    var running = spikeCrc('abcde'.codeUnits);
    expect(running, 2338359752);
    running = spikeCrc('fghi'.codeUnits, seed: running);
    expect(running, 2840675804);
  });

  test('pack and unpack match the official COBS vectors', () {
    const cases = [
      (
        '0001020304050600010203040554ea36002d170c',
        '0054a8040007060554a80a00070657e935052e140f02',
      ),
      (
        'fffedfd57daf64613615412d',
        '0cfcfddcd67eac67623516422e02',
      ),
      (
        '0a03003d5b9700b9d95770c3ddcfd8283fdcfd2af855c3af067eb53217aefaff03b71ee00e02c75639e300f2eaffc2f36ba269ebfbb14d495dbb7a95ebabd5075db14fb32bf40031f30a2ed312626b45868ac41386605f8c3695bb951b46d84f75057bedf9c4cfa77236e7a6d5cdcb763de076596b2c0b8d446c175b1912472a32d4974a4c8896981c2d91beace081a352a2edb5476f5c9ab2d000656c500bad215e05fdb7c00ed716da7ff529756b1f752c',
        '060900053e5894cabada5473c0deccdb2b3cdffe29fb56c0ac057db63114adf9fc00b41de30d04c4553ae01df1e9fcc1f068a16ae8f8b24e4a5eb87996e8a8d6045eb24cb028f75532f0092dd0116168468589c71085635c8f3596b8961845db4c760678eefac7cca47135e4a5d6cec8753ee3755a682f088e476f14581a11442931d794494f8b959b1f2e92bdafe382a051a1eeb6446c5f99b1d319666f5308ae225d06feb4c30dd415d97cf62a76681c762f02',
      ),
    ];
    for (final item in cases) {
      final raw = hexToBytes(item.$1);
      final packed = hexToBytes(item.$2);
      expect(bytesHex(spikePack(raw)), item.$2);
      expect(spikeUnpack(packed), raw);
    }
    expect(bytesHex(spikePack([0x00])), '000002');
  });

  test('framer reassembles a split notification', () {
    final packed = spikePack([1, 2, 3, 4, 5]);
    final framer = SpikeFramer();
    expect(framer.add(packed.sublist(0, 2)), isEmpty);
    final frames = framer.add(packed.sublist(2));
    expect(spikeUnpack(frames.single), [1, 2, 3, 4, 5]);
  });

  test('info response and device notification match python struct layout', () {
    final info = parseHubMessage(hexToBytes('0101000c00030402004000001000020000'));
    expect(info, isA<InfoHubMessage>());
    final infoMessage = (info as InfoHubMessage).info;
    expect(infoMessage.rpcBuild, 12);
    expect(infoMessage.fwMajor, 3);
    expect(infoMessage.fwMinor, 4);
    expect(infoMessage.maxPacketSize, 64);
    expect(infoMessage.maxMessageSize, 4096);
    expect(infoMessage.maxChunkSize, 512);

    final note = parseHubMessage(
      hexToBytes('3c230000500a0031a6ffdc05ec40e201000100000a00ecff1e00010002000300040005000600'),
    ) as DeviceHubMessage;
    expect(note.batch.battery, 80);
    final motor = note.batch.ports.single;
    expect(motor.letter, 'A');
    expect(motor.deviceType, 0x31);
    expect(motor.absPosition, -90);
    expect(motor.power, 1500);
    expect(motor.speed, -20);
    expect(motor.position, 123456);
    expect(note.batch.yaw, 10);
    expect(note.batch.pitch, -20);
    expect(note.batch.roll, 30);
  });

  test('file upload header matches the official struct', () {
    expect(
      bytesHex(startFileUploadRequest('program.py', 0, 4169156781)),
      '0c70726f6772616d2e70790000ad4880f8',
    );
  });

  test('upload sequence follows the official client', () async {
    final pipe = _ScriptedPipe();
    final rpc = SpikeRpc(pipe);
    rpc.start();
    pipe.reply = (payload) {
      switch (payload[0]) {
        case 0x00:
          pipe.respond(hexToBytes('0101000c00030402004000001000020000'));
        case 0x18:
          pipe.respond([0x19, ...'Hub'.codeUnits, 0]);
        case 0x28:
        case 0x46:
        case 0x0C:
        case 0x10:
        case 0x1E:
          pipe.respond([payload[0] + 1, 0x00]);
      }
    };
    await rpc.uploadAndStart('print(1)\n'.codeUnits, slot: 0, notifyMs: 100);
    expect(pipe.types, [0x00, 0x28, 0x18, 0x46, 0x0C, 0x10, 0x1E]);
    expect(pipe.types.where((type) => type == 0x1E), [0x1E]);
    final flow = pipe.payloads.last;
    expect(flow[1], 0);
    expect(flow[2], 0);
    await rpc.close();
  });
}

class _ScriptedPipe implements BytePipe {
  final _in = StreamController<List<int>>.broadcast();
  final framer = SpikeFramer();
  final types = <int>[];
  final payloads = <List<int>>[];
  late void Function(List<int> payload) reply;

  @override
  Stream<List<int>> get inbound => _in.stream;

  @override
  Future<void> write(List<int> data) async {
    for (final frame in framer.add(data)) {
      final payload = spikeUnpack(frame);
      payloads.add(payload);
      types.add(payload[0]);
      reply(payload);
    }
  }

  void respond(List<int> payload) {
    _in.add(spikePack(payload));
  }
}
