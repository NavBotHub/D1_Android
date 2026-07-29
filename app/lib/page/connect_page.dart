import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:toastification/toastification.dart';
import 'package:navbot_d1_flutter/language/l10n/gen/app_localizations.dart';

const bool kSkipRosConnectForDebug = false;

enum _ConnectionMode { address, d1Hotspot }

class _ConnectionEndpoint {
  const _ConnectionEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  String get authority => '$host:$port';
  String get webSocketUrl => 'ws://$authority/ws/robot';
}

class ConnectPage extends StatefulWidget {
  @override
  _ConnectPageState createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _ipController = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _portController = TextEditingController(
    text: '8081',
  );
  bool _isConnecting = false;
  bool _awaitingWifiSettingsReturn = false;
  bool _wifiSettingsWasBackgrounded = false;
  bool _hotspotCheckFailed = false;
  _ConnectionMode _connectionMode = _ConnectionMode.address;
  late final Future<bool> _settingsFuture;
  late AnimationController _animationController;
  late CurvedAnimation _fadeAnimation;
  late AnimationController _connectShineController;

  static const String _d1HotspotHost = '192.168.50.1';
  static const int _d1HotspotPort = 8081;
  static const Color _brandBlue = Color(0xFF2196F3);
  static const Color _brandBlueDark = Color(0xFF1976D2);
  static const Color _pageBackground = Color(0xFFF8FAFD);
  static const Color _ink = Color(0xFF172033);
  static const Color _mutedInk = Color(0xFF657184);
  static const Color _softBorder = Color(0xFFDCE4EE);
  static const MethodChannel _systemSettingsChannel = MethodChannel(
    'navbot/system_settings',
  );

