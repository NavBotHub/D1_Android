import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:gamepads/gamepads.dart';
import 'package:provider/provider.dart';
import 'package:navbot_d1_flutter/display/tile_map.dart';
import 'package:navbot_d1_flutter/provider/global_state.dart';
import 'package:navbot_d1_flutter/provider/http_channel.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';
import 'package:navbot_d1_flutter/basic/action_status.dart';
import 'package:navbot_d1_flutter/basic/RobotPose.dart';
import 'package:navbot_d1_flutter/page/map_edit_page.dart';
import 'package:navbot_d1_flutter/basic/nav_point.dart';
import 'package:navbot_d1_flutter/basic/topology_map.dart';
import 'package:toastification/toastification.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/page/gamepad_widget.dart';
import 'package:navbot_d1_flutter/page/camera_view.dart';
import 'package:navbot_d1_flutter/basic/diagnostic_status.dart';
import 'package:navbot_d1_flutter/page/diagnostic_page.dart';
import 'package:navbot_d1_flutter/provider/diagnostic_manager.dart';
import 'package:navbot_d1_flutter/language/l10n/gen/app_localizations.dart';
import 'package:navbot_d1_flutter/page/setting_page.dart';
import 'package:navbot_d1_flutter/page/ssh_quick_commands_page.dart';
import 'package:navbot_d1_flutter/page/ssh_terminal_page.dart';
import 'package:navbot_d1_flutter/page/ssh_widgets.dart';
import 'package:navbot_d1_flutter/provider/d1_mode_protocol.dart';
import 'package:navbot_d1_flutter/provider/robot_action_topic_publisher.dart';

class MainFlamePage extends StatefulWidget {
  @override
  _MainFlamePageState createState() => _MainFlamePageState();
}

enum _AssumedD1State { passive, stand, rl }

class _MainFlamePageState extends State<MainFlamePage> {
  final GlobalKey<TileMapState> _tileMapKey = GlobalKey<TileMapState>();
  bool showCamera = true;
  NavPoint? selectedNavPoint;
  TopologyRoute? _selectedRoute;
  RouteInfo? _editingRouteInfo;
  bool _isRecoveringConnection = false;
  bool _sshRailExpanded = false;
  bool _showGamepadOutput = false;
  bool _showGamepadControls = false;
  bool _gamepadControlsManuallyToggled = false;
  bool _isStanding = false;
  bool _d1ModeCommandPending = false;
  _AssumedD1State _assumedD1State = _AssumedD1State.passive;
  bool _reinforcementLearningHighlighted = false;
  bool _emergencyStopActive = false;
  String _lastDiscreteAction = '-';
  String _lastActionCommand = '-';
  double _lastCommandVx = 0;
  double _lastCommandVy = 0;
  double _lastCommandVw = 0;
  final ValueNotifier<GamepadDebugSnapshot> _gamepadDebugNotifier =
      ValueNotifier<GamepadDebugSnapshot>(GamepadDebugSnapshot.empty);
  final ValueNotifier<int> _manualCommandRestoreSignal = ValueNotifier<int>(0);
  final Set<GamepadMappedControl> _pressedGamepadControls =
      <GamepadMappedControl>{};
  GamepadDebugSnapshot _pendingGamepadDebug = GamepadDebugSnapshot.empty;
  final RobotActionTopicPublisher _robotActionPublisher =
      RobotActionTopicPublisher();
  Timer? _transientActionHighlightTimer;
  Timer? _gamepadDebugRefreshTimer;
  static const double _toolbarButtonSide = 56;
  static const double _toolbarIconSize = 34;
  static const double _statusChipIconSize = 24;
  static const double _statusChipTextSize = 16;
  static const double _dialogIconSize = 28;

