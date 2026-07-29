import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:navbot_d1_flutter/basic/ssh_quick_cmd.dart';

enum KeyName {
  None,
  leftAxisX,
  leftAxisY,
  rightAxisX,
  rightAxisY,
  lS,
  rS,
  triggerLeft,
  triggerRight,
  buttonUpDown,
  buttonLeftRight,
  buttonA,
  buttonB,
  buttonX,
  buttonY,
  buttonLB,
  buttonRB,
}

class JoyStickEvent {
  late KeyName keyName;
  bool reverse = false; //是否反转(反转填-1)Q
  double maxValue = 32767;
  double minValue = -32767;
  double value = 0;

  JoyStickEvent(
    this.keyName, {
    this.reverse = false,
    this.maxValue = 32767,
    this.minValue = -32767,
  });
}

enum TempConfigType { ROS2, ROS1 }

String tempConfigTypeToString(TempConfigType type) {
  return type.toString().split('.').last;
}

class Setting {
  static const String _motionDefaultsVersionKey = 'motionDefaultsVersion';
  static const String _controlLogEnabledKey = 'controlLogEnabled';
  static const int _motionDefaultsVersion = 1;
  static const String _defaultMaxVx = '0.9';
  static const String _defaultMaxVy = '0.5';
  static const String _defaultMaxVw = '0.4';

  late SharedPreferences prefs;
  bool _initialized = false;
  Future<bool>? _initFuture;

  final Map<String, String> _backendGuiStrings = {};

  String SSHHost = '';
  int SSHPort = 22;
  String SSHUsername = '';
  String SSHPassword = '';
  List<SshQuickCmd> SSHQuickCommands = [];
  int MapTileFreeColor = 0xFFFFFFFF;
  int MapTileOccColor = 0xFF000000;
  int MapTileUnknownColor = 0xFFCDCDCD;
  int MapTileFreeThresh = 25;
  int MapTileOccThresh = 65;
  final ValueNotifier<int> MapTileStyleEpoch = ValueNotifier(0);
  final ValueNotifier<bool> controlLogEnabledNotifier = ValueNotifier<bool>(
    false,
  );

