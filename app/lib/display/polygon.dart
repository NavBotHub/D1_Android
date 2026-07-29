import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';

typedef WorldToLatLngFn = LatLng Function(double worldX, double worldY);

Widget buildRobotFootprintLayer(WsChannel wsChannel, WorldToLatLngFn worldToLatLng) {
  final footprint = wsChannel.robotFootprint.value;
  if (footprint.isEmpty) return const SizedBox.shrink();
  final pts = footprint.map((p) => worldToLatLng(p.x, p.y)).toList();
  return PolygonLayer(
    polygons: [
      Polygon(
        points: pts,
        color: Colors.green.withValues(alpha: 0.2),
        borderColor: Colors.green,
        borderStrokeWidth: 1,
      ),
    ],
  );
}