  bool get _isAndroidApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isMobileApp =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsFuture = initGlobalSetting();
    unawaited(
      _settingsFuture.then((_) {
        if (!mounted) return;
        setState(() {
          _ipController.text = globalSetting.robotIp;
          _portController.text = globalSetting.httpServerPort;
          _connectionMode =
              globalSetting.config.getString('connectionMode') == 'd1Hotspot'
                  ? _ConnectionMode.d1Hotspot
                  : _ConnectionMode.address;
        });
      }),
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
    _connectShineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _connectShineController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_awaitingWifiSettingsReturn) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wifiSettingsWasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wifiSettingsWasBackgrounded) {
      _awaitingWifiSettingsReturn = false;
      _wifiSettingsWasBackgrounded = false;
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted ||
            _connectionMode != _ConnectionMode.d1Hotspot ||
            _isConnecting) {
          return;
        }
        unawaited(_handleConnect());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: FutureBuilder<bool>(
        future: _settingsFuture,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ConnectLoadingScreen();
          } else if (snapshot.hasError) {
            return ColoredBox(
              color: _pageBackground,
              child: Center(
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.init_error(snapshot.error.toString()),
                  style: const TextStyle(color: _ink),
                ),
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              const _LightConnectBackground(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildCenteredLayout(context, constraints),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenteredLayout(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final mobileApp = _isMobileApp;
    final compact = constraints.maxWidth < 700;
    final topInset =
        mobileApp ? (compact ? 88.0 : 104.0) : (compact ? 78.0 : 86.0);
    final bottomInset =
        mobileApp ? (compact ? 20.0 : 30.0) : (compact ? 18.0 : 28.0);
    final availableHeight = constraints.maxHeight - topInset - bottomInset;
    return Stack(
      children: [
        Positioned(
          top: mobileApp ? (compact ? 18 : 26) : (compact ? 18 : 28),
          left: compact ? 0 : (mobileApp ? 32 : 40),
          right: compact ? 0 : null,
          child: Align(
            alignment: compact ? Alignment.topCenter : Alignment.topLeft,
            child: _buildBrandHeader(
              logoHeight: mobileApp ? (compact ? 46 : 54) : (compact ? 36 : 44),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              mobileApp ? (compact ? 18 : 30) : (compact ? 16 : 28),
              topInset,
              mobileApp ? (compact ? 18 : 30) : (compact ? 16 : 28),
              bottomInset,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: availableHeight > 0 ? availableHeight : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: mobileApp ? 640 : 520),
                  child: _buildConnectionPanel(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandHeader({required double logoHeight}) {
    return Image.asset(
      'assets/icons/navbot-logo.png',
      height: logoHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'NavBot',
    );
  }

  Widget _buildConnectionPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mobileApp = _isMobileApp;
    return Container(
      padding:
          mobileApp
              ? const EdgeInsets.fromLTRB(30, 28, 30, 28)
              : const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(mobileApp ? 22 : 20),
        border: Border.all(color: _softBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF18324D).withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: mobileApp ? 52 : 42,
                height: mobileApp ? 52 : 42,
                decoration: BoxDecoration(
                  color: _brandBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(mobileApp ? 15 : 12),
                  border: Border.all(color: _brandBlue.withValues(alpha: 0.20)),
                ),
                child: Icon(
                  Icons.hub_rounded,
                  color: _brandBlue,
                  size: mobileApp ? 27 : 21,
                ),
              ),
              SizedBox(width: mobileApp ? 16 : 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.connect_robot,
                      style: TextStyle(
                        color: _ink,
                        fontSize: mobileApp ? 25 : 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: mobileApp ? -0.45 : -0.35,
                      ),
                    ),
                    SizedBox(height: mobileApp ? 5 : 3),
                    Text(
                      l10n.connect_robot_subtitle,
                      style: TextStyle(
                        color: _mutedInk,
                        fontSize: mobileApp ? 15 : 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              _LiveIndicator(large: mobileApp),
            ],
          ),
          SizedBox(height: mobileApp ? 27 : 22),
          _buildConnectionModeSelector(context, _brandBlue),
          SizedBox(height: mobileApp ? 20 : 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child:
                _connectionMode == _ConnectionMode.address
                    ? _buildAddressConnectionForm(context, _brandBlue)
                    : _buildHotspotConnectionCard(context, _brandBlue),
          ),
          SizedBox(height: mobileApp ? 21 : 17),
          _buildPrimaryButton(context),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mobileApp = _isMobileApp;
    final label =
        _connectionMode == _ConnectionMode.d1Hotspot
            ? _isAndroidApp
                ? l10n.connection_hotspot_open_wifi
                : l10n.connection_hotspot_connect
            : l10n.connect_robot;
    return SizedBox(
      width: double.infinity,
      height: mobileApp ? 64 : 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors:
                _isConnecting
                    ? const [Color(0xFF9EADBA), Color(0xFF8798A8)]
                    : const [_brandBlueDark, _brandBlue],
          ),
          borderRadius: BorderRadius.circular(mobileApp ? 17 : 15),
          boxShadow:
              _isConnecting
                  ? null
                  : [
                    BoxShadow(
                      color: _brandBlue.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isConnecting ? null : _handlePrimaryAction,
            borderRadius: BorderRadius.circular(mobileApp ? 17 : 15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child:
                      _isConnecting
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                          : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _connectionMode == _ConnectionMode.d1Hotspot &&
                                        _isAndroidApp
                                    ? Icons.settings_rounded
                                    : Icons.bolt_rounded,
                                color: Colors.white,
                                size: mobileApp ? 23 : 19,
                              ),
                              SizedBox(width: mobileApp ? 10 : 8),
                              Text(
                                label,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: mobileApp ? 18 : 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                ),
                if (!_isConnecting)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _connectShineController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _ConnectButtonShinePainter(
                            progress: _connectShineController.value,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionModeSelector(
    BuildContext context,
    Color primaryColor,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final mobileApp = _isMobileApp;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_ConnectionMode>(
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        segments: [
          ButtonSegment<_ConnectionMode>(
            value: _ConnectionMode.address,
            enabled: !_isConnecting,
            icon: Icon(Icons.link_rounded, size: mobileApp ? 22 : 18),
            label: Text(
              l10n.connection_address_mode,
              style: TextStyle(
                fontSize: mobileApp ? 16 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ButtonSegment<_ConnectionMode>(
            value: _ConnectionMode.d1Hotspot,
            enabled: !_isConnecting,
            icon: Icon(Icons.wifi_tethering_rounded, size: mobileApp ? 22 : 18),
            label: Text(
              l10n.connection_hotspot_mode,
              style: TextStyle(
                fontSize: mobileApp ? 16 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        selected: {_connectionMode},
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? primaryColor
                    : _mutedInk,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? primaryColor.withValues(alpha: 0.10)
                    : const Color(0xFFF5F7FA),
          ),
          side: WidgetStatePropertyAll(const BorderSide(color: _softBorder)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: mobileApp ? 15 : 12,
              vertical: mobileApp ? 16 : 12,
            ),
          ),
          visualDensity:
              mobileApp ? VisualDensity.standard : VisualDensity.compact,
        ),
        onSelectionChanged: (selection) {
          if (selection.isEmpty || _isConnecting) return;
          final mode = selection.first;
          setState(() {
            _connectionMode = mode;
            _hotspotCheckFailed = false;
          });
          unawaited(
            globalSetting.config.setString('connectionMode', mode.name),
          );
        },
      ),
    );
  }

  Widget _buildAddressConnectionForm(BuildContext context, Color primaryColor) {
    final l10n = AppLocalizations.of(context)!;
    return KeyedSubtree(
      key: const ValueKey<String>('address-connection'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final addressField = _FrostedTextField(
            controller: _ipController,
            labelText: l10n.connection_address,
            hintText: l10n.connection_address_hint,
            prefixIcon: Icons.language_rounded,
            textInputAction: TextInputAction.next,
            tintColor: primaryColor,
            large: _isMobileApp,
          );
          final portField = _FrostedTextField(
            controller: _portController,
            labelText: l10n.port,
            hintText: '8081',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleConnect(),
            tintColor: primaryColor,
            large: _isMobileApp,
          );

          if (constraints.maxWidth < 430) {
            return Column(
              children: [addressField, const SizedBox(height: 12), portField],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: addressField),
              const SizedBox(width: 12),
              Expanded(child: portField),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHotspotConnectionCard(BuildContext context, Color primaryColor) {
    final l10n = AppLocalizations.of(context)!;
    final mobileApp = _isMobileApp;
    const endpoint = _ConnectionEndpoint(
      host: _d1HotspotHost,
      port: _d1HotspotPort,
    );
    return Container(
      key: const ValueKey<String>('d1-hotspot-connection'),
      width: double.infinity,
      padding: EdgeInsets.all(mobileApp ? 18 : 14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(mobileApp ? 18 : 16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: mobileApp ? 52 : 42,
            height: mobileApp ? 52 : 42,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(mobileApp ? 15 : 13),
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: _brandBlue,
              size: mobileApp ? 27 : 22,
            ),
          ),
          SizedBox(width: mobileApp ? 15 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.connection_hotspot_title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    fontSize: mobileApp ? 18 : null,
                  ),
                ),
                SizedBox(height: mobileApp ? 6 : 4),
                Text(
                  _isAndroidApp
                      ? l10n.connection_hotspot_app_description
                      : l10n.connection_hotspot_web_description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: _mutedInk,
                    fontSize: mobileApp ? 15 : null,
                  ),
                ),
                SizedBox(height: mobileApp ? 13 : 10),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: mobileApp ? 13 : 10,
                    vertical: mobileApp ? 10 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _softBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.electrical_services_rounded,
                        size: mobileApp ? 18 : 15,
                        color: primaryColor,
                      ),
                      SizedBox(width: mobileApp ? 8 : 6),
                      Flexible(
                        child: Text(
                          endpoint.webSocketUrl,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: _ink,
                            fontSize: mobileApp ? 14 : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAndroidApp) ...[
                  SizedBox(height: mobileApp ? 13 : 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: mobileApp ? 13 : 10,
                      vertical: mobileApp ? 11 : 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _hotspotCheckFailed
                              ? const Color(0xFFFFE9EC)
                              : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            _hotspotCheckFailed
                                ? const Color(0xFFFFB3BD)
                                : _softBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hotspotCheckFailed
                              ? Icons.info_outline_rounded
                              : Icons.auto_mode_rounded,
                          size: mobileApp ? 19 : 16,
                          color:
                              _hotspotCheckFailed
                                  ? const Color(0xFFD9394C)
                                  : _brandBlue,
                        ),
                        SizedBox(width: mobileApp ? 9 : 7),
                        Expanded(
                          child: Text(
                            _hotspotCheckFailed
                                ? l10n.connection_hotspot_retry_hint
                                : l10n.connection_hotspot_auto_hint,
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color:
                                  _hotspotCheckFailed
                                      ? const Color(0xFF9F2635)
                                      : _mutedInk,
                              height: 1.25,
                              fontSize: mobileApp ? 14 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: mobileApp ? 6 : 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _isConnecting ? null : _handleConnect,
                      style: TextButton.styleFrom(
                        foregroundColor: _brandBlue,
                        disabledForegroundColor: _mutedInk.withValues(
                          alpha: 0.50,
                        ),
                      ),
                      icon:
                          _isConnecting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Icon(
                                Icons.refresh_rounded,
                                size: mobileApp ? 21 : 18,
                              ),
                      label: Text(
                        _isConnecting
                            ? l10n.connection_hotspot_checking
                            : l10n.connection_hotspot_check_now,
                        style: TextStyle(
                          fontSize: mobileApp ? 15 : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _ConnectionEndpoint _resolveConnectionEndpoint() {
    if (_connectionMode == _ConnectionMode.d1Hotspot) {
      return const _ConnectionEndpoint(
        host: _d1HotspotHost,
        port: _d1HotspotPort,
      );
    }

    final rawAddress = _ipController.text.trim();
    final fallbackPort = int.tryParse(_portController.text.trim());
    if (rawAddress.isEmpty ||
        fallbackPort == null ||
        fallbackPort < 1 ||
        fallbackPort > 65535) {
      throw const FormatException('invalid address or port');
    }

    final hasScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(rawAddress);
    final uri = Uri.tryParse(hasScheme ? rawAddress : 'http://$rawAddress');
    if (uri == null || uri.host.trim().isEmpty) {
      throw const FormatException('invalid address');
    }
    if (hasScheme &&
        !const {
          'http',
          'https',
          'ws',
          'wss',
        }.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('unsupported scheme');
    }

    final port =
        hasScheme || _hasExplicitPort(rawAddress) ? uri.port : fallbackPort;
    if (port < 1 || port > 65535) {
      throw const FormatException('invalid port');
    }
    return _ConnectionEndpoint(host: uri.host, port: port);
  }

  bool _hasExplicitPort(String address) {
    if (address.startsWith('[')) {
      final bracket = address.indexOf(']');
      return bracket >= 0 &&
          bracket + 1 < address.length &&
          address[bracket + 1] == ':';
    }
    return ':'.allMatches(address).length == 1;
  }

  Future<void> _handlePrimaryAction() async {
    if (_connectionMode == _ConnectionMode.d1Hotspot && _isAndroidApp) {
      await _openWifiSettings();
      return;
    }
    await _handleConnect();
  }

  Future<void> _openWifiSettings() async {
    setState(() {
      _awaitingWifiSettingsReturn = true;
      _wifiSettingsWasBackgrounded = false;
      _hotspotCheckFailed = false;
    });
    try {
      await _systemSettingsChannel.invokeMethod<void>('openWifiSettings');
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _awaitingWifiSettingsReturn = false;
        _wifiSettingsWasBackgrounded = false;
      });
      toastification.show(
        context: context,
        title: Text(
          AppLocalizations.of(context)!.connection_hotspot_open_wifi_failed,
        ),
        autoCloseDuration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _handleConnect() async {
    setState(() {
      _isConnecting = true;
      if (_connectionMode == _ConnectionMode.d1Hotspot) {
        _hotspotCheckFailed = false;
      }
    });
    try {
      late final _ConnectionEndpoint endpoint;
      try {
        endpoint = _resolveConnectionEndpoint();
      } on FormatException {
        if (!context.mounted) return;
        toastification.show(
          context: context,
          title: Text(AppLocalizations.of(context)!.connection_address_invalid),
          autoCloseDuration: const Duration(seconds: 4),
        );
        return;
      }

      final provider = Provider.of<WsChannel>(context, listen: false);
      globalSetting.setRobotIp(endpoint.host);
      globalSetting.setHttpServerPort(endpoint.port.toString());
      globalSetting.setRobotPort(endpoint.port.toString());
      unawaited(
        globalSetting.config.setString('connectionMode', _connectionMode.name),
      );

      if (!kSkipRosConnectForDebug) {
        final err = await provider.connectBackend(endpoint.host, endpoint.port);
        if (err.isNotEmpty) {
          if (!context.mounted) {
            return;
          }
          if (_connectionMode == _ConnectionMode.d1Hotspot && _isAndroidApp) {
            setState(() => _hotspotCheckFailed = true);
          }
          toastification.show(
            context: context,
            title: Text(AppLocalizations.of(context)!.connection_failed(err)),
            autoCloseDuration: const Duration(seconds: 5),
          );
          return;
        }
      }

      if (!context.mounted) {
        return;
      }
      Navigator.pushNamed(context, "/map");
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}

class _ConnectLoadingScreen extends StatelessWidget {
  const _ConnectLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF8FAFD),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _LightConnectBackground(),
          Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Color(0xFF2196F3),
                strokeWidth: 2.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LightConnectBackground extends StatelessWidget {
  const _LightConnectBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(surface, scheme.primary, 0.10)!,
                  Color.lerp(surface, scheme.primary, 0.06)!,
                  Color.lerp(surface, scheme.secondary, 0.05)!,
                  Color.lerp(surface, scheme.tertiary, 0.04)!,
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          _CyberBezierBackdrop(
            seedColor: scheme.primary,
            surfaceColor: surface,
            brightness: Theme.of(context).brightness,
          ),
          Positioned(
            left: -80,
            top: -70,
            child: _SoftGlowBlob(
              diameter: 240,
              color: scheme.tertiary.withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            right: -90,
            bottom: -80,
            child: _SoftGlowBlob(
              diameter: 260,
              color: scheme.primary.withValues(alpha: 0.20),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftGlowBlob extends StatelessWidget {
  const _SoftGlowBlob({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _CyberBezierBackdrop extends StatefulWidget {
  const _CyberBezierBackdrop({
    required this.seedColor,
    required this.surfaceColor,
    required this.brightness,
  });

  final Color seedColor;
  final Color surfaceColor;
  final Brightness brightness;

  @override
  State<_CyberBezierBackdrop> createState() => _CyberBezierBackdropState();
}

class _CyberBezierBackdropState extends State<_CyberBezierBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6400),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ZigzagFlowBackdropPainter(
        animation: _flowController,
        seedColor: widget.seedColor,
        surfaceColor: widget.surfaceColor,
        brightness: widget.brightness,
      ),
    );
  }
}

class _ZigzagFlowBackdropPainter extends CustomPainter {
  _ZigzagFlowBackdropPainter({
    required this.animation,
    required this.seedColor,
    required this.surfaceColor,
    required this.brightness,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color seedColor;
  final Color surfaceColor;
  final Brightness brightness;

  static Path _flowBackdropPath(Size size) {
    final width = size.width;
    final height = size.height;
    return Path()
      ..moveTo(width * 0.08, height * 0.22)
      ..quadraticBezierTo(
        width * 0.26,
        height * 0.12,
        width * 0.40,
        height * 0.20,
      )
      ..quadraticBezierTo(
        width * 0.62,
        height * 0.30,
        width * 0.86,
        height * 0.16,
      )
      ..quadraticBezierTo(
        width * 0.92,
        height * 0.52,
        width * 0.72,
        height * 0.64,
      )
      ..quadraticBezierTo(
        width * 0.50,
        height * 0.78,
        width * 0.18,
        height * 0.70,
      );
  }

  void _paintGrid(Canvas canvas, Size size, Color base, bool isDark) {
    final gridPaint =
        Paint()
          ..color = (isDark ? Colors.white : base).withValues(
            alpha: isDark ? 0.048 : 0.058,
          )
          ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _paintStaticRail(Canvas canvas, Path path, Color base, bool isDark) {
    final track =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.2
          ..color = base.withValues(alpha: isDark ? 0.14 : 0.12);
    canvas.drawPath(path, track);
  }

  void _paintFlowPulse(Canvas canvas, Path path, double phase, Color neon) {
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      if (length < 24) continue;
      final head = (phase * length) % length;
      final tail = length * 0.12;
      final tailStart = head - tail;

      final glow =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 6
            ..color = neon.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      final core =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.2
            ..color = neon.withValues(alpha: 0.92);
      final headDot =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      void drawRange(double start, double end) {
        if (end <= start) return;
        final segment = metric.extractPath(start, end);
        canvas.drawPath(segment, glow);
        canvas.drawPath(segment, core);
      }

      if (tailStart >= 0) {
        drawRange(tailStart, head);
      } else {
        drawRange(0, head);
        drawRange(length + tailStart, length);
      }

      final tangent = metric.getTangentForOffset(head);
      if (tangent != null) {
        canvas.drawCircle(tangent.position, 4.5, headDot);
        canvas.drawCircle(tangent.position, 2.4, Paint()..color = neon);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    _paintGrid(canvas, size, seedColor, isDark);

    final track = _flowBackdropPath(size);
    _paintStaticRail(canvas, track, seedColor, isDark);

    final pulse = Color.lerp(Colors.cyanAccent, seedColor, 0.38)!;
    _paintFlowPulse(canvas, track, animation.value, pulse);
  }

  @override
  bool shouldRepaint(covariant _ZigzagFlowBackdropPainter oldDelegate) {
    return oldDelegate.seedColor != seedColor ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.brightness != brightness ||
        oldDelegate.animation != animation;
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator({this.large = false});

  final bool large;

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      lowerBound: 0.35,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.large ? 11 : 9,
        vertical: widget.large ? 7 : 6,
      ),
      // decoration: BoxDecoration(
      //   color: const Color(0xFFF4F8FC),
      //   borderRadius: BorderRadius.circular(999),
      //   border: Border.all(color: const Color(0xFFDCE4EE)),
      // ),
      // child: Row(
      //   mainAxisSize: MainAxisSize.min,
      //   children: [
      //     FadeTransition(
      //       opacity: _controller,
      //       child: Container(
      //         width: widget.large ? 8 : 6,
      //         height: widget.large ? 8 : 6,
      //         decoration: const BoxDecoration(
      //           color: Color(0xFF35B458),
      //           shape: BoxShape.circle,
      //         ),
      //       ),
      //     ),
      //     SizedBox(width: widget.large ? 7 : 6),
      //     Text(
      //       'READY',
      //       style: TextStyle(
      //         color: Color(0xFF536274),
      //         fontSize: widget.large ? 11 : 9,
      //         fontWeight: FontWeight.w800,
      //         letterSpacing: 1.1,
      //       ),
      //     ),
      //   ],
      // ),
    );
  }
}

class _ConnectButtonShinePainter extends CustomPainter {
  _ConnectButtonShinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint =
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = LinearGradient(
            begin: Alignment(-1.35 + progress * 2.7, -1.1),
            end: Alignment(-0.25 + progress * 2.7, 1.1),
            colors: <Color>[
              Colors.transparent,
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.38),
              Colors.white.withValues(alpha: 0.58),
              Colors.white.withValues(alpha: 0.38),
              Colors.white.withValues(alpha: 0.0),
              Colors.transparent,
            ],
            stops: const <double>[0.0, 0.38, 0.46, 0.5, 0.54, 0.62, 1.0],
          ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectButtonShinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _FrostedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Color tintColor;
  final bool large;

  const _FrostedTextField({
    required this.controller,
    required this.labelText,
    required this.tintColor,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    const fill = Color(0xFFF7F9FC);
    const border = Color(0xFFDCE4EE);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      cursorColor: const Color(0xFF2196F3),
      style: TextStyle(
        color: const Color(0xFF172033),
        fontSize: large ? 17 : 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        labelStyle: TextStyle(
          color: const Color(0xFF657184),
          fontSize: large ? 15 : 13,
        ),
        floatingLabelStyle: TextStyle(
          color: tintColor,
          fontSize: large ? 15 : 13,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          fontSize: large ? 14 : 12,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF9AA5B4),
        ),
        isDense: true,
        prefixIcon:
            prefixIcon == null
                ? null
                : Icon(
                  prefixIcon,
                  size: large ? 22 : 18,
                  color: const Color(0xFF2196F3),
                ),
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: tintColor.withValues(alpha: 0.75),
            width: 1.2,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: large ? 16 : 12,
          vertical: large ? 17 : 12,
        ),
      ),
    );
  }
}
