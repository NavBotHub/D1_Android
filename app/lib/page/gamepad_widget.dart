import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:gamepads/gamepads.dart';
import 'package:provider/provider.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';
import 'package:navbot_d1_flutter/provider/control_log_store.dart';

enum GamepadMappedControl {
  stand,
  lieDown,
  emergencyStop,
  zoomIn,
  reinforcementLearning,
}

class GamepadWidget extends StatefulWidget {
  const GamepadWidget({
    super.key,
    this.showVirtualJoysticks = false,
    this.onEmergencyStop,
    this.onToggleCamera,
    this.onStand,
    this.onLieDown,
    this.onReinforcementLearning,
    this.onZoomIn,
    this.onZoomOut,
    this.onCommandChanged,
    this.onDebugChanged,
    this.manualCommandRestoreSignal,
    this.onMappedControlPressedChanged,
  });

  final bool showVirtualJoysticks;
  final VoidCallback? onEmergencyStop;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onStand;
  final VoidCallback? onLieDown;
  final VoidCallback? onReinforcementLearning;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final void Function(double vx, double vy, double vw)? onCommandChanged;
  final void Function(GamepadDebugSnapshot snapshot)? onDebugChanged;
  final ValueListenable<int>? manualCommandRestoreSignal;
  final void Function(GamepadMappedControl control, bool pressed)?
  onMappedControlPressedChanged;

  @override
  State<GamepadWidget> createState() => _GamepadWidgetState();
}

class GamepadDebugSnapshot {
  const GamepadDebugSnapshot({
    required this.eventType,
    required this.eventKey,
    required this.eventValue,
    required this.action,
    required this.leftAxisX,
    required this.leftAxisY,
    required this.rightAxisX,
    required this.hatAxisX,
    required this.hatAxisY,
    required this.moveX,
    required this.moveY,
    required this.rotationAxis,
    required this.rotationSource,
    required this.pressedButtons,
    required this.maxVx,
    required this.maxVy,
    required this.maxVw,
    required this.vx,
    required this.vy,
    required this.vw,
  });

  final String eventType;
  final String eventKey;
  final double eventValue;
  final String action;
  final double leftAxisX;
  final double leftAxisY;
  final double rightAxisX;
  final double hatAxisX;
  final double hatAxisY;
  final double moveX;
  final double moveY;
  final double rotationAxis;
  final String rotationSource;
  final List<String> pressedButtons;
  final double maxVx;
  final double maxVy;
  final double maxVw;
  final double vx;
  final double vy;
  final double vw;

  static const empty = GamepadDebugSnapshot(
    eventType: '-',
    eventKey: '-',
    eventValue: 0,
    action: '-',
    leftAxisX: 0,
    leftAxisY: 0,
    rightAxisX: 0,
    hatAxisX: 0,
    hatAxisY: 0,
    moveX: 0,
    moveY: 0,
    rotationAxis: 0,
    rotationSource: '-',
    pressedButtons: <String>[],
    maxVx: 0,
    maxVy: 0,
    maxVw: 0,
    vx: 0,
    vy: 0,
    vw: 0,
  );
}

class _PhysicalStickAxes {
  double x = 0;
  double y = 0;

  bool get isActive =>
      x.abs() >= _GamepadWidgetState._axisDeadZone ||
      y.abs() >= _GamepadWidgetState._axisDeadZone;

  double get strength => x.abs() > y.abs() ? x.abs() : y.abs();
}

