import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:oktoast/oktoast.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:navbot_d1_flutter/basic/RobotPose.dart';
import 'package:navbot_d1_flutter/basic/action_status.dart';
import 'package:navbot_d1_flutter/basic/diagnostic_array.dart' as darr;
import 'package:navbot_d1_flutter/basic/diagnostic_status.dart' as dstatus;
import 'package:navbot_d1_flutter/basic/key_value.dart';
import 'package:navbot_d1_flutter/basic/math.dart';
import 'package:navbot_d1_flutter/basic/occupancy_map.dart';
import 'package:navbot_d1_flutter/basic/pointcloud2.dart';
import 'package:navbot_d1_flutter/basic/topology_map.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/protobuf/geometry_msgs.pb.dart' as gpb;
import 'package:navbot_d1_flutter/protobuf/nav_msgs.pb.dart' as npb;
import 'package:navbot_d1_flutter/protobuf/robot_message.pb.dart';
import 'package:navbot_d1_flutter/protobuf/sensor_msg.pb.dart' as sensor_msg;
import 'package:navbot_d1_flutter/protobuf/diagnostic_msgs.pb.dart' as dipb;
import 'package:navbot_d1_flutter/protobuf/action_msgs.pb.dart' as apb;
import 'package:navbot_d1_flutter/provider/diagnostic_manager.dart';
import 'package:navbot_d1_flutter/provider/control_log_store.dart';
import 'package:navbot_d1_flutter/provider/d1_mode_protocol.dart';
import 'package:navbot_d1_flutter/provider/http_channel.dart';
import 'package:navbot_d1_flutter/provider/map_manager.dart';

class TopicWithSchemaName {
  final String name;
  final String schemaName;
  TopicWithSchemaName({required this.name, required this.schemaName});
}

class LaserData {
  RobotPose robotPose;
  List<vm.Vector2> laserPoseBaseLink;
  LaserData({required this.robotPose, required this.laserPoseBaseLink});
}

class RobotSpeed {
  double vx;
  double vy;
  double vw;
  RobotSpeed({required this.vx, required this.vy, required this.vw});

  double get planarSpeed => math.sqrt(vx * vx + vy * vy);
}

class GpsFix {
  final double latitude;
  final double longitude;
  final double altitude;
  final int status;

  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.status,
  });
}

sealed class _HeavyRobotPayload {
  const _HeavyRobotPayload();
}

final class _HeavyLaserPayload extends _HeavyRobotPayload {
  final List<vm.Vector2> points;

  const _HeavyLaserPayload(this.points);
}

final class _HeavyCostmapPayload extends _HeavyRobotPayload {
  final bool isLocal;
  final OccupancyMap map;

  const _HeavyCostmapPayload({required this.isLocal, required this.map});
}

final class _HeavyPointCloudPayload extends _HeavyRobotPayload {
  final List<Point3D> points;

  const _HeavyPointCloudPayload(this.points);
}

_HeavyRobotPayload? _decodeHeavyRobotPayload(Uint8List raw) {
  final RobotMessage msg;
  try {
    msg = RobotMessage.fromBuffer(raw);
  } catch (_) {
    return null;
  }

  switch (msg.whichPayload()) {
    case RobotMessage_Payload.laserScan:
      final scan = msg.laserScan;
      final count =
          scan.x.length < scan.y.length ? scan.x.length : scan.y.length;
      return _HeavyLaserPayload(
        List<vm.Vector2>.generate(
          count,
          (index) =>
              vm.Vector2(scan.x[index].toDouble(), scan.y[index].toDouble()),
          growable: false,
        ),
      );
    case RobotMessage_Payload.localCostmap:
      return _HeavyCostmapPayload(
        isLocal: true,
        map: _occupancyFromProtoInWorker(msg.localCostmap),
      );
    case RobotMessage_Payload.globalCostmap:
      return _HeavyCostmapPayload(
        isLocal: false,
        map: _occupancyFromProtoInWorker(msg.globalCostmap),
      );
    case RobotMessage_Payload.pointcloudMap:
      final pointCloud = msg.pointcloudMap;
      final count =
          pointCloud.x.length < pointCloud.y.length
              ? pointCloud.x.length
              : pointCloud.y.length;
      return _HeavyPointCloudPayload(
        List<Point3D>.generate(
          count,
          (index) => Point3D(
            pointCloud.x[index],
            pointCloud.y[index],
            index < pointCloud.z.length ? pointCloud.z[index] : 0.0,
          ),
          growable: false,
        ),
      );
    default:
      return null;
  }
}

void _heavyDecodeWorker(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == null) {
      inbox.close();
      return;
    }
    final request = message as List<Object?>;
    final requestId = request[0] as int;
    final bytes =
        (request[1] as TransferableTypedData).materialize().asUint8List();
    mainPort.send(<Object?>[requestId, _decodeHeavyRobotPayload(bytes)]);
  });
}

