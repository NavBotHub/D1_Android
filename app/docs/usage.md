# NavBot RobotFlutter Client User Guide

[中文](usage_ZH.md) · [Repository home](../../README.md)

This guide covers only the Flutter client: connection, screen layout, and user controls. Robot-side services, ROS, CAN, and the Robotruntime are outside this repository. For the companion service, see
[D1_Backend](https://gitee.com/lookc4/D1_Backend).

## Contents

- [1. Before You Start](#1-before-you-start)
- [2. Connect to the Robot](#2-connect-to-the-robot)
- [3. Map Screen Overview](#3-map-screen-overview)
- [4. Button Reference](#4-button-reference)
- [5. Virtual Joysticks and Speed Display](#5-virtual-joysticks-and-speed-display)
- [6. Physical Gamepad Mapping](#6-physical-gamepad-mapping)
- [7. Navigation, Relocation, and Map Editing](#7-navigation-relocation-and-map-editing)
- [8. Settings, Layers, Camera, SSH, and Logs](#8-settings-layers-camera-ssh-and-logs)
- [9. Safety and Loss-of-Connection Behavior](#9-safety-and-loss-of-connection-behavior)
- [10. Troubleshooting](#10-troubleshooting)

## 1. Before You Start

Confirm the following before running the client:

- The Robotis safely positioned. Suspend it for the first motion test and prepare an independent physical emergency-stop method.
- The control service is reachable on TCP `8081`.
- The optional video service is reachable on TCP `8080`.
- The phone or computer is on the same network as the D1, or is already connected to the Robothotspot.
- If the Web client is served through HTTPS, the robot endpoints also support HTTPS/WSS so that the browser does not block mixed content.

Default endpoints:

| Purpose | Address |
| --- | --- |
| Settings and control HTTP | `http://<D1-IP>:8081` |
| State and control WebSocket | `ws://<D1-IP>:8081/ws/robot` |
| SSH tunnel | `ws://<D1-IP>:8081/ws/ssh` |
| MJPEG video | `http://<D1-IP>:8080/stream?topic=/image_raw` |

## 2. Connect to the Robot

The connection screen provides two modes.

### Address

1. Select **Address**.
2. Enter an IP, `host:port`, HTTP URL, or full WebSocket URL.
3. If no port is supplied, the client uses `8081`.
4. Select **Connect To Robot**.

### RobotHotspot

The default hotspot endpoint is `192.168.50.1:8081`.

- **Web:** a browser cannot switch the operating system's Wi-Fi network on the user's behalf. Join the Robothotspot in system settings, return to the page, and select Connect.
- **Android app:** the hotspot action opens the system Wi-Fi list. Select the Robothotspot and return to the app. The client checks the default endpoint and can enter the Map screen when the check succeeds. If it fails, run the check again from the connection screen.
- A phone may report that the hotspot has no Internet access. Choose the option that keeps the phone connected.

Connection sequence:

```text
GET /api/settings
  → WebSocket /ws/robot
  → send one zero-velocity command
  → open the Map screen
```

If either network step fails, the client remains on the connection screen and shows an error.

## 3. Map Screen Overview

| Area | Contents |
| --- | --- |
| Top-left status row | Translational command speed, rotational command speed, navigation state, and diagnostics |
| Left toolbar | Layers, relocation, live gamepad output, control logs, camera, and manual controls |
| Right toolbar | Settings, map editor, SSH, zoom, and follow-robot mode |
| Top-right actions | Stand/Lie Down and Enter/Exit RL |
| Bottom-left joystick | Forward/backward and lateral translation |
| Bottom-right joystick | Rotation |
| Top-right legend | Free, Occupied, and Unknown occupancy values |

The map can render robot pose, navigation points, topology routes, laser data, point clouds, paths, trace, footprint, and costmaps. If no map is available or map metadata returns `404`, the client renders a frontend-only placeholder map with `NAVBOT` written as occupied cells and keeps waiting for a real map.

## 4. Button Reference

### 4.1 Top-left status row

| Icon/status | Function |
| --- | --- |
| Speedometer | Shows the planar command magnitude from the left joystick: `sqrt(vx² + vy²)` in `m/s` |
| Rotate arrow | Shows the angular command from the right joystick in `deg/s` |
| Navigation arrow | Shows the current navigation state, such as `unknown`, `accepted`, or `executing` |
| Diagnostic status | Shows Normal or WARN/ERROR counts; select it to open diagnostic details |

These values describe the commands that the client is preparing to send. They are not measured odometry feedback from the robot.

### 4.2 Left toolbar

| Button | Function | How it behaves |
| --- | --- | --- |
| Layers | Opens layer settings | Enables or disables the grid, local costmap, laser, point cloud, global/local paths, trace, topology, and footprint; selected colors, thresholds, styles, and dot sizes are configurable |
| Relocation | Sets the robot's initial pose | Position and rotate the pose on the map, select the green check to send it, or select the red close button to cancel |
| Gamepad output | Opens the live input panel | Shows current axes, buttons, and calculated `vx/vy/vw`; this transient panel is separate from stored control logs |
| Control logs | Opens the control-log screen | Visible only after Control logs is enabled in Settings; disabled and hidden by default |
| Camera | Opens or closes the camera overlay | Use the button inside the overlay to enter or leave fullscreen |
| Gamepad/manual control | Shows or hides the virtual controls | Enables manual control using the two joysticks and action buttons |

### 4.3 Right toolbar

| Button | Function | How it behaves |
| --- | --- | --- |
| Settings | Opens client settings | Edits connection, speed, video, topics, SSH, layers, logs, and screen orientation |
| Map Edit | Opens the map editor | Edits points, routes, and occupied cells; Save operations write to the robot service |
| SSH Hub | Expands or collapses SSH tools | Reveals Quick Commands and Terminal |
| Bolt | Opens SSH quick commands | Runs a configured remote command |
| Terminal | Opens the interactive SSH terminal | Uses the robot-side `/ws/ssh` tunnel |
| Zoom In | Increases map zoom | Physical gamepad `X` triggers the same action |
| Zoom Out | Decreases map zoom | Decreases the current map zoom |
| Location ring | Toggles follow-robot mode | Green means enabled and keeps the robot centered; select it again to return to free map browsing |

### 4.4 Top-right robot actions

| Button | Physical gamepad | Function |
| --- | --- | --- |
| Stand | `A` | Sends the stand command |
| Lie Down | `B` | Sends the lie-down command |
| Enter RL / Exit RL | D-pad Up + `R1` | Enters or exits reinforcement-learning control mode |

Stand and Lie Down share one control. The highlighted item is the latest client-side mode state. A mode command waits for its matching ACK with a three-second default timeout. An accepted ACK does not prove that the physical motion has finished.

### 4.5 Map and navigation-point actions

| Action | Function |
| --- | --- |
| Drag map | Pans the map |
| Pinch/mouse wheel | Changes map zoom |
| Select navigation point | Opens point details |
| Send Nav Goal | Sends the selected point as a navigation target |
| Blue stop button | Appears only while navigation is accepted/executing and cancels the current navigation |

## 5. Virtual Joysticks and Speed Display

### Left joystick

- Up/down controls forward and backward velocity through `MaxVx`.
- Left/right controls lateral velocity through `MaxVy`.
- Diagonal movement produces both `vx` and `vy`.

### Right joystick

- Left/right controls angular velocity through `MaxVw`.

Conversion:

```text
vx = MaxVx × left-stick Y
vy = MaxVy × -left-stick X
vw = MaxVw × -right-stick X
top translational speed = sqrt(vx² + vy²)
```

`MaxVx` and `MaxVy` are intentionally independent. For example, with `MaxVx=0.9` and `MaxVy=0.5`, full forward input displays about `0.90 m/s`, while full lateral input displays about `0.50 m/s`.

Fresh manual commands are sent every `20ms` (`50Hz`). Releasing a joystick returns that component to zero.

## 6. Physical Gamepad Mapping

| Input | Function |
| --- | --- |
| Left stick | Forward/backward and lateral motion |
| Right stick | Rotation |
| `A` | Stand |
| `B` | Lie down |
| `X` | Zoom map in |
| `Y` | Currently unbound |
| D-pad Up + `R1` | Enter/exit RL mode |
| `L1`, `L2`, `R2`, or `R1` alone | No current action |

D-pad Up and `R1` must be pressed within `320ms` of each other.

## 7. Navigation, Relocation, and Map Editing

### Navigation

Select a navigation point, verify its details, and select **Send Nav Goal**. While navigation is active, the stop button sends a cancel request.

### Relocation

1. Select Relocation in the left toolbar.
2. Position and rotate the initial pose on the map.
3. Select the green check to send it, or the red close button to cancel.

### Map editor buttons

Top toolbar:

| Button | Function |
| --- | --- |
| Undo | Reverts the latest point, route, or obstacle edit; desktop users can also press `Ctrl+Z` |
| Save | Saves changes to the current map |
| Save As | Saves the edited map under a new name |
| Map Management | Lists maps and allows switching, editing, or deleting a map that is not current |
| Add Current Position | Visible with the Point tool; adds a navigation point at the robot's current pose |
| Close | Leaves the map editor |

Right-side tools:

| Tool | Function |
| --- | --- |
| Move | Browses the map and selects or drags navigation points |
| Point | Adds a navigation point at the selected map position |
| Route | Creates a topology route by selecting a start point and then an end point |
| Brush | Paints occupied cells |
| Eraser | Clears occupied cells |
| Brush size | Appears for Brush/Eraser and selects a `0.05–1.0m` editing radius |

Selecting an existing point allows its name, coordinates, angle, and type to be edited or the point to be deleted. Selecting an existing route allows its controller to be inspected or the route to be deleted. Confirm the target map name before deleting or overwriting data.

## 8. Settings, Layers, Camera, SSH, and Logs

### Speed settings

| Setting | Meaning |
| --- | --- |
| `MaxVx` | Maximum forward/backward velocity in `m/s` |
| `MaxVy` | Maximum lateral velocity in `m/s` |
| `MaxVw` | Maximum angular velocity in `rad/s` |

### Camera

Default stream:

```text
http://<D1-IP>:8080/stream?topic=/image_raw
```

`imagePort`, `imageTopic`, `imageWidth`, and `imageHeight` are configurable.

### SSH

Quick commands and the terminal use the robot-side `/ws/ssh` tunnel. Configure the SSH port, username, and password before first use. Do not send credentials over an untrusted HTTP/WS network.

### Control logs

Control logging is disabled by default. While disabled:

- The control-log button is not shown on the Map screen.
- No high-frequency entries are written to the in-memory ring buffer.
- Control-path logging has no ongoing performance cost.

Enable it temporarily to inspect device events, raw axes, `vx/vy/vw`, send frequency, and WebSocket state, then disable it after troubleshooting.

## 9. Safety and Loss-of-Connection Behavior

- The current UI has **no independent emergency-stop button**. Do not treat Stand, Lie Down, or Cancel Navigation as a physical emergency stop.
- Suspend the robot for the first physical test and keep a robot-side or hardware emergency-stop method available.
- The client clears stale motion state on disconnection, app suspension, gamepad-device changes, and manual-control shutdown.
- If no robot message arrives for more than 10 seconds, the connection is treated as stale and the client attempts to reconnect.
- A WebSocket write or mode ACK does not prove that the robot completed an action. Observe the robot and diagnostic feedback.
- An open hotspot without authentication exposes the control interface to nearby devices. Use it only in a controlled environment.

## 10. Troubleshooting

### Loading settings fails

Verify the IP, TCP `8081`, and `GET /api/settings`. The main WebSocket is not opened when settings cannot be loaded.

### The Web client cannot join the Robothotspot automatically

This is a browser security restriction. Join the hotspot in operating-system Wi-Fi settings, return to the Web page, and select Connect.

### The WebSocket reconnects repeatedly

Verify that the robot continues to send state or heartbeat messages. Ten seconds without any message is treated as a stale connection.

### Lateral speed is unexpected

Check `MaxVy`. The first status value is `sqrt(vx² + vy²)`; lateral motion does not use `MaxVx`.

### A physical joystick does not respond

Temporarily enable Control logs or open the gamepad-output panel and inspect the device ID, axis events, and calculated command.

### The camera does not render

Open the MJPEG URL directly and check its port, topic, CORS headers, and mixed-content restrictions when an HTTPS page loads an HTTP stream.

### Map metadata returns 404

The client displays a frontend placeholder and keeps retrying. The placeholder is for UI continuity only and must not be used for real navigation.

### The robot does not move

Verify the connection, manual-control state, changing command output, and robot-side emergency stop, operating mode, and safety protections. The frontend can confirm a network write, but cannot independently prove physical execution.