class _GamepadWidgetState extends State<GamepadWidget>
    with WidgetsBindingObserver {
  static const EventChannel _deviceEventChannel = EventChannel(
    'navbot/gamepad_devices',
  );

  final JoystickController _leftJoystickController = JoystickController();
  final JoystickController _rightJoystickController = JoystickController();
  final ValueNotifier<Offset> _physicalLeftVisual = ValueNotifier<Offset>(
    Offset.zero,
  );
  final ValueNotifier<Offset> _physicalRightVisual = ValueNotifier<Offset>(
    Offset.zero,
  );
  StreamSubscription<GamepadEvent>? _subscription;
  StreamSubscription<dynamic>? _deviceEventSubscription;
  Timer? _gamepadResubscribeTimer;
  bool _gamepadSubscriptionRestarting = false;
  WsChannel? _wsChannel;
  final Map<String, _PhysicalStickAxes> _physicalLeftAxes =
      <String, _PhysicalStickAxes>{};
  String? _activePhysicalLeftDevice;
  final Map<String, double> _physicalRightAxes = <String, double>{};
  String? _activePhysicalRightAxis;
  bool _inputSuspended = false;

  double _physicalLeftAxisX = 0;
  double _physicalLeftAxisY = 0;
  double _physicalRightAxisRx = 0;
  double _virtualLeftAxisX = 0;
  double _virtualLeftAxisY = 0;
  double _virtualRightAxisX = 0;
  bool _virtualLeftActive = false;
  bool _virtualRightActive = false;
  double _hatAxisX = 0;
  double _hatAxisY = 0;
  final Set<String> _pressedButtons = <String>{};
  String _lastEventType = '-';
  String _lastEventKey = '-';
  double _lastEventValue = 0;
  String _lastAction = '-';
  DateTime? _lastDpadUpAt;
  DateTime? _lastR1At;
  DateTime? _lastReinforcementLearningAt;
  bool _r1ComboPressed = false;
  bool _dpadUpComboPressed = false;
  double _joystickVisualSide = 148;

  double get _leftAxisX =>
      _inputSuspended
          ? 0
          : (_virtualLeftActive ? _virtualLeftAxisX : _physicalLeftAxisX);

  double get _leftAxisY =>
      _inputSuspended
          ? 0
          : (_virtualLeftActive ? _virtualLeftAxisY : _physicalLeftAxisY);

  double get _rightAxisX =>
      _inputSuspended
          ? 0
          : _virtualRightActive
          ? _virtualRightAxisX
          : _physicalRightAxisRx;

  bool get _hasActiveManualInput =>
      _leftAxisX.abs() >= _axisDeadZone ||
      _leftAxisY.abs() >= _axisDeadZone ||
      _rightAxisX.abs() >= _axisDeadZone;

  String _t(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.manualCommandRestoreSignal?.addListener(_restoreActiveManualCommand);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wsChannel = context.read<WsChannel>();
      _wsChannel?.connectionReadySignal.addListener(
        _restoreActiveManualCommand,
      );
      _wsChannel?.startMunalCtrl();
    });

    unawaited(_subscribeGamepadEvents());
    _subscribeDeviceEvents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gamepadResubscribeTimer?.cancel();
    _subscription?.cancel();
    _deviceEventSubscription?.cancel();
    widget.manualCommandRestoreSignal?.removeListener(
      _restoreActiveManualCommand,
    );
    _wsChannel?.connectionReadySignal.removeListener(
      _restoreActiveManualCommand,
    );
    _physicalLeftVisual.dispose();
    _physicalRightVisual.dispose();
    _wsChannel?.stopMunalCtrl();
    super.dispose();
  }

  void _restoreActiveManualCommand() {
    if (!mounted || _inputSuspended || !_hasActiveManualInput) return;
    _lastAction = _t('恢复当前摇杆控制', 'Restore active joystick control');
    _applyGamepadControl();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inputSuspended = false;
        unawaited(_subscribeGamepadEvents());
        final wsChannel = _wsChannel;
        if (wsChannel != null) {
          wsChannel.startMunalCtrl();
        }
        _updatePhysicalLeftVisual();
        _updatePhysicalRightVisual();
        _applyGamepadControl();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _suspendManualControl();
        break;
    }
  }

  void _subscribeDeviceEvents() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _deviceEventSubscription = _deviceEventChannel
        .receiveBroadcastStream()
        .listen(_onDeviceEvent, onError: (_) {}, cancelOnError: false);
  }

  void _onDeviceEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    final deviceId = event['deviceId']?.toString();
    ControlLogStore.instance.info(
      'DEVICE',
      'type=${type ?? '-'} id=${deviceId ?? '-'} data=$event',
    );
    if ((type != 'removed' && type != 'changed') || deviceId == null) {
      return;
    }
    final removedLeft = _physicalLeftAxes.containsKey(deviceId);
    final removedRight = _physicalRightAxes.keys.any(
      (source) => source.startsWith('$deviceId:'),
    );
    if (removedLeft) {
      _physicalLeftAxes.remove(deviceId);
      if (_activePhysicalLeftDevice == deviceId) {
        _activePhysicalLeftDevice = null;
        _selectFallbackLeftDevice();
      }
    }
    if (removedRight) {
      _physicalRightAxes.removeWhere(
        (source, _) => source.startsWith('$deviceId:'),
      );
      if (_activePhysicalRightAxis?.startsWith('$deviceId:') ?? false) {
        _activePhysicalRightAxis = null;
      }
    }
    _syncPhysicalLeftAxes();
    _syncPhysicalRightAxis();
    _resetPressedButtonState();
    if (removedLeft || removedRight) {
      _applyGamepadControl();
    }
  }

  void _suspendManualControl() {
    if (_inputSuspended) return;
    _inputSuspended = true;
    _virtualLeftActive = false;
    _virtualRightActive = false;
    _virtualLeftAxisX = 0;
    _virtualLeftAxisY = 0;
    _virtualRightAxisX = 0;
    _physicalLeftAxisX = 0;
    _physicalLeftAxisY = 0;
    _physicalLeftAxes.clear();
    _activePhysicalLeftDevice = null;
    _physicalRightAxisRx = 0;
    _physicalRightAxes.clear();
    _activePhysicalRightAxis = null;
    _hatAxisX = 0;
    _hatAxisY = 0;
    _resetPressedButtonState();
    _physicalLeftVisual.value = Offset.zero;
    _physicalRightVisual.value = Offset.zero;
    _wsChannel?.stopMunalCtrl();
    widget.onCommandChanged?.call(0, 0, 0);
  }

  Future<void> _subscribeGamepadEvents() async {
    if (_gamepadSubscriptionRestarting) return;
    _gamepadSubscriptionRestarting = true;
    _gamepadResubscribeTimer?.cancel();
    _gamepadResubscribeTimer = null;
    final previousSubscription = _subscription;
    _subscription = null;
    try {
      await previousSubscription?.cancel();
      if (!mounted) return;
      _subscription = Gamepads.events.listen(
        _onGamepadEvent,
        onError: (Object error, StackTrace stackTrace) {
          ControlLogStore.instance.error(
            'GAMEPAD',
            'event stream error: $error',
          );
          _lastEventType = 'stream_error';
          _lastEventKey = '-';
          _lastEventValue = 0;
          _lastAction = _t('手柄事件流重连', 'Gamepad event stream reconnecting');
          _resetPhysicalAxes(applyControl: false);
          _resetPressedButtonState();
          _wsChannel?.stopMunalCtrl();
          _scheduleGamepadResubscribe();
        },
        onDone: () {
          ControlLogStore.instance.warning('GAMEPAD', 'event stream closed');
          _resetPhysicalAxes(applyControl: false);
          _resetPressedButtonState();
          _wsChannel?.stopMunalCtrl();
          _scheduleGamepadResubscribe();
        },
        cancelOnError: true,
      );
      if (!_inputSuspended && _wsChannel != null) {
        _wsChannel!.startMunalCtrl();
        _applyGamepadControl();
      }
    } finally {
      _gamepadSubscriptionRestarting = false;
    }
  }

  void _onGamepadEvent(GamepadEvent event) {
    final key = event.key;
    final value = event.value;
    _lastEventType = event.type.name;
    _lastEventKey = key;
    _lastEventValue = value;
    _lastAction = '-';
    ControlLogStore.instance.debugLazy(
      'INPUT',
      () =>
          'device=${event.gamepadId} type=${event.type.name} '
          'key=$key value=${value.toStringAsFixed(4)}',
    );

    if (event.type == KeyType.button) {
      _handleButtonEvent(key, value);
      return;
    }

    if (_updateAxisValue(event.gamepadId, key, value)) {
      _applyGamepadControl();
    } else {
      _emitDebugSnapshot();
    }
  }

  void _scheduleGamepadResubscribe() {
    if (!mounted || _gamepadResubscribeTimer != null) return;
    _gamepadResubscribeTimer = Timer(const Duration(seconds: 1), () {
      _gamepadResubscribeTimer = null;
      if (mounted) unawaited(_subscribeGamepadEvents());
    });
  }

  void _resetPhysicalAxes({bool applyControl = true}) {
    _physicalLeftAxisX = 0;
    _physicalLeftAxisY = 0;
    _physicalLeftAxes.clear();
    _activePhysicalLeftDevice = null;
    _physicalRightAxisRx = 0;
    _physicalRightAxes.clear();
    _activePhysicalRightAxis = null;
    if (!_virtualLeftActive) _physicalLeftVisual.value = Offset.zero;
    if (!_virtualRightActive) _physicalRightVisual.value = Offset.zero;
    if (mounted && applyControl) _applyGamepadControl();
  }

  void _resetPressedButtonState() {
    _pressedButtons.clear();
    _r1ComboPressed = false;
    _dpadUpComboPressed = false;
    _lastDpadUpAt = null;
    _lastR1At = null;
  }

  @override
  void didUpdateWidget(covariant GamepadWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manualCommandRestoreSignal !=
        widget.manualCommandRestoreSignal) {
      oldWidget.manualCommandRestoreSignal?.removeListener(
        _restoreActiveManualCommand,
      );
      widget.manualCommandRestoreSignal?.addListener(
        _restoreActiveManualCommand,
      );
    }
    if (oldWidget.showVirtualJoysticks && !widget.showVirtualJoysticks) {
      _virtualLeftActive = false;
      _virtualRightActive = false;
      _virtualLeftAxisX = 0;
      _virtualLeftAxisY = 0;
      _virtualRightAxisX = 0;
      _applyGamepadControl();
    }
  }

  static const double _axisDeadZone = 0.08;
  static const double _hatTrigger = 0.5;
  static const double _sideToolbarClearance = 72;
  static const double _bottomClearance = 24;
  static const Duration _reinforcementLearningComboWindow = Duration(
    milliseconds: 320,
  );
  static const Duration _reinforcementLearningRepeatGuard = Duration(
    milliseconds: 700,
  );

  double _safeConfigDouble(String key, double fallback) {
    final raw = globalSetting.getConfig(key).trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return fallback;
    }
    return parsed;
  }

  void _handleButtonEvent(String key, double value) {
    final isPressed = value > 0.5;
    if (_isDpadUpButton(key)) {
      if (isPressed) {
        _pressedButtons.add(key);
        _dpadUpComboPressed = true;
        _lastDpadUpAt = DateTime.now();
        if (_tryTriggerReinforcementLearning()) return;
      } else {
        _pressedButtons.remove(key);
        _dpadUpComboPressed = false;
        widget.onMappedControlPressedChanged?.call(
          GamepadMappedControl.reinforcementLearning,
          false,
        );
      }
      _lastAction = _t('方向键上组合键', 'D-pad up combo key');
      _emitDebugSnapshot();
      return;
    }

    if (_isShoulderButton(key)) {
      if (isPressed) {
        _pressedButtons.add(key);
        if (_isR1Button(key)) {
          _r1ComboPressed = true;
          _lastR1At = DateTime.now();
          if (_tryTriggerReinforcementLearning()) return;
        }
      } else {
        _pressedButtons.remove(key);
        if (_isR1Button(key)) {
          _r1ComboPressed = false;
          widget.onMappedControlPressedChanged?.call(
            GamepadMappedControl.reinforcementLearning,
            false,
          );
        }
      }
      _lastAction =
          _isR1Button(key)
              ? _t('R1组合键', 'R1 combo key')
              : _t('未绑定肩键', 'Unbound shoulder key');
      _emitDebugSnapshot();
      return;
    }

    if (!isPressed) {
      _pressedButtons.remove(key);
      final mappedControl = _mappedControlForButton(key);
      if (mappedControl != null) {
        widget.onMappedControlPressedChanged?.call(mappedControl, false);
      }
      _lastAction = _t('按钮释放', 'Button released');
      _emitDebugSnapshot();
      return;
    }
    if (!_pressedButtons.add(key)) return;
    final mappedControl = _mappedControlForButton(key);
    if (mappedControl != null) {
      widget.onMappedControlPressedChanged?.call(mappedControl, true);
    }

    switch (key) {
      case "KEYCODE_BUTTON_A":
        _lastAction = _t('站起', 'Stand');
        widget.onStand?.call();
        _emitDebugSnapshot();
        return;
      case "KEYCODE_BUTTON_B":
        _lastAction = _t('趴下', 'Lie Down');
        widget.onLieDown?.call();
        _emitDebugSnapshot();
        return;
      case "KEYCODE_BUTTON_X":
        _lastAction = _t('地图放大', 'Map zoom in');
        widget.onZoomIn?.call();
        _emitDebugSnapshot();
        return;
    }

    _lastAction = _t('未映射按钮', 'Unmapped button');
    debugPrint("unmapped gamepad button: $key value=$value");
    _emitDebugSnapshot();
  }

  GamepadMappedControl? _mappedControlForButton(String key) {
    return switch (key) {
      "KEYCODE_BUTTON_A" => GamepadMappedControl.stand,
      "KEYCODE_BUTTON_B" => GamepadMappedControl.lieDown,
      "KEYCODE_BUTTON_X" => GamepadMappedControl.zoomIn,
      _ => null,
    };
  }

  bool _isShoulderButton(String key) {
    return key == "KEYCODE_BUTTON_L1" ||
        key == "KEYCODE_BUTTON_L2" ||
        _isR1Button(key) ||
        key == "KEYCODE_BUTTON_R2";
  }

  bool _isR1Button(String key) {
    return key == "KEYCODE_BUTTON_R1" ||
        key == "BUTTON_R1" ||
        key == "R1" ||
        key == "KEYCODE_BUTTON_RB" ||
        key == "BUTTON_RB";
  }

  bool _isDpadUpButton(String key) {
    return key == "KEYCODE_DPAD_UP" ||
        key == "DPAD_UP" ||
        key == "BUTTON_DPAD_UP" ||
        key == "HAT_UP";
  }

  bool _updateAxisValue(String deviceId, String key, double value) {
    final axisValue = _normalizeAxis(value);
    switch (key) {
      case "AXIS_X":
        _virtualLeftActive = false;
        _virtualLeftAxisX = 0;
        _virtualLeftAxisY = 0;
        _updatePhysicalLeftAxis(deviceId, key, axisValue);
        _lastAction = _t('左摇杆左右', 'Left stick horizontal');
        return true;
      case "AXIS_Y":
        _virtualLeftActive = false;
        _virtualLeftAxisX = 0;
        _virtualLeftAxisY = 0;
        _updatePhysicalLeftAxis(deviceId, key, axisValue);
        _lastAction = _t('左摇杆上下', 'Left stick vertical');
        return true;
      case "AXIS_RX":
      case "AXIS_Z":
        _virtualRightActive = false;
        _virtualRightAxisX = 0;
        _updatePhysicalRightAxis(deviceId, key, axisValue);
        _lastAction =
            key == "AXIS_RX"
                ? _t('右摇杆旋转 RX', 'Right stick rotation RX')
                : _t('右摇杆旋转 Z', 'Right stick rotation Z');
        return true;
      case "AXIS_RY":
      case "AXIS_RZ":
        _lastAction = _t('当前忽略轴', 'Ignored axis');
        return false;
      case "AXIS_HAT_X":
        _hatAxisX = _normalizeHat(value);
        _lastAction = _t('方向键左右未绑定', 'D-pad horizontal unbound');
        return false;
      case "AXIS_HAT_Y":
        _hatAxisY = _normalizeHat(value);
        // gamepads_android normalizes D-pad Up to +1.
        if (_hatAxisY > 0) {
          _dpadUpComboPressed = true;
          _lastDpadUpAt = DateTime.now();
          _lastAction = _t('方向键上组合键', 'D-pad up combo key');
          return true;
        }
        _dpadUpComboPressed = false;
        widget.onMappedControlPressedChanged?.call(
          GamepadMappedControl.reinforcementLearning,
          false,
        );
        _lastAction = _t('方向键释放', 'D-pad released');
        return false;
      default:
        _lastAction = _t('未映射轴', 'Unmapped axis');
        debugPrint("unmapped gamepad axis: $key value=$value");
        return false;
    }
  }

  void _updatePhysicalLeftVisual() {
    if (_virtualLeftActive) return;
    _physicalLeftVisual.value = Offset(_physicalLeftAxisX, -_physicalLeftAxisY);
  }

  void _updatePhysicalRightVisual() {
    if (_virtualRightActive) return;
    _physicalRightVisual.value = Offset(_physicalRightAxisRx, 0);
  }

  void _updatePhysicalLeftAxis(String deviceId, String axisName, double value) {
    final axes = _physicalLeftAxes.putIfAbsent(
      deviceId,
      _PhysicalStickAxes.new,
    );
    if (axisName == 'AXIS_X') {
      axes.x = value;
    } else {
      axes.y = value;
    }

    if (value.abs() >= _axisDeadZone && _activePhysicalLeftDevice != deviceId) {
      _activePhysicalLeftDevice = deviceId;
      ControlLogStore.instance.info('INPUT', 'left stick source=$deviceId');
    }

    if (_activePhysicalLeftDevice == null && axes.isActive) {
      _activePhysicalLeftDevice = deviceId;
    }
    if (_activePhysicalLeftDevice == deviceId && !axes.isActive) {
      _selectFallbackLeftDevice(excludingDeviceId: deviceId);
    }
    _syncPhysicalLeftAxes();
  }

  void _selectFallbackLeftDevice({String? excludingDeviceId}) {
    MapEntry<String, _PhysicalStickAxes>? fallback;
    for (final entry in _physicalLeftAxes.entries) {
      if (entry.key == excludingDeviceId || !entry.value.isActive) continue;
      if (fallback == null || entry.value.strength > fallback.value.strength) {
        fallback = entry;
      }
    }
    _activePhysicalLeftDevice = fallback?.key;
  }

  void _syncPhysicalLeftAxes() {
    final axes = _physicalLeftAxes[_activePhysicalLeftDevice];
    _physicalLeftAxisX = axes?.x ?? 0;
    _physicalLeftAxisY = axes?.y ?? 0;
    _updatePhysicalLeftVisual();
  }

  void _updatePhysicalRightAxis(
    String deviceId,
    String axisName,
    double value,
  ) {
    final source = '$deviceId:$axisName';
    _physicalRightAxes[source] = value;

    if (value.abs() >= _axisDeadZone) {
      if (_activePhysicalRightAxis != source) {
        ControlLogStore.instance.info('INPUT', 'right stick source=$source');
      }
      _activePhysicalRightAxis = source;
      _physicalRightAxisRx = value;
      _updatePhysicalRightVisual();
      return;
    }

    if (_activePhysicalRightAxis != source) return;
    MapEntry<String, double>? fallback;
    for (final entry in _physicalRightAxes.entries) {
      if (entry.value.abs() < _axisDeadZone) continue;
      if (fallback == null || entry.value.abs() > fallback.value.abs()) {
        fallback = entry;
      }
    }
    _activePhysicalRightAxis = fallback?.key;
    _physicalRightAxisRx = fallback?.value ?? 0;
    _updatePhysicalRightVisual();
  }

  void _syncPhysicalRightAxis() {
    final activeValue = _physicalRightAxes[_activePhysicalRightAxis];
    if (activeValue != null && activeValue.abs() >= _axisDeadZone) {
      _physicalRightAxisRx = activeValue;
      _updatePhysicalRightVisual();
      return;
    }

    MapEntry<String, double>? fallback;
    for (final entry in _physicalRightAxes.entries) {
      if (entry.value.abs() < _axisDeadZone) continue;
      if (fallback == null || entry.value.abs() > fallback.value.abs()) {
        fallback = entry;
      }
    }
    _activePhysicalRightAxis = fallback?.key;
    _physicalRightAxisRx = fallback?.value ?? 0;
    _updatePhysicalRightVisual();
  }

  double _normalizeAxis(double value) {
    return value.abs() < _axisDeadZone ? 0 : value.clamp(-1.0, 1.0);
  }

  double _normalizeHat(double value) {
    if (value.abs() < _hatTrigger) {
      return 0;
    }
    return value > 0 ? 1 : -1;
  }

  void _applyGamepadControl() {
    if (!mounted) return;

    if (_tryTriggerReinforcementLearning()) return;

    final moveX = _leftAxisX;
    final moveY = _leftAxisY;

    final wsChannel = _wsChannel ?? context.read<WsChannel>();
    _wsChannel = wsChannel;
    wsChannel.startMunalCtrl();
    final maxVx = _safeConfigDouble('MaxVx', globalSetting.maxVx);
    final maxVy = _safeConfigDouble('MaxVy', globalSetting.maxVy);
    final maxVw = _safeConfigDouble('MaxVw', globalSetting.maxVw);

    final rotationAxis = _rightAxisX * -1;
    final rotationSource =
        rotationAxis.abs() >= _axisDeadZone
            ? _t('右摇杆', 'Right stick')
            : _t('无旋转', 'No rotation');

    final vx = maxVx * moveY;
    final vy = maxVy * moveX * -1;
    final vw = maxVw * rotationAxis;

    wsChannel.updateManualCommand(vx, vy, vw);
    ControlLogStore.instance.debugLazy(
      'COMMAND',
      () =>
          'left=(${moveX.toStringAsFixed(3)},'
          '${moveY.toStringAsFixed(3)}) '
          'right=${rotationAxis.toStringAsFixed(3)} '
          '=> vx=${vx.toStringAsFixed(3)} '
          'vy=${vy.toStringAsFixed(3)} vw=${vw.toStringAsFixed(3)}',
    );
    widget.onCommandChanged?.call(vx, vy, vw);
    _emitDebugSnapshot(
      maxVx: maxVx,
      maxVy: maxVy,
      maxVw: maxVw,
      moveX: moveX,
      moveY: moveY,
      rotationAxis: rotationAxis,
      rotationSource: rotationSource,
      vx: vx,
      vy: vy,
      vw: vw,
    );
  }

  void _applyVirtualLeftStick(StickDragDetails details) {
    _lastEventType = 'virtual_left_stick';
    _lastEventKey = 'VIRTUAL_LEFT_STICK';
    _lastEventValue = details.x.abs() > details.y.abs() ? details.x : details.y;
    _lastAction = _t('虚拟左摇杆', 'Virtual left stick');
    _virtualLeftActive = true;
    _virtualLeftAxisX = _normalizeAxis(details.x);
    _virtualLeftAxisY = _normalizeAxis(details.y) * -1;
    _hatAxisX = 0;
    _hatAxisY = 0;
    _applyGamepadControl();
  }

  void _applyVirtualRightStick(StickDragDetails details) {
    _lastEventType = 'virtual_right_stick';
    _lastEventKey = 'VIRTUAL_RIGHT_STICK';
    _lastEventValue = details.x;
    _lastAction = _t('虚拟右摇杆旋转', 'Virtual right stick rotation');
    _virtualRightActive = true;
    _virtualRightAxisX = _normalizeAxis(details.x);
    _applyGamepadControl();
  }

  void _releaseVirtualLeftStick() {
    _lastEventType = 'virtual_left_stick';
    _lastEventKey = 'VIRTUAL_LEFT_STICK_RELEASE';
    _lastEventValue = 0;
    _lastAction = _t('虚拟左摇杆释放', 'Virtual left stick released');
    _virtualLeftActive = false;
    _virtualLeftAxisX = 0;
    _virtualLeftAxisY = 0;
    _updatePhysicalLeftVisual();
    _applyGamepadControl();
  }

  void _releaseVirtualRightStick() {
    _lastEventType = 'virtual_right_stick';
    _lastEventKey = 'VIRTUAL_RIGHT_STICK_RELEASE';
    _lastEventValue = 0;
    _lastAction = _t('虚拟右摇杆释放', 'Virtual right stick released');
    _virtualRightActive = false;
    _virtualRightAxisX = 0;
    _updatePhysicalRightVisual();
    _applyGamepadControl();
  }

  bool _tryTriggerReinforcementLearning() {
    final now = DateTime.now();
    final dpadUpRecent =
        _dpadUpComboPressed ||
        _hatAxisY > 0 ||
        (_lastDpadUpAt != null &&
            now.difference(_lastDpadUpAt!) <=
                _reinforcementLearningComboWindow);
    final r1Recent =
        _r1ComboPressed ||
        (_lastR1At != null &&
            now.difference(_lastR1At!) <= _reinforcementLearningComboWindow);
    if (!dpadUpRecent || !r1Recent) return false;

    final lastTrigger = _lastReinforcementLearningAt;
    if (lastTrigger != null &&
        now.difference(lastTrigger) < _reinforcementLearningRepeatGuard) {
      return true;
    }

    _lastReinforcementLearningAt = now;
    widget.onMappedControlPressedChanged?.call(
      GamepadMappedControl.reinforcementLearning,
      true,
    );
    _lastAction = _t('强化学习', 'Reinforcement Learning');
    _hatAxisY = 0;
    _dpadUpComboPressed = false;
    _lastDpadUpAt = null;
    final wsChannel = _wsChannel ?? context.read<WsChannel>();
    _wsChannel = wsChannel;
    wsChannel.setVx(0);
    wsChannel.setVy(0);
    wsChannel.setVw(0);
    widget.onReinforcementLearning?.call();
    widget.onCommandChanged?.call(0, 0, 0);
    _emitDebugSnapshot(
      moveX: 0,
      moveY: 0,
      rotationAxis: 0,
      rotationSource: _t('方向键上 + R1', 'D-pad up + R1'),
      vx: 0,
      vy: 0,
      vw: 0,
    );
    return true;
  }

  void _emitDebugSnapshot({
    double? maxVx,
    double? maxVy,
    double? maxVw,
    double? moveX,
    double? moveY,
    double? rotationAxis,
    String? rotationSource,
    double? vx,
    double? vy,
    double? vw,
  }) {
    final ws = _wsChannel;
    widget.onDebugChanged?.call(
      GamepadDebugSnapshot(
        eventType: _lastEventType,
        eventKey: _lastEventKey,
        eventValue: _lastEventValue,
        action: _lastAction,
        leftAxisX: _leftAxisX,
        leftAxisY: _leftAxisY,
        rightAxisX: _rightAxisX,
        hatAxisX: _hatAxisX,
        hatAxisY: _hatAxisY,
        moveX: moveX ?? _leftAxisX,
        moveY: moveY ?? _leftAxisY,
        rotationAxis: rotationAxis ?? 0,
        rotationSource: rotationSource ?? _t('无旋转', 'No rotation'),
        pressedButtons: _pressedButtons.toList()..sort(),
        maxVx: maxVx ?? _safeConfigDouble('MaxVx', globalSetting.maxVx),
        maxVy: maxVy ?? _safeConfigDouble('MaxVy', globalSetting.maxVy),
        maxVw: maxVw ?? _safeConfigDouble('MaxVw', globalSetting.maxVw),
        vx: vx ?? ws?.cmdVel_.vx ?? 0,
        vy: vy ?? ws?.cmdVel_.vy ?? 0,
        vw: vw ?? ws?.cmdVel_.vw ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showVirtualJoysticks) {
      return const SizedBox.expand();
    }

    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            (constraints.maxWidth * 0.16).clamp(118.0, 158.0).toDouble();
        _joystickVisualSide = side;
        final bottom = _bottomClearance + pad.bottom + 86;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: _sideToolbarClearance + pad.left,
              bottom: bottom,
              width: side,
              height: side,
              child: _buildVirtualJoystick(
                mode: JoystickMode.all,
                controller: _leftJoystickController,
                label: _t('移动', 'Move'),
                accent: Theme.of(context).colorScheme.primary,
                onStickDragStart: () {
                  _virtualLeftActive = true;
                  _virtualLeftAxisX = 0;
                  _virtualLeftAxisY = 0;
                  _physicalLeftVisual.value = Offset.zero;
                },
                listener: _applyVirtualLeftStick,
                onStickDragEnd: _releaseVirtualLeftStick,
                physicalVisual: _physicalLeftVisual,
              ),
            ),
            Positioned(
              right: _sideToolbarClearance + pad.right,
              bottom: bottom,
              width: side,
              height: side,
              child: _buildVirtualJoystick(
                mode: JoystickMode.horizontal,
                controller: _rightJoystickController,
                label: _t('旋转', 'Rotate'),
                accent: Theme.of(context).colorScheme.primary,
                onStickDragStart: () {
                  _virtualRightActive = true;
                  _virtualRightAxisX = 0;
                  _physicalRightVisual.value = Offset.zero;
                },
                listener: _applyVirtualRightStick,
                onStickDragEnd: _releaseVirtualRightStick,
                physicalVisual: _physicalRightVisual,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVirtualJoystick({
    required JoystickMode mode,
    required JoystickController controller,
    required String label,
    required Color accent,
    required VoidCallback onStickDragStart,
    required StickDragCallback listener,
    required VoidCallback onStickDragEnd,
    required ValueListenable<Offset> physicalVisual,
  }) {
    return Listener(
      onPointerCancel: (_) => onStickDragEnd(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.08),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Joystick(
              controller: controller,
              mode: mode,
              period: const Duration(milliseconds: 20),
              includeInitialAnimation: false,
              onStickDragStart: () {
                onStickDragStart();
                final wsChannel = _wsChannel ?? context.read<WsChannel>();
                _wsChannel = wsChannel;
                wsChannel.startMunalCtrl();
              },
              onStickDragEnd: onStickDragEnd,
              listener: listener,
              base: JoystickBase(
                mode: mode,
                size: _joystickVisualSide,
                decoration: JoystickBaseDecoration(
                  drawArrows: true,
                  outerCircleColor: accent.withValues(alpha: 0.36),
                  middleCircleColor: accent.withValues(alpha: 0.22),
                  innerCircleColor: accent.withValues(alpha: 0.12),
                  boxShadowColor: accent.withValues(alpha: 0.16),
                ),
                arrowsDecoration: JoystickArrowsDecoration(
                  color: accent.withValues(alpha: 0.56),
                  enableAnimation: false,
                ),
              ),
              stick: ValueListenableBuilder<Offset>(
                valueListenable: physicalVisual,
                builder: (context, axis, child) {
                  final travel = _joystickVisualSide * 0.33;
                  return Transform.translate(
                    offset: Offset(axis.dx * travel, axis.dy * travel),
                    child: child,
                  );
                },
                child: JoystickStick(
                  size: _joystickVisualSide * 0.34,
                  decoration: JoystickStickDecoration(
                    color: accent.withValues(alpha: 0.68),
                    shadowColor: accent.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _joystickVisualSide * 0.16),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: _joystickVisualSide * 0.12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