OccupancyMap _occupancyFromProtoInWorker(npb.OccupancyGridProto grid) {
  final info = grid.info;
  final origin = info.origin;
  final orientation = origin.orientation;
  final euler = quaternionToEuler(
    vm.Quaternion(orientation.x, orientation.y, orientation.z, orientation.w),
  );
  final map = OccupancyMap();
  final width = info.width;
  final height = info.height;
  map.mapConfig
    ..resolution = info.resolution.toDouble()
    ..width = width
    ..height = height
    ..originX = origin.position.x
    ..originY = origin.position.y
    ..originTheta = euler[0];

  if (width <= 0 || height <= 0) {
    map.data = <List<int>>[];
    return map;
  }

  final rows = List<List<int>>.generate(
    height,
    (_) => List<int>.filled(width, 0),
    growable: false,
  );
  final dataLength =
      grid.data.length < width * height ? grid.data.length : width * height;
  for (var index = 0; index < dataLength; index++) {
    rows[index ~/ width][index % width] = grid.data[index];
  }
  map.data = rows.reversed.toList(growable: false);
  return map;
}

class _ProtoCursor {
  int offset;
  _ProtoCursor(this.offset);
}

class WsChannel {
  static const int _manualCommandIntervalMs = 20;

  final HttpChannel _http = HttpChannel();
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSub;
  int _connectionGeneration = 0;

  Timer? cmdVelTimer;
  Timer? _reconnectTimer;
  bool isReconnect_ = false;
  bool _reconnectAttemptRunning = false;
  bool _disposed = false;
  bool _manualCommandFresh = false;
  bool _emergencyStopLatched = false;
  DateTime? _lastWsMessageAt;

  bool manualCtrlMode_ = false;
  final ValueNotifier<int> connectionReadySignal = ValueNotifier<int>(0);
  final ValueNotifier<bool> emergencyStopLatched = ValueNotifier<bool>(false);
  ValueNotifier<double> battery_ = ValueNotifier(100);
  ValueNotifier<GpsFix?> gpsFix_ = ValueNotifier<GpsFix?>(null);
  ValueNotifier<Uint8List?> imageFrame = ValueNotifier<Uint8List?>(null);
  RobotSpeed cmdVel_ = RobotSpeed(vx: 0, vy: 0, vw: 0);
  final ValueNotifier<RobotSpeed> controlSpeed_ = ValueNotifier(
    RobotSpeed(vx: 0, vy: 0, vw: 0),
  );
  ValueNotifier<RobotSpeed> robotSpeed_ = ValueNotifier(
    RobotSpeed(vx: 0, vy: 0, vw: 0),
  );
  String backendHost_ = "";
  int backendHttpPort_ = 8080;
  Status rosConnectState_ = Status.none;
  String? _streamError;
  String? _activeImageTopicRaw;
  String? _activeImageTopicNormalized;
  bool imageStreamStarting_ = false;
  int? _lastImagePushMs;
  int _nextD1ModeSeq = 1;
  final Map<int, Uint8List> _pendingHeavyMessages = <int, Uint8List>{};
  final Map<int, int> _lastHeavyApplyMs = <int, int>{};
  bool _heavyMessageDrainRunning = false;
  Isolate? _heavyWorkerIsolate;
  ReceivePort? _heavyWorkerReceivePort;
  SendPort? _heavyWorkerSendPort;
  Completer<SendPort>? _heavyWorkerStarting;
  int _nextHeavyRequestId = 1;
  final Map<int, Completer<_HeavyRobotPayload?>> _heavyWorkerRequests =
      <int, Completer<_HeavyRobotPayload?>>{};
  final Map<int, Completer<D1ModeAck>> _pendingD1ModeAcks =
      <int, Completer<D1ModeAck>>{};
  ValueNotifier<D1ModeAck?> d1ModeAck_ = ValueNotifier<D1ModeAck?>(null);

  ValueNotifier<OccupancyMap> get map_ => mapManager.occupancyMap;
  ValueNotifier<TopologyMap> get topologyMap_ => mapManager.topologyMap;
  ValueNotifier<RobotPose> robotPoseMap = ValueNotifier(RobotPose.zero());
  ValueNotifier<List<vm.Vector2>> laserBasePoint_ = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> localPath = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> globalPath = ValueNotifier([]);
  ValueNotifier<List<vm.Vector2>> tracePath = ValueNotifier([]);
  ValueNotifier<LaserData> laserPointData = ValueNotifier(
    LaserData(robotPose: RobotPose(0, 0, 0), laserPoseBaseLink: []),
  );
  ValueNotifier<ActionStatus> navStatus_ = ValueNotifier(ActionStatus.unknown);
  ValueNotifier<List<vm.Vector2>> robotFootprint = ValueNotifier([]);
  ValueNotifier<OccupancyMap> localCostmap = ValueNotifier(OccupancyMap());
  ValueNotifier<OccupancyMap> globalCostmap = ValueNotifier(OccupancyMap());
  ValueNotifier<List<Point3D>> pointCloud2Data = ValueNotifier([]);
  ValueNotifier<darr.DiagnosticArray> diagnosticData = ValueNotifier(
    darr.DiagnosticArray(),
  );
  late DiagnosticManager diagnosticManager;
  late MapManager mapManager;

