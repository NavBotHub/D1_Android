import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:navbot_d1_flutter/global/setting.dart';
import 'package:navbot_d1_flutter/provider/global_state.dart';

import 'package:flutter/material.dart';
import 'package:navbot_d1_flutter/page/control_log_page.dart';
import 'package:provider/provider.dart';
import 'package:navbot_d1_flutter/page/main_page.dart';
import 'package:navbot_d1_flutter/page/connect_page.dart';
import 'package:navbot_d1_flutter/provider/http_channel.dart';
import 'package:navbot_d1_flutter/provider/ws_channel.dart';
import 'package:navbot_d1_flutter/provider/control_log_store.dart';
import 'package:navbot_d1_flutter/page/setting_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:navbot_d1_flutter/language/l10n/gen/app_localizations.dart';

import 'package:oktoast/oktoast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGlobalSetting();
  ControlLogStore.instance.setEnabled(globalSetting.controlLogEnabled);

  // 设置全局错误处理
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter Error: ${details.exception}');
    print('Stack trace: ${details.stack}');
  };

  // 捕获未处理的异步异常
  PlatformDispatcher.instance.onError = (error, stack) {
    print('Unhandled async error: $error');
    print('Stack trace: $stack');
    return true; // 防止程序崩溃
  };

  await _setInitialOrientation();
  runApp(
    MultiProvider(
      providers: [
        Provider<WsChannel>(
          create: (_) => WsChannel(),
          dispose: (_, channel) => channel.dispose(),
        ),
        Provider<HttpChannel>(create: (_) => HttpChannel()),
        ChangeNotifierProvider<GlobalState>(create: (_) => GlobalState()),
      ],
      child: MyApp(),
    ),
  );
}

Future<void> _enableWakelockSafe() async {
  try {
    await WakelockPlus.toggle(enable: true);
  } catch (_) {}
}

Future<void> _setInitialOrientation() async {
  final prefs = globalSetting.config;
  final orientationValue = prefs.getString('screenOrientation') ?? 'landscape';
  if (orientationValue == 'portrait') {
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

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = Locale('en'); // 默认语言

  @override
  void initState() {
    super.initState();
    _loadLocale();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    unawaited(_enableWakelockSafe());

    // 将 globalSetting.setLanguage 的赋值移到 initState 中
    globalSetting.setLanguage = (Locale locale) {
      setState(() {
        _locale = locale;
      });
    };
  }

  Future<void> _loadLocale() async {
    final prefs = globalSetting.config;
    final languageCode = prefs.getString('language') ?? 'en';
    setState(() {
      _locale = Locale(languageCode);
    });
  }

  void setLocale(Locale newLocale) {
    _locale = newLocale;
  }

  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: 'Navbot Robot',
        debugShowCheckedModeBanner: false,
        locale: _locale, // 设置应用的语言
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('en'), // English
          Locale('zh'), // Chinese
        ],
        initialRoute: "/connect",
        routes: {
          "/connect": ((context) => ConnectPage()),
          "/map": ((context) => MainFlamePage()),
          "/control-log": ((context) => const ControlLogPage()),
          "/setting": ((context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            return SettingsPage(
              scrollToLayerSection: args == kSettingsRouteArgLayers,
            );
          }),
          // "/gamepad":((context) => GamepadPage()),
        },
        themeMode: ThemeMode.light,
        theme: ThemeData(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: Colors.blue,
            secondary: Colors.blue[50],
            background: Color.fromRGBO(240, 240, 240, 1),
            surface: Color.fromARGB(153, 224, 224, 224),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue, width: 2.0),
            ),
          ),
          iconTheme: IconThemeData(
            color: Colors.black, // 设置全局图标颜色为绿色
          ),
          cardColor: Color.fromRGBO(230, 230, 230, 1),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: AppBarTheme(elevation: 0),
          chipTheme: ThemeData.light().chipTheme.copyWith(
            backgroundColor: Colors.white,
            elevation: 10.0,
            shape: StadiumBorder(
              side: BorderSide(
                color: Colors.grey[300]!, // 设置边框颜色
                width: 1.0, // 设置边框宽度
              ),
            ),
          ),
        ),
      ),
    );
  }
}
