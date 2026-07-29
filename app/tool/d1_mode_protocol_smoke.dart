import 'dart:typed_data';

import 'package:navbot_d1_flutter/provider/d1_mode_protocol.dart';

void main() {
  final command = D1ModeProtocol.encodeCommand(
    seq: 1,
    mode: D1Mode.stand,
    clientTimeMs: 0,
  );
  const expectedCommand = <int>[0x42, 0x06, 0x08, 0x01, 0x10, 0x01, 0x18, 0x00];
  if (!_sameBytes(command, expectedCommand)) {
    throw StateError('unexpected D1ModeCommand encoding: $command');
  }

  final ackEnvelope = Uint8List.fromList(<int>[
    0xa2,
    0x01,
    0x0a,
    0x08,
    0x01,
    0x10,
    0x03,
    0x18,
    0x01,
    0x22,
    0x02,
    0x6f,
    0x6b,
  ]);
  final ack = D1ModeProtocol.tryDecodeAckEnvelope(ackEnvelope);
  if (ack == null ||
      ack.seq != 1 ||
      ack.mode != D1Mode.enterRl ||
      ack.result != D1ModeResult.sent ||
      ack.message != 'ok') {
    throw StateError('unexpected D1ModeAck decoding');
  }

  print('Robot mode protobuf smoke test passed');
}

bool _sameBytes(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}
