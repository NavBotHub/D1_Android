import 'dart:io';

import 'device_status_model.dart';

class DeviceStatusReader {
  static const List<String> _batteryCapacityFiles = [
    '/sys/class/power_supply/battery/capacity',
    '/sys/class/power_supply/BAT0/capacity',
    '/sys/class/power_supply/BAT1/capacity',
  ];

  Future<DeviceStatusSnapshot> read() async {
    final batteryPercent = await _readBatteryPercent();
    final wifiSignalPercent = await _readWifiSignalPercent();
    return DeviceStatusSnapshot(
      batteryPercent: batteryPercent,
      wifiSignalPercent: wifiSignalPercent,
    );
  }

  Future<int?> _readBatteryPercent() async {
    for (final path in _batteryCapacityFiles) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final raw = (await file.readAsString()).trim();
        final value = int.tryParse(raw);
        if (value != null) return value.clamp(0, 100).toInt();
      } catch (_) {}
    }
    return null;
  }

  Future<int?> _readWifiSignalPercent() async {
    try {
      final file = File('/proc/net/wireless');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      for (final line in lines.skip(2)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 4) continue;
        final linkQuality = double.tryParse(parts[2].replaceAll('.', ''));
        if (linkQuality == null) continue;
        return ((linkQuality.clamp(0, 70) / 70) * 100).round();
      }
    } catch (_) {}
    return null;
  }
}
