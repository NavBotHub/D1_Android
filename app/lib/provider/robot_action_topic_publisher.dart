import 'package:navbot_d1_flutter/provider/http_channel.dart';

class RobotActionTopicPublisher {
  final HttpChannel _httpChannel;

  RobotActionTopicPublisher({HttpChannel? httpChannel})
    : _httpChannel = httpChannel ?? HttpChannel();

  Future<void> publish(String command) async {
    if (command.trim().isEmpty) return;
    final ok = await _httpChannel.postRobotActionCommand(command);
    if (!ok) {
      throw Exception('POST /robot/action_cmd failed');
    }
  }

  void close() {}
}
