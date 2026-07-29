package com.navbot.d1

import android.content.Intent
import android.hardware.input.InputManager
import android.os.Handler
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

class MainActivity: FlutterActivity(), GamepadsCompatibleActivity {
    companion object {
        private const val DEVICE_EVENT_CHANNEL = "navbot/gamepad_devices"
        private const val SYSTEM_SETTINGS_CHANNEL = "navbot/system_settings"
    }

    var keyListener: ((KeyEvent) -> Boolean)? = null
    var motionListener: ((MotionEvent) -> Boolean)? = null
    private var deviceEventSink: EventChannel.EventSink? = null
    private var deviceListenerRegistered = false
    private val deviceListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) {
            emitDeviceEvent("added", deviceId)
        }

        override fun onInputDeviceRemoved(deviceId: Int) {
            emitDeviceEvent("removed", deviceId)
        }

        override fun onInputDeviceChanged(deviceId: Int) {
            emitDeviceEvent("changed", deviceId)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deviceEventSink = events
                registerDeviceEventListener()
            }

            override fun onCancel(arguments: Any?) {
                deviceEventSink = null
                unregisterDeviceEventListener()
            }
        })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "WIFI_SETTINGS_UNAVAILABLE",
                            error.message,
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        if (motionListener?.invoke(motionEvent) == true) {
            return true
        }
        return super.dispatchGenericMotionEvent(motionEvent)
    }
    
    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        if (keyListener?.invoke(keyEvent) == true) {
            return true
        }
        return super.dispatchKeyEvent(keyEvent)
    }

    override fun registerInputDeviceListener(
      listener: InputManager.InputDeviceListener, handler: Handler?) {
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun unregisterInputDeviceListener(listener: InputManager.InputDeviceListener) {
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.unregisterInputDeviceListener(listener)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun unregisterKeyEventHandler() {
        keyListener = null
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
    }

    override fun unregisterMotionEventHandler() {
        motionListener = null
    }

    private fun registerDeviceEventListener() {
        if (deviceListenerRegistered) return
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(deviceListener, null)
        deviceListenerRegistered = true
    }

    private fun unregisterDeviceEventListener() {
        if (!deviceListenerRegistered) return
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.unregisterInputDeviceListener(deviceListener)
        deviceListenerRegistered = false
    }

    private fun emitDeviceEvent(type: String, deviceId: Int) {
        deviceEventSink?.success(
            mapOf(
                "type" to type,
                "deviceId" to deviceId.toString(),
            ),
        )
    }

    override fun onDestroy() {
        unregisterDeviceEventListener()
        unregisterKeyEventHandler()
        unregisterMotionEventHandler()
        super.onDestroy()
    }
}
