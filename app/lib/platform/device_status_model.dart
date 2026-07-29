class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({this.batteryPercent, this.wifiSignalPercent});

  final int? batteryPercent;
  final int? wifiSignalPercent;

  static const unknown = DeviceStatusSnapshot();
}
