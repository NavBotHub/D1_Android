import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

bool get useDirectMjpegView => true;

const int _maxBufferedBytes = 4 * 1024 * 1024;
const Duration _minimumFrameInterval = Duration(milliseconds: 33);

void _mjpegParserIsolateMain(SendPort outputPort) {
  final inputPort = ReceivePort();
  outputPort.send(inputPort.sendPort);

  var buffer = Uint8List(0);
  Uint8List? pendingFrame;
  Timer? publishTimer;
  var lastPublishedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void publishLatest() {
    publishTimer?.cancel();
    publishTimer = null;
    final frame = pendingFrame;
    pendingFrame = null;
    if (frame == null) return;
    lastPublishedAt = DateTime.now();
    outputPort.send(TransferableTypedData.fromList(<Uint8List>[frame]));
  }

  void offerFrame(Uint8List frame) {
    pendingFrame = frame;
    final elapsed = DateTime.now().difference(lastPublishedAt);
    if (elapsed >= _minimumFrameInterval) {
      publishLatest();
      return;
    }
    publishTimer ??= Timer(_minimumFrameInterval - elapsed, publishLatest);
  }

  inputPort.listen((dynamic message) {
    if (message == null) {
      publishTimer?.cancel();
      inputPort.close();
      return;
    }
    if (message is! TransferableTypedData) return;

    final chunk = message.materialize().asUint8List();
    if (chunk.isEmpty) return;

    final combined = Uint8List(buffer.length + chunk.length)
      ..setRange(0, buffer.length, buffer)
      ..setRange(buffer.length, buffer.length + chunk.length, chunk);
    buffer = combined;

    Uint8List? newestFrame;
    var consumedUntil = 0;
    var bufferReplaced = false;
    while (true) {
      final start = _findJpegMarker(buffer, consumedUntil, 0xff, 0xd8);
      if (start < 0) {
        if (buffer.isNotEmpty && buffer.last == 0xff) {
          buffer = Uint8List.fromList(<int>[0xff]);
        } else {
          buffer = Uint8List(0);
        }
        bufferReplaced = true;
        break;
      }

      final end = _findJpegMarker(buffer, start + 2, 0xff, 0xd9);
      if (end < 0) {
        buffer = Uint8List.fromList(buffer.sublist(start));
        if (buffer.length > _maxBufferedBytes) {
          buffer = Uint8List.fromList(
            buffer.sublist(buffer.length - _maxBufferedBytes),
          );
        }
        bufferReplaced = true;
        break;
      }

      final frameEnd = end + 2;
      newestFrame = Uint8List.fromList(buffer.sublist(start, frameEnd));
      consumedUntil = frameEnd;
      if (consumedUntil >= buffer.length) {
        buffer = Uint8List(0);
        bufferReplaced = true;
        break;
      }
    }

    if (!bufferReplaced &&
        consumedUntil > 0 &&
        consumedUntil < buffer.length) {
      buffer = Uint8List.fromList(buffer.sublist(consumedUntil));
    }
    if (newestFrame != null) {
      offerFrame(newestFrame);
    }
  });
}

int _findJpegMarker(
  Uint8List bytes,
  int from,
  int first,
  int second,
) {
  for (var index = from; index + 1 < bytes.length; index++) {
    if (bytes[index] == first && bytes[index + 1] == second) {
      return index;
    }
  }
  return -1;
}

class MjpegView extends StatefulWidget {
  const MjpegView({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.onError,
  });

  final String url;
  final double width;
  final double height;
  final VoidCallback? onError;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  final ValueNotifier<Uint8List?> _latestFrame = ValueNotifier(null);

  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  ReceivePort? _parserOutputPort;
  StreamSubscription<dynamic>? _parserOutputSubscription;
  SendPort? _parserInputPort;
  Isolate? _parserIsolate;

