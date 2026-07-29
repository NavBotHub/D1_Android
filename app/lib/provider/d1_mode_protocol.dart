import 'dart:convert';
import 'dart:typed_data';

enum D1Mode {
  unspecified(0),
  stand(1),
  lieDown(2),
  enterRl(3),
  exitRl(4);

  const D1Mode(this.value);
  final int value;

  static D1Mode fromValue(int value) {
    return values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => unspecified,
    );
  }
}

enum D1ModeResult {
  unspecified(0),
  sent(1),
  bridgeNotReady(2),
  rlOffline(3),
  busy(4),
  rateLimited(5),
  duplicate(6);

  const D1ModeResult(this.value);
  final int value;

  static D1ModeResult fromValue(int value) {
    return values.firstWhere(
      (result) => result.value == value,
      orElse: () => unspecified,
    );
  }
}

class D1ModeAck {
  const D1ModeAck({
    required this.seq,
    required this.mode,
    required this.result,
    required this.message,
  });

  final int seq;
  final D1Mode mode;
  final D1ModeResult result;
  final String message;

  bool get sent => result == D1ModeResult.sent;
}

class D1ModeProtocol {
  static const int _clientD1ModeCommandField = 8;
  static const int _robotD1ModeAckField = 20;

  static Uint8List encodeCommand({
    required int seq,
    required D1Mode mode,
    required int clientTimeMs,
  }) {
    final command =
        BytesBuilder(copy: false)
          ..add(_encodeKey(1, 0))
          ..add(_encodeVarint(seq))
          ..add(_encodeKey(2, 0))
          ..add(_encodeVarint(mode.value))
          ..add(_encodeKey(3, 0))
          ..add(_encodeInt64Varint(clientTimeMs));
    final payload = command.takeBytes();
    return Uint8List.fromList(<int>[
      ..._encodeKey(_clientD1ModeCommandField, 2),
      ..._encodeVarint(payload.length),
      ...payload,
    ]);
  }

  static D1ModeAck? tryDecodeAckEnvelope(Uint8List bytes) {
    final cursor = _Cursor();
    while (cursor.offset < bytes.length) {
      final key = _readVarint(bytes, cursor);
      if (key == null) return null;
      final field = key >> 3;
      final wireType = key & 0x07;
      if (field == _robotD1ModeAckField && wireType == 2) {
        final payload = _readLengthDelimited(bytes, cursor);
        return payload == null ? null : _decodeAck(payload);
      }
      if (!_skipField(bytes, cursor, wireType)) return null;
    }
    return null;
  }

  static D1ModeAck? _decodeAck(Uint8List bytes) {
    final cursor = _Cursor();
    var seq = 0;
    var mode = D1Mode.unspecified;
    var result = D1ModeResult.unspecified;
    var message = '';

    while (cursor.offset < bytes.length) {
      final key = _readVarint(bytes, cursor);
      if (key == null) return null;
      final field = key >> 3;
      final wireType = key & 0x07;
      if (field == 1 && wireType == 0) {
        seq = _readVarint(bytes, cursor) ?? 0;
      } else if (field == 2 && wireType == 0) {
        mode = D1Mode.fromValue(_readVarint(bytes, cursor) ?? 0);
      } else if (field == 3 && wireType == 0) {
        result = D1ModeResult.fromValue(_readVarint(bytes, cursor) ?? 0);
      } else if (field == 4 && wireType == 2) {
        final raw = _readLengthDelimited(bytes, cursor);
        if (raw == null) return null;
        message = utf8.decode(raw, allowMalformed: true);
      } else if (!_skipField(bytes, cursor, wireType)) {
        return null;
      }
    }

    return D1ModeAck(seq: seq, mode: mode, result: result, message: message);
  }

  static List<int> _encodeKey(int field, int wireType) {
    return _encodeVarint((field << 3) | wireType);
  }

  static List<int> _encodeVarint(int value) {
    return _encodeBigIntVarint(BigInt.from(value));
  }

  static List<int> _encodeInt64Varint(int value) {
    return _encodeBigIntVarint(BigInt.from(value));
  }

  static List<int> _encodeBigIntVarint(BigInt value) {
    final result = <int>[];
    var remaining = value;
    final mask = BigInt.from(0x7f);
    do {
      var byte = (remaining & mask).toInt();
      remaining >>= 7;
      if (remaining != BigInt.zero) byte |= 0x80;
      result.add(byte);
    } while (remaining != BigInt.zero);
    return result;
  }

  static int? _readVarint(Uint8List bytes, _Cursor cursor) {
    var result = 0;
    var shift = 0;
    while (cursor.offset < bytes.length && shift <= 63) {
      final byte = bytes[cursor.offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    return null;
  }

  static Uint8List? _readLengthDelimited(Uint8List bytes, _Cursor cursor) {
    final length = _readVarint(bytes, cursor);
    if (length == null || length < 0 || cursor.offset + length > bytes.length) {
      return null;
    }
    final result = Uint8List.sublistView(
      bytes,
      cursor.offset,
      cursor.offset + length,
    );
    cursor.offset += length;
    return result;
  }

  static bool _skipField(Uint8List bytes, _Cursor cursor, int wireType) {
    switch (wireType) {
      case 0:
        return _readVarint(bytes, cursor) != null;
      case 1:
        if (cursor.offset + 8 > bytes.length) return false;
        cursor.offset += 8;
        return true;
      case 2:
        return _readLengthDelimited(bytes, cursor) != null;
      case 5:
        if (cursor.offset + 4 > bytes.length) return false;
        cursor.offset += 4;
        return true;
      default:
        return false;
    }
  }
}

class _Cursor {
  int offset = 0;
}
