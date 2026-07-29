import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navbot_d1_flutter/basic/RobotPose.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';

typedef WorldToLatLngFn = LatLng Function(double worldX, double worldY);

Widget buildLaserLayer(
  WsChannel wsChannel,
  WorldToLatLngFn worldToLatLng, {
  RobotPose? robotPoseOverride,
  Color? color,
  double dotRadius = 2,
}) {
  final laserData = wsChannel.laserPointData.value;
  if (laserData.laserPoseBaseLink.isEmpty) return const SizedBox.shrink();
  final robotPose = robotPoseOverride ?? laserData.robotPose;
  final c = color ?? Colors.red;
  final alpha = (c.a * 0.8).clamp(0.0, 1.0);
  final fill = c.withValues(alpha: alpha);
  final points = <LatLng>[];
  const maxVisiblePoints = 4000;
  final rawPoints = laserData.laserPoseBaseLink;
  final step =
      rawPoints.length > maxVisiblePoints
          ? (rawPoints.length / maxVisiblePoints).ceil()
          : 1;
  for (var index = 0; index < rawPoints.length; index += step) {
    final lp = rawPoints[index];
    final poseMap = absoluteSum(robotPose, RobotPose(lp.x, lp.y, 0));
    points.add(worldToLatLng(poseMap.x, poseMap.y));
  }
  if (points.isEmpty) return const SizedBox.shrink();
  final r = dotRadius.clamp(0.5, 24.0);
  final circles =
      points
          .map((p) => CircleMarker(point: p, radius: r, color: fill))
          .toList();
  return RepaintBoundary(child: CircleLayer(circles: circles));
}
