package org.flame_engine.gamepads_android

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

data class SupportedAxis(
    val axisId: Int,
    val invert: Boolean = false,
)

class EventListener {
    companion object {
        private const val EPSILON = 0.001
    }

    private data class AxisCacheKey(
        val deviceId: Int,
        val axisId: Int,
    )

    private data class MotionEventFingerprint(
        val deviceId: Int,
        val eventTime: Long,
        val action: Int,
        val source: Int,
        val axisValuesHash: Int,
    )

    private val lastAxisValue = mutableMapOf<AxisCacheKey, Float>()
    private var lastMotionEventFingerprint: MotionEventFingerprint? = null

    // Reference: https://developer.android.com/reference/android/view/MotionEvent
    private val supportedAxes = listOf(
        SupportedAxis(MotionEvent.AXIS_X),
        SupportedAxis(MotionEvent.AXIS_Y, invert = true),
        SupportedAxis(MotionEvent.AXIS_Z),
        SupportedAxis(MotionEvent.AXIS_RZ, invert = true),
        SupportedAxis(MotionEvent.AXIS_HAT_X),
        SupportedAxis(MotionEvent.AXIS_HAT_Y, invert = true),
        SupportedAxis(MotionEvent.AXIS_LTRIGGER),
        SupportedAxis(MotionEvent.AXIS_RTRIGGER),
        SupportedAxis(MotionEvent.AXIS_BRAKE),
        SupportedAxis(MotionEvent.AXIS_GAS),
        SupportedAxis(MotionEvent.AXIS_WHEEL),
        // Right-stick axes for non-Xbox layouts (Xbox uses AXIS_Z/RZ).
        // E.g. DJI RC Pro reports its right stick on RX/RY.
        SupportedAxis(MotionEvent.AXIS_RX),
        SupportedAxis(MotionEvent.AXIS_RY, invert = true),
    )

    fun onKeyEvent(keyEvent: KeyEvent, channel: MethodChannel): Boolean {
        val device = InputDevice.getDevice(keyEvent.deviceId)
        val arguments = mutableMapOf<String, Any>(
            "gamepadId" to keyEvent.deviceId.toString(),
            "time" to keyEvent.eventTime,
            "type" to "button",
            "key" to KeyEvent.keyCodeToString(keyEvent.keyCode),
            "value" to if (keyEvent.action == KeyEvent.ACTION_DOWN) 1.0 else 0.0,
        )
        if (device != null) {
            arguments["vendorId"] = device.vendorId
            arguments["productId"] = device.productId
        }
        channel.invokeMethod("onGamepadEvent", arguments)
        return true
    }

    fun onMotionEvent(motionEvent: MotionEvent, channel: MethodChannel): Boolean {
        if (motionEvent.actionMasked != MotionEvent.ACTION_MOVE) {
            return false
        }
        if (!motionEvent.isFromSource(InputDevice.SOURCE_JOYSTICK) &&
            !motionEvent.isFromSource(InputDevice.SOURCE_GAMEPAD)
        ) {
            return false
        }
        val device = InputDevice.getDevice(motionEvent.deviceId) ?: return false
        val availableRanges = device.motionRanges
            .filter(::isGamepadMotionRange)
            .associateBy { range -> range.axis }
        val fingerprint = MotionEventFingerprint(
            deviceId = motionEvent.deviceId,
            eventTime = motionEvent.eventTime,
            action = motionEvent.actionMasked,
            source = motionEvent.source,
            axisValuesHash = availableRanges.keys
                .sorted()
                .fold(1) { hash, axisId ->
                    31 * hash + motionEvent.getAxisValue(axisId).toBits()
                },
        )
        if (fingerprint == lastMotionEventFingerprint) {
            return false
        }
        lastMotionEventFingerprint = fingerprint

        var handled = false
        supportedAxes.forEach { axis ->
            val range = availableRanges[axis.axisId] ?: return@forEach
            val axisHandled = reportAxis(motionEvent, channel, device, range, axis)
            if (axisHandled) handled = true
        }

        return handled
    }

    fun clearDevice(deviceId: Int) {
        lastAxisValue.keys.removeAll { key -> key.deviceId == deviceId }
        if (lastMotionEventFingerprint?.deviceId == deviceId) {
            lastMotionEventFingerprint = null
        }
    }

    private fun reportAxis(
        motionEvent: MotionEvent,
        channel: MethodChannel,
        device: InputDevice,
        range: InputDevice.MotionRange,
        axis: SupportedAxis,
    ): Boolean {
        val multiplier = if (axis.invert) -1 else 1
        val rawValue = motionEvent.getAxisValue(axis.axisId)
        val value = if (abs(rawValue) <= range.flat) {
            0f
        } else {
            rawValue * multiplier
        }

        // No-op if threshold is not met
        val cacheKey = AxisCacheKey(motionEvent.deviceId, axis.axisId)
        val lastValue = lastAxisValue[cacheKey]
        if (lastValue is Float) {
            if (abs(value - lastValue) < EPSILON) {
                return false
            }
        }
        // Update last value
        lastAxisValue[cacheKey] = value

        val arguments = mutableMapOf<String, Any>(
            "gamepadId" to motionEvent.deviceId.toString(),
            "time" to motionEvent.eventTime,
            "type" to "analog",
            "key" to MotionEvent.axisToString(axis.axisId),
            "value" to value,
        )
        arguments["vendorId"] = device.vendorId
        arguments["productId"] = device.productId
        channel.invokeMethod("onGamepadEvent", arguments)
        return true
    }

    private fun isGamepadMotionRange(range: InputDevice.MotionRange): Boolean {
        return range.isFromSource(InputDevice.SOURCE_JOYSTICK) ||
            range.isFromSource(InputDevice.SOURCE_GAMEPAD)
    }
}