  WsChannel() {
    diagnosticManager = DiagnosticManager();
    mapManager = MapManager();
    mapManager.init();

    globalSetting.init().then((success) {
      if (_disposed) return;
      _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_disposed) return;
        final lastMessageAt = _lastWsMessageAt;
        if (rosConnectState_ == Status.connected &&
            lastMessageAt != null &&
            DateTime.now().difference(lastMessageAt) >
                const Duration(seconds: 10)) {
          final staleChannel = _wsChannel;
          rosConnectState_ = Status.errored;
          _resetManualCommandSnapshot();
          await _teardownWs(expectedChannel: staleChannel);
          return;
        }
        if (isReconnect_ &&
            rosConnectState_ != Status.connected &&
            backendHost_.isNotEmpty &&
            !_reconnectAttemptRunning) {
          _reconnectAttemptRunning = true;
          showToast(
            "lost connection to $backendHost_:$backendHttpPort_ try reconnect...",
            position: ToastPosition.bottom,
            backgroundColor: Colors.black.withValues(alpha: 0.8),
            textStyle: const TextStyle(color: Colors.white),
          );
          try {
            final error = await connectBackend(backendHost_, backendHttpPort_);
            if (error.isEmpty) {
              showToast(
                "reconnect success!",
                position: ToastPosition.bottom,
                backgroundColor: Colors.green.withValues(alpha: 0.8),
                textStyle: const TextStyle(color: Colors.white),
              );
            } else {
              showToast(
                "reconnect failed: $error",
                position: ToastPosition.bottom,
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                textStyle: const TextStyle(color: Colors.white),
              );
            }
          } finally {
            _reconnectAttemptRunning = false;
          }
        }
      });
    });
  }

  String? get streamError => _streamError;
  bool get imageStreamStarting => imageStreamStarting_;

  static String normalizeTopic(String t) {
    if (t.isEmpty) return t;
    return t.startsWith('/') ? t : '/$t';
  }

  static String _wsAuthority(String host, int port) {
    final h = host.trim();
    if (h.contains(':') && !h.startsWith('[')) {
      return '[$h]:$port';
    }
    return '$h:$port';
  }

  static Uri robotWebSocketUri(String host, int port) {
    final pageHttps = kIsWeb && Uri.base.scheme == 'https';
    final scheme = pageHttps ? 'wss' : 'ws';
    final authority = _wsAuthority(host, port);
    return Uri.parse('$scheme://$authority/ws/robot');
  }

  static Uri sshTunnelWebSocketUri(String host, int port) {
    final pageHttps = kIsWeb && Uri.base.scheme == 'https';
    final scheme = pageHttps ? 'wss' : 'ws';
    final authority = _wsAuthority(host, port);
    return Uri.parse('$scheme://$authority/ws/ssh');
  }

  Future<String> connectBackend(String host, int httpPort) async {
    final controlLog = ControlLogStore.instance;
    final generation = ++_connectionGeneration;
    backendHost_ = host.trim();
    backendHttpPort_ = httpPort;
    globalSetting.setRobotIp(host);
    globalSetting.setHttpServerPort(httpPort.toString());
    rosConnectState_ = Status.connecting;
    controlLog.info(
      'WS',
      'connect start host=$backendHost_ port=$backendHttpPort_ '
          'generation=$generation',
    );

    await _teardownWs();
    if (_disposed || generation != _connectionGeneration) {
      return 'connection superseded';
    }

    try {
      final settings = await _http.getGuiSettings();
      if (_disposed || generation != _connectionGeneration) {
        return 'connection superseded';
      }
      globalSetting.applyBackendGuiSettings(settings);
    } catch (e) {
      controlLog.error('HTTP', 'settings failed: $e');
      if (generation == _connectionGeneration) {
        rosConnectState_ = Status.none;
      }
      return 'settings: $e';
    }

    if (kIsWeb) {
      final ping = Uri.parse('http://${_wsAuthority(host, httpPort)}/tiles/');
      try {
        final r = await http.get(ping).timeout(const Duration(seconds: 5));
        if (_disposed || generation != _connectionGeneration) {
          return 'connection superseded';
        }
        if (r.statusCode >= 500) {
          rosConnectState_ = Status.none;
          return 'HTTP ${r.statusCode}';
        }
      } catch (e) {
        if (generation == _connectionGeneration) {
          rosConnectState_ = Status.none;
        }
        return 'HTTP unreachable: $e';
      }
    }

    final wsErr = await _attachRobotWebSocket(host, httpPort, generation);
    if (_disposed || generation != _connectionGeneration) {
      return 'connection superseded';
    }
    if (wsErr.isNotEmpty) {
      controlLog.error('WS', 'connect failed: $wsErr');
      rosConnectState_ = Status.none;
      return wsErr;
    }

    _resetManualCommandSnapshot();
    _lastWsMessageAt = DateTime.now();
    rosConnectState_ = Status.connected;
    controlLog.info('WS', 'connected ${robotWebSocketUri(host, httpPort)}');
    sendSpeed(0, 0, 0);
    connectionReadySignal.value++;
    if (!isReconnect_) {
      isReconnect_ = true;
    }
    return '';
  }

  Future<void> _teardownWs({WebSocketChannel? expectedChannel}) async {
    final activeChannel = _wsChannel;
    if (expectedChannel != null && !identical(expectedChannel, activeChannel)) {
      try {
        await expectedChannel.sink.close().timeout(const Duration(seconds: 1));
      } catch (_) {}
      return;
    }

    final channelToClose = activeChannel;
    final subscriptionToCancel = _wsSub;
    _wsChannel = null;
    _wsSub = null;
    _lastWsMessageAt = null;
    _failPendingD1ModeAcks(StateError('robot websocket disconnected'));
    _pendingHeavyMessages.clear();
    try {
      await Future.wait<void>([
        if (subscriptionToCancel != null) subscriptionToCancel.cancel(),
        if (channelToClose != null) channelToClose.sink.close(),
      ]).timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  Future<String> _attachRobotWebSocket(
    String host,
    int httpPort,
    int generation,
  ) async {
    final uri = robotWebSocketUri(host, httpPort);
    debugPrint('backend ws $uri');
    _streamError = null;
    final channel = WebSocketChannel.connect(uri);
    if (_disposed || generation != _connectionGeneration) {
      try {
        await channel.sink.close();
      } catch (_) {}
      return 'connection superseded';
    }
    _wsChannel = channel;
    _wsSub = channel.stream.listen(
      (data) {
        if (identical(channel, _wsChannel)) {
          _onWsBinary(data);
        }
      },
      onError: (Object e) {
        _handleRobotWebSocketClosed(channel, e);
      },
      onDone: () {
        _handleRobotWebSocketClosed(channel);
      },
      cancelOnError: true,
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await _teardownWs(expectedChannel: channel);
      return 'ws handshake timeout';
    } catch (e) {
      await _teardownWs(expectedChannel: channel);
      return 'ws: $e';
    }
    if (_disposed ||
        generation != _connectionGeneration ||
        !identical(channel, _wsChannel)) {
      await _teardownWs(expectedChannel: channel);
      return 'connection superseded';
    }
    return '';
  }

  void _handleRobotWebSocketClosed(WebSocketChannel channel, [Object? error]) {
    if (!identical(channel, _wsChannel)) return;
    if (error != null) {
      _streamError = error.toString();
      ControlLogStore.instance.error('WS', 'closed with error: $error');
    } else {
      ControlLogStore.instance.warning('WS', 'remote connection closed');
    }
    _resetManualCommandSnapshot();
    rosConnectState_ = Status.errored;
    unawaited(_teardownWs(expectedChannel: channel));
  }

  void _onWsBinary(dynamic data) {
    _lastWsMessageAt = DateTime.now();
    Uint8List? raw;
    if (data is Uint8List) {
      raw = data;
    } else if (data is List<int>) {
      raw = Uint8List.fromList(data);
    }
    if (raw == null) return;

    final topLevelField = _topLevelProtoField(raw);
    if (topLevelField == 4 ||
        topLevelField == 12 ||
        topLevelField == 13 ||
        topLevelField == 14) {
      _enqueueHeavyMessage(topLevelField!, raw);
      return;
    }

    final d1ModeAck = D1ModeProtocol.tryDecodeAckEnvelope(raw);
    if (d1ModeAck != null) {
      d1ModeAck_.value = d1ModeAck;
      final completer = _pendingD1ModeAcks.remove(d1ModeAck.seq);
      if (completer != null && !completer.isCompleted) {
        completer.complete(d1ModeAck);
      }
      return;
    }

    if (_tryDecodeGpsRobotMessage(raw)) {
      return;
    }

    final RobotMessage msg;
    try {
      msg = RobotMessage.fromBuffer(raw);
    } catch (_) {
      return;
    }

    switch (msg.whichPayload()) {
      case RobotMessage_Payload.image:
        _onStreamImage(msg.image);
        break;
      case RobotMessage_Payload.heartbeat:
        break;
      case RobotMessage_Payload.laserScan:
        break;
      case RobotMessage_Payload.robotPoseMap:
        _onRobotPoseMap(msg.robotPoseMap);
        break;
      case RobotMessage_Payload.pathLocal:
        _onPathPb(msg.pathLocal, localPath);
        break;
      case RobotMessage_Payload.pathGlobal:
        _onPathPb(msg.pathGlobal, globalPath);
        break;
      case RobotMessage_Payload.pathTrace:
        _onPathPb(msg.pathTrace, tracePath);
        break;
      case RobotMessage_Payload.odometry:
        _onOdometryPb(msg.odometry);
        break;
      case RobotMessage_Payload.battery:
        _onBatteryPb(msg.battery);
        break;
      case RobotMessage_Payload.footprint:
        _onFootprintPb(msg.footprint);
        break;
      case RobotMessage_Payload.localCostmap:
        break;
      case RobotMessage_Payload.globalCostmap:
        break;
      case RobotMessage_Payload.pointcloudMap:
        break;
      case RobotMessage_Payload.diagnostic:
        _onDiagnosticPb(msg.diagnostic);
        break;
      case RobotMessage_Payload.navStatus:
        _onNavStatusPb(msg.navStatus);
        break;
      case RobotMessage_Payload.transformLookupResponse:
      case RobotMessage_Payload.notSet:
        break;
    }
  }

  int? _topLevelProtoField(Uint8List raw) {
    var value = 0;
    var shift = 0;
    final length = raw.length < 10 ? raw.length : 10;
    for (var index = 0; index < length; index++) {
      final byte = raw[index];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return value >> 3;
      }
      shift += 7;
    }
    return null;
  }

  void _enqueueHeavyMessage(int field, Uint8List raw) {
    _pendingHeavyMessages[field] = raw;
    if (!_heavyMessageDrainRunning) {
      unawaited(_drainHeavyMessages());
    }
  }

  Future<SendPort> _ensureHeavyWorker() {
    final existing = _heavyWorkerSendPort;
    if (existing != null) return Future<SendPort>.value(existing);
    final starting = _heavyWorkerStarting;
    if (starting != null) return starting.future;

    final completer = Completer<SendPort>();
    _heavyWorkerStarting = completer;
    final receivePort = ReceivePort();
    _heavyWorkerReceivePort = receivePort;
    receivePort.listen((message) {
      if (message is SendPort) {
        _heavyWorkerSendPort = message;
        if (!completer.isCompleted) {
          completer.complete(message);
        }
        return;
      }
      if (message is! List<Object?> || message.length < 2) return;
      final requestId = message[0] as int;
      _heavyWorkerRequests
          .remove(requestId)
          ?.complete(message[1] as _HeavyRobotPayload?);
    });
    Isolate.spawn(_heavyDecodeWorker, receivePort.sendPort)
        .then((isolate) {
          if (_disposed) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _heavyWorkerIsolate = isolate;
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          _heavyWorkerStarting = null;
          receivePort.close();
        });
    return completer.future;
  }

  Future<_HeavyRobotPayload?> _decodeHeavyMessage(Uint8List raw) async {
    if (kIsWeb) {
      return compute(_decodeHeavyRobotPayload, raw);
    }
    final sendPort = await _ensureHeavyWorker();
    final requestId = _nextHeavyRequestId++;
    final completer = Completer<_HeavyRobotPayload?>();
    _heavyWorkerRequests[requestId] = completer;
    sendPort.send(<Object?>[
      requestId,
      TransferableTypedData.fromList(<Uint8List>[raw]),
    ]);
    return completer.future;
  }

  Future<void> _drainHeavyMessages() async {
    if (_heavyMessageDrainRunning) return;
    _heavyMessageDrainRunning = true;
    try {
      while (_pendingHeavyMessages.isNotEmpty) {
        final field = _pendingHeavyMessages.keys.first;
        var raw = _pendingHeavyMessages.remove(field)!;
        final throttleMs = field == 4 ? 100 : 250;
        final elapsed =
            DateTime.now().millisecondsSinceEpoch -
            (_lastHeavyApplyMs[field] ?? 0);
        if (elapsed < throttleMs) {
          await Future<void>.delayed(
            Duration(milliseconds: throttleMs - elapsed),
          );
          raw = _pendingHeavyMessages.remove(field) ?? raw;
        }

        final decoded = await _decodeHeavyMessage(raw);
        if (decoded == null) continue;

        _applyHeavyPayload(decoded);
        _lastHeavyApplyMs[field] = DateTime.now().millisecondsSinceEpoch;
      }
    } finally {
      _heavyMessageDrainRunning = false;
      if (_pendingHeavyMessages.isNotEmpty) {
        unawaited(_drainHeavyMessages());
      }
    }
  }

  void _applyHeavyPayload(_HeavyRobotPayload payload) {
    switch (payload) {
      case _HeavyLaserPayload():
        final pose = robotPoseMap.value;
        laserBasePoint_.value = payload.points;
        laserPointData.value = LaserData(
          robotPose: pose,
          laserPoseBaseLink: payload.points,
        );
      case _HeavyCostmapPayload():
        if (payload.isLocal) {
          localCostmap.value = payload.map;
        } else {
          globalCostmap.value = payload.map;
        }
      case _HeavyPointCloudPayload():
        pointCloud2Data.value = payload.points;
    }
  }

  void _onStreamImage(ImageFrame img) {
    final topic = normalizeTopic(img.topic);
    if (topic != _activeImageTopicNormalized) return;
    if (img.data.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastImagePushMs != null && now - _lastImagePushMs! < 66) return;
    _lastImagePushMs = now;
    final u8 = Uint8List.fromList(img.data);
    imageFrame.value = u8;
  }

  RobotPose _poseFromGpbPose(gpb.Pose p) {
    final o = p.orientation;
    final q = vm.Quaternion(o.x, o.y, o.z, o.w);
    final euler = quaternionToEuler(q);
    final yaw = euler[0];
    return RobotPose(p.position.x, p.position.y, yaw);
  }

  void _onRobotPoseMap(gpb.PoseStamped ps) {
    robotPoseMap.value = _poseFromGpbPose(ps.pose);
  }

  void _onPathPb(npb.Path path, ValueNotifier<List<vm.Vector2>> out) {
    final pts = <vm.Vector2>[];
    for (final p in path.poses) {
      final pose = p.pose;
      pts.add(vm.Vector2(pose.position.x, pose.position.y));
    }
    out.value = pts;
  }

  void _onOdometryPb(npb.Odometry o) {
    final lin = o.twist.linear;
    final ang = o.twist.angular;
    robotSpeed_.value = RobotSpeed(vx: lin.x, vy: lin.y, vw: ang.z);
  }

  void _onBatteryPb(sensor_msg.BatteryState b) {
    final p = b.percentage;
    battery_.value = p > 0 ? p.toDouble() : battery_.value;
  }

  bool _tryDecodeGpsRobotMessage(Uint8List raw) {
    final data = ByteData.view(
      raw.buffer,
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final cursor = _ProtoCursor(0);
    final end = raw.lengthInBytes;
    while (cursor.offset < end) {
      final tag = _readVarint(data, cursor, end);
      if (tag == null || tag == 0) return false;
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      if (fieldNumber == 19 && wireType == 2) {
        final length = _readVarint(data, cursor, end);
        if (length == null || length < 0 || cursor.offset + length > end) {
          return false;
        }
        return _decodeGpsFix(data, cursor.offset, cursor.offset + length);
      }
      if (!_skipProtoField(data, cursor, end, wireType)) return false;
    }
    return false;
  }

  bool _decodeGpsFix(ByteData data, int start, int end) {
    final cursor = _ProtoCursor(start);
    int status = 0;
    double? latitude;
    double? longitude;
    double altitude = 0;
    while (cursor.offset < end) {
      final tag = _readVarint(data, cursor, end);
      if (tag == null || tag == 0) return false;
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;
      switch (fieldNumber) {
        case 2:
          final v = _readVarint(data, cursor, end);
          if (v == null) return false;
          status = v;
          break;
        case 3:
          if (wireType != 1 || cursor.offset + 8 > end) return false;
          latitude = data.getFloat64(cursor.offset, Endian.little);
          cursor.offset += 8;
          break;
        case 4:
          if (wireType != 1 || cursor.offset + 8 > end) return false;
          longitude = data.getFloat64(cursor.offset, Endian.little);
          cursor.offset += 8;
          break;
        case 5:
          if (wireType != 1 || cursor.offset + 8 > end) return false;
          altitude = data.getFloat64(cursor.offset, Endian.little);
          cursor.offset += 8;
          break;
        default:
          if (!_skipProtoField(data, cursor, end, wireType)) return false;
      }
    }
    if (latitude == null || longitude == null) return false;
    gpsFix_.value = GpsFix(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      status: status,
    );
    return true;
  }

  int? _readVarint(ByteData data, _ProtoCursor cursor, int end) {
    var result = 0;
    var shift = 0;
    while (cursor.offset < end && shift < 64) {
      final b = data.getUint8(cursor.offset++);
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
    return null;
  }

  bool _skipProtoField(
    ByteData data,
    _ProtoCursor cursor,
    int end,
    int wireType,
  ) {
    switch (wireType) {
      case 0:
        return _readVarint(data, cursor, end) != null;
      case 1:
        if (cursor.offset + 8 > end) return false;
        cursor.offset += 8;
        return true;
      case 2:
        final length = _readVarint(data, cursor, end);
        if (length == null || length < 0 || cursor.offset + length > end) {
          return false;
        }
        cursor.offset += length;
        return true;
      case 5:
        if (cursor.offset + 4 > end) return false;
        cursor.offset += 4;
        return true;
      default:
        return false;
    }
  }

  void _onFootprintPb(gpb.PolygonStamped poly) {
    final pts = <vm.Vector2>[];
    for (final p in poly.polygon.points) {
      pts.add(vm.Vector2(p.x, p.y));
    }
    robotFootprint.value = pts;
  }

  void _onDiagnosticPb(dipb.DiagnosticArray arr) {
    final list = <dstatus.DiagnosticStatus>[];
    for (final s in arr.status) {
      final vals = <KeyValue>[];
      for (final kv in s.values) {
        vals.add(KeyValue(key: kv.key, value: kv.value));
      }
      list.add(
        dstatus.DiagnosticStatus(
          level: s.level,
          name: s.name,
          message: s.message,
          hardwareId: s.hardwareId,
          values: vals,
        ),
      );
    }
    final header =
        arr.hasHeader() ? darr.Header(frameId: arr.header.frameId) : null;
    diagnosticData.value = darr.DiagnosticArray(header: header, status: list);
    diagnosticManager.updateDiagnosticStates(diagnosticData.value);
  }

  void _onNavStatusPb(apb.GoalStatusArray arr) {
    if (arr.statusList.isEmpty) return;
    final last = arr.statusList.last;
    navStatus_.value = ActionStatus.fromValue(last.status);
  }

  Future<void> beginImageStream(String topic) async {
    imageStreamStarting_ = true;
    _streamError = null;
    _lastImagePushMs = null;
    imageFrame.value = null;
    final prev = _activeImageTopicRaw;
    if (prev != null && prev.isNotEmpty && prev != topic) {
      try {
        await _http.postSubImage(prev, false);
      } catch (_) {}
    }
    _activeImageTopicRaw = null;
    _activeImageTopicNormalized = null;
    try {
      await _http.postSubImage(topic, true);
      _activeImageTopicRaw = topic;
      _activeImageTopicNormalized = normalizeTopic(topic);
    } catch (e) {
      _streamError = '$e';
    }
    imageStreamStarting_ = false;
  }

  Future<void> endImageStream() async {
    _lastImagePushMs = null;
    imageFrame.value = null;
    imageStreamStarting_ = false;
    final raw = _activeImageTopicRaw;
    _activeImageTopicRaw = null;
    _activeImageTopicNormalized = null;
    if (raw != null && raw.isNotEmpty) {
      try {
        await _http.postSubImage(raw, false);
      } catch (_) {}
    }
  }

  Future<String> connect(String url) async {
    final u = Uri.parse(url);
    final host = u.host.isNotEmpty ? u.host : backendHost_;
    final port = u.port > 0 ? u.port : backendHttpPort_;
    return connectBackend(host, port);
  }

  void closeConnection() {
    _connectionGeneration++;
    _lastWsMessageAt = null;
    robotFootprint.value = [];
    laserBasePoint_.value = [];
    localPath.value = [];
    globalPath.value = [];
    tracePath.value = [];
    laserPointData.value.laserPoseBaseLink.clear();
    laserPointData.value.robotPose = RobotPose.zero();
    robotSpeed_.value = RobotSpeed(vx: 0, vy: 0, vw: 0);
    _setControlSpeed(0, 0, 0);
    robotPoseMap.value = RobotPose.zero();
    navStatus_.value = ActionStatus.unknown;
    battery_.value = 0;
    gpsFix_.value = null;
    imageFrame.value = null;
    pointCloud2Data.value = [];
    localCostmap.value = OccupancyMap();
    globalCostmap.value = OccupancyMap();
    diagnosticData.value = darr.DiagnosticArray();
    _resetManualCommandSnapshot();
    unawaited(endImageStream());
    unawaited(_teardownWs());
    rosConnectState_ = Status.none;
  }

  ValueNotifier<OccupancyMap> get map => map_;

  List<TopicWithSchemaName> get topics => [];
  Map<String, dynamic> get datatypes => {};
  int get currentRosVersion => 2;

  void refreshTopics() {}

  Future<Map<String, dynamic>> sendTopologyGoal(String name) async {
    debugPrint('sendTopologyGoal not supported on backend: $name');
    return {'is_success': false, 'message': 'not_supported'};
  }

  Future<void> sendNavigationGoal(RobotPose pose) async {
    await _http.postRobotNavGoal(pose.x, pose.y, pose.theta);
  }

  void sendEmergencyStop() {
    _emergencyStopLatched = true;
    emergencyStopLatched.value = true;
    cmdVel_
      ..vx = 0
      ..vy = 0
      ..vw = 0;
    _manualCommandFresh = true;
    startMunalCtrl();
    sendSpeed(0, 0, 0);
  }

  void clearEmergencyStop() {
    _emergencyStopLatched = false;
    emergencyStopLatched.value = false;
    _resetManualCommandSnapshot();
    sendSpeed(0, 0, 0);
  }

  Future<void> sendCancelNav() async {
    await _http.postRobotCancelNav();
  }

  void destroyConnection() {
    closeConnection();
  }

  void setVx(double vx) =>
      cmdVel_.vx = _emergencyStopLatched ? 0 : _finiteOrZero(vx);
  void setVy(double vy) =>
      cmdVel_.vy = _emergencyStopLatched ? 0 : _finiteOrZero(vy);
  void setVw(double vw) =>
      cmdVel_.vw = _emergencyStopLatched ? 0 : _finiteOrZero(vw);

  void updateManualCommand(double vx, double vy, double vw) {
    final blockMotion = _emergencyStopLatched;
    final safeVx = blockMotion ? 0.0 : _finiteOrZero(vx);
    final safeVy = blockMotion ? 0.0 : _finiteOrZero(vy);
    final safeVw = blockMotion ? 0.0 : _finiteOrZero(vw);
    cmdVel_
      ..vx = safeVx
      ..vy = safeVy
      ..vw = safeVw;
    _setControlSpeed(safeVx, safeVy, safeVw);
    _manualCommandFresh = true;
    startMunalCtrl();
  }

  void startMunalCtrl() {
    if (cmdVelTimer?.isActive ?? false) return;
    cmdVelTimer?.cancel();
    cmdVelTimer = Timer.periodic(
      const Duration(milliseconds: _manualCommandIntervalMs),
      (_) {
        if (_manualCommandFresh && rosConnectState_ == Status.connected) {
          sendSpeed(cmdVel_.vx, cmdVel_.vy, cmdVel_.vw);
        }
      },
    );
  }

  void stopMunalCtrl() {
    cmdVelTimer?.cancel();
    cmdVelTimer = null;
    _resetManualCommandSnapshot();
    sendSpeed(0, 0, 0);
  }

  void sendSpeed(double vx, double vy, double vw) {
    final ws = _wsChannel;
    if (ws == null || rosConnectState_ != Status.connected) return;
    final blockMotion = _emergencyStopLatched;
    final safeVx = blockMotion ? 0.0 : _finiteOrZero(vx);
    final safeVy = blockMotion ? 0.0 : _finiteOrZero(vy);
    final safeVw = blockMotion ? 0.0 : _finiteOrZero(vw);
    _setControlSpeed(safeVx, safeVy, safeVw);
    final twist =
        gpb.Twist()
          ..linear =
              (gpb.Vector3()
                ..x = safeVx
                ..y = safeVy
                ..z = 0.0)
          ..angular =
              (gpb.Vector3()
                ..x = 0.0
                ..y = 0.0
                ..z = safeVw);
    final msg = ClientRobotMessage()..cmdVel = twist;
    try {
      ws.sink.add(msg.writeToBuffer());
      ControlLogStore.instance.recordSpeedPacket(safeVx, safeVy, safeVw);
    } catch (error) {
      ControlLogStore.instance.error('TX', 'cmd_vel send failed: $error');
      if (identical(ws, _wsChannel)) {
        _resetManualCommandSnapshot();
        rosConnectState_ = Status.errored;
        unawaited(_teardownWs(expectedChannel: ws));
      }
    }
  }

  double _finiteOrZero(double value) => value.isFinite ? value : 0.0;

  void _setControlSpeed(double vx, double vy, double vw) {
    final current = controlSpeed_.value;
    if (current.vx == vx && current.vy == vy && current.vw == vw) return;
    controlSpeed_.value = RobotSpeed(vx: vx, vy: vy, vw: vw);
  }

  void _resetManualCommandSnapshot() {
    cmdVel_
      ..vx = 0
      ..vy = 0
      ..vw = 0;
    _setControlSpeed(0, 0, 0);
    _manualCommandFresh = false;
  }

  Future<D1ModeAck> sendD1Mode(
    D1Mode mode, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final ws = _wsChannel;
    if (ws == null || rosConnectState_ != Status.connected) {
      throw StateError('robot websocket is not connected');
    }
    final seq = _allocateD1ModeSeq();
    final completer = Completer<D1ModeAck>();
    _pendingD1ModeAcks[seq] = completer;
    ws.sink.add(
      D1ModeProtocol.encodeCommand(
        seq: seq,
        mode: mode,
        clientTimeMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pendingD1ModeAcks.remove(seq);
    }
  }

  int _allocateD1ModeSeq() {
    final seq = _nextD1ModeSeq;
    _nextD1ModeSeq = (_nextD1ModeSeq + 1) & 0xffffffff;
    if (_nextD1ModeSeq == 0) _nextD1ModeSeq = 1;
    return seq;
  }

  void _failPendingD1ModeAcks(Object error) {
    final pending = _pendingD1ModeAcks.values.toList(growable: false);
    _pendingD1ModeAcks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  Future<void> sendRelocPose(RobotPose pose) async {
    await _http.postRobotInitialPose(pose.x, pose.y, pose.theta);
  }

  Future<void> updateTopologyMap(TopologyMap updatedMap) async {
    mapManager.updateTopologyMap(updatedMap);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionGeneration++;
    _lastWsMessageAt = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    cmdVelTimer?.cancel();
    cmdVelTimer = null;
    _resetManualCommandSnapshot();
    _pendingHeavyMessages.clear();
    for (final completer in _heavyWorkerRequests.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _heavyWorkerRequests.clear();
    _heavyWorkerSendPort?.send(null);
    _heavyWorkerIsolate?.kill(priority: Isolate.immediate);
    _heavyWorkerIsolate = null;
    _heavyWorkerReceivePort?.close();
    _heavyWorkerReceivePort = null;
    _heavyWorkerSendPort = null;
    unawaited(_teardownWs());
    diagnosticManager.dispose();
    connectionReadySignal.dispose();
    emergencyStopLatched.dispose();
  }
}

enum Status { none, connecting, connected, errored }
