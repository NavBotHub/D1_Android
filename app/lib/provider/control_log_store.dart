import 'dart:async';

import 'package:flutter/foundation.dart';

enum ControlLogLevel { debug, info, warning, error }

class ControlLogEntry {
  const ControlLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  final DateTime timestamp;
  final ControlLogLevel level;
  final String category;
  final String message;

  String get levelLabel => switch (level) {
    ControlLogLevel.debug => 'D',
    ControlLogLevel.info => 'I',
    ControlLogLevel.warning => 'W',
    ControlLogLevel.error => 'E',
  };

  String format() {
    final local = timestamp.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}.'
        '${local.millisecond.toString().padLeft(3, '0')}';
    return '$time $levelLabel/$category $message';
  }
}

/// Lightweight diagnostic log for the control path.
///
/// The ring buffer is kept in memory so logging never performs file I/O on the
/// 20 ms command path. High-frequency speed packets are sampled before they are
/// added to the visible log, while the total packet count remains exact.
class ControlLogStore {
  ControlLogStore._();

  static final ControlLogStore instance = ControlLogStore._();
  static const int maxEntries = 3000;
  static const Duration _speedLogInterval = Duration(milliseconds: 250);

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final List<ControlLogEntry> _entries = <ControlLogEntry>[];
  Timer? _revisionTimer;
  bool _enabled = false;

  int _speedPacketCount = 0;
  DateTime? _lastSpeedPacketAt;
  DateTime? _lastSpeedLogAt;
  double? _lastLoggedVx;
  double? _lastLoggedVy;
  double? _lastLoggedVw;

  List<ControlLogEntry> get entries =>
      List<ControlLogEntry>.unmodifiable(_entries);

  int get speedPacketCount => _speedPacketCount;

  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      clear();
    }
  }

  void debug(String category, String message) {
    if (!_enabled) return;
    _append(ControlLogLevel.debug, category, message);
  }

  void debugLazy(String category, String Function() messageBuilder) {
    if (!_enabled) return;
    _append(ControlLogLevel.debug, category, messageBuilder());
  }

  void info(String category, String message) {
    if (!_enabled) return;
    _append(ControlLogLevel.info, category, message);
  }

  void warning(String category, String message) {
    if (!_enabled) return;
    _append(ControlLogLevel.warning, category, message);
  }

  void error(String category, String message) {
    if (!_enabled) return;
    _append(ControlLogLevel.error, category, message);
  }

  void recordSpeedPacket(double vx, double vy, double vw) {
    if (!_enabled) return;
    final now = DateTime.now();
    final previousPacketAt = _lastSpeedPacketAt;
    _lastSpeedPacketAt = now;
    _speedPacketCount++;

    final commandChanged =
        _lastLoggedVx == null ||
        (vx - _lastLoggedVx!).abs() >= 0.005 ||
        (vy - _lastLoggedVy!).abs() >= 0.005 ||
        (vw - _lastLoggedVw!).abs() >= 0.005;
    final intervalElapsed =
        _lastSpeedLogAt == null ||
        now.difference(_lastSpeedLogAt!) >= _speedLogInterval;
    if (!commandChanged && !intervalElapsed) return;

    _lastSpeedLogAt = now;
    _lastLoggedVx = vx;
    _lastLoggedVy = vy;
    _lastLoggedVw = vw;
    final intervalMs =
        previousPacketAt == null
            ? '-'
            : now.difference(previousPacketAt).inMicroseconds / 1000.0;
    final intervalText =
        intervalMs is double ? intervalMs.toStringAsFixed(1) : intervalMs;
    _append(
      ControlLogLevel.debug,
      'TX',
      '#$_speedPacketCount dt=${intervalText}ms '
          'cmd_vel vx=${vx.toStringAsFixed(3)} '
          'vy=${vy.toStringAsFixed(3)} vw=${vw.toStringAsFixed(3)}',
      timestamp: now,
    );
  }

  void clear() {
    _entries.clear();
    _speedPacketCount = 0;
    _lastSpeedPacketAt = null;
    _lastSpeedLogAt = null;
    _lastLoggedVx = null;
    _lastLoggedVy = null;
    _lastLoggedVw = null;
    _revisionTimer?.cancel();
    _revisionTimer = null;
    revision.value++;
  }

  String exportText() => _entries.map((entry) => entry.format()).join('\n');

  void _append(
    ControlLogLevel level,
    String category,
    String message, {
    DateTime? timestamp,
  }) {
    if (!_enabled) return;
    _entries.add(
      ControlLogEntry(
        timestamp: timestamp ?? DateTime.now(),
        level: level,
        category: category,
        message: message,
      ),
    );
    final overflow = _entries.length - maxEntries;
    if (overflow > 0) {
      _entries.removeRange(0, overflow);
    }
    _scheduleRevision();
  }

  void _scheduleRevision() {
    if (_revisionTimer?.isActive ?? false) return;
    _revisionTimer = Timer(const Duration(milliseconds: 100), () {
      _revisionTimer = null;
      revision.value++;
    });
  }
}
