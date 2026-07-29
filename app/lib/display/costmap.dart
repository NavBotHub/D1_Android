import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:navbot_d1_flutter/basic/layer_config.dart';
import 'package:navbot_d1_flutter/basic/occupancy_map.dart';
import 'package:navbot_d1_flutter/display/grid.dart' show WorldToLatLngFn;

class _CostmapRgbaImageProvider
    extends ImageProvider<_CostmapRgbaImageProvider> {
  _CostmapRgbaImageProvider({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final Uint8List pixels;
  final int width;
  final int height;

  @override
  Future<_CostmapRgbaImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_CostmapRgbaImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CostmapRgbaImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_decodeAsync());
  }

  Future<ImageInfo> _decodeAsync() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    return ImageInfo(image: image, scale: 1.0);
  }
}

int _alphaEigen(double opacity) => (50 * opacity).round().clamp(0, 255);

Uint8List _buildCostmapRgba(
  OccupancyMap cm,
  double opacity,
  LocalCostmapMapStyle style,
) {
  final w = cm.mapConfig.width;
  final h = cm.mapConfig.height;
  final out = Uint8List(w * h * 4);
  var o = 0;
  final op = opacity.clamp(0.0, 1.0);
  final ae = _alphaEigen(op);
  for (var row = 0; row < h; row++) {
    final line = cm.data[row];
    for (var col = 0; col < w; col++) {
      final v = line[col];
      int a;
      int r;
      int g;
      int b;
      switch (style) {
        case LocalCostmapMapStyle.raw:
          if (v < 0) {
            r = 205;
            g = 205;
            b = 205;
            a = (0.45 * 255 * op).round().clamp(0, 255);
          } else if (v == 0) {
            a = 0;
            r = 0;
            g = 0;
            b = 0;
          } else {
            final t = (v > 100 ? 100 : v) / 100.0;
            final lum = (255 * (1 - t)).round().clamp(0, 255);
            r = lum;
            g = lum;
            b = lum;
            a = (0.88 * 255 * op).round().clamp(0, 255);
          }
          break;
        case LocalCostmapMapStyle.obs:
          if (v >= 100) {
            r = 0;
            g = 0;
            b = 0;
            a = 255;
          } else {
            a = 0;
            r = 0;
            g = 0;
            b = 0;
          }
          break;
        case LocalCostmapMapStyle.costmap:
          if (v >= 100) {
            r = 0xff;
            g = 0;
            b = 0xff;
            a = ae;
          } else if (v >= 90 && v < 100) {
            r = 0x66;
            g = 0xff;
            b = 0xff;
            a = ae;
          } else if (v >= 70 && v <= 90) {
            r = 0xff;
            g = 0;
            b = 0x33;
            a = ae;
          } else if (v >= 60 && v <= 70) {
            r = 0xbe;
            g = 0x28;
            b = 0x1a;
            a = ae;
          } else if (v >= 50 && v < 60) {
            r = 0xbe;
            g = 0x1f;
            b = 0x58;
            a = ae;
          } else if (v >= 40 && v < 50) {
            r = 0xbe;
            g = 0x25;
            b = 0x76;
            a = ae;
          } else if (v >= 30 && v < 40) {
            r = 0xbe;
            g = 0x2a;
            b = 0x99;
            a = ae;
          } else if (v >= 20 && v < 30) {
            r = 0xbe;
            g = 0x35;
            b = 0xb3;
            a = ae;
          } else if (v >= 10 && v < 20) {
            r = 0xb0;
            g = 0x3c;
            b = 0xbe;
            a = ae;
          } else {
            a = 0;
            r = 0;
            g = 0;
            b = 0;
          }
          break;
      }
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
      out[o++] = a.clamp(0, 255);
    }
  }
  return out;
}

class _CostmapRgbaRequest {
  const _CostmapRgbaRequest({
    required this.map,
    required this.opacity,
    required this.style,
  });

  final OccupancyMap map;
  final double opacity;
  final LocalCostmapMapStyle style;
}

Uint8List _buildCostmapRgbaInBackground(_CostmapRgbaRequest request) {
  return _buildCostmapRgba(request.map, request.opacity, request.style);
}