  // 相机相关变量
  Offset camPosition = Offset.zero;
  bool isCamFullscreen = true;
  Offset camPreviousPosition = Offset.zero;
  double camWidgetWidth = 0;
  double camWidgetHeight = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeGamepadControlsVisibility());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverConnectionIfNeeded();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GlobalState>().isManualCtrl.value = true;
      context.read<WsChannel>().startMunalCtrl();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GlobalState>().loadLayerSettings();
      _setupDiagnosticListener();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final httpChannel = context.read<HttpChannel>();
        final mapManager = context.read<WsChannel>().mapManager;
        final topo = await httpChannel.getTopologyMap();
        mapManager.updateTopologyMap(topo);
      } catch (_) {}
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenSize = MediaQuery.of(context).size;
        setState(() {
          camWidgetWidth = screenSize.width / 3.5;
          camWidgetHeight =
              camWidgetWidth /
              (globalSetting.imageWidth / globalSetting.imageHeight);
          camPreviousPosition = Offset(
            (screenSize.width - camWidgetWidth) / 2,
            (screenSize.height - camWidgetHeight) / 2,
          );
          camPosition = isCamFullscreen ? Offset.zero : camPreviousPosition;
        });
      }
    });
  }

  void _toggleCamera() {
    setState(() {
      showCamera = !showCamera;
    });
  }

  void _toggleCameraFullscreen() {
    setState(() {
      isCamFullscreen = !isCamFullscreen;
      if (isCamFullscreen) {
        camPreviousPosition = camPosition;
        camPosition = Offset.zero;
      } else {
        camPosition = camPreviousPosition;
      }
    });
  }

  void _zoomIn() {
    _tileMapKey.currentState?.zoomIn();
  }

  void _zoomOut() {
    _tileMapKey.currentState?.zoomOut();
  }

  String _t(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  String get _standLabel => _t('站起', 'Stand');

  String get _lieDownLabel => _t('趴下', 'Lie Down');

  String get _reinforcementLearningLabel =>
      _assumedD1State == _AssumedD1State.rl
          ? _t('退出强化学习', 'Exit RL')
          : _t('进入强化学习', 'Enter RL');

  String get _emergencyStopLabel => _t('急停', 'Emergency Stop');

  String _actionTriggeredText(String actionName) {
    return _t('$actionName 已触发', '$actionName triggered');
  }

  String _actionTopicFailedText(String actionName, Object error) {
    return _t(
      '$actionName topic 下发失败: $error',
      '$actionName topic publish failed: $error',
    );
  }

  String _lastActionDisplayName() {
    switch (_lastActionCommand) {
      case 'stand':
        return _standLabel;
      case 'lie_down':
        return _lieDownLabel;
      case 'reinforcement_learning':
      case 'enter_rl':
      case 'exit_rl':
        return _reinforcementLearningLabel;
      case 'emergency_stop':
        return _emergencyStopLabel;
      case '-':
        return '-';
      default:
        return _lastDiscreteAction;
    }
  }

  void _clearTransientActionHighlightNow() {
    _transientActionHighlightTimer?.cancel();
    _transientActionHighlightTimer = null;
    _reinforcementLearningHighlighted = _assumedD1State == _AssumedD1State.rl;
  }

  void _triggerEmergencyStop() {
    final wsChannel = context.read<WsChannel>();
    final actionName = _emergencyStopLabel;
    wsChannel.sendEmergencyStop();
    _updateLastCommand(0, 0, 0);
    unawaited(_publishRobotAction('emergency_stop', actionName));
    if (mounted) {
      _transientActionHighlightTimer?.cancel();
      _transientActionHighlightTimer = null;
      setState(() {
        _emergencyStopActive = true;
        _reinforcementLearningHighlighted = false;
        _lastDiscreteAction = actionName;
        _lastActionCommand = 'emergency_stop';
      });
    }
    toastification.show(
      context: context,
      title: Text(_actionTriggeredText(actionName)),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  void _triggerStand() {
    unawaited(_sendD1ModeCommand(D1Mode.stand));
  }

  void _triggerLieDown() {
    unawaited(_sendD1ModeCommand(D1Mode.lieDown));
  }

  void _triggerReinforcementLearning() {
    final mode =
        _assumedD1State == _AssumedD1State.rl ? D1Mode.exitRl : D1Mode.enterRl;
    unawaited(_sendD1ModeCommand(mode));
  }

  Future<void> _sendD1ModeCommand(D1Mode mode) async {
    if (_d1ModeCommandPending) return;
    final wsChannel = context.read<WsChannel>();
    final actionName = _d1ModeLabel(mode);
    final command = _d1ModeCommandName(mode);
    wsChannel.clearEmergencyStop();
    wsChannel.setVx(0);
    wsChannel.setVy(0);
    wsChannel.setVw(0);
    _updateLastCommand(0, 0, 0);
    wsChannel.sendSpeed(0, 0, 0);
    setState(() {
      _d1ModeCommandPending = true;
      _emergencyStopActive = false;
      _lastDiscreteAction = actionName;
      _lastActionCommand = command;
    });
    try {
      final ack = await wsChannel.sendD1Mode(mode);
      if (!ack.sent) {
        final detail = ack.message.isEmpty ? ack.result.name : ack.message;
        throw StateError(detail);
      }
      if (!mounted) return;
      setState(() {
        switch (mode) {
          case D1Mode.stand:
          case D1Mode.exitRl:
            _assumedD1State = _AssumedD1State.stand;
            _isStanding = true;
            break;
          case D1Mode.lieDown:
            _assumedD1State = _AssumedD1State.passive;
            _isStanding = false;
            break;
          case D1Mode.enterRl:
            _assumedD1State = _AssumedD1State.rl;
            _isStanding = true;
            break;
          case D1Mode.unspecified:
            break;
        }
        _reinforcementLearningHighlighted =
            _assumedD1State == _AssumedD1State.rl;
      });
      toastification.show(
        context: context,
        title: Text(_t('$actionName 指令已发送', '$actionName command sent')),
        autoCloseDuration: const Duration(seconds: 2),
      );
    } catch (error) {
      if (!mounted) return;
      toastification.show(
        context: context,
        title: Text(
          _t(
            '$actionName 指令下发失败: $error',
            '$actionName command failed: $error',
          ),
        ),
        autoCloseDuration: const Duration(seconds: 3),
      );
    } finally {
      if (mounted) {
        setState(() => _d1ModeCommandPending = false);
        _manualCommandRestoreSignal.value++;
      }
    }
  }

  String _d1ModeLabel(D1Mode mode) {
    switch (mode) {
      case D1Mode.stand:
        return _standLabel;
      case D1Mode.lieDown:
        return _lieDownLabel;
      case D1Mode.enterRl:
        return _t('进入强化学习', 'Enter RL');
      case D1Mode.exitRl:
        return _t('退出强化学习', 'Exit RL');
      case D1Mode.unspecified:
        return _t('未知模式', 'Unknown mode');
    }
  }

  String _d1ModeCommandName(D1Mode mode) {
    switch (mode) {
      case D1Mode.stand:
        return 'stand';
      case D1Mode.lieDown:
        return 'lie_down';
      case D1Mode.enterRl:
        return 'enter_rl';
      case D1Mode.exitRl:
        return 'exit_rl';
      case D1Mode.unspecified:
        return 'unspecified';
    }
  }

  Future<void> _publishRobotAction(String command, String actionName) async {
    try {
      await _robotActionPublisher.publish(command);
    } catch (e) {
      if (!mounted) return;
      toastification.show(
        context: context,
        title: Text(_actionTopicFailedText(actionName, e)),
        autoCloseDuration: const Duration(seconds: 3),
      );
    }
  }

  void _toggleGamepadOutput() {
    setState(() {
      _showGamepadOutput = !_showGamepadOutput;
    });
    if (_showGamepadOutput) {
      _gamepadDebugNotifier.value = _pendingGamepadDebug;
    }
  }

  void _toggleGamepadControls() {
    setState(() {
      _gamepadControlsManuallyToggled = true;
      _showGamepadControls = !_showGamepadControls;
    });
  }

  Future<void> _initializeGamepadControlsVisibility() async {
    var isHandheld = false;
    try {
      final controllers = await Gamepads.list();
      isHandheld = controllers.isNotEmpty;
      await Future.wait(controllers.map((controller) => controller.dispose()));
    } catch (_) {
      // If device detection is unavailable, keep virtual controls accessible.
    }

    if (!mounted || _gamepadControlsManuallyToggled) return;
    setState(() {
      _showGamepadControls = !isHandheld;
    });
  }

  void _updateMappedControlPressed(GamepadMappedControl control, bool pressed) {
    if (!mounted) return;
    final changed =
        pressed
            ? _pressedGamepadControls.add(control)
            : _pressedGamepadControls.remove(control);
    if (changed) setState(() {});
  }

  void _updateLastCommand(double vx, double vy, double vw) {
    if (!mounted) return;
    _lastCommandVx = vx;
    _lastCommandVy = vy;
    _lastCommandVw = vw;
    if (vx != 0 || vy != 0 || vw != 0) {
      final highlightNeedsRefresh =
          _reinforcementLearningHighlighted !=
          (_assumedD1State == _AssumedD1State.rl);
      if (highlightNeedsRefresh) {
        setState(() {
          _clearTransientActionHighlightNow();
        });
      } else {
        _clearTransientActionHighlightNow();
      }
    }
  }

  void _updateGamepadDebug(GamepadDebugSnapshot snapshot) {
    if (!mounted) return;
    _pendingGamepadDebug = snapshot;
    _lastCommandVx = snapshot.vx;
    _lastCommandVy = snapshot.vy;
    _lastCommandVw = snapshot.vw;
    if (!_showGamepadOutput || _gamepadDebugRefreshTimer != null) return;
    _gamepadDebugRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _gamepadDebugRefreshTimer = null;
      if (!mounted || !_showGamepadOutput) return;
      _gamepadDebugNotifier.value = _pendingGamepadDebug;
    });
  }

  Future<void> _recoverConnectionIfNeeded() async {
    if (!mounted || _isRecoveringConnection) return;
    final wsChannel = context.read<WsChannel>();
    if (wsChannel.rosConnectState_ == Status.connected ||
        wsChannel.rosConnectState_ == Status.connecting) {
      return;
    }

    _isRecoveringConnection = true;
    try {
      final host = globalSetting.robotIp.trim();
      final port = int.tryParse(globalSetting.httpServerPort.trim()) ?? 8081;
      if (host.isEmpty) {
        _redirectToConnectPage();
        return;
      }

      String error = '';
      const maxAttempts = 4;
      for (int i = 0; i < maxAttempts; i++) {
        if (!mounted) return;
        error = await wsChannel.connectBackend(host, port);
        if (error.isEmpty) {
          return;
        }
        if (i < maxAttempts - 1) {
          await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
        }
      }

      if (!mounted) return;
      toastification.show(
        context: context,
        title: Text(AppLocalizations.of(context)!.init_error(error)),
        autoCloseDuration: const Duration(seconds: 4),
      );
      _redirectToConnectPage();
    } finally {
      _isRecoveringConnection = false;
    }
  }

  void _redirectToConnectPage() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/connect", (route) => false);
  }

  Widget _MapToolbarShell(
    ThemeData theme, {
    required Widget child,
    Color? backgroundColor,
  }) {
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      color: backgroundColor ?? scheme.surfaceContainerHigh.withOpacity(0.55),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  ButtonStyle _toolbarIconButtonStyle({Color? foregroundColor}) {
    return IconButton.styleFrom(
      minimumSize: const Size(_toolbarButtonSide, _toolbarButtonSide),
      iconSize: _toolbarIconSize,
      foregroundColor: foregroundColor,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.all(11),
    );
  }

  Future<void> _reloadData() async {
    try {
      final httpChannel = context.read<HttpChannel>();
      final wsChannel = context.read<WsChannel>();
      final topo = await httpChannel.getTopologyMap();
      wsChannel.mapManager.updateTopologyMap(topo);
    } catch (_) {}
    _tileMapKey.currentState?.reloadMeta();
  }

  Future<bool> _pullLatestGuiSettingsForSsh(BuildContext context) async {
    try {
      final s = await HttpChannel().getGuiSettings();
      globalSetting.applyBackendGuiSettings(s);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
      return false;
    }
  }

  Future<bool> _ensureSshCredentialsInteractive(BuildContext context) async {
    if (globalSetting.sshCredentialsConfigured) return true;
    final l10n = AppLocalizations.of(context)!;
    final go = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.ssh_required_title),
            content: Text(l10n.ssh_required_body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.ssh_go_configure),
              ),
            ],
          ),
    );
    if (go != true || !context.mounted) return false;
    await ShowSshConfigSheet(context);
    return globalSetting.sshCredentialsConfigured;
  }

  Future<void> _openSSHQuickCommands(BuildContext context) async {
    if (!await _pullLatestGuiSettingsForSsh(context)) return;
    if (!context.mounted) return;
    if (!await _ensureSshCredentialsInteractive(context)) return;
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SSHQuickCommandsPage()),
    );
  }

  Future<void> _openSshTerminal(BuildContext context) async {
    if (!await _pullLatestGuiSettingsForSsh(context)) return;
    if (!context.mounted) return;
    if (!await _ensureSshCredentialsInteractive(context)) return;
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SshTerminalPage()),
    );
  }

  void _openLayerSettings(BuildContext context) {
    Navigator.pushNamed(
      context,
      '/setting',
      arguments: kSettingsRouteArgLayers,
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.pushNamed(context, '/setting');
  }

  // 设置诊断数据监听器
  void _setupDiagnosticListener() {
    context.read<WsChannel>().diagnosticManager.setOnNewErrorsWarnings(
      _onNewErrorsWarnings,
    );
  }

  // 新错误/警告/失活回调
  void _onNewErrorsWarnings(List<Map<String, dynamic>> newErrorsWarnings) {
    for (var errorWarning in newErrorsWarnings) {
      final hardwareId = errorWarning['hardwareId'] as String;
      final componentName = errorWarning['componentName'] as String;
      final state = errorWarning['state'] as DiagnosticState;

      // 只对错误、警告和失活状态显示toast
      if (state.level == DiagnosticStatus.ERROR ||
          state.level == DiagnosticStatus.WARN ||
          state.level == DiagnosticStatus.STALE) {
        _showDiagnosticToast(hardwareId, componentName, state);
      }
    }
  }

  // 显示诊断toast通知
  void _showDiagnosticToast(
    String hardwareId,
    String componentName,
    DiagnosticState state,
  ) {
    if (!mounted) return;

    String levelText;
    Color levelColor;
    ToastificationType toastType;
    IconData iconData;

    switch (state.level) {
      case DiagnosticStatus.WARN:
        levelText = AppLocalizations.of(context)!.diagnostic_warning;
        levelColor = Colors.orange;
        toastType = ToastificationType.warning;
        iconData = Icons.warning;
        break;
      case DiagnosticStatus.ERROR:
        levelText = AppLocalizations.of(context)!.diagnostic_error;
        levelColor = Colors.red;
        toastType = ToastificationType.error;
        iconData = Icons.error;
        break;
      case DiagnosticStatus.STALE:
        levelText = AppLocalizations.of(context)!.diagnostic_stale;
        levelColor = Colors.grey;
        toastType = ToastificationType.info;
        iconData = Icons.schedule;
        break;
      default:
        return; // 其他状态不显示toast
    }

    final l10n = AppLocalizations.of(context)!;
    final hwId =
        hardwareId == 'unknown_hardware' ? l10n.unknown_hardware : hardwareId;
    final msg = state.message == 'data_stale' ? l10n.data_stale : state.message;
    toastification.show(
      context: context,
      type: toastType,
      title: Text(l10n.diagnostic_health(levelText, componentName)),
      description: Text(l10n.diagnostic_hardware(hwId, msg)),
      autoCloseDuration: const Duration(seconds: 5),
      icon: Icon(iconData, color: levelColor, size: _dialogIconSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final globalState = Provider.of<GlobalState>(context, listen: true);
    return Scaffold(
      body: ValueListenableBuilder<Mode>(
        valueListenable: globalState.mode,
        builder: (context, mode, _) {
          return Stack(
            children: [
              TileMap(
                key: _tileMapKey,
                onTap: () {
                  setState(() {
                    selectedNavPoint = null;
                    _selectedRoute = null;
                    _editingRouteInfo = null;
                  });
                },
                onNavPointTap: (NavPoint? point) {
                  setState(() {
                    selectedNavPoint = point;
                    if (point != null) {
                      _selectedRoute = null;
                      _editingRouteInfo = null;
                      _showNavPointDialog(context, point);
                    }
                  });
                },
                selectedRoute: _selectedRoute,
                onRouteTap: (route) {
                  setState(() {
                    _selectedRoute = route;
                    _editingRouteInfo = RouteInfo(
                      controller: route.routeInfo.controller,
                    );
                    selectedNavPoint = null;
                  });
                },
                selectedNavPointName: selectedNavPoint?.name,
                enableMapInteraction: mode != Mode.reloc,
                followRobot: mode == Mode.robotFixedCenter,
              ),
              _buildCameraWidget(context, theme),
              _buildTopMenuBar(context, theme),
              _buildLeftToolbar(context, theme),
              _buildRightToolbar(context, theme),
              Positioned(top: 60, right: 5, child: _buildSelectionPanel(theme)),
              _buildBottomControls(context, theme),
              _buildPostureActionButtons(context, theme),
              _buildGamepadWidget(context, theme),
              _buildGamepadOutputPanel(context, theme),
              _buildMapLegend(context, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionPanel(ThemeData theme) {
    final route = _selectedRoute;
    if (route != null) {
      final info = _editingRouteInfo ?? route.routeInfo;

      return Card(
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.route_properties,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: _dialogIconSize,
                      tooltip: AppLocalizations.of(context)!.close,
                      onPressed: () {
                        setState(() {
                          _selectedRoute = null;
                          _editingRouteInfo = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.direction(route.fromPoint, route.toPoint),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: info.controller,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context)!.controller_readonly,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStatusChip(
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required Widget label,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 36,
      child: RawChip(
        avatar: Icon(icon, color: iconColor, size: _statusChipIconSize),
        avatarBoxConstraints: const BoxConstraints.tightFor(
          width: _statusChipIconSize,
          height: _statusChipIconSize,
        ),
        label: label,
        labelStyle: theme.textTheme.bodyMedium?.copyWith(
          fontSize: _statusChipTextSize,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: const EdgeInsets.only(left: 6, right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: theme.colorScheme.surfaceContainerHigh.withValues(
          alpha: 0.85,
        ),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.38),
          width: 1,
        ),
        shape: const StadiumBorder(),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: false,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildTopMenuBar(BuildContext context, ThemeData theme) {
    final TextStyle? statusChipLabelStyle = theme.textTheme.bodyMedium
        ?.copyWith(fontSize: _statusChipTextSize, fontWeight: FontWeight.w600);
    return Positioned(
      left: 25,
      top: 4,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // 线速度显示
              _buildStatusChip(
                theme,
                icon: Icons.speed_rounded,
                iconColor: Colors.green.shade600,
                label: ValueListenableBuilder<RobotSpeed>(
                  valueListenable:
                      Provider.of<WsChannel>(
                        context,
                        listen: false,
                      ).controlSpeed_,
                  builder: (context, speed, child) {
                    return Text(
                      '${speed.planarSpeed.toStringAsFixed(2)} m/s',
                      style: statusChipLabelStyle,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 角速度显示
              _buildStatusChip(
                theme,
                icon: Icons.rotate_right_rounded,
                iconColor: Colors.blue.shade600,
                label: ValueListenableBuilder<RobotSpeed>(
                  valueListenable:
                      Provider.of<WsChannel>(
                        context,
                        listen: false,
                      ).controlSpeed_,
                  builder: (context, speed, child) {
                    return Text(
                      '${rad2deg(speed.vw).toStringAsFixed(2)} deg/s',
                      style: statusChipLabelStyle,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 电池电量显示(目前先注释掉)
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 5.0),
              //   child: RawChip(
              //     avatar: Icon(
              //       const IconData(0xe995, fontFamily: "Battery"),
              //       color: Colors.amber[300],
              //       size: _statusChipIconSize,
              //     ),
              //     backgroundColor: chipBackgroundColor,
              //     labelStyle: statusChipLabelStyle,
              //     labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              //     padding: const EdgeInsets.symmetric(
              //       horizontal: 8,
              //       vertical: 6,
              //     ),
              //     label: ValueListenableBuilder<double>(
              //       valueListenable:
              //           Provider.of<WsChannel>(context, listen: false).battery_,
              //       builder: (context, battery, child) {
              //         return Text(
              //           '${battery.toStringAsFixed(0)} %',
              //           style: statusChipLabelStyle,
              //         );
              //       },
              //     ),
              //   ),
              // ),

              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 5.0),
              //   child: RawChip(
              //     avatar: const Icon(
              //       Icons.phone_android_rounded,
              //       color: Colors.green,
              //       size: _statusChipIconSize,
              //     ),
              //     backgroundColor: chipBackgroundColor,
              //     labelStyle: statusChipLabelStyle,
              //     labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              //     padding: const EdgeInsets.symmetric(
              //       horizontal: 8,
              //       vertical: 6,
              //     ),
              //     label: Text(
              //       _deviceStatus.batteryPercent == null
              //           ? '--%'
              //           : '${_deviceStatus.batteryPercent}%',
              //       style: statusChipLabelStyle,
              //     ),
              //   ),
              // ),
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 5.0),
              //   child: RawChip(
              //    8 avatar: const Icon(
              //       Icons.wifi_rounded,
              //       color: Colors.lightBlue,
              //       size: _statusChipIconSize,
              //     ),
              //     backgroundColor: chipBackgroundColor,
              //     labelStyle: statusChipLabelStyle,
              //     labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              //     padding: const EdgeInsets.symmetric(
              //       horizontal: 8,
              //       vertical: 6,
              //     ),
              //     label: Text(
              //       _deviceStatus.wifiSignalPercent == null
              //           ? '--%'
              //           : '${_deviceStatus.wifiSignalPercent}%',
              //       style: statusChipLabelStyle,
              //     ),
              //   ),
              // ),
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 5.0),
              //   child: RawChip(
              //     avatar: const Icon(
              //       Icons.gps_fixed_rounded,
              //       color: Colors.lightGreenAccent,
              //       size: _statusChipIconSize,
              //     ),
              //     backgroundColor: chipBackgroundColor,
              //     labelStyle: statusChipLabelStyle,
              //     labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              //     padding: const EdgeInsets.symmetric(
              //       horizontal: 8,
              //       vertical: 6,
              //     ),
              //     label: ValueListenableBuilder<GpsFix?>(
              //       valueListenable:
              //           Provider.of<WsChannel>(context, listen: false).gpsFix_,
              //       builder: (context, gps, child) {
              //         final text =
              //             gps == null
              //                 ? 'GPS --'
              //                 : '${gps.latitude.toStringAsFixed(6)}, '
              //                     '${gps.longitude.toStringAsFixed(6)}, '
              //                     '${gps.altitude.toStringAsFixed(1)}m';
              //         return Text(text, style: statusChipLabelStyle);
              //       },
              //     ),
              //   ),
              // ),
              // 导航状态显示
              _buildStatusChip(
                theme,
                icon: Icons.near_me_outlined,
                iconColor: Colors.green.shade600,
                label: ValueListenableBuilder<ActionStatus>(
                  valueListenable:
                      Provider.of<WsChannel>(context, listen: true).navStatus_,
                  builder: (context, navStatus, child) {
                    return Text(
                      navStatus.toString(),
                      style: statusChipLabelStyle,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 诊断状态显示（监听 DiagnosticManager，而非仅 Consumer<WsChannel>）
              Builder(
                builder: (BuildContext context) {
                  final WsChannel ws = Provider.of<WsChannel>(
                    context,
                    listen: false,
                  );
                  return ListenableBuilder(
                    listenable: ws.diagnosticManager,
                    builder: (BuildContext context, Widget? child) {
                      final Map<int, int> statusCounts =
                          ws.diagnosticManager.getStatusCounts();
                      final int errorCount =
                          statusCounts[DiagnosticStatus.ERROR] ?? 0;
                      final int warnCount =
                          statusCounts[DiagnosticStatus.WARN] ?? 0;
                      final AppLocalizations l10n =
                          AppLocalizations.of(context)!;

                      Color chipColor = Colors.green.shade600;
                      IconData chipIcon = Icons.check_circle_outline_rounded;
                      String chipText = l10n.diagnostic_normal;

                      if (errorCount > 0) {
                        chipColor = Colors.red.shade600;
                        chipIcon = Icons.error_outline_rounded;
                        chipText = l10n.error_count(errorCount.toString());
                      } else if (warnCount > 0) {
                        chipColor = Colors.orange.shade700;
                        chipIcon = Icons.warning_amber_rounded;
                        chipText = l10n.warn_count(warnCount.toString());
                      }

                      return _buildStatusChip(
                        theme,
                        icon: chipIcon,
                        iconColor: chipColor,
                        label: Text(chipText, style: statusChipLabelStyle),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (BuildContext context) =>
                                      const DiagnosticPage(),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftToolbar(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 10,
      top: 60,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapToolbarShell(
              theme,
              child: IconButton(
                style: _toolbarIconButtonStyle(),
                icon: Icon(Icons.layers_outlined, color: theme.iconTheme.color),
                tooltip: AppLocalizations.of(context)!.layers,
                onPressed: () => _openLayerSettings(context),
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder(
              valueListenable:
                  Provider.of<GlobalState>(context, listen: false).mode,
              builder: (context, mode, _) {
                return _MapToolbarShell(
                  theme,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        style: _toolbarIconButtonStyle(),
                        onPressed: () {
                          var globalState = Provider.of<GlobalState>(
                            context,
                            listen: false,
                          );
                          globalState.mode.value =
                              mode == Mode.reloc ? Mode.normal : Mode.reloc;
                        },
                        icon: Icon(
                          const IconData(0xe60f, fontFamily: "Reloc"),
                          color:
                              mode == Mode.reloc
                                  ? Colors.green
                                  : theme.iconTheme.color,
                        ),
                      ),
                      if (mode == Mode.reloc) ...[
                        IconButton(
                          style: _toolbarIconButtonStyle(),
                          onPressed: () {
                            Provider.of<GlobalState>(context, listen: false)
                                .mode
                                .value = Mode.normal;
                            Provider.of<WsChannel>(
                              context,
                              listen: false,
                            ).sendRelocPose(
                              _tileMapKey.currentState?.getRelocRobotPose() ??
                                  RobotPose.zero(),
                            );
                          },
                          icon: Icon(Icons.check, color: Colors.green),
                        ),
                        IconButton(
                          style: _toolbarIconButtonStyle(),
                          onPressed: () {
                            Provider.of<GlobalState>(context, listen: false)
                                .mode
                                .value = Mode.normal;
                          },
                          icon: Icon(Icons.close, color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            _MapToolbarShell(
              theme,
              child: IconButton(
                style: _toolbarIconButtonStyle(),
                icon: Icon(
                  Icons.article_outlined,
                  color:
                      _showGamepadOutput ? Colors.green : theme.iconTheme.color,
                ),
                onPressed: _toggleGamepadOutput,
                tooltip: '输出',
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<bool>(
              valueListenable: globalSetting.controlLogEnabledNotifier,
              builder: (context, enabled, _) {
                if (!enabled) return const SizedBox.shrink();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapToolbarShell(
                      theme,
                      child: IconButton(
                        style: _toolbarIconButtonStyle(),
                        icon: Icon(
                          Icons.receipt_long_outlined,
                          color: theme.iconTheme.color,
                        ),
                        onPressed:
                            () => Navigator.pushNamed(context, '/control-log'),
                        tooltip:
                            Localizations.localeOf(context).languageCode == 'zh'
                                ? '控制日志'
                                : 'Control logs',
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
            _MapToolbarShell(
              theme,
              child: IconButton(
                style: _toolbarIconButtonStyle(),
                icon: Icon(
                  Icons.photo_camera_outlined,
                  color: showCamera ? Colors.green : theme.iconTheme.color,
                ),
                onPressed: _toggleCamera,
                tooltip: AppLocalizations.of(context)!.camera_image,
              ),
            ),
            // const SizedBox(height: 6),
            // _MapToolbarShell(
            //   theme,
            //   child: IconButton(
            //     style: _toolbarIconButtonStyle(),
            //     icon: Icon(
            //       Icons.gamepad_outlined,
            //       color:
            //           _showGamepadControls ? Colors.green : theme.iconTheme.color,
            //     ),
            //     onPressed: _toggleGamepadControls,
            //     tooltip: _t('手柄控件', 'Gamepad controls'),
            //   ),
            // ),
            const SizedBox(height: 6),
            _MapToolbarShell(
              theme,
              child: IconButton(
                style: _toolbarIconButtonStyle(),
                icon: Icon(
                  const IconData(0xea45, fontFamily: "GamePad"),
                  color:
                      _showGamepadControls
                          ? Colors.green
                          : theme.iconTheme.color,
                ),
                onPressed: _toggleGamepadControls,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNavPointDialog(BuildContext context, NavPoint point) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.blue[700],
                  size: _dialogIconSize,
                ),
                const SizedBox(width: 10),
                Text(AppLocalizations.of(context)!.nav_point_info),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.label,
                          color: Colors.blue[700],
                          size: _dialogIconSize,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                point.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _getTypeColor(point.type),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getTypeText(point.type),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoSection(
                    ctx,
                    theme,
                    AppLocalizations.of(context)!.position_coords,
                    Icons.gps_fixed,
                    [
                      _buildInfoRow(
                        AppLocalizations.of(context)!.coord_x,
                        '${point.x.toStringAsFixed(2)} m',
                      ),
                      _buildInfoRow(
                        AppLocalizations.of(context)!.coord_y,
                        '${point.y.toStringAsFixed(2)} m',
                      ),
                      _buildInfoRow(
                        AppLocalizations.of(context)!.heading,
                        '${(point.theta * 180 / 3.14159).toStringAsFixed(1)}°',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (Provider.of<GlobalState>(
                    context,
                    listen: false,
                  ).isManualCtrl.value) {
                    toastification.show(
                      context: context,
                      title: Text(
                        AppLocalizations.of(context)!.stop_manual_first,
                      ),
                      autoCloseDuration: const Duration(seconds: 3),
                    );
                    return;
                  }
                  Provider.of<WsChannel>(
                    context,
                    listen: false,
                  ).sendNavigationGoal(
                    RobotPose(point.x, point.y, point.theta),
                  );
                  toastification.show(
                    context: context,
                    title: Text(
                      AppLocalizations.of(context)!.nav_goal_sent(point.name),
                    ),
                    autoCloseDuration: const Duration(seconds: 3),
                  );
                  Navigator.of(ctx).pop();
                  setState(() => selectedNavPoint = null);
                },
                icon: const Icon(Icons.navigation, size: _dialogIconSize),
                label: Text(AppLocalizations.of(context)!.send_nav_goal),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildRightToolbar(BuildContext context, ThemeData theme) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ButtonStyle tbStyle = _toolbarIconButtonStyle();
    return Positioned(
      right: 10,
      top: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _MapToolbarShell(
            theme,
            child: IconButton(
              style: tbStyle,
              icon: Icon(Icons.settings, color: theme.iconTheme.color),
              tooltip: l10n.setting,
              onPressed: () => _openSettings(context),
            ),
          ),
          const SizedBox(height: 6),
          _MapToolbarShell(
            theme,
            child: IconButton(
              style: tbStyle,
              icon: Icon(
                Icons.edit_document,
                color:
                    (Provider.of<GlobalState>(
                              context,
                              listen: false,
                            ).mode.value ==
                            Mode.mapEdit)
                        ? Colors.orange
                        : theme.iconTheme.color,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => MapEditPage(
                          onExit: () {
                            _reloadData();
                          },
                        ),
                  ),
                );
              },
              tooltip: l10n.map_edit,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerRight,
                child:
                    _sshRailExpanded
                        ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MapToolbarShell(
                              theme,
                              child: IconButton(
                                style: tbStyle,
                                onPressed: () async {
                                  setState(() => _sshRailExpanded = false);
                                  await _openSSHQuickCommands(context);
                                },
                                icon: Icon(
                                  Icons.bolt_rounded,
                                  color: theme.iconTheme.color,
                                ),
                                tooltip: l10n.ssh_quick_commands_tooltip,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _MapToolbarShell(
                              theme,
                              child: IconButton(
                                style: tbStyle,
                                onPressed: () async {
                                  setState(() => _sshRailExpanded = false);
                                  await _openSshTerminal(context);
                                },
                                icon: Icon(
                                  Icons.terminal_rounded,
                                  color: theme.iconTheme.color,
                                ),
                                tooltip: l10n.ssh_terminal_tooltip,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        )
                        : const SizedBox(height: _toolbarButtonSide),
              ),
              _MapToolbarShell(
                theme,
                child: IconButton(
                  style: tbStyle,
                  onPressed: () {
                    setState(() => _sshRailExpanded = !_sshRailExpanded);
                  },
                  icon: Icon(
                    _sshRailExpanded
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.hub_outlined,
                    color:
                        _sshRailExpanded
                            ? theme.colorScheme.primary
                            : theme.iconTheme.color,
                  ),
                  tooltip: l10n.ssh_remote_section,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _MapToolbarShell(
            theme,
            backgroundColor:
                _pressedGamepadControls.contains(GamepadMappedControl.zoomIn)
                    ? theme.colorScheme.primary.withValues(alpha: 0.18)
                    : null,
            child: IconButton(
              style: tbStyle,
              onPressed: _zoomIn,
              icon: Icon(
                Icons.zoom_in_rounded,
                color:
                    _pressedGamepadControls.contains(
                          GamepadMappedControl.zoomIn,
                        )
                        ? theme.colorScheme.primary
                        : theme.iconTheme.color,
              ),
              tooltip: l10n.zoom_in,
            ),
          ),
          const SizedBox(height: 6),
          _MapToolbarShell(
            theme,
            child: IconButton(
              style: tbStyle,
              onPressed: _zoomOut,
              icon: Icon(Icons.zoom_out_rounded, color: theme.iconTheme.color),
              tooltip: l10n.zoom_out,
            ),
          ),
          const SizedBox(height: 6),
          _MapToolbarShell(
            theme,
            child: IconButton(
              style: tbStyle,
              onPressed: () {
                var globalState = Provider.of<GlobalState>(
                  context,
                  listen: false,
                );
                if (globalState.mode.value == Mode.robotFixedCenter) {
                  globalState.mode.value = Mode.normal;
                } else {
                  globalState.mode.value = Mode.robotFixedCenter;
                }
                setState(() {});
              },
              icon: Icon(
                Icons.location_searching_rounded,
                color:
                    Provider.of<GlobalState>(
                              context,
                              listen: false,
                            ).mode.value ==
                            Mode.robotFixedCenter
                        ? Colors.green
                        : theme.iconTheme.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, ThemeData theme) {
    return Positioned(
      left: 5,
      bottom: 10,
      child: Consumer<GlobalState>(
        builder: (context, globalState, child) {
          return Visibility(
            visible: !globalState.isManualCtrl.value,
            child: Row(
              children: [
                // 停止导航按钮
                Consumer<WsChannel>(
                  builder: (context, wsChannel, child) {
                    return ValueListenableBuilder<ActionStatus>(
                      valueListenable: wsChannel.navStatus_,
                      builder: (context, navStatus, child) {
                        return Visibility(
                          visible:
                              navStatus == ActionStatus.executing ||
                              navStatus == ActionStatus.accepted,
                          child: _MapToolbarShell(
                            theme,
                            backgroundColor: Colors.blue,
                            child: SizedBox(
                              width: _toolbarButtonSide,
                              height: _toolbarButtonSide,
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  iconSize: _toolbarIconSize,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.all(8),
                                ),
                                icon: const Icon(
                                  Icons.stop_circle_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  Provider.of<WsChannel>(
                                    context,
                                    listen: false,
                                  ).sendCancelNav();
                                  toastification.show(
                                    context: context,
                                    title: Text(
                                      AppLocalizations.of(context)!.nav_stopped,
                                    ),
                                    autoCloseDuration: const Duration(
                                      seconds: 3,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostureActionButtons(BuildContext context, ThemeData theme) {
    return Positioned(
      right: 82,
      top: 78,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildStandLieActionButton(
              theme,
              onPressed:
                  _d1ModeCommandPending
                      ? null
                      : (_isStanding ? _triggerLieDown : _triggerStand),
            ),
            _buildPostureActionButton(
              theme,
              label: _reinforcementLearningLabel,
              shortcut: '↑ + R1',
              icon: Icons.flash_on_rounded,
              selected: _reinforcementLearningHighlighted,
              pressed: _pressedGamepadControls.contains(
                GamepadMappedControl.reinforcementLearning,
              ),
              accentColor: theme.colorScheme.primary,
              onPressed:
                  _d1ModeCommandPending ? null : _triggerReinforcementLearning,
            ),
            // _buildPostureActionButton(
            //   theme,
            //   label: _emergencyStopLabel,
            //   shortcut: 'Y',
            //   icon: Icons.stop_circle_rounded,
            //   selected: _emergencyStopActive,
            //   accentColor: Colors.redAccent,
            //   onPressed: _triggerEmergencyStop,
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandLieActionButton(
    ThemeData theme, {
    required VoidCallback? onPressed,
  }) {
    final accent = theme.colorScheme.primary;
    final inactive = theme.colorScheme.onSurface;
    final standPressed = _pressedGamepadControls.contains(
      GamepadMappedControl.stand,
    );
    final lieDownPressed = _pressedGamepadControls.contains(
      GamepadMappedControl.lieDown,
    );
    final standSelected = standPressed || (!lieDownPressed && _isStanding);
    final lieDownSelected = lieDownPressed || (!standPressed && !_isStanding);
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: Colors.white,
          side: BorderSide(color: accent.withOpacity(0.78), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              standSelected ? Icons.upload_rounded : Icons.download_rounded,
              size: 30,
              color: accent,
            ),
            const SizedBox(width: 10),
            _buildPostureModeText(
              _standLabel,
              shortcut: 'A',
              selected: standSelected,
              accent: accent,
              inactive: inactive,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '/',
                style: TextStyle(
                  color: inactive.withOpacity(0.72),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _buildPostureModeText(
              _lieDownLabel,
              shortcut: 'B',
              selected: lieDownSelected,
              accent: accent,
              inactive: inactive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostureModeText(
    String label, {
    required String shortcut,
    required bool selected,
    required Color accent,
    required Color inactive,
  }) {
    final foreground = selected ? Colors.white : inactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$label $shortcut',
        style: TextStyle(
          color: foreground,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPostureActionButton(
    ThemeData theme, {
    required String label,
    required String shortcut,
    required IconData icon,
    required bool selected,
    bool pressed = false,
    required VoidCallback? onPressed,
    Color? accentColor,
  }) {
    final accent = accentColor ?? theme.colorScheme.primary;
    final visuallySelected = selected || pressed;
    final foreground = visuallySelected ? accent : theme.colorScheme.onSurface;
    final borderColor =
        visuallySelected ? accent : accent.withValues(alpha: 0.78);
    final backgroundColor =
        visuallySelected
            ? accent.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.88);
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 30),
        label: Text(
          '$label  $shortcut',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.grey[600], size: _dialogIconSize),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(NavPointType type) {
    switch (type) {
      case NavPointType.navGoal:
        return Colors.blue[600]!;
      case NavPointType.chargeStation:
        return Colors.green[600]!;
    }
  }

  String _getTypeText(NavPointType type) {
    switch (type) {
      case NavPointType.navGoal:
        return AppLocalizations.of(context)!.nav_goal;
      case NavPointType.chargeStation:
        return AppLocalizations.of(context)!.charge_station;
    }
  }

  // 构建相机显示组件
  Widget _buildCameraWidget(BuildContext context, ThemeData theme) {
    if (!showCamera) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    final cameraWidth =
        camWidgetWidth > 0 ? camWidgetWidth : screenSize.width / 3.5;
    final cameraHeight =
        camWidgetHeight > 0
            ? camWidgetHeight
            : cameraWidth /
                (globalSetting.imageWidth / globalSetting.imageHeight);

    return Positioned(
      left: camPosition.dx,
      top: camPosition.dy,
      child: GestureDetector(
        onDoubleTap: _toggleCameraFullscreen,
        onPanUpdate: (details) {
          if (!isCamFullscreen) {
            setState(() {
              double newX = camPosition.dx + details.delta.dx;
              double newY = camPosition.dy + details.delta.dy;
              // 限制位置在屏幕范围内
              newX = newX.clamp(0.0, screenSize.width - cameraWidth);
              newY = newY.clamp(0.0, screenSize.height - cameraHeight);
              camPosition = Offset(newX, newY);
            });
          }
        },
        child: Container(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // 在非全屏状态下，获取屏幕宽高
                  double containerWidth =
                      isCamFullscreen ? screenSize.width : cameraWidth;
                  double containerHeight =
                      isCamFullscreen ? screenSize.height : cameraHeight;

                  return CameraView(
                    width: containerWidth,
                    height: containerHeight,
                  );
                },
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  iconSize: _toolbarIconSize,
                  icon: Icon(
                    isCamFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.black,
                  ),
                  constraints: BoxConstraints(), // 移除按钮的默认大小约束，变得更加紧凑
                  onPressed: _toggleCameraFullscreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGamepadWidget(BuildContext context, ThemeData theme) {
    return Positioned.fill(
      child: GamepadWidget(
        showVirtualJoysticks: _showGamepadControls,
        onEmergencyStop: _triggerEmergencyStop,
        onToggleCamera: _toggleCamera,
        onStand: _triggerStand,
        onLieDown: _triggerLieDown,
        onReinforcementLearning: _triggerReinforcementLearning,
        onZoomIn: _zoomIn,
        onZoomOut: _zoomOut,
        onCommandChanged: _updateLastCommand,
        onDebugChanged: _updateGamepadDebug,
        manualCommandRestoreSignal: _manualCommandRestoreSignal,
        onMappedControlPressedChanged: _updateMappedControlPressed,
      ),
    );
  }

  Widget _buildGamepadOutputPanel(BuildContext context, ThemeData theme) {
    if (!_showGamepadOutput) return const SizedBox.shrink();

    final panelTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontFamily: 'monospace',
      height: 1.35,
    );
    return Positioned(
      left: 64,
      top: 62,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
        child: _MapToolbarShell(
          theme,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: ValueListenableBuilder<GamepadDebugSnapshot>(
                valueListenable: _gamepadDebugNotifier,
                builder:
                    (context, snapshot, child) => SelectableText(
                      _gamepadOutputText(snapshot),
                      style: panelTextStyle,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _gamepadOutputText(GamepadDebugSnapshot gamepadDebug) {
    final host = globalSetting.robotIp.trim();
    final port = globalSetting.httpServerPort.trim();
    final actionTopic = globalSetting.robotActionTopic;
    final standLabel = _standLabel;
    final lieDownLabel = _lieDownLabel;
    final reinforcementLearningLabel = _reinforcementLearningLabel;
    // final emergencyStopLabel = _emergencyStopLabel;
    final lastActionDisplay = _lastActionDisplayName();
    final pressed =
        gamepadDebug.pressedButtons.isEmpty
            ? '-'
            : gamepadDebug.pressedButtons.join(', ');
    return '''
${_t('实时操控', 'Realtime control')}:
${_t('最近事件类型', 'Last event type')} = ${gamepadDebug.eventType}
${_t('最近事件 key', 'Last event key')} = ${gamepadDebug.eventKey}
${_t('最近事件 value', 'Last event value')} = ${gamepadDebug.eventValue.toStringAsFixed(3)}
${_t('触发动作', 'Triggered action')} = ${gamepadDebug.action}
${_t('最近离散动作', 'Last discrete action')} = $lastActionDisplay
${_t('最近动作命令', 'Last action command')} = $_lastActionCommand
${_t('本地急停锁定', 'Local emergency-stop latch')} = $_emergencyStopActive
${_t('当前按住按钮', 'Pressed buttons')} = $pressed

${_t('实时轴值', 'Realtime axes')}:
AXIS_X ${_t('左摇杆左右', 'left stick horizontal')} = ${gamepadDebug.leftAxisX.toStringAsFixed(3)}
AXIS_Y ${_t('左摇杆上下', 'left stick vertical')} = ${gamepadDebug.leftAxisY.toStringAsFixed(3)}
AXIS_RX/AXIS_Z ${_t('右摇杆旋转', 'right stick rotation')} = ${gamepadDebug.rightAxisX.toStringAsFixed(3)}
AXIS_HAT_X ${_t('方向键左右', 'D-pad horizontal')} = ${gamepadDebug.hatAxisX.toStringAsFixed(3)}
AXIS_HAT_Y ${_t('方向键上下', 'D-pad vertical')} = ${gamepadDebug.hatAxisY.toStringAsFixed(3)}

${_t('当前实际映射', 'Current mapping')}:
moveX = ${gamepadDebug.moveX.toStringAsFixed(3)}
moveY = ${gamepadDebug.moveY.toStringAsFixed(3)}
rotationAxis = ${gamepadDebug.rotationAxis.toStringAsFixed(3)}
rotationSource = ${gamepadDebug.rotationSource}

${_t('按钮固定映射', 'Fixed button mapping')}:
A / KEYCODE_BUTTON_A = $standLabel, D1_MODE_STAND
B / KEYCODE_BUTTON_B = $lieDownLabel, D1_MODE_LIE_DOWN
X / KEYCODE_BUTTON_X = ${_t('地图放大', 'Map zoom in')}
Y / KEYCODE_BUTTON_Y = ${_t('未绑定', 'Unbound')}
L1 / KEYCODE_BUTTON_L1 = ${_t('未绑定', 'Unbound')}
L2 / KEYCODE_BUTTON_L2 = ${_t('未绑定', 'Unbound')}
R1 / KEYCODE_BUTTON_R1 = ${_t('只作为组合键', 'Combo key only')}
R2 / KEYCODE_BUTTON_R2 = ${_t('未绑定', 'Unbound')}
${_t('方向键上 + R1', 'D-pad up + R1')} = $reinforcementLearningLabel, D1_MODE_ENTER_RL / D1_MODE_EXIT_RL, ${_t('间隔 <= 320ms', 'interval <= 320ms')}

${_t('轴映射', 'Axis mapping')}:
AXIS_X = ${_t('左摇杆左右', 'left stick horizontal')}
AXIS_Y = ${_t('左摇杆上下', 'left stick vertical')}
AXIS_HAT_X = ${_t('方向键左右不参与移动', 'D-pad horizontal does not control movement')}
AXIS_HAT_Y = ${_t('仅方向键上 + R1 触发强化学习', 'Only D-pad up + R1 triggers reinforcement learning')}
AXIS_RX = ${_t('右摇杆左右旋转', 'right stick horizontal rotation')}
AXIS_Z / AXIS_RY / AXIS_RZ = ${_t('当前忽略', 'Ignored')}

${_t('速度换算', 'Speed conversion')}:
MaxVx = ${gamepadDebug.maxVx.toStringAsFixed(3)}
MaxVy = ${gamepadDebug.maxVy.toStringAsFixed(3)}
MaxVw = ${gamepadDebug.maxVw.toStringAsFixed(3)}
vx = MaxVx * moveY = ${_lastCommandVx.toStringAsFixed(3)}
vy = MaxVy * moveX * -1 = ${_lastCommandVy.toStringAsFixed(3)}
vw = MaxVw * rotationAxis = ${_lastCommandVw.toStringAsFixed(3)}

${_t('发送地址', 'Send address')}:
ws://$host:$port/ws/robot

${_t('模式命令协议', 'Mode command protocol')}:
ClientRobotMessage.d1_mode_command = field 8
RobotMessage.d1_mode_ack = field 20
${_t('等待同一 seq 的 Ack 后更新估计状态', 'Estimated state updates after the matching seq Ack')}

${_t('急停兼容接口', 'Emergency stop compatibility endpoint')}:
POST http://$host:$port/robot/action_cmd
$actionTopic
std_msgs/msg/String
data: emergency_stop

${_t('当前发送数据', 'Current sent data')}:
ClientRobotMessage {
  cmd_vel: Twist {
    linear: {
      x: ${_lastCommandVx.toStringAsFixed(3)}
      y: ${_lastCommandVy.toStringAsFixed(3)}
      z: 0.000
    }
    angular: {
      x: 0.000
      y: 0.000
      z: ${_lastCommandVw.toStringAsFixed(3)}
    }
  }
  d1_mode_command: {
    mode: $_lastActionCommand
  }
}
''';
  }

  // 构建地图图例组件
  Widget _buildMapLegend(BuildContext context, ThemeData theme) {
    final AppLocalizations? l10n = AppLocalizations.of(context);
    final double maxLegendWidth = MediaQuery.sizeOf(context).width * 0.62;
    return Positioned(
      right: 24,
      top: 8,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxLegendWidth),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactLegendItem(
                l10n?.legend_free ?? 'Free',
                _getFreeAreaColor(),
              ),
              const SizedBox(width: 22),
              _buildCompactLegendItem(
                l10n?.legend_occupied ?? 'Occupied',
                _getOccupiedAreaColor(),
              ),
              const SizedBox(width: 22),
              _buildCompactLegendItem(
                l10n?.legend_unknown ?? 'Unknown',
                _getUnknownAreaColor(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建精简图例项目
  Widget _buildCompactLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Color _getFreeAreaColor() => globalSetting.mapTileFreeColor;

  Color _getOccupiedAreaColor() => globalSetting.mapTileOccColor;

  Color _getUnknownAreaColor() => globalSetting.mapTileUnknownColor;

  @override
  void dispose() {
    _transientActionHighlightTimer?.cancel();
    _gamepadDebugRefreshTimer?.cancel();
    _gamepadDebugNotifier.dispose();
    _manualCommandRestoreSignal.dispose();
    _robotActionPublisher.close();
    super.dispose();
  }
}
