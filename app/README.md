# NavBot RobotFlutter Frontend

[中文](README_ZH.md) · [Repository home](../README.md)

`app` is the main project in this repository. It contains the Flutter client, platform projects, local gamepad plugins, assets, and generated Dart protobuf code.

This directory does not build or deploy robot-side software. Before running the app, make sure the target robot already exposes the compatible endpoints listed below.

Companion robot-side deployment: [D1_Backend](https://gitee.com/lookc4/D1_Backend).

## 1. Environment

Recommended versions:

- Flutter `3.44.8`
- Dart `>=3.12.0 <4.0.0`
- JDK 17 for Android builds

Check the environment and fetch dependencies:

```bash
flutter doctor
cd app
flutter pub get
```

`lib/protobuf/` already contains the generated code needed by the current client. Normal builds do not require `protoc`.

Android and Windows gamepad packages use local implementations under `thirdparty/` through `dependency_overrides` in `pubspec.yaml`. Keep these directories when copying or publishing the source.

## 2. Run

List available devices:

```bash
flutter devices
```

Run on a target:

```bash
flutter run
flutter run -d chrome
flutter run -d windows
```

The app opens on the connection screen with two modes:

- **Address**: enter an IP, `host:port`, HTTP URL, or full WebSocket URL; the client extracts the host and port.
- **Robot Hotspot**: on the web, join the hotspot manually before connecting. The Android app opens the system Wi-Fi list and automatically checks the default `192.168.50.1:8081` after you return.

Connection flow:

1. Load UI and topic settings from `GET /api/settings`.
2. Open the `/ws/robot` binary WebSocket.
3. Enter the main screen and send one zero-velocity packet.
4. Clear motion state and reconnect if the connection closes or no message arrives for more than 10 seconds.

## 3. Build

### Android

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Web

```bash
flutter build web --release
```

Output:

```text
build/web/
```

### Windows

```bash
flutter build windows --release
```

### Linux

```bash
flutter build linux --release
```

macOS and iOS targets require a macOS build environment.

## 4. Network interfaces used by the client

Addresses are based on the robot IP entered on the connection screen:

| Feature | Method or address |
| --- | --- |
| Load/save settings | `GET/POST http://<IP>:8081/api/settings` |
| State and control | `ws://<IP>:8081/ws/robot` |
| Navigation goal | `POST /robot/nav_goal` |
| Relocation | `POST /robot/initial_pose` |
| Cancel navigation | `POST /robot/cancel_nav` |
| Compatibility action API | `POST /robot/action_cmd` |
| Map tiles | `GET /tiles/...` |
| Map and topology management | Endpoints defined in `HttpChannel` |
| SSH tunnel | `ws://<IP>:8081/ws/ssh` |
| Camera | `http://<IP>:8080/stream?topic=/image_raw` |

When the Web build is served over HTTPS, WebSocket URLs automatically use `wss://`. The robot endpoints must also satisfy the browser's CORS and mixed-content requirements.

## 5. Main modules

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App entry point, providers, and routes |
| `lib/page/connect_page.dart` | Connection screen |
| `lib/page/main_page.dart` | Map, controls, telemetry, and tools |
| `lib/page/gamepad_widget.dart` | Virtual and physical gamepad input |
| `lib/provider/ws_channel.dart` | WebSocket, decoding, and velocity output |
| `lib/provider/http_channel.dart` | HTTP APIs |
| `lib/provider/d1_mode_protocol.dart` | Robotmode command and ACK wire codec |
| `lib/provider/control_log_store.dart` | Control-log ring buffer |
| `lib/provider/map_manager.dart` | Map and topology state |
| `lib/display/` | Map render layers |
| `lib/protobuf/` | Generated communication types |
| `thirdparty/gamepads_android/` | Local Android gamepad plugin |
| `thirdparty/gamepads_windows/` | Local Windows gamepad plugin |

## 6. Control behavior

The left stick produces translation and the right stick produces rotation:

```text
vx = MaxVx × left-stick Y
vy = MaxVy × -left-stick X
vw = MaxVw × -right-stick X
```

Fresh commands are sent every `20ms`. Non-finite values are replaced with zero. Motion state is cleared on disconnection, gamepad device changes, app suspension, and manual-control shutdown.

Robot mode controls:

| Input | Action |
| --- | --- |
| A | Stand |
| B | Lie down |
| D-pad up + R1 | Enter/exit reinforcement-learning mode |
| Y | Unbound |

Mode commands wait for their matching ACK with a default timeout of three seconds.

The complete Map-screen button reference—including status chips, both toolbars, navigation, relocation, camera, SSH, logs, and every map-editor tool—is in the [user guide](docs/usage.md).

## 7. Camera and SSH

The Web build loads the MJPEG URL directly. Other platforms use the client camera implementation and can display image frames from the robot WebSocket. Image port, topic, and dimensions are configurable.

SSH quick commands and the interactive terminal use the `/ws/ssh` tunnel. Plain `ws://` from an HTTP page is not encrypted; use HTTPS/WSS on untrusted networks.

## 8. Debugging

The Control Log screen shows:

- Gamepad device add/change/remove events
- Raw axes and button events
- Calculated `vx/vy/vw`
- Actual velocity send count and interval
- WebSocket connection, close, and error events

High-frequency entries are throttled and stored in an in-memory ring buffer that can be copied or cleared.

More documentation:

- [User guide](docs/usage.md) · [中文](docs/usage_ZH.md)
- [NavBot Robotfrontend communication contract](docs/navbot_d1_topics_and_payloads.md) · [中文](docs/navbot_d1_topics_and_payloads_ZH.md)

English files are the default documentation for Git hosting. Chinese translations use the `_ZH.md` suffix.

## 9. Known limitations

- This repository is client-only and cannot simulate the robot interfaces by itself.
- Communication field changes require matching generated code or a compatible client-side decoder.
- Web camera access depends on CORS, HTTPS/WSS, and browser mixed-content policy.
- Very large point clouds and high-rate map data are still limited by device performance and network bandwidth.

## 10. License

See [LICENSE](LICENSE).
