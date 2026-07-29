package org.flame_engine.gamepads_android

import android.hardware.input.InputManager
import android.os.Handler
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

interface GamepadsCompatibleActivity {
    fun isGamepadsInputDevice(device: InputDevice): Boolean {
        val hasGamepadSource =
            device.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD
        val hasJoystickSource =
            device.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
        // Some Bluetooth keyboards are identified as gamepads.
        return (hasGamepadSource || hasJoystickSource) &&
            device.keyboardType != InputDevice.KEYBOARD_TYPE_ALPHABETIC
    }

    fun registerInputDeviceListener(listener: InputManager.InputDeviceListener, handler: Handler?)
    fun unregisterInputDeviceListener(listener: InputManager.InputDeviceListener)
    fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean)
    fun unregisterKeyEventHandler()
    fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean)
    fun unregisterMotionEventHandler()
}
