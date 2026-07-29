import 'device_status_model.dart';

class DeviceStatusReader {
  Future<DeviceStatusSnapshot> read() async {
    return DeviceStatusSnapshot.unknown;
  }
}
