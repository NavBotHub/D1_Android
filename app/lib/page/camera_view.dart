import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/page/mjpeg_view.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  Timer? _retryTimer;
  bool _isRetrying = false;
  int _retryGeneration = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _onDirectMjpegError() {
    if (!mounted || _isRetrying || (_retryTimer?.isActive ?? false)) {
      return;
    }
    setState(() {
      _isRetrying = true;
    });
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _retryGeneration++;
        _isRetrying = false;
      });
      _retryTimer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isRetrying) {
      final isChinese =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              isChinese ? '视频重连中' : 'Reconnecting video',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
        ),
      );
    }
    return MjpegView(
      key: ValueKey('${globalSetting.imageStreamUrl}#$_retryGeneration'),
      url: globalSetting.imageStreamUrl,
      width: widget.width,
      height: widget.height,
      onError: _onDirectMjpegError,
    );
  }
}
