import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';

typedef WorldToLatLngFn = LatLng Function(double worldX, double worldY);

Widget buildPointCloudLayer(
  WsChannel wsChannel,
  WorldToLatLngFn worldToLatLng,
) {
  final points = wsChannel.pointCloud2Data.value;
  if (points.isEmpty) return const SizedBox.shrink();
  const maxVisiblePoints = 5000;
  final step =
      points.length > maxVisiblePoints
          ? (points.length / maxVisiblePoints).ceil()
          : 1;
  final circles = <CircleMarker>[];
  for (var index = 0; index < points.length; index += step) {
    final point = points[index];
    if (!point.x.isFinite || !point.y.isFinite) continue;
    circles.add(
      CircleMarker(
        point: worldToLatLng(point.x, point.y),
        radius: 1,
        color: Colors.orange,
      ),
    );
  }
  if (circles.isEmpty) return const SizedBox.shrink();
  return RepaintBoundary(child: CircleLayer(circles: circles));
}
