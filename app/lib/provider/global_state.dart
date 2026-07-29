import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navbot_d1_flutter/basic/layer_config.dart';
import 'dart:convert';

enum Mode {
  normal,
  reloc,
  addNavPoint,
  robotFixedCenter,
  mapEdit,
}

class GlobalState extends ChangeNotifier {
  ValueNotifier<bool> isManualCtrl = ValueNotifier(false);
  ValueNotifier<Mode> mode = ValueNotifier(Mode.normal);

  static final List<String> _layerIds =
      LayerType.values.map((e) => e.name).toList();

  final Map<String, LayerConfig> _layerConfig = {};

  GlobalState() {
    for (final t in LayerType.values) {
      _layerConfig[t.name] = LayerConfig.defaultFor(t);
    }
  }

  static const String _layerSettingsKey = 'layer_settings';

  Map<String, LayerConfig> get layerConfig =>
      UnmodifiableMapView(_layerConfig);

  Color layerColorFor(String layerId, Color fallback) {
    final cfg = _layerConfig[layerId];
    if (cfg == null) return fallback;
    return layerConfigColorArgb(cfg, fallback);
  }

  double layerLaserDotRadius() {
    final cfg = _layerConfig['laser'];
    if (cfg == null) return 2.0;
    return layerConfigLaserDotRadius(cfg);
  }

  void patchLayer(
    String layerId, {
    bool? enable,
    String? colorArgb,
    String? dotRadius,
    LocalCostmapMapStyle? mapStyle,
  }) {
    final cur = _layerConfig[layerId];
    if (cur == null) return;
    _layerConfig[layerId] = patchLayerConfig(
      cur,
      enable: enable,
      colorArgb: colorArgb,
      dotRadius: dotRadius,
      mapStyle: mapStyle,
    );
    notifyListeners();
  }

  LocalCostmapMapStyle localCostmapMapStyle() {
    final cfg = _layerConfig['localCostmap'];
    if (cfg is LayerLocalCostmapConfig) return cfg.mapStyle;
    return LocalCostmapMapStyle.costmap;
  }

  void setLayerState(String layerName, bool value) {
    if (!_layerConfig.containsKey(layerName)) return;
    patchLayer(layerName, enable: value);
    saveLayerSettings();
  }

  void toggleLayer(String layerName) {
    final cur = _layerConfig[layerName];
    if (cur == null) return;
    patchLayer(layerName, enable: !cur.enable);
    saveLayerSettings();
  }

  Map<String, dynamic> configToJson() {
    final out = <String, dynamic>{};
    _layerConfig.forEach((k, v) => out[k] = v.toJson());
    return out;
  }

  void _applyLayerSettingsFromJson(Map<String, dynamic> raw) {
    raw.forEach((k, v) {
      if (k.startsWith('_')) return;
      if (!_layerConfig.containsKey(k)) return;
      if (v is! Map) return;
      final prev = _layerConfig[k]!;
      _layerConfig[k] = LayerConfig.mergeDecoded(
        k,
        prev,
        Map<String, dynamic>.from(v),
      );
    });
  }

  Future<void> saveLayerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_layerSettingsKey, jsonEncode(configToJson()));
  }

  Future<void> loadLayerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final layerSettingsStr = prefs.getString(_layerSettingsKey);
    Map<String, dynamic>? layerSettings;

    if (layerSettingsStr != null) {
      try {
        layerSettings =
            Map<String, dynamic>.from(jsonDecode(layerSettingsStr));
        _applyLayerSettingsFromJson(layerSettings);
        for (final id in _layerIds) {
          _layerConfig.putIfAbsent(
            id,
            () => LayerConfig.defaultFor(layerTypeFromStorageId(id)!),
          );
        }
        notifyListeners();
      } catch (e) {
        print('加载图层设置失败: $e');
      }
    }
    final legacyStyle = prefs.getString('localCostmapDisplayStyle');
    final migrated = LocalCostmapMapStyle.tryParse(legacyStyle);
    final localEntry = layerSettings?['localCostmap'];
    final hadStoredMapStyle =
        localEntry is Map && localEntry.containsKey('mapStyle');
    if (migrated != null && !hadStoredMapStyle) {
      patchLayer('localCostmap', mapStyle: migrated);
      await prefs.remove('localCostmapDisplayStyle');
      await saveLayerSettings();
    }
  }

  List<String> get layerNames => List.unmodifiable(_layerIds);

  bool isLayerVisible(String layerName) {
    return _layerConfig[layerName]?.enable ?? false;
  }
}
