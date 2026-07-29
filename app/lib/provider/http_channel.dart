import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:navbot_d1_flutter/basic/topology_map.dart';
import 'package:navbot_d1_flutter/global/setting.dart';

class AppException implements Exception {
  final String key;
  AppException(this.key);
  @override
  String toString() => key;
}

class HttpChannel {
  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final base = globalSetting.tileServerUrl;
    return Uri.parse('$base$path').replace(queryParameters: queryParameters);
  }

  Future<List<String>> getAllMapList() async {
    final uri = _buildUri('/getAllMapList');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('getAllMapList failed: ${res.statusCode} ${res.body}');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e.toString()).toList();
  }

  Future<String> getCurrentMap() async {
    final uri = _buildUri('/currentMap');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('getCurrentMap failed: ${res.statusCode} ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['current_map'] as String? ?? '';
  }

  Future<void> setCurrentMap(String name) async {
    final uri = _buildUri('/setCurrentMap', queryParameters: {'name': name});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('setCurrentMap failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> deleteMap(String mapName) async {
    final uri = _buildUri('/deleteMap', queryParameters: {'map_name': mapName});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('deleteMap failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<TopologyMap> getTopologyMap({String? mapName}) async {
    final uri = mapName != null && mapName.isNotEmpty
        ? _buildUri('/getTopologyMap', queryParameters: {'map_name': mapName})
        : _buildUri('/getTopologyMap');
    final res = await http.get(uri);
    if (res.statusCode == 404) {
      return TopologyMap(points: []);
    }
    if (res.statusCode != 200) {
      throw Exception('getTopologyMap failed: ${res.statusCode} ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return TopologyMap.fromJson(j);
  }

  Future<void> saveMapEdit({
    required String editSessionId,
    required TopologyMap topologyMap,
    required Map<int, int> obstacleEdits,
    String? mapName,
    String? sourceMapName,
  }) async {
    final name = mapName ?? await getCurrentMap();
    if (name.isEmpty) {
      throw AppException('no_map_available');
    }
    final obstacleEditsJson = obstacleEdits
        .map((cellIndex, value) => MapEntry(cellIndex.toString(), value));
    final topologyJson = topologyMap.toJson();
    topologyJson['map_name'] = name;
    final uri = _buildUri(
      '/saveMapEdit',
      queryParameters: <String, String>{
        'session_id': editSessionId,
        'map_name': name,
        'source_map_name': sourceMapName ?? name,
        'topology_json': jsonEncode(topologyJson),
        'obstacle_edits_json': jsonEncode(obstacleEditsJson),
      },
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('saveMapEdit failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<Map<String, dynamic>> getGuiSettings() async {
    final uri = _buildUri('/api/settings');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('api/settings ${res.statusCode} ${res.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> saveGuiSettings(Map<String, dynamic> body) async {
    final uri = _buildUri('/api/settings');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('api/settings POST ${res.statusCode} ${res.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<bool> postRobotNavGoal(double x, double y, double yaw,
      {double roll = 0, double pitch = 0}) async {
    final uri = _buildUri('/robot/nav_goal');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(
          {'x': x, 'y': y, 'yaw': yaw, 'roll': roll, 'pitch': pitch}),
    );
    return res.statusCode == 200;
  }

  Future<bool> postRobotInitialPose(double x, double y, double yaw,
      {double roll = 0, double pitch = 0}) async {
    final uri = _buildUri('/robot/initial_pose');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(
          {'x': x, 'y': y, 'yaw': yaw, 'roll': roll, 'pitch': pitch}),
    );
    return res.statusCode == 200;
  }

  Future<bool> postRobotCancelNav() async {
    final uri = _buildUri('/robot/cancel_nav');
    final res =
        await http.post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'});
    return res.statusCode == 200;
  }

  Future<bool> postRobotActionCommand(String command) async {
    final uri = _buildUri('/robot/action_cmd');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'data': command}),
    );
    return res.statusCode == 200;
  }

  Future<void> postSubImage(String topic, bool subscribe) async {
    final uri = _buildUri('/subImage');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'topic': topic, 'subscribe': subscribe}),
    );
    if (res.statusCode != 200) {
      throw Exception('subImage ${res.statusCode} ${res.body}');
    }
  }

  Future<Map<String, dynamic>?> getTf(
      {required String targetFrame, required String sourceFrame}) async {
    final uri = _buildUri('/api/tf',
        queryParameters: {'target_frame': targetFrame, 'source_frame': sourceFrame});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      return null;
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }
}
