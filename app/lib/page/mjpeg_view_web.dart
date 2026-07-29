import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

bool get useDirectMjpegView => true;

int _nextMjpegViewId = 0;

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
  late final String _viewType;
  late final web.HTMLImageElement _image;
  StreamSubscription<web.Event>? _errorSubscription;
  bool _reportedError = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'mjpeg-view-${_nextMjpegViewId++}';
    _image = web.document.createElement('img') as web.HTMLImageElement;
    _image.style
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('object-fit', 'cover')
      ..setProperty('display', 'block')
      ..setProperty('border', '0')
      ..setProperty('pointer-events', 'none')
      ..setProperty('user-select', 'none');
    _errorSubscription = _image.onError.listen((_) {
      if (_reportedError) return;
      _reportedError = true;
      widget.onError?.call();
    });
    _image.src = widget.url;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _image,
    );
  }

  @override
  void didUpdateWidget(covariant MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _reportedError = false;
      _image.src = widget.url;
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription?.cancel());
    _image.src = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