  // 定义一个映射关系，将Dart中的类名映射到JavaScript中的类名
  Map<String, JoyStickEvent> axisMapping = {
    "AXIS_X": JoyStickEvent(KeyName.leftAxisX),
    "AXIS_Y": JoyStickEvent(KeyName.leftAxisY),
    "AXIS_RX": JoyStickEvent(KeyName.rightAxisX),
    "AXIS_RY": JoyStickEvent(KeyName.rightAxisY),
    "AXIS_HAT_X": JoyStickEvent(KeyName.buttonLeftRight),
    "AXIS_HAT_Y": JoyStickEvent(KeyName.buttonUpDown),
    "triggerRight": JoyStickEvent(KeyName.triggerRight),
    "triggerLeft": JoyStickEvent(KeyName.triggerLeft),
  };
  Map<String, JoyStickEvent> buttonMapping = {
    "KEYCODE_BUTTON_A": JoyStickEvent(
      KeyName.buttonA,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
    "KEYCODE_BUTTON_B": JoyStickEvent(
      KeyName.buttonB,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
    "KEYCODE_BUTTON_X": JoyStickEvent(
      KeyName.buttonX,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
    "KEYCODE_BUTTON_Y": JoyStickEvent(
      KeyName.buttonY,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
    "KEYCODE_BUTTON_L1": JoyStickEvent(
      KeyName.buttonLB,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
    "KEYCODE_BUTTON_R1": JoyStickEvent(
      KeyName.buttonRB,
      maxValue: 1,
      minValue: 0,
      reverse: true,
    ),
  };

  Future<bool> init() {
    return _initFuture ??= _initialize();
  }

  Future<bool> _initialize() async {
    prefs = await SharedPreferences.getInstance();
    _initialized = true;
    controlLogEnabledNotifier.value =
        prefs.getBool(_controlLogEnabledKey) ?? false;
    await _ensureMotionDefaults();

    // 从配置中加载手柄映射
    await _loadGamepadMapping();

    return true;
  }

  bool get controlLogEnabled => controlLogEnabledNotifier.value;

  Future<void> setControlLogEnabled(bool enabled) async {
    controlLogEnabledNotifier.value = enabled;
    await prefs.setBool(_controlLogEnabledKey, enabled);
  }

  Future<void> _ensureMotionDefaults() async {
    final storedVersion = prefs.getInt(_motionDefaultsVersionKey) ?? 0;
    if (!prefs.containsKey('MaxVx')) {
      await prefs.setString('MaxVx', _defaultMaxVx);
    }
    if (!prefs.containsKey('MaxVy')) {
      await prefs.setString('MaxVy', _defaultMaxVy);
    } else if (storedVersion < _motionDefaultsVersion &&
        prefs.getString('MaxVy') == '0.9') {
      await prefs.setString('MaxVy', _defaultMaxVy);
    }
    if (!prefs.containsKey('MaxVw')) {
      await prefs.setString('MaxVw', _defaultMaxVw);
    } else if (storedVersion < _motionDefaultsVersion &&
        prefs.getString('MaxVw') == '0.9') {
      await prefs.setString('MaxVw', _defaultMaxVw);
    }
    await prefs.setInt(_motionDefaultsVersionKey, _motionDefaultsVersion);
  }

  //设置语言回调
  late Function(Locale locale) setLanguage;

  Future<void> _loadGamepadMapping() async {
    final mappingStr = prefs.getString('gamepadMapping');
    if (mappingStr != null) {
      try {
        final mapping = jsonDecode(mappingStr);

        // 清空现有映射
        axisMapping.clear();
        buttonMapping.clear();

        // 加载 axisMapping
        if (mapping['axisMapping'] != null) {
          (mapping['axisMapping'] as Map<String, dynamic>).forEach((
            key,
            value,
          ) {
            final keyName = _parseKeyName(value['keyName']);
            axisMapping[key] = JoyStickEvent(
              keyName,
              maxValue: value['maxValue'] ?? 32767,
              minValue: value['minValue'] ?? -32767,
              reverse: value['reverse'] ?? false,
            );
          });
        }

        // 加载 buttonMapping
        if (mapping['buttonMapping'] != null) {
          (mapping['buttonMapping'] as Map<String, dynamic>).forEach((
            key,
            value,
          ) {
            final keyName = _parseKeyName(value['keyName']);
            buttonMapping[key] = JoyStickEvent(
              keyName,
              maxValue: value['maxValue'] ?? 1,
              minValue: value['minValue'] ?? 0,
              reverse: value['reverse'] ?? true,
            );
          });
        }
      } catch (e) {
        print('Error loading gamepad mapping: $e');
        // 如果加载失败，使用默认映射
        resetGamepadMapping();
      }
    }
  }

  KeyName _parseKeyName(String keyNameStr) {
    // 移除 'KeyName.' 前缀
    final enumStr = keyNameStr.replaceAll('KeyName.', '');
    return KeyName.values.firstWhere(
      (e) => e.toString() == 'KeyName.$enumStr',
      orElse: () => KeyName.None,
    );
  }

  Future<void> saveGamepadMapping() async {
    // 将默认映射保存到配置中
    final mapping = {
      'axisMapping': axisMapping.map(
        (key, value) => MapEntry(key, {
          'keyName': value.keyName.toString(),
          'maxValue': value.maxValue,
          'minValue': value.minValue,
          'reverse': value.reverse,
        }),
      ),
      'buttonMapping': buttonMapping.map(
        (key, value) => MapEntry(key, {
          'keyName': value.keyName.toString(),
          'maxValue': value.maxValue,
          'minValue': value.minValue,
          'reverse': value.reverse,
        }),
      ),
    };
    print(jsonEncode(mapping));
    await prefs.setString('gamepadMapping', jsonEncode(mapping));
  }

  Future<void> resetGamepadMapping() async {
    axisMapping.clear();
    buttonMapping.clear();

    // 恢复默认的轴映射
    axisMapping.addAll({
      "AXIS_X": JoyStickEvent(KeyName.leftAxisX),
      "AXIS_Y": JoyStickEvent(KeyName.leftAxisY),
      "AXIS_RX": JoyStickEvent(KeyName.rightAxisX),
      "AXIS_RY": JoyStickEvent(KeyName.rightAxisY),
      "AXIS_HAT_X": JoyStickEvent(KeyName.buttonLeftRight),
      "AXIS_HAT_Y": JoyStickEvent(KeyName.buttonUpDown),
      "triggerRight": JoyStickEvent(KeyName.triggerRight),
      "triggerLeft": JoyStickEvent(KeyName.triggerLeft),
    });

    // 恢复默认的按钮映射
    buttonMapping.addAll({
      "KEYCODE_BUTTON_A": JoyStickEvent(
        KeyName.buttonA,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
      "KEYCODE_BUTTON_B": JoyStickEvent(
        KeyName.buttonB,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
      "KEYCODE_BUTTON_X": JoyStickEvent(
        KeyName.buttonX,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
      "KEYCODE_BUTTON_Y": JoyStickEvent(
        KeyName.buttonY,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
      "KEYCODE_BUTTON_L1": JoyStickEvent(
        KeyName.buttonLB,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
      "KEYCODE_BUTTON_R1": JoyStickEvent(
        KeyName.buttonRB,
        maxValue: 1,
        minValue: 0,
        reverse: true,
      ),
    });

    // 将默认映射保存到配置中
    final mapping = {
      'axisMapping': axisMapping.map(
        (key, value) => MapEntry(key, {
          'keyName': value.keyName.toString(),
          'maxValue': value.maxValue,
          'minValue': value.minValue,
          'reverse': value.reverse,
        }),
      ),
      'buttonMapping': buttonMapping.map(
        (key, value) => MapEntry(key, {
          'keyName': value.keyName.toString(),
          'maxValue': value.maxValue,
          'minValue': value.minValue,
          'reverse': value.reverse,
        }),
      ),
    };

    await prefs.setString('gamepadMapping', jsonEncode(mapping));
  }

  void setDefaultCfgRos2() {
    prefs.setInt("tempConfig", TempConfigType.ROS2.index);
    prefs.setString('mapTopic', "map");
    prefs.setString('MaxVx', _defaultMaxVx);
    prefs.setString('MaxVy', _defaultMaxVy);
    prefs.setString('MaxVw', _defaultMaxVw);
    prefs.setString('imagePort', "8080");
    prefs.setString('imageTopic', "/image_raw");
    prefs.setDouble('imageWidth', 640);
    prefs.setDouble('imageHeight', 480);
    prefs.setDouble('robotSize', 30.0);
    _backendGuiStrings
      ..clear()
      ..addAll({
        'NavToPoseStatusTopic': 'navigate_to_pose/_action/status',
        'NavThroughPosesStatusTopic': 'navigate_through_poses/_action/status',
        'LaserTopic': 'scan',
        'PointCloud2Topic': 'points',
        'GlobalPathTopic': '/plan',
        'LocalPathTopic': '/local_plan',
        'TracePathTopic': '/transformed_global_plan',
        'RelocTopic': '/initialpose',
        'NavGoalTopic': '/goal_pose',
        'OdomTopic': '/wheel/odometry',
        'SpeedCtrlTopic': '/cmd_vel',
        'RobotActionTopic': '/navbot/action_cmd',
        'BatteryTopic': '/battery_status',
        'GpsTopic': '/fix',
        'RobotFootprintTopic': '/local_costmap/published_footprint',
        'LocalCostmapTopic': '/local_costmap/costmap',
        'DiagnosticTopic': '/diagnostics',
        'TopologyLiveTopic': '/map/topology',
        'TopologyJsonTopic': '',
        'TopologyPublishTopic': '/map/topology/update',
        'MapFrameName': 'map',
        'BaseLinkFrameName': 'base_link',
      });
  }

  void setDefaultCfgRos1() {
    prefs.setInt("tempConfig", TempConfigType.ROS1.index);
    prefs.setString('mapTopic', "map");
    prefs.setString('MaxVx', _defaultMaxVx);
    prefs.setString('MaxVy', _defaultMaxVy);
    prefs.setString('MaxVw', _defaultMaxVw);
    prefs.setString('imagePort', "8080");
    prefs.setString('imageTopic', "/image_raw");
    prefs.setDouble('imageWidth', 640);
    prefs.setDouble('imageHeight', 480);
    prefs.setDouble('robotSize', 30.0);
    _backendGuiStrings
      ..clear()
      ..addAll({
        'NavToPoseStatusTopic': 'navigate_to_pose/_action/status',
        'NavThroughPosesStatusTopic': 'navigate_through_poses/_action/status',
        'LaserTopic': 'scan',
        'PointCloud2Topic': 'points',
        'GlobalPathTopic': '/move_base/DWAPlannerROS/global_plan',
        'LocalPathTopic': '/move_base/DWAPlannerROS/local_plan',
        'TracePathTopic': '/transformed_global_plan',
        'RelocTopic': '/initialpose',
        'NavGoalTopic': 'move_base_simple/goal',
        'OdomTopic': '/odom',
        'SpeedCtrlTopic': '/cmd_vel',
        'RobotActionTopic': '/navbot/action_cmd',
        'BatteryTopic': '/battery_status',
        'GpsTopic': '/fix',
        'RobotFootprintTopic': '/local_costmap/published_footprint',
        'LocalCostmapTopic': '/local_costmap/costmap',
        'DiagnosticTopic': '/diagnostics',
        'TopologyLiveTopic': '/map/topology',
        'TopologyJsonTopic': '',
        'TopologyPublishTopic': '/map/topology/update',
        'MapFrameName': 'map',
        'BaseLinkFrameName': 'base_link',
      });
  }

  SharedPreferences get config {
    return prefs;
  }

  static const Set<String> backendGuiStorageKeys = {
    'MapPubTopic',
    'MapSubTopic',
    'MapManagerFrameId',
    'NavToPoseStatusTopic',
    'NavThroughPosesStatusTopic',
    'LaserTopic',
    'LocalPathTopic',
    'GlobalPathTopic',
    'TracePathTopic',
    'OdomTopic',
    'BatteryTopic',
    'GpsTopic',
    'RobotFootprintTopic',
    'LocalCostmapTopic',
    'GlobalCostmapTopic',
    'PointCloud2Topic',
    'DiagnosticTopic',
    'TopologyLiveTopic',
    'TopologyJsonTopic',
    'TopologyPublishTopic',
    'RelocTopic',
    'NavGoalTopic',
    'SpeedCtrlTopic',
    'RobotActionTopic',
    'MapFrameName',
    'BaseLinkFrameName',
  };

  String _guiStr(String key, String defaultValue) {
    final v = _backendGuiStrings[key];
    if (v != null) return v;
    return defaultValue;
  }

  void applyBackendGuiSettings(Map<String, dynamic> j) {
    _backendGuiStrings.clear();
    j.forEach((k, v) {
      if (v == null || v is List || v is Map) return;
      _backendGuiStrings[k] = '$v';
    });
    SSHHost = '${j['SSHHost'] ?? ''}';
    final portRaw = j['SSHPort'];
    if (portRaw is int) {
      SSHPort = portRaw.clamp(1, 65535);
    } else if (portRaw != null) {
      SSHPort = int.tryParse('$portRaw') ?? 22;
    } else {
      SSHPort = 22;
    }
    SSHUsername = '${j['SSHUsername'] ?? ''}';
    SSHPassword = '${j['SSHPassword'] ?? ''}';
    final qc = j['SSHQuickCommands'];
    if (qc is List) {
      SSHQuickCommands =
          qc
              .whereType<Map>()
              .map((e) => SshQuickCmd.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.name.isNotEmpty && e.cmd.isNotEmpty)
              .toList();
    } else {
      SSHQuickCommands = [];
    }
    MapTileFreeColor = _parseMapTileColor(
      j['MapTileFreeColor'],
      j['MapTileFreeGray'],
      0xFFFFFFFF,
    );
    MapTileOccColor = _parseMapTileColor(
      j['MapTileOccColor'],
      j['MapTileOccGray'],
      0xFF000000,
    );
    MapTileUnknownColor = _parseMapTileColor(
      j['MapTileUnknownColor'],
      j['MapTileUnknownGray'],
      0xFFCDCDCD,
    );
    MapTileFreeThresh = _parseOccThresh(j['MapTileFreeThresh'], 25);
    MapTileOccThresh = _parseOccThresh(j['MapTileOccThresh'], 65);
  }

  int _parseOccThresh(dynamic raw, int fallback) {
    if (raw is int) return raw.clamp(0, 100);
    if (raw != null) {
      final n = int.tryParse('$raw');
      if (n != null) return n.clamp(0, 100);
    }
    return fallback;
  }

  static int normalizeArgb(int value) => value & 0xFFFFFFFF;

  void notifyMapTileStyleChanged() {
    MapTileStyleEpoch.value++;
  }

  int _parseMapTileColor(dynamic colorRaw, dynamic grayRaw, int fallback) {
    if (colorRaw is int) return normalizeArgb(colorRaw);
    if (colorRaw is double) return normalizeArgb(colorRaw.toInt());
    if (colorRaw != null) {
      final n = int.tryParse('$colorRaw');
      if (n != null) return normalizeArgb(n);
    }
    if (grayRaw is int) {
      final g = grayRaw.clamp(0, 255);
      return Color.fromRGBO(g, g, g, 1).toARGB32();
    }
    if (grayRaw != null) {
      final n = int.tryParse('$grayRaw');
      if (n != null) {
        final g = n.clamp(0, 255);
        return Color.fromRGBO(g, g, g, 1).toARGB32();
      }
    }
    return fallback;
  }

  Color get mapTileFreeColor => Color(normalizeArgb(MapTileFreeColor));

  Color get mapTileOccColor => Color(normalizeArgb(MapTileOccColor));

  Color get mapTileUnknownColor => Color(normalizeArgb(MapTileUnknownColor));

  bool get sshCredentialsConfigured =>
      robotIp.trim().isNotEmpty &&
      SSHUsername.trim().isNotEmpty &&
      SSHPassword.isNotEmpty;

  List<SshQuickCmd> get effectiveSSHQuickCommands =>
      SSHQuickCommands.isEmpty ? defaultSSHQuickCommands() : SSHQuickCommands;

  void patchBackendGuiSetting(String key, String value) {
    _backendGuiStrings[key] = value;
  }

  Map<String, dynamic> buildBackendGuiSettingsJson() {
    return {
      'MapPubTopic': mapPubTopic,
      'MapSubTopic': mapSubTopic,
      'MapManagerFrameId': mapManagerFrameId,
      'NavToPoseStatusTopic': navToPoseStatusTopic,
      'NavThroughPosesStatusTopic': navThroughPosesStatusTopic,
      'LaserTopic': laserTopic,
      'LocalPathTopic': localPathTopic,
      'GlobalPathTopic': globalPathTopic,
      'TracePathTopic': tracePathTopic,
      'OdomTopic': odomTopic,
      'BatteryTopic': batteryTopic,
      'RobotFootprintTopic': robotFootprintTopic,
      'LocalCostmapTopic': localCostmapTopic,
      'GlobalCostmapTopic': globalCostmapTopic,
      'PointCloud2Topic': pointCloud2Topic,
      'DiagnosticTopic': diagnosticTopic,
      'TopologyLiveTopic': topologyMapTopic,
      'TopologyJsonTopic': topologyJsonTopic,
      'TopologyPublishTopic': topologyPublishTopic,
      'RelocTopic': relocTopic,
      'NavGoalTopic': navGoalTopic,
      'SpeedCtrlTopic': speedCtrlTopic,
      'RobotActionTopic': robotActionTopic,
      'MapFrameName': mapFrameName,
      'BaseLinkFrameName': baseLinkFrameName,
      'SSHHost': robotIp.trim(),
      'SSHPort': SSHPort,
      'SSHUsername': SSHUsername,
      'SSHPassword': SSHPassword,
      'SSHQuickCommands': SSHQuickCommands.map((e) => e.toJson()).toList(),
      'MapTileFreeColor': MapTileFreeColor,
      'MapTileOccColor': MapTileOccColor,
      'MapTileUnknownColor': MapTileUnknownColor,
      'MapTileFreeThresh': MapTileFreeThresh,
      'MapTileOccThresh': MapTileOccThresh,
    };
  }

  double get imageWidth {
    final p = _prefsOrNull;
    return p?.getDouble("imageWidth") ?? 640;
  }

  double get imageHeight {
    final p = _prefsOrNull;
    return p?.getDouble("imageHeight") ?? 480;
  }

  String get robotIp {
    final p = _prefsOrNull;
    return p?.getString("robotIp") ?? "127.0.0.1";
  }

  String get httpServerPort {
    final p = _prefsOrNull;
    return p?.getString("httpServerPort") ?? "8081";
  }

  void setHttpServerPort(String port) {
    final p = _prefsOrNull;
    if (p == null) return;
    final t = port.trim();
    if (t.isEmpty || t == "8081") {
      p.remove("httpServerPort");
    } else {
      p.setString("httpServerPort", t);
    }
    p.remove("tileServerUrl");
  }

  String get tileServerUrl {
    final host = prefs.getString("robotIp") ?? "127.0.0.1";
    return "http://$host:$httpServerPort";
  }

  String get imagePort {
    final raw = prefs.getString("imagePort");
    final port = raw?.trim() ?? "";
    return port.isEmpty ? "8080" : port;
  }

  String get imageTopic {
    final raw = prefs.getString("imageTopic");
    final topic = raw?.trim() ?? "";
    if (topic.isEmpty ||
        topic == "/camera/rgb/image_raw" ||
        topic == "/camera/image_raw") {
      return "/image_raw";
    }
    return topic;
  }

  String get imageStreamUrl {
    final host = prefs.getString("robotIp") ?? "127.0.0.1";
    return "http://$host:$imagePort/stream"
        "?topic=$imageTopic"
        "&type=mjpeg"
        "&width=480"
        "&height=360"
        "&quality=65";
  }

  String get robotActionTopic {
    return _guiStr('RobotActionTopic', "/navbot/action_cmd");
  }

  void setRobotActionTopic(String topic) {
    _backendGuiStrings['RobotActionTopic'] = topic;
  }

  String get robotPort {
    final p = _prefsOrNull;
    return p?.getString("robotPort") ?? "8080";
  }

  String get robotFootprintTopic {
    return _guiStr('RobotFootprintTopic', "/local_costmap/published_footprint");
  }

  void setRobotFootprintTopic(String topic) {
    _backendGuiStrings['RobotFootprintTopic'] = topic;
  }

  String get localCostmapTopic {
    return _guiStr('LocalCostmapTopic', "/local_costmap/costmap");
  }

  void setLocalCostmapTopic(String topic) {
    _backendGuiStrings['LocalCostmapTopic'] = topic;
  }

  String get globalCostmapTopic {
    return _guiStr('GlobalCostmapTopic', "/global_costmap/costmap");
  }

  String get mapPubTopic {
    return _guiStr('MapPubTopic', "/map_manager/map");
  }

  String get mapSubTopic {
    return _guiStr('MapSubTopic', "/map");
  }

  String get mapManagerFrameId {
    return _guiStr('MapManagerFrameId', "map");
  }

  void setMapTopic(String topic) {
    prefs.setString('mapTopic', topic);
  }

  String get mapTopic {
    return prefs.getString("mapTopic") ?? "map";
  }

  String get topologyMapTopic {
    return _guiStr('TopologyLiveTopic', "/map/topology");
  }

  String get topologyJsonTopic {
    return _guiStr('TopologyJsonTopic', '');
  }

  String get topologyPublishTopic {
    return _guiStr('TopologyPublishTopic', "/map/topology/update");
  }

  String get navToPoseStatusTopic {
    return _guiStr('NavToPoseStatusTopic', "navigate_to_pose/_action/status");
  }

  String get navThroughPosesStatusTopic {
    return _guiStr(
      'NavThroughPosesStatusTopic',
      "navigate_through_poses/_action/status",
    );
  }

  void setLaserTopic(String topic) {
    _backendGuiStrings['LaserTopic'] = topic;
  }

  String get laserTopic {
    return _guiStr('LaserTopic', "scan");
  }

  void setPointCloud2Topic(String topic) {
    _backendGuiStrings['PointCloud2Topic'] = topic;
  }

  String get pointCloud2Topic {
    return _guiStr('PointCloud2Topic', "points");
  }

  void setGloalPathTopic(String topic) {
    _backendGuiStrings['GlobalPathTopic'] = topic;
  }

  String get globalPathTopic {
    return _guiStr('GlobalPathTopic', "/plan");
  }

  String get tracePathTopic {
    return _guiStr('TracePathTopic', "/transformed_global_plan");
  }

  void setLocalPathTopic(String topic) {
    _backendGuiStrings['LocalPathTopic'] = topic;
  }

  String get localPathTopic {
    return _guiStr('LocalPathTopic', "/local_plan");
  }

  void setRelocTopic(String topic) {
    _backendGuiStrings['RelocTopic'] = topic;
  }

  String get relocTopic {
    return _guiStr('RelocTopic', "/initialpose");
  }

  String get mapFrameName {
    return _guiStr('MapFrameName', "map");
  }

  String get baseLinkFrameName {
    return _guiStr('BaseLinkFrameName', "base_link");
  }

  String get navGoalTopic {
    return _guiStr('NavGoalTopic', "/goal_pose");
  }

  void setNavGoalTopic(String topic) {
    _backendGuiStrings['NavGoalTopic'] = topic;
  }

  String get batteryTopic {
    return _guiStr('BatteryTopic', "/battery_status");
  }

  void setBatteryTopic(String topic) {
    _backendGuiStrings['BatteryTopic'] = topic;
  }

  String get gpsTopic {
    return _guiStr('GpsTopic', "/fix");
  }

  void setGpsTopic(String topic) {
    _backendGuiStrings['GpsTopic'] = topic;
  }

  String get diagnosticTopic {
    return _guiStr('DiagnosticTopic', "/diagnostics");
  }

  void setDiagnosticTopic(String topic) {
    _backendGuiStrings['DiagnosticTopic'] = topic;
  }

  String getConfig(String key) {
    return prefs.getString(key) ?? "";
  }

  String get odomTopic {
    return _guiStr('OdomTopic', "/wheel/odometry");
  }

  void setOdomTopic(String topic) {
    _backendGuiStrings['OdomTopic'] = topic;
  }

  void setSpeedCtrlTopic(String topic) {
    _backendGuiStrings['SpeedCtrlTopic'] = topic;
  }

  String get speedCtrlTopic {
    return _guiStr('SpeedCtrlTopic', "/cmd_vel");
  }

  // 添加最大速度设置方法
  void setMaxVx(String value) {
    prefs.setString('MaxVx', value);
  }

  void setMaxVy(String value) {
    prefs.setString('MaxVy', value);
  }

  void setMaxVw(String value) {
    prefs.setString('MaxVw', value);
  }

  TempConfigType get tempConfig {
    final i = prefs.getInt("tempConfig") ?? 0;
    if (i == TempConfigType.ROS1.index) {
      return TempConfigType.ROS1;
    }
    return TempConfigType.ROS2;
  }

  // 添加最大速度获取方法
  double get maxVx {
    return double.parse(prefs.getString("MaxVx") ?? _defaultMaxVx);
  }

  double get maxVy {
    return double.parse(prefs.getString("MaxVy") ?? _defaultMaxVy);
  }

  double get maxVw {
    return double.parse(prefs.getString("MaxVw") ?? _defaultMaxVw);
  }

  // 添加图像设置方法
  void setImagePort(String port) {
    prefs.setString('imagePort', port);
  }

  void setImageTopic(String topic) {
    prefs.setString('imageTopic', topic);
  }

  void setImageWidth(double width) {
    prefs.setDouble('imageWidth', width);
  }

  void setImageHeight(double height) {
    prefs.setDouble('imageHeight', height);
  }

  // 添加框架名称设置方法
  void setMapFrameName(String name) {
    _backendGuiStrings['MapFrameName'] = name;
  }

  void setBaseLinkFrameName(String name) {
    _backendGuiStrings['BaseLinkFrameName'] = name;
  }

  // 添加通用配置设置方法
  void setConfig(String key, String value) {
    prefs.setString(key, value);
  }

  // 基本设置相关方法
  void setRobotIp(String ip) {
    final p = _prefsOrNull;
    if (p == null) return;
    p.setString('robotIp', ip);
  }

  void setRobotPort(String port) {
    final p = _prefsOrNull;
    if (p == null) return;
    p.setString('robotPort', port);
  }

  // 地图相关方法

  void setMapMetadataTopic(String topic) {
    prefs.setString('mapMetadataTopic', topic);
  }

  // 定位相关方法

  void setInitPoseTopic(String topic) {
    prefs.setString('initPoseTopic', topic);
  }

  void setAmclPoseTopic(String topic) {
    prefs.setString('amclPoseTopic', topic);
  }

  // 导航相关方法
  void setMoveBaseTopic(String topic) {
    prefs.setString('moveBaseTopic', topic);
  }

  void setCmdVelTopic(String topic) {
    prefs.setString('cmdVelTopic', topic);
  }

  void setGlobalPlanTopic(String topic) {
    prefs.setString('globalPlanTopic', topic);
  }

  void setLocalPlanTopic(String topic) {
    prefs.setString('localPlanTopic', topic);
  }

  void setGlobalCostmapTopic(String topic) {
    _backendGuiStrings['GlobalCostmapTopic'] = topic;
  }

  void setGlobalPathTopic(String topic) {
    _backendGuiStrings['GlobalPathTopic'] = topic;
  }

  void setTracePathTopic(String topic) {
    _backendGuiStrings['TracePathTopic'] = topic;
  }

  // 状态监控相关方法
  void setRobotStatusTopic(String topic) {
    prefs.setString('robotStatusTopic', topic);
  }

  void setJointStatesTopic(String topic) {
    prefs.setString('jointStatesTopic', topic);
  }

  // 图层开关配置相关方法
  void setShowGlobalCostmap(bool show) {
    prefs.setBool('showGlobalCostmap', show);
  }

  bool get showGlobalCostmap {
    return prefs.getBool('showGlobalCostmap') ?? false;
  }

  void setShowLocalCostmap(bool show) {
    prefs.setBool('showLocalCostmap', show);
  }

  bool get showLocalCostmap {
    return prefs.getBool('showLocalCostmap') ?? true;
  }

  void setShowLaser(bool show) {
    prefs.setBool('showLaser', show);
  }

  bool get showLaser {
    return prefs.getBool('showLaser') ?? true;
  }

  void setShowPointCloud(bool show) {
    prefs.setBool('showPointCloud', show);
  }

  bool get showPointCloud {
    return prefs.getBool('showPointCloud') ?? false;
  }

  void setShowTopologyPath(bool show) {
    prefs.setBool('showTopologyPath', show);
  }

  bool get showTopologyPath {
    return prefs.getBool('showTopologyPath') ?? true;
  }

  // 机器人尺寸相关方法
  void setRobotSize(double size) {
    prefs.setDouble('robotSize', size);
  }

  double get robotSize {
    return prefs.getDouble('robotSize') ?? 30.0;
  }
}

extension on Setting {
  SharedPreferences? get _prefsOrNull {
    if (!_initialized) return null;
    return prefs;
  }
}

Setting globalSetting = Setting();

// 初始化全局配置
Future<bool> initGlobalSetting() async {
  return globalSetting.init();
}
