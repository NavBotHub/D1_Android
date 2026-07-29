import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:navbot_d1_flutter/basic/layer_config.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/language/l10n/gen/app_localizations.dart';
import 'package:navbot_d1_flutter/provider/global_state.dart';
import 'package:navbot_d1_flutter/provider/http_channel.dart';

Future<Color?> pickColor(
  BuildContext context,
  Color current, {
  String? title,
}) async {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(
      initialColor: current,
      title: title ?? AppLocalizations.of(ctx)!.layer_color,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initialColor,
    required this.title,
  });

  final Color initialColor;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const double _svHeight = 120;
  static const double _hueBarHeight = 22;

  late HSVColor _hsv;

  double _panelWidth(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return (screenW * 0.82).clamp(220.0, 280.0);
  }

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _updateSv(Offset local, double width, double height) {
    if (width <= 0 || height <= 0) return;
    final s = (local.dx / width).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / height).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withSaturation(s).withValue(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final picked = _hsv.toColor();
    final hex = Setting.normalizeArgb(picked.toARGB32())
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2);

    final panelWidth = _panelWidth(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      content: SizedBox(
        width: panelWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: panelWidth,
                  height: _svHeight,
                  child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _updateSv(e.localPosition, w, h),
                      onPointerMove: (e) => _updateSv(e.localPosition, w, h),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1)
                                  .toColor(),
                            ),
                          ),
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.white, Color(0x00FFFFFF)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            ),
                          ),
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0x00000000), Colors.black],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (_hsv.saturation * w - 8)
                                .clamp(0.0, w - 16),
                            top: ((1 - _hsv.value) * h - 8)
                                .clamp(0.0, h - 16),
                            child: IgnorePointer(
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black38, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: _hueBarHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: List<Color>.generate(
                              7,
                              (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1)
                                  .toColor(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: _hueBarHeight,
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: _hsv.hue.clamp(0.0, 360.0),
                        min: 0,
                        max: 360,
                        onChanged: (h) =>
                            setState(() => _hsv = _hsv.withHue(h)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 24,
                    decoration: BoxDecoration(
                      color: picked,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '#${hex.toUpperCase()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, picked),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}

class LayerSettingsPanel extends StatefulWidget {
  const LayerSettingsPanel({super.key});

  @override
  State<LayerSettingsPanel> createState() => _LayerSettingsPanelState();
}

class _LayerSettingsPanelState extends State<LayerSettingsPanel> {
  late double _laserDotDraft;
  late int _mapTileFreeColorDraft;
  late int _mapTileOccColorDraft;
  late int _mapTileUnknownColorDraft;
  late int _mapTileFreeThreshDraft;
  late int _mapTileOccThreshDraft;

  final Set<String> _openLayerIds = <String>{'mapColors'};

  static const _dividerColor = Color(0x33000000);

  @override
  void initState() {
    super.initState();
    _laserDotDraft = Provider.of<GlobalState>(context, listen: false)
        .layerLaserDotRadius();
    _mapTileFreeColorDraft = globalSetting.MapTileFreeColor;
    _mapTileOccColorDraft = globalSetting.MapTileOccColor;
    _mapTileUnknownColorDraft = globalSetting.MapTileUnknownColor;
    _mapTileFreeThreshDraft = globalSetting.MapTileFreeThresh;
    _mapTileOccThreshDraft = globalSetting.MapTileOccThresh;
  }

  Future<void> _saveMapTileSetting(BuildContext context, String key, dynamic value) async {
    try {
      final out = await HttpChannel().saveGuiSettings({key: value});
      globalSetting.applyBackendGuiSettings(out);
      globalSetting.notifyMapTileStyleChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 3)),
        );
      }
      rethrow;
    }
  }

  void _toggleOpen(String id) {
    setState(() {
      if (_openLayerIds.contains(id)) {
        _openLayerIds.remove(id);
      } else {
        _openLayerIds.add(id);
      }
    });
  }

  Widget _groupRowBorder({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _dividerColor, width: 0.5),
        ),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required String id,
    required String title,
  }) {
    final open = _openLayerIds.contains(id);
    return _groupRowBorder(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleOpen(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_less : Icons.chevron_right,
                  size: 20,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerHeader(
    BuildContext context, {
    required String id,
    required String title,
    required String layerKey,
  }) {
    return Consumer<GlobalState>(
      builder: (ctx, gs, __) {
        final open = _openLayerIds.contains(id);
        final scheme = Theme.of(ctx).colorScheme;
        return _groupRowBorder(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleOpen(id),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_less : Icons.chevron_right,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Theme(
                      data: Theme.of(ctx).copyWith(
                        switchTheme: SwitchThemeData(
                          thumbColor:
                              WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return scheme.onPrimary;
                            }
                            return const Color(0xFF616161);
                          }),
                          trackColor:
                              WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return scheme.primary;
                            }
                            return const Color(0xFFE0E0E0);
                          }),
                        ),
                      ),
                      child: Switch.adaptive(
                        value: gs.isLayerVisible(layerKey),
                        onChanged: (v) => gs.setLayerState(layerKey, v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapTileColorRow(
    BuildContext context, {
    required String label,
    required int argb,
    required String configKey,
    required ValueChanged<int> onDraftChanged,
  }) {
    final color = Color(Setting.normalizeArgb(argb));
    return _groupRowBorder(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final picked = await pickColor(context, color,
                title: AppLocalizations.of(context)!.map_tile_colors);
            if (picked == null || !context.mounted) return;
            final next = Setting.normalizeArgb(picked.toARGB32());
            try {
              await _saveMapTileSetting(context, configKey, next);
            } catch (_) {
              return;
            }
            if (!context.mounted) return;
            onDraftChanged(next);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                ),
                Container(
                  width: 44,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapTileThreshRow(
    BuildContext context, {
    required String label,
    required int value,
    required String configKey,
    required ValueChanged<int> onDraftChanged,
  }) {
    return _groupRowBorder(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Slider.adaptive(
                value: value.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '$value',
                onChanged: (v) => onDraftChanged(v.round()),
                onChangeEnd: (v) =>
                    _saveMapTileSetting(context, configKey, v.round()),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$value',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorRow(
    BuildContext context,
    GlobalState gs,
    String label,
    String layerId,
    Color fallback,
  ) {
    final c = gs.layerColorFor(layerId, fallback);
    return _groupRowBorder(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final p = await pickColor(context, c);
            if (p != null) {
              gs.patchLayer(layerId, colorArgb: p.toARGB32().toString());
              await gs.saveLayerSettings();
              setState(() {});
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                ),
                Container(
                  width: 44,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gs = Provider.of<GlobalState>(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
            id: 'mapColors', title: l10n.map_tile_colors),
        if (_openLayerIds.contains('mapColors')) ...[
          _buildMapTileColorRow(
            context,
            label: l10n.legend_free,
            argb: _mapTileFreeColorDraft,
            configKey: 'MapTileFreeColor',
            onDraftChanged: (v) => setState(() => _mapTileFreeColorDraft = v),
          ),
          _buildMapTileColorRow(
            context,
            label: l10n.legend_occupied,
            argb: _mapTileOccColorDraft,
            configKey: 'MapTileOccColor',
            onDraftChanged: (v) => setState(() => _mapTileOccColorDraft = v),
          ),
          _buildMapTileColorRow(
            context,
            label: l10n.legend_unknown,
            argb: _mapTileUnknownColorDraft,
            configKey: 'MapTileUnknownColor',
            onDraftChanged: (v) => setState(() => _mapTileUnknownColorDraft = v),
          ),
          _buildMapTileThreshRow(
            context,
            label: l10n.map_tile_free_thresh,
            value: _mapTileFreeThreshDraft,
            configKey: 'MapTileFreeThresh',
            onDraftChanged: (v) => setState(() => _mapTileFreeThreshDraft = v),
          ),
          _buildMapTileThreshRow(
            context,
            label: l10n.map_tile_occ_thresh,
            value: _mapTileOccThreshDraft,
            configKey: 'MapTileOccThresh',
            onDraftChanged: (v) => setState(() => _mapTileOccThreshDraft = v),
          ),
        ],
        _buildLayerHeader(context,
            id: 'grid', title: l10n.layer_grid, layerKey: 'grid'),
        _buildLayerHeader(context,
            id: 'lcost',
            title: l10n.layer_local_costmap,
            layerKey: 'localCostmap'),
        if (_openLayerIds.contains('lcost')) ...[
          Consumer<GlobalState>(
            builder: (ctx, gs, __) {
              final cfg = gs.layerConfig['localCostmap'];
              final style = cfg is LayerLocalCostmapConfig
                  ? cfg.mapStyle
                  : LocalCostmapMapStyle.costmap;
              return _groupRowBorder(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.local_costmap_map_style,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<LocalCostmapMapStyle>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: LocalCostmapMapStyle.raw,
                            label: Text(l10n.local_costmap_style_raw),
                          ),
                          ButtonSegment(
                            value: LocalCostmapMapStyle.costmap,
                            label: Text(l10n.local_costmap_style_costmap),
                          ),
                          ButtonSegment(
                            value: LocalCostmapMapStyle.obs,
                            label: Text(l10n.local_costmap_style_obs),
                          ),
                        ],
                        selected: {style},
                        onSelectionChanged: (next) {
                          if (next.isEmpty) return;
                          gs.patchLayer(
                            'localCostmap',
                            mapStyle: next.first,
                          );
                          gs.saveLayerSettings();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        _buildLayerHeader(context,
            id: 'laser', title: l10n.layer_laser, layerKey: 'laser'),
        if (_openLayerIds.contains('laser')) ...[
          _buildColorRow(context, gs, l10n.layer_color, 'laser', Colors.red),
          _groupRowBorder(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      l10n.layer_dot_size,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Slider.adaptive(
                      value: _laserDotDraft,
                      min: 0.5,
                      max: 8,
                      divisions: 15,
                      label: _laserDotDraft.toStringAsFixed(1),
                      onChanged: (v) {
                        setState(() => _laserDotDraft = v);
                      },
                      onChangeEnd: (_) {
                        gs.patchLayer(
                            'laser', dotRadius: _laserDotDraft.toString());
                        gs.saveLayerSettings();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        _buildLayerHeader(context,
            id: 'pc',
            title: l10n.layer_pointcloud,
            layerKey: 'pointCloud'),
        if (_openLayerIds.contains('pc')) ...[],
        _buildLayerHeader(context,
            id: 'gpath',
            title: l10n.layer_global_path,
            layerKey: 'globalPath'),
        if (_openLayerIds.contains('gpath')) ...[
          _buildColorRow(context, gs, l10n.layer_color, 'globalPath',
              const Color(0xFF2196F3)),
        ],
        _buildLayerHeader(context,
            id: 'lpath',
            title: l10n.layer_local_path,
            layerKey: 'localPath'),
        if (_openLayerIds.contains('lpath')) ...[
          _buildColorRow(
              context, gs, l10n.layer_color, 'localPath', Colors.green),
        ],
        _buildLayerHeader(context,
            id: 'tpath',
            title: l10n.layer_trace,
            layerKey: 'tracePath'),
        if (_openLayerIds.contains('tpath')) ...[
          _buildColorRow(
              context, gs, l10n.layer_color, 'tracePath', Colors.yellow),
        ],
        _buildLayerHeader(context,
            id: 'topo',
            title: l10n.layer_topology,
            layerKey: 'topology'),
        _buildLayerHeader(context,
            id: 'foot',
            title: l10n.layer_robot_footprint,
            layerKey: 'robotFootprint'),
        if (_openLayerIds.contains('foot')) ...[],
      ],
    );
  }
}
