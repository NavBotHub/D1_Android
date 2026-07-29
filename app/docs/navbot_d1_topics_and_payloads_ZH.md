# NavBot Robot前端通信与控制说明

[English](navbot_d1_topics_and_payloads.md) · [返回项目首页](../../README_ZH.md)

本文记录当前 Flutter 客户端使用的网络接口、二进制字段和控制映射。它是前端兼容性说明，不包含机器人端实现、构建或部署内容。

## 1. 连接总览

| 用途 | 地址 |
| --- | --- |
| 设置、导航和地图 HTTP 接口 | `http://<机器人IP>:8081` |
| 状态与控制 WebSocket | `ws://<机器人IP>:8081/ws/robot` |
| SSH 隧道 | `ws://<机器人IP>:8081/ws/ssh` |
| MJPEG 视频 | `http://<机器人IP>:8080/stream?topic=/image_raw` |

```text
连接页
  → GET /api/settings
  → WebSocket /ws/robot
  → 发送 cmd_vel = 0,0,0
  → 进入 Map 页面
```

Web 构建在 HTTPS 页面中会把 WebSocket scheme 切换为 `wss`。

## 2. 速度控制

速度通过 `/ws/robot` 的 binary frame 发送：

```proto
message ClientRobotMessage {
  oneof payload {
    Twist cmd_vel = 2;
  }
}

message Twist {
  Vector3 linear = 1;
  Vector3 angular = 2;
}
```

客户端赋值：

```text
linear.x  = vx
linear.y  = vy
linear.z  = 0
angular.x = 0
angular.y = 0
angular.z = vw
```

摇杆换算：

```text
vx = MaxVx × 左摇杆Y
vy = MaxVy × -左摇杆X
vw = MaxVw × -右摇杆X
顶部平移速度 = sqrt(vx² + vy²)
```

有效手动控制命令每 `20ms` 发送一次，即 `50Hz`。每次发送前会处理急停锁定、非有限数值、连接状态和日志开关。连接、手柄或应用生命周期发生变化时，客户端会清除旧速度快照。

## 3. Robot模式控制

当前 wire contract：

```text
ClientRobotMessage.d1_mode_command = field 8
RobotMessage.d1_mode_ack = field 20
```

```proto
message D1ModeCommand {
  uint32 seq = 1;
  D1Mode mode = 2;
  int64 client_time_ms = 3;
}

message D1ModeAck {
  uint32 seq = 1;
  D1Mode mode = 2;
  D1ModeResult result = 3;
  string message = 4;
}
```

| 值 | 模式 |
| ---: | --- |
| `1` | 站起 |
| `2` | 趴下 |
| `3` | 进入强化学习 |
| `4` | 退出强化学习 |

| 值 | 结果 |
| ---: | --- |
| `1` | `sent` |
| `2` | `bridgeNotReady` |
| `3` | `rlOffline` |
| `4` | `busy` |
| `5` | `rateLimited` |
| `6` | `duplicate` |

客户端为每条命令分配递增 `seq`，等待相同序号的 ACK，默认 3 秒超时。`sent` 只表示命令已接受，不代表实体动作已经完成。

Robot 字段由 [d1_mode_protocol.dart](../lib/provider/d1_mode_protocol.dart) 按 protobuf wire format 编解码，不依赖仓库中不存在的 `.proto` 源文件。

## 4. 接收数据

客户端从 `/ws/robot` 接收 `RobotMessage`：

| 数据 | 用途 |
| --- | --- |
| `image` | WebSocket 图像帧 |
| `heartbeat` | 连接存活 |
| `laser_scan` | 激光点 |
| `robot_pose_map` | 地图坐标系机器人位姿 |
| `path_local` / `path_global` / `path_trace` | 路径与轨迹 |
| `odometry` | 速度/里程计 |
| `battery` | 电量 |
| `footprint` | 机器人轮廓 |
| `local_costmap` / `global_costmap` | 代价地图 |
| `pointcloud_map` | 点云 |
| `diagnostic` | 诊断信息 |
| `nav_status` | 导航状态 |

高负载消息只保留最新一条，并按消息类型节流更新界面。

## 5. GPS 兼容字段

```text
RobotMessage.gps = field 19
```

当前生成的 `RobotMessage` 尚未声明 field 19，因此 [ws_channel.dart](../lib/provider/ws_channel.dart) 在常规生成类解码前执行兼容解析并更新 GPS 状态。

## 6. HTTP 接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET/POST | `/api/settings` | 读取/保存设置 |
| POST | `/robot/nav_goal` | 导航目标 |
| POST | `/robot/initial_pose` | 重定位 |
| POST | `/robot/cancel_nav` | 取消导航 |
| POST | `/robot/action_cmd` | 兼容动作命令 |
| POST | `/subImage` | 控制 WebSocket 图像订阅 |
| GET | `/api/tf` | 查询坐标变换 |
| GET | `/getAllMapList` | 地图列表 |
| GET | `/currentMap` | 当前地图 |
| GET | `/setCurrentMap` | 切换地图 |
| GET | `/deleteMap` | 删除地图 |
| GET | `/getTopologyMap` | 读取拓扑 |
| GET | `/saveMapEdit` | 保存地图编辑 |

具体参数以 [http_channel.dart](../lib/provider/http_channel.dart) 为准。

## 7. 视频与 SSH

默认视频地址：

```text
http://<机器人IP>:8080/stream?topic=/image_raw
```

SSH 快捷指令和终端通过 `/ws/ssh` 工作。Web 页面使用 HTTPS 时，机器人端必须提供兼容的安全连接，并满足 CORS 和混合内容策略。

## 8. 手柄映射

| 输入 | 前端动作 |
| --- | --- |
| `AXIS_X / AXIS_Y` | 左摇杆平移 |
| `AXIS_RX` 或兼容 `AXIS_Z` | 右摇杆旋转 |
| `A` | 站起 |
| `B` | 趴下 |
| `X` | 地图放大 |
| `Y` | 未绑定 |
| `方向键上 + R1` | 进入/退出强化学习 |

## 9. 兼容性原则

- 本仓库只保留前端使用的生成代码，不提供 `.proto` 源文件。
- 机器人接口必须与现有字段号和消息结构兼容。
- WebSocket binary 数据不能替换为 JSON。
- 客户端写入 WebSocket 不等于机器人已执行，需要结合 ACK、诊断和实体状态判断。
- 控制日志默认关闭；关闭时不显示日志按钮，也不记录高频控制日志。
