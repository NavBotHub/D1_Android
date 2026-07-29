import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/provider/http_channel.dart';
import 'package:navbot_d1_flutter/provider/control_log_store.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/services.dart';
import 'package:navbot_d1_flutter/language/l10n/gen/app_localizations.dart';
import 'package:navbot_d1_flutter/page/layer_settings_panel.dart';
import 'package:navbot_d1_flutter/page/ssh_widgets.dart';

const String kSettingsRouteArgLayers = 'layers';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.scrollToLayerSection = false});

  final bool scrollToLayerSection;

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Map<String, String> _settings = {};
  final GlobalKey _layersSectionKey = GlobalKey();
  String _version = '';
  Orientation _selectedOrientation = Orientation.landscape;

  String _text(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
    _loadOrientation();
    if (widget.scrollToLayerSection) {
      _scheduleScrollToLayersSection();
    }
  }

  void _scheduleScrollToLayersSection() {
    void run() {
      if (!mounted) return;
      _scrollToLayersSection();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      run();
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    });
  }

  void _scrollToLayersSection() {
    if (!mounted) return;
    final ctx = _layersSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = packageInfo.version;
    });
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final Map<String, String> newSettings = {};

    for (String key in keys) {
      final value = prefs.get(key);
      newSettings[key] = value?.toString() ?? '';
    }

    setState(() {
      _settings.addAll(newSettings);
    });
  }

  Future<void> _showEditDialog(String key, String currentValue) async {
    final controller = TextEditingController(text: currentValue);
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (context) => Theme(
            data: Theme.of(context).copyWith(
              dialogBackgroundColor: Theme.of(
                context,
              ).dialogBackgroundColor.withOpacity(1.0),
            ),
            child: AlertDialog(
              title: Text('Edit ${_getDisplayName(key)}'),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Please input ${_getDisplayName(key)}',
                  border: const OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                TextButton(
                  onPressed: () async {
                    await _saveSettings(key, controller.text);
                    Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.config_saved,
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.ok),
                ),
              ],
            ),
          ),
    );
  }

  String _getDisplayName(String key) {
    final Map<String, String> displayNames = {
      'robotIp': AppLocalizations.of(context)!.ip_address,
      'robotPort': AppLocalizations.of(context)!.port,
      'httpServerPort': AppLocalizations.of(context)!.http_server_port,
      'mapTopic': AppLocalizations.of(context)!.map_topic,
      'LaserTopic': AppLocalizations.of(context)!.laser_topic,
      'GlobalPathTopic': AppLocalizations.of(context)!.global_path_topic,
      'LocalPathTopic': AppLocalizations.of(context)!.local_path_topic,
      'TracePathTopic': AppLocalizations.of(context)!.trace_path_topic,
      'RelocTopic': AppLocalizations.of(context)!.reloc_topic,
      'NavGoalTopic': AppLocalizations.of(context)!.nav_goal_topic,
      'OdomTopic': AppLocalizations.of(context)!.odometry_topic,
      'SpeedCtrlTopic': AppLocalizations.of(context)!.speed_ctrl_topic,
      'BatteryTopic': AppLocalizations.of(context)!.battery_topic,
      'GpsTopic':
          Localizations.localeOf(context).languageCode == 'zh'
              ? 'GPS话题'
              : 'GPS Topic',
      'MaxVx': AppLocalizations.of(context)!.max_speed,
      'MaxVy': AppLocalizations.of(context)!.max_y_speed,
      'MaxVw': AppLocalizations.of(context)!.max_angular_speed,
      'MapFrameName': AppLocalizations.of(context)!.map_frame,
      'BaseLinkFrameName': AppLocalizations.of(context)!.base_frame,
      'imagePort': AppLocalizations.of(context)!.image_port,
      'imageTopic': AppLocalizations.of(context)!.image_topic,
      'imageWidth': AppLocalizations.of(context)!.image_width,
      'imageHeight': AppLocalizations.of(context)!.image_height,
      'RobotActionTopic': '动作控制话题',
      'RobotFootprintTopic':
          AppLocalizations.of(context)!.robot_footprint_topic,
      'LocalCostmapTopic': AppLocalizations.of(context)!.local_cost_map_topic,
      'PointCloud2Topic': AppLocalizations.of(context)!.pointcloud2_topic,
      'robotSize': AppLocalizations.of(context)!.robot_size,
      'MapPubTopic': AppLocalizations.of(context)!.map_publish_topic,
      'MapSubTopic': AppLocalizations.of(context)!.map_subscribe_topic,
      'MapManagerFrameId': AppLocalizations.of(context)!.map_manager_frame,
      'GlobalCostmapTopic': AppLocalizations.of(context)!.global_costmap_topic,
      'NavToPoseStatusTopic':
          AppLocalizations.of(context)!.nav_to_pose_status_topic,
      'NavThroughPosesStatusTopic':
          AppLocalizations.of(context)!.nav_through_poses_status_topic,
      'TopologyLiveTopic': AppLocalizations.of(context)!.topology_live_topic,
      'TopologyJsonTopic': AppLocalizations.of(context)!.topology_json_topic,
      'TopologyPublishTopic':
          AppLocalizations.of(context)!.topology_publish_topic,
      'DiagnosticTopic': AppLocalizations.of(context)!.diagnostic_topic_label,
    };
    return displayNames[key] ?? key;
  }

  Future<void> _saveSettings(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();

    if (key == 'httpServerPort') {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed == '8081') {
        globalSetting.setHttpServerPort('');
      } else {
        final n = int.tryParse(trimmed);
        if (n != null && n >= 1 && n <= 65535) {
          globalSetting.setHttpServerPort(trimmed);
        }
      }
      _loadSettings();
      return;
    }

    if (Setting.backendGuiStorageKeys.contains(key)) {
      try {
        await HttpChannel().saveGuiSettings({key: value});
        globalSetting.patchBackendGuiSetting(key, value);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), duration: const Duration(seconds: 3)),
          );
        }
        return;
      }
      _loadSettings();
      return;
    }

    await prefs.setString(key, value);
    switch (key) {
      case 'robotIp':
        globalSetting.setRobotIp(value);
        break;
      case 'robotPort':
        globalSetting.setRobotPort(value);
        break;
      case 'mapTopic':
        globalSetting.setMapTopic(value);
        break;
      case 'MaxVx':
        globalSetting.setMaxVx(value);
        break;
      case 'MaxVy':
        globalSetting.setMaxVy(value);
        break;
      case 'MaxVw':
        globalSetting.setMaxVw(value);
        break;
      case 'imagePort':
        globalSetting.setImagePort(value);
        break;
      case 'imageTopic':
        globalSetting.setImageTopic(value);
        break;
      case 'imageWidth':
        globalSetting.setImageWidth(double.parse(value));
        break;
      case 'imageHeight':
        globalSetting.setImageHeight(double.parse(value));
        break;
      case 'robotSize':
        globalSetting.setRobotSize(double.parse(value));
        break;
    }

    _loadSettings();
  }

  List<Widget> _buildSettingGroups() {
    return [
      _buildLanguageSection(),
      _buildBasicSection(),
      _buildBackendSettingsSection(),
      _buildLayersSection(),
      _buildOrientationSection(),
      // ... 其他设置组
    ];
  }

  Widget _buildLanguageSection() {
    return _buildSection(AppLocalizations.of(context)!.language, [
      ListTile(
        title: Text(AppLocalizations.of(context)!.language),
        trailing: DropdownButton<String>(
          value:
              _settings['language'] == 'zh'
                  ? AppLocalizations.of(context)!.zh
                  : AppLocalizations.of(context)!.en,
          dropdownColor: Colors.white,
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                if (newValue == AppLocalizations.of(context)!.en) {
                  _settings['language'] = 'en';
                  _saveLanguage('en');
                  globalSetting.setLanguage(Locale('en'));
                } else if (newValue == AppLocalizations.of(context)!.zh) {
                  _settings['language'] = 'zh';
                  _saveLanguage('zh');
                  globalSetting.setLanguage(Locale('zh'));
                }
              });
            }
          },
          items:
              [
                AppLocalizations.of(context)!.en,
                AppLocalizations.of(context)!.zh,
              ].map<DropdownMenuItem<String>>((String language) {
                return DropdownMenuItem<String>(
                  value: language,
                  child: Text(language),
                );
              }).toList(),
        ),
      ),
    ]);
  }

  Future<void> _saveLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingItem(String key, String value) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEditDialog(key, value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.withOpacity(0.2),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _getDisplayName(key),
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicSection() {
    return _buildSection(AppLocalizations.of(context)!.basic_setting, [
      _buildSettingItem('robotIp', _settings['robotIp'] ?? '127.0.0.1'),
      _buildSettingItem('robotPort', _settings['robotPort'] ?? '8080'),
      _buildSettingItem(
        'httpServerPort',
        _settings['httpServerPort'] ?? '8081',
      ),
      _buildSettingItem('MaxVx', _settings['MaxVx'] ?? '0.9'),
      _buildSettingItem('MaxVy', _settings['MaxVy'] ?? '0.5'),
      _buildSettingItem('MaxVw', _settings['MaxVw'] ?? '0.4'),
      _buildSettingItem(
        'robotSize',
        _settings['robotSize']?.toString() ?? '3.0',
      ),
      _buildSettingItem('imagePort', _settings['imagePort'] ?? '8080'),
      _buildSettingItem('imageTopic', _settings['imageTopic'] ?? '/image_raw'),
      _buildSettingItem(
        'imageWidth',
        _settings['imageWidth']?.toString() ?? '640',
      ),
      _buildSettingItem(
        'imageHeight',
        _settings['imageHeight']?.toString() ?? '480',
      ),
    ]);
  }

  Widget _buildBackendSettingsSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildSection(l10n.backend_setting, [
      ListTile(
        title: Text(l10n.ssh_config_list_tile_title),
        subtitle: Text(
          globalSetting.sshCredentialsConfigured
              ? l10n.ssh_user_at_host_port(
                globalSetting.SSHUsername.trim(),
                globalSetting.robotIp.trim(),
                globalSetting.SSHPort,
              )
              : l10n.ssh_not_configured_hint,
        ),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: () => ShowSshConfigSheet(context),
      ),
      _buildSettingItem('MapFrameName', globalSetting.mapFrameName),
      _buildSettingItem('BaseLinkFrameName', globalSetting.baseLinkFrameName),
      _buildSettingItem('MapPubTopic', globalSetting.mapPubTopic),
      _buildSettingItem('MapSubTopic', globalSetting.mapSubTopic),
      _buildSettingItem('MapManagerFrameId', globalSetting.mapManagerFrameId),
      _buildSettingItem('RelocTopic', globalSetting.relocTopic),
      _buildSettingItem('NavGoalTopic', globalSetting.navGoalTopic),
      _buildSettingItem('OdomTopic', globalSetting.odomTopic),
      _buildSettingItem('SpeedCtrlTopic', globalSetting.speedCtrlTopic),
      _buildSettingItem('RobotActionTopic', globalSetting.robotActionTopic),
      _buildSettingItem('BatteryTopic', globalSetting.batteryTopic),
      _buildSettingItem('GpsTopic', globalSetting.gpsTopic),
      _buildSettingItem('GlobalCostmapTopic', globalSetting.globalCostmapTopic),
      _buildSettingItem(
        'RobotFootprintTopic',
        globalSetting.robotFootprintTopic,
      ),
      _buildSettingItem('LocalCostmapTopic', globalSetting.localCostmapTopic),
      _buildSettingItem('PointCloud2Topic', globalSetting.pointCloud2Topic),
      _buildSettingItem('DiagnosticTopic', globalSetting.diagnosticTopic),
      _buildSettingItem('GlobalPathTopic', globalSetting.globalPathTopic),
      _buildSettingItem('LocalPathTopic', globalSetting.localPathTopic),
      _buildSettingItem('TracePathTopic', globalSetting.tracePathTopic),
      _buildSettingItem('TopologyLiveTopic', globalSetting.topologyMapTopic),
      _buildSettingItem('TopologyJsonTopic', globalSetting.topologyJsonTopic),
      _buildSettingItem(
        'TopologyPublishTopic',
        globalSetting.topologyPublishTopic,
      ),
      _buildSettingItem(
        'NavToPoseStatusTopic',
        globalSetting.navToPoseStatusTopic,
      ),
      _buildSettingItem(
        'NavThroughPosesStatusTopic',
        globalSetting.navThroughPosesStatusTopic,
      ),
      _buildSettingItem('LaserTopic', globalSetting.laserTopic),
    ]);
  }

  Widget _buildLayersSection() {
    return Column(
      key: _layersSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            AppLocalizations.of(context)!.layers,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: const LayerSettingsPanel(),
        ),
      ],
    );
  }

  Widget _buildOrientationSection() {
    return _buildSection(AppLocalizations.of(context)!.app_setting, [
      ValueListenableBuilder<bool>(
        valueListenable: globalSetting.controlLogEnabledNotifier,
        builder: (context, enabled, _) {
          return SwitchListTile(
            title: Text(_text('控制日志', 'Control logs')),
            subtitle: Text(
              _text(
                '默认关闭；关闭时不显示日志按钮，也不会记录控制日志。',
                'Off by default. When disabled, the log button is hidden and no control logs are recorded.',
              ),
            ),
            value: enabled,
            onChanged: (value) async {
              ControlLogStore.instance.setEnabled(value);
              await globalSetting.setControlLogEnabled(value);
            },
          );
        },
      ),
      ListTile(
        title: Text(AppLocalizations.of(context)!.screen_orientation),
        trailing: DropdownButton<Orientation>(
          value: _selectedOrientation,
          dropdownColor: Colors.white,
          onChanged: (Orientation? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedOrientation = newValue;
                _setOrientation(newValue);
                _saveOrientation(newValue);
              });
            }
          },
          items:
              Orientation.values.map<DropdownMenuItem<Orientation>>((
                Orientation orientation,
              ) {
                return DropdownMenuItem<Orientation>(
                  value: orientation,
                  child: Text(
                    orientation == Orientation.portrait
                        ? AppLocalizations.of(context)!.portrait
                        : AppLocalizations.of(context)!.landscape,
                  ),
                );
              }).toList(),
        ),
      ),
    ]);
  }

  Future<void> _loadOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    final orientationValue =
        prefs.getString('screenOrientation') ?? 'landscape';
    _selectedOrientation =
        orientationValue == 'portrait'
            ? Orientation.portrait
            : Orientation.landscape;
    _setOrientation(_selectedOrientation);
  }

  void _setOrientation(Orientation orientation) {
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _saveOrientation(Orientation orientation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'screenOrientation',
      orientation == Orientation.portrait ? 'portrait' : 'landscape',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.setting),
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text('v$_version', style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildSettingGroups(),
        ),
      ),
    );
  }
}