  Future<void> _restartChain = Future<void>.value();
  int _connectionGeneration = 0;
  bool _reportedError = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _queueRestart();
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _queueRestart();
    }
  }

  void _queueRestart() {
    final generation = ++_connectionGeneration;
    _client?.close();
    _restartChain = _restartChain
        .catchError((Object _) {})
        .then((_) => _restart(generation));
  }

  Future<void> _restart(int generation) async {
    await _disconnect();
    if (_disposed || !mounted || generation != _connectionGeneration) return;

    _latestFrame.value = null;
    _reportedError = false;
    await _connect(generation);
  }

  Future<void> _connect(int generation) async {
    final client = http.Client();
    _client = client;
    try {
      final uri = Uri.parse(widget.url);
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'multipart/x-mixed-replace';
      final response = await client.send(request);
      if (!_isCurrentConnection(client, generation)) {
        client.close();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'MJPEG HTTP ${response.statusCode}',
          uri,
        );
      }

      final parserReady = await _startParser(generation);
      if (!parserReady || !_isCurrentConnection(client, generation)) {
        client.close();
        return;
      }

      final subscription = response.stream.listen(
        (chunk) => _forwardChunk(chunk, generation),
        onError: (_) => _reportError(generation),
        onDone: () => _reportError(generation),
        cancelOnError: true,
      );
      if (!_isCurrentConnection(client, generation)) {
        await subscription.cancel();
        client.close();
        return;
      }
      _subscription = subscription;
    } catch (_) {
      client.close();
      if (identical(_client, client)) {
        _client = null;
      }
      _reportError(generation);
    }
  }

  bool _isCurrentConnection(http.Client client, int generation) {
    return !_disposed &&
        mounted &&
        generation == _connectionGeneration &&
        identical(client, _client);
  }

  Future<bool> _startParser(int generation) async {
    final outputPort = ReceivePort();
    final ready = Completer<SendPort>();
    late final StreamSubscription<dynamic> outputSubscription;

    outputSubscription = outputPort.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is TransferableTypedData &&
          !_disposed &&
          mounted &&
          generation == _connectionGeneration) {
        _latestFrame.value = message.materialize().asUint8List();
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<SendPort>(
        _mjpegParserIsolateMain,
        outputPort.sendPort,
        debugName: 'mjpeg-frame-parser',
      );
      if (_disposed || !mounted || generation != _connectionGeneration) {
        isolate.kill(priority: Isolate.immediate);
        await outputSubscription.cancel();
        outputPort.close();
        return false;
      }

      _parserOutputPort = outputPort;
      _parserOutputSubscription = outputSubscription;
      _parserIsolate = isolate;
      _parserInputPort = await ready.future.timeout(
        const Duration(seconds: 2),
      );
      return generation == _connectionGeneration && !_disposed;
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await outputSubscription.cancel();
      outputPort.close();
      if (identical(_parserOutputPort, outputPort)) {
        _parserOutputPort = null;
        _parserOutputSubscription = null;
        _parserInputPort = null;
        _parserIsolate = null;
      }
      return false;
    }
  }

  void _forwardChunk(List<int> chunk, int generation) {
    final inputPort = _parserInputPort;
    if (_disposed ||
        !mounted ||
        generation != _connectionGeneration ||
        inputPort == null ||
        chunk.isEmpty) {
      return;
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    inputPort.send(TransferableTypedData.fromList(<Uint8List>[bytes]));
  }

  void _reportError(int generation) {
    if (_disposed ||
        !mounted ||
        generation != _connectionGeneration ||
        _reportedError) {
      return;
    }
    _reportedError = true;
    widget.onError?.call();
  }

  Future<void> _disconnect() async {
    final subscription = _subscription;
    final client = _client;
    final parserInputPort = _parserInputPort;
    final parserOutputSubscription = _parserOutputSubscription;
    final parserOutputPort = _parserOutputPort;
    final parserIsolate = _parserIsolate;

    _subscription = null;
    _client = null;
    _parserInputPort = null;
    _parserOutputSubscription = null;
    _parserOutputPort = null;
    _parserIsolate = null;

    await subscription?.cancel();
    client?.close();
    parserInputPort?.send(null);
    await parserOutputSubscription?.cancel();
    parserOutputPort?.close();
    parserIsolate?.kill(priority: Isolate.immediate);
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionGeneration++;
    _client?.close();
    unawaited(_disconnect());
    _latestFrame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<Uint8List?>(
        valueListenable: _latestFrame,
        builder: (context, frame, _) {
          if (frame == null) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _LatestMjpegFrame(
            bytes: frame,
            width: widget.width,
            height: widget.height,
          );
        },
      ),
    );
  }
}

class _LatestMjpegFrame extends StatefulWidget {
  const _LatestMjpegFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final double width;
  final double height;

  @override
  State<_LatestMjpegFrame> createState() => _LatestMjpegFrameState();
}

class _LatestMjpegFrameState extends State<_LatestMjpegFrame> {
  ui.Image? _image;
  Uint8List? _pendingBytes;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _submit(widget.bytes);
  }

  @override
  void didUpdateWidget(covariant _LatestMjpegFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _submit(widget.bytes);
    }
  }

  void _submit(Uint8List bytes) {
    _pendingBytes = bytes;
    if (!_decoding) {
      unawaited(_decodeLatest());
    }
  }

  Future<void> _decodeLatest() async {
    _decoding = true;
    try {
      while (mounted && _pendingBytes != null) {
        final bytes = _pendingBytes!;
        _pendingBytes = null;
        ui.Codec? codec;
        ui.Image? nextImage;
        try {
          codec = await ui.instantiateImageCodec(bytes);
          nextImage = (await codec.getNextFrame()).image;
        } catch (_) {
          nextImage?.dispose();
          continue;
        } finally {
          codec?.dispose();
        }
        if (!mounted) {
          nextImage.dispose();
          return;
        }

        final oldImage = _image;
        setState(() {
          _image = nextImage;
        });
        if (oldImage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            oldImage.dispose();
          });
        }
      }
    } finally {
      _decoding = false;
      if (mounted && _pendingBytes != null) {
        unawaited(_decodeLatest());
      }
    }
  }

  @override
  void dispose() {
    _pendingBytes = null;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _MjpegImagePainter(image),
    );
  }
}

class _MjpegImagePainter extends CustomPainter {
  const _MjpegImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final inputSize = Size(image.width.toDouble(), image.height.toDouble());
    final scale = math.max(
      size.width / inputSize.width,
      size.height / inputSize.height,
    );
    final outputSize = Size(inputSize.width * scale, inputSize.height * scale);
    final destination = Alignment.center.inscribe(
      outputSize,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      Offset.zero & inputSize,
      destination,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _MjpegImagePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
