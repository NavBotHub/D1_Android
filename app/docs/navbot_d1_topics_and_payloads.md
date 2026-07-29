# NavBot RobotFrontend Communication and Control Contract

[中文](navbot_d1_topics_and_payloads_ZH.md) · [Repository home](../../README.md)

This document records the network endpoints, binary fields, and control mapping used by the current Flutter client. It is a frontend compatibility contract, not robot-side implementation or deployment documentation.

## 1. Connection Overview

| Purpose | Address |
| --- | --- |
| Settings, navigation, and map HTTP APIs | `http://<D1-IP>:8081` |
| State and control WebSocket | `ws://<D1-IP>:8081/ws/robot` |
| SSH tunnel | `ws://<D1-IP>:8081/ws/ssh` |
| MJPEG video | `http://<D1-IP>:8080/stream?topic=/image_raw` |

```text
Connection screen
  → GET /api/settings
  → WebSocket /ws/robot
  → send cmd_vel = 0,0,0
  → open the Map screen
```

An HTTPS Web build changes the WebSocket scheme to `wss`.

## 2. Velocity Control

Velocity is sent as a binary frame over `/ws/robot`:

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

Client assignment:

```text
linear.x  = vx
linear.y  = vy
linear.z  = 0
angular.x = 0
angular.y = 0
angular.z = vw
```

Joystick conversion:

```text
vx = MaxVx × left-stick Y
vy = MaxVy × -left-stick X
vw = MaxVw × -right-stick X
top translational speed = sqrt(vx² + vy²)
```

Fresh manual-control commands are sent every `20ms` (`50Hz`). Before each write, the client applies the current stop lock, replaces non-finite values with zero, checks the connection, and respects the control-log setting. Connection, gamepad, or app-lifecycle changes clear the stale velocity snapshot.

## 3. RobotMode Control

Current wire contract:

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

Mode values:

| Value | Mode |
| ---: | --- |
| `1` | Stand |
| `2` | Lie down |
| `3` | Enter reinforcement learning |
| `4` | Exit reinforcement learning |

Result values:

| Value | Result |
| ---: | --- |
| `1` | `sent` |
| `2` | `bridgeNotReady` |
| `3` | `rlOffline` |
| `4` | `busy` |
| `5` | `rateLimited` |
| `6` | `duplicate` |

The client assigns an increasing `seq`, waits for the ACK with the same sequence, and uses a three-second default timeout. `sent` means that the command was accepted; it does not mean that the physical motion completed.

[d1_mode_protocol.dart](../lib/provider/d1_mode_protocol.dart) encodes and decodes these fields directly in protobuf wire format because the protocol source is intentionally not part of this frontend-only repository.

## 4. Received Robot Data

The client receives binary `RobotMessage` frames from `/ws/robot`:

| Data | Use |
| --- | --- |
| `image` | WebSocket image frame |
| `heartbeat` | Connection liveness |
| `laser_scan` | Laser points |
| `robot_pose_map` | Robot pose in the map frame |
| `path_local` / `path_global` / `path_trace` | Paths and trace |
| `odometry` | Velocity/odometry feedback |
| `battery` | Battery state |
| `footprint` | Robot footprint |
| `local_costmap` / `global_costmap` | Costmaps |
| `pointcloud_map` | Point cloud |
| `diagnostic` | Diagnostics |
| `nav_status` | Navigation state |

High-load messages keep only the latest pending value and are throttled before they update the UI.

## 5. GPS Compatibility Field

```text
RobotMessage.gps = field 19
```

The current generated `RobotMessage` type does not declare field 19. [ws_channel.dart](../lib/provider/ws_channel.dart) therefore performs compatibility parsing before normal generated-message decoding and updates the GPS state.

## 6. HTTP Interfaces

| Method | Path | Purpose |
| --- | --- | --- |
| GET/POST | `/api/settings` | Load/save settings |
| POST | `/robot/nav_goal` | Send a navigation target |
| POST | `/robot/initial_pose` | Send relocation pose |
| POST | `/robot/cancel_nav` | Cancel navigation |
| POST | `/robot/action_cmd` | Compatibility action command |
| POST | `/subImage` | Control WebSocket image subscription |
| GET | `/api/tf` | Query a transform |
| GET | `/getAllMapList` | List maps |
| GET | `/currentMap` | Read the current map |
| GET | `/setCurrentMap` | Switch maps |
| GET | `/deleteMap` | Delete a map |
| GET | `/getTopologyMap` | Read topology |
| GET | `/saveMapEdit` | Save map edits |

See [http_channel.dart](../lib/provider/http_channel.dart) for the exact parameters used by the client.

## 7. Video and SSH

Default video URL:

```text
http://<D1-IP>:8080/stream?topic=/image_raw
```

SSH quick commands and the terminal use `/ws/ssh`. If the Web page is served through HTTPS, the robot service must provide compatible secure endpoints and satisfy browser CORS and mixed-content policies.

## 8. Gamepad Mapping

| Input | Frontend action |
| --- | --- |
| `AXIS_X / AXIS_Y` | Left-stick translation |
| `AXIS_RX` or compatible `AXIS_Z` | Right-stick rotation |
| `A` | Stand |
| `B` | Lie down |
| `X` | Zoom map in |
| `Y` | Unbound |
| D-pad Up + `R1` | Enter/exit reinforcement learning |

## 9. Compatibility Rules

- This repository keeps the generated Dart types used by the frontend and does not include `.proto` sources.
- The robot interface must remain compatible with the existing field numbers and message structures.
- Binary WebSocket frames cannot be replaced with JSON without a matching client change.
- A successful WebSocket write does not prove robot execution; use ACKs, diagnostics, and physical state together.
- Control logging is off by default. When disabled, the log button is hidden and high-frequency control logs are not recorded.