(double, double) _mapFrameToWorld(
  double ox,
  double oy,
  double c,
  double s,
  double mx,
  double my,
) {
  final wx = ox + mx * c - my * s;
  final wy = oy + mx * s + my * c;
  return (wx, wy);
}

class _AsyncCostmapOverlay extends StatefulWidget {
  const _AsyncCostmapOverlay({
    required this.map,
    required this.opacity,
    required this.worldToLatLng,
    required this.mapStyle,
  });

  final OccupancyMap map;
  final double opacity;
  final WorldToLatLngFn worldToLatLng;
  final LocalCostmapMapStyle mapStyle;

  @override
  State<_AsyncCostmapOverlay> createState() => _AsyncCostmapOverlayState();
}

class _AsyncCostmapOverlayState extends State<_AsyncCostmapOverlay> {
  _CostmapRgbaRequest? _pendingRequest;
  OccupancyMap? _renderedMap;
  Uint8List? _renderedRgba;
  bool _processing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _queueLatest();
  }

  @override
  void didUpdateWidget(_AsyncCostmapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.map, widget.map) ||
        oldWidget.opacity != widget.opacity ||
        oldWidget.mapStyle != widget.mapStyle) {
      _queueLatest();
    }
  }

  void _queueLatest() {
    _generation++;
    _pendingRequest = _CostmapRgbaRequest(
      map: widget.map,
      opacity: widget.opacity.clamp(0.0, 1.0),
      style: widget.mapStyle,
    );
    if (!_processing) {
      unawaited(_drainQueue());
    }
  }

  Future<void> _drainQueue() async {
    _processing = true;
    while (mounted && _pendingRequest != null) {
      final request = _pendingRequest!;
      final requestGeneration = _generation;
      _pendingRequest = null;
      final rgba = await compute(_buildCostmapRgbaInBackground, request);
      if (!mounted) return;
      if (requestGeneration == _generation) {
        setState(() {
          _renderedMap = request.map;
          _renderedRgba = rgba;
        });
      }
    }
    _processing = false;
  }

  @override
  Widget build(BuildContext context) {
    final cm = _renderedMap;
    final rgba = _renderedRgba;
    if (cm == null || rgba == null) {
      return const SizedBox.shrink();
    }
    final w = cm.mapConfig.width;
    final h = cm.mapConfig.height;
    final r = cm.mapConfig.resolution;
    final ox = cm.mapConfig.originX;
    final oy = cm.mapConfig.originY;
    final th = cm.mapConfig.originTheta;
    final c = math.cos(th);
    final s = math.sin(th);
    final nw = _mapFrameToWorld(ox, oy, c, s, 0, h * r);
    final sw = _mapFrameToWorld(ox, oy, c, s, 0, 0);
    final se = _mapFrameToWorld(ox, oy, c, s, w * r, 0);
    return RepaintBoundary(
      child: OverlayImageLayer(
        overlayImages: [
          RotatedOverlayImage(
            imageProvider: _CostmapRgbaImageProvider(
              pixels: rgba,
              width: w,
              height: h,
            ),
            topLeftCorner: widget.worldToLatLng(nw.$1, nw.$2),
            bottomLeftCorner: widget.worldToLatLng(sw.$1, sw.$2),
            bottomRightCorner: widget.worldToLatLng(se.$1, se.$2),
            opacity: 1,
            filterQuality: FilterQuality.none,
          ),
        ],
      ),
    );
  }
}

Widget buildLocalCostMapOverlayLayer(
  OccupancyMap cm,
  double opacity,
  WorldToLatLngFn worldToLatLng,
  LocalCostmapMapStyle mapStyle,
) {
  final w = cm.mapConfig.width;
  final h = cm.mapConfig.height;
  if (w <= 0 || h <= 0 || cm.data.isEmpty) {
    return const SizedBox.shrink();
  }
  if (cm.data.length < h) {
    return const SizedBox.shrink();
  }
  for (var i = 0; i < h; i++) {
    if (cm.data[i].length < w) {
      return const SizedBox.shrink();
    }
  }
  return _AsyncCostmapOverlay(
    map: cm,
    opacity: opacity,
    worldToLatLng: worldToLatLng,
    mapStyle: mapStyle,
  );
}
