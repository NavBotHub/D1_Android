# NavBot RobotFlutter 前端

[English](README.md) · [仓库首页](../README_ZH.md)

`app` 是本仓库的主体，包含完整的 Flutter 客户端、平台工程、本地手柄插件、资源文件以及已生成的 Dart protobuf 代码。

本目录不负责机器人端软件的构建或部署。运行应用前，请确认目标机器人已经提供本文列出的兼容接口。

配套机器人端部署：[D1_Backend](https://gitee.com/lookc4/D1_Backend)。

## 1. 环境

推荐版本：

- Flutter `3.29.3`
- Dart `>=3.7.0 <4.0.0`
- Android 构建使用 JDK 17

检查环境并获取依赖：

```bash
flutter doctor
cd app
flutter pub get
```

`lib/protobuf/` 已包含当前客户端所需的生成代码，普通构建不需要安装 `protoc`。

Android 和 Windows 手柄插件通过 `pubspec.yaml` 的 `dependency_overrides` 使用 `thirdparty/` 下的本地实现，复制或发布源码时必须保留这些目录。

## 2. 运行

列出设备：

```bash
flutter devices
```

选择目标运行：

```bash
flutter run
flutter run -d chrome
flutter run -d windows
```

应用启动后进入连接页，可选择：

- **地址连接**：输入 IP、`host:port`、HTTP URL 或完整 WebSocket URL，客户端自动提取主机和端口。
- **Robot 热点**：网页端先手动连接热点再点击连接；Android App 可直接打开系统 Wi-Fi 列表，返回 App 后自动检测并连接默认 `192.168.50.1:8081`。

连接过程：

1. 从 `GET /api/settings` 读取界面和话题配置。
2. 建立 `/ws/robot` 二进制 WebSocket。
3. 连接成功后进入主界面，并发送一次零速度。
4. 连接中断或超过 10 秒没有收到消息时清零控制状态并自动重连。

## 3. 构建

### Android

```bash
flutter build apk --release
```

输出：

```text
build/app/outputs/flutter-apk/app-release.apk
```

### Web

```bash
flutter build web --release
```

输出：

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

macOS 和 iOS 需要在 macOS 环境中构建。

## 4. 前端使用的网络接口

以下地址以连接页填写的机器人 IP 为基础：

| 功能 | 方法或地址 |
| --- | --- |
| 读取/保存设置 | `GET/POST http://<IP>:8081/api/settings` |
| 状态与控制 | `ws://<IP>:8081/ws/robot` |
| 导航目标 | `POST /robot/nav_goal` |
| 重定位 | `POST /robot/initial_pose` |
| 取消导航 | `POST /robot/cancel_nav` |
| 动作兼容接口 | `POST /robot/action_cmd` |
| 地图瓦片 | `GET /tiles/...` |
| 地图与拓扑管理 | 与 `HttpChannel` 中定义的接口一致 |
| SSH 隧道 | `ws://<IP>:8081/ws/ssh` |
| 相机 | `http://<IP>:8080/stream?topic=/image_raw` |

Web 页面通过 HTTPS 打开时，WebSocket 会自动使用 `wss://`。机器人端接口还需要允许页面来源所需的 CORS 和混合内容策略。

## 5. 主要模块

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | 应用入口、Provider 和路由 |
| `lib/page/connect_page.dart` | 连接页 |
| `lib/page/main_page.dart` | 地图、控制、状态和工具入口 |
| `lib/page/gamepad_widget.dart` | 虚拟/物理手柄输入 |
| `lib/provider/ws_channel.dart` | WebSocket、数据解码和速度发送 |
| `lib/provider/http_channel.dart` | HTTP 接口 |
| `lib/provider/d1_mode_protocol.dart` | Robot模式命令与 ACK wire codec |
| `lib/provider/control_log_store.dart` | 控制日志环形缓冲 |
| `lib/provider/map_manager.dart` | 地图与拓扑状态 |
| `lib/display/` | 地图渲染图层 |
| `lib/protobuf/` | 已生成的通信数据类型 |
| `thirdparty/gamepads_android/` | Android 手柄本地插件 |
| `thirdparty/gamepads_windows/` | Windows 手柄本地插件 |

## 6. 控制行为

左摇杆计算平移速度，右摇杆计算角速度：

```text
vx = MaxVx × 左摇杆Y
vy = MaxVy × -左摇杆X
vw = MaxVw × -右摇杆X
```

有效控制状态以 `20ms` 周期发送。速度值会过滤 `NaN` 和无穷值；连接断开、手柄设备变化、应用暂停和停止手动控制时会清零。

Robot 模式控制：

| 输入 | 功能 |
| --- | --- |
| A | 站起 |
| B | 趴下 |
| 方向键上 + R1 | 进入/退出强化学习 |
| Y | 未绑定 |

模式命令会等待对应 ACK，默认超时时间为 3 秒。

Map 页状态栏、左右工具栏、导航、重定位、相机、SSH、日志以及地图编辑器的全部按钮说明见[使用手册](docs/usage_ZH.md)。

## 7. 相机与 SSH

Web 端相机直接加载 MJPEG URL；其他平台优先使用客户端相机组件，并保留 WebSocket 图像帧显示能力。图像端口、话题和尺寸可以在设置页调整。

SSH 快捷指令和终端通过 `/ws/ssh` 隧道工作。HTTP 页面下的 `ws://` 不提供传输加密，在非可信网络中应使用 HTTPS/WSS。

## 8. 调试

主界面可进入“控制日志”页面，查看：

- 手柄设备新增、变化和移除
- 原始轴值与按钮事件
- 计算后的 `vx/vy/vw`
- 实际速度发送计数和间隔
- WebSocket 连接、断开和错误

高频事件会节流并保存在内存环形缓冲中，可复制或清空。

更多内容：

- [使用手册](docs/usage_ZH.md) · [English](docs/usage.md)
- [NavBot Robot前端通信契约](docs/navbot_d1_topics_and_payloads_ZH.md) · [English](docs/navbot_d1_topics_and_payloads.md)

Git 托管页面默认使用英文文档，中文翻译使用 `_ZH.md` 后缀。

## 9. 已知限制

- 本仓库只提供客户端，不能单独模拟机器人接口。
- 修改通信字段时，需要同时取得与机器人端匹配的生成代码或在客户端实现兼容解码。
- Web 相机受 CORS、HTTPS/WSS 和浏览器混合内容策略影响。
- 超大点云和高频地图数据仍会受到终端性能与网络带宽限制。

## 10. 许可

见 [LICENSE](LICENSE)。
