# Navbot Robot Flutter 客户端

![Flutter](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-supported-3DDC84?logo=android&logoColor=white)
![Web](https://img.shields.io/badge/Web-supported-4285F4?logo=googlechrome&logoColor=white)
![D1](https://img.shields.io/badge/D1-external%20service-0078D4)

[English](README.md)

本仓库只包含 **Navbot Robot 的 Flutter 前端源码**，用于在 Android、Web、Windows、Linux、macOS 和 iOS 上连接机器人、显示状态并执行控制。

仓库不包含机器人端服务源码和 `.proto` 源文件。前端运行时需要连接一台已经提供兼容 HTTP、WebSocket 和视频接口的机器人；正常构建直接使用仓库中已经生成的 Dart protobuf 文件。

配套机器人端部署：[D1_Backend](https://gitee.com/lookc4/D1_Backend)。

> **项目来源**
>
> 当前项目由 `E:\GitHubD1Demo\D1_Demo` 复制到
> `E:\GitHubProject\Robot_Android`。后续开发、构建和文档维护均以
> `E:\GitHubProject\Robot_Android` 中的内容为准；原目录仅用于追溯项目来源，
> 不是本项目的运行或构建依赖。

## 目录

- [1. 范围与职责边界](#1-范围与职责边界)
- [2. 功能](#2-功能)
- [3. 运行架构](#3-运行架构)
- [4. 环境与接口](#4-环境与接口)
- [5. 快速开始与构建](#5-快速开始与构建)
- [6. 控制摘要](#6-控制摘要)
- [7. 项目结构与文档](#7-项目结构与文档)
- [8. 安全与已知限制](#8-安全与已知限制)
- [9. 许可](#9-许可)

## 1. 范围与职责边界

本仓库负责 Flutter UI、平台工程、连接与重连、客户端设置、地图与状态显示、相机、诊断、SSH、虚拟/物理手柄输入，以及当前客户端所需的 Dart 生成代码。

本仓库不负责机器人端 HTTP/WebSocket 服务、ROS 2、CAN、D1 驱动、策略模型、systemd 服务、热点配置或物理急停，也不包含 `.proto` 源文件。

## 2. 功能

- 连接机器人并自动重连
- 瓦片地图、机器人位姿、激光、点云、路径、轨迹和代价地图
- 虚拟摇杆与 Android/Windows 物理手柄控制
- 站起、趴下和强化学习模式切换
- 导航目标、重定位、取消导航和地图编辑
- 电量、GPS、里程计、导航状态和诊断信息
- MJPEG 相机浮窗
- SSH 快捷指令与交互终端
- 中英文界面、横竖屏设置和控制日志

<p align="center">
  <img src="machine-dog-preview.png" alt="Navbot Robot 客户端预览" width="78%" />
</p>

## 3. 运行架构

```text
Android / Web / Desktop Flutter 客户端
  ├─ 设置、地图和导航 HTTP 接口
  ├─ /ws/robot 二进制状态与控制
  ├─ /ws/ssh 可选 SSH 隧道
  └─ :8080 可选 MJPEG 视频
             │
             ▼
       已独立部署的 D1 服务
             │
             ▼
          D1 机器人运行时
```

前端不会配置 CAN、启动机器人服务，也不能替代硬件急停。

## 4. 环境与接口

- Flutter `3.44.8`
- Dart `>=3.12.0 <4.0.0`
- 可访问的机器人控制服务，默认地址为 `http://<机器人IP>:8081`
- 使用相机时需要可访问的 MJPEG 地址，默认端口为 `8080`

前端默认使用：

| 用途 | 地址 |
| --- | --- |
| 设置与控制 HTTP 接口 | `http://<机器人IP>:8081` |
| 机器人二进制 WebSocket | `ws://<机器人IP>:8081/ws/robot` |
| SSH 隧道 WebSocket | `ws://<机器人IP>:8081/ws/ssh` |
| MJPEG 视频 | `http://<机器人IP>:8080/stream?topic=/image_raw` |

连接页支持手动地址和固定热点地址 `192.168.50.1:8081`。Android 可打开系统 Wi-Fi 列表；浏览器不能切换系统 Wi-Fi，网页用户必须手动连接热点。

## 5. 快速开始与构建

所有 Flutter 命令都在 `app` 目录执行：

```bash
cd app
flutter pub get
flutter run
```

常用构建命令：

```bash
flutter build apk --release
flutter build web --release
flutter build windows --release
flutter build linux --release
```

现有 Dart protobuf 代码位于 `app/lib/protobuf/`，普通开发和打包不需要运行协议生成步骤。

## 6. 控制摘要

| 控件 | 功能 |
| --- | --- |
| 左虚拟/物理摇杆 | 前后使用 `MaxVx`，横移使用 `MaxVy` |
| 右虚拟/物理摇杆 | 旋转使用 `MaxVw` |
| `A` / Stand | 站起 |
| `B` / Lie Down | 趴下 |
| 方向键上 + `R1` / Enter RL | 进入或退出强化学习模式 |
| `X` | 地图放大 |
| 重定位 | 设置并确认机器人初始位姿 |
| 导航点 | 查看详情并发送导航目标 |
| 相机 | 打开/关闭相机浮窗和切换全屏 |
| 设置 | 配置速度、视频、话题、SSH、图层、日志和屏幕方向 |

左上平移速度显示实际控制合成值 `sqrt(vx² + vy²)`，`MaxVx` 与 `MaxVy` 分别生效。

Map 页面和地图编辑器的全部按钮见[完整使用手册](app/docs/usage_ZH.md)。

## 7. 项目结构与文档

```text
app/
├── lib/
│   ├── basic/       数据模型与坐标变换
│   ├── display/     地图图层和机器人可视化
│   ├── page/        连接、主界面、设置、日志等页面
│   ├── provider/    HTTP、WebSocket、地图与全局状态
│   ├── protobuf/    已生成的 Dart protobuf 代码
│   └── ssh/         SSH 隧道客户端
├── thirdparty/      本地手柄插件
├── assets/          图标和字体
└── docs/            前端使用与通信说明
```

详细说明：

- [前端开发说明](app/README.md)
- [使用手册](app/docs/usage_ZH.md) · [English](app/docs/usage.md)
- [前端通信契约](app/docs/navbot_d1_topics_and_payloads_ZH.md) · [English](app/docs/navbot_d1_topics_and_payloads.md)

Git 托管页面默认使用英文文件，中文翻译使用 `_ZH.md` 后缀。

## 8. 安全与已知限制

- 当前 UI 没有独立急停按钮，必须准备物理或机器人侧急停。
- 首次运动测试应悬空机器人。
- WebSocket 写入成功或模式 ACK 已接受，不代表实体动作已经完成。
- 网页不能自动切换 Wi-Fi。
- 无真实地图时显示的前端占位地图只能保持 UI 可用，不能用于真实导航。
- 控制日志默认关闭，关闭时隐藏按钮且不记录高频控制日志。

## 9. 许可

见 [app/LICENSE](app/LICENSE)。
