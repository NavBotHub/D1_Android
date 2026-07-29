import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navbot_d1_flutter/basic/RobotPose.dart';
import 'package:navbot_d1_flutter/display/pose_marker.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';

typedef WorldToLatLngFn = LatLng Function(double worldX, double worldY);

Widget buildRobotMarkerLayer(
  WsChannel wsChannel,
  WorldToLatLngFn worldToLatLng, {
  RobotPose? poseOverride,
  bool isEditMode = false,
  ValueChanged<double>? onThetaChanged,
  ValueChanged<Offset>? onMoveDelta,
  double sizeScale = 1.0,
}) {
  final robotPose = poseOverride ?? wsChannel.robotPoseMap.value;
  final robotSize =
      globalSetting.robotSize.toDouble() * sizeScale.clamp(0.25, 4.0);
  return MarkerLayer(
    markers: [
      Marker(
        point: worldToLatLng(robotPose.x, robotPose.y),
        width: robotSize,
        height: robotSize,
        alignment: Alignment.center,
        child: PoseMarkerWidget(
          size: robotSize,
          theta: -robotPose.theta,
          type: PoseMarkerType.Robot,
          isEditMode: isEditMode,
          onThetaChanged: onThetaChanged,
          onMoveDelta: onMoveDelta,
          color: const Color(0xFF0080ff),
        ),
      ),
    ],
  );
}
