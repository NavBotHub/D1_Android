package org.flame_engine.gamepads_android

import android.app.Activity
import android.view.View

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class GamepadsAndroidPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel : MethodChannel
  private var compatibleActivity: GamepadsCompatibleActivity? = null
  private var devices: DeviceListener? = null
  private var events: EventListener? = null

  // Decor view we attach an OnGenericMotionListener to, plus the listener
  // itself, so analog motion is captured even when the focused view (e.g.
  // FlutterView) consumes joystick MotionEvents before they bubble up to
  // Activity.dispatchGenericMotionEvent. Kept for removal on detach.
  private var motionDecorView: View? = null
  private var genericMotionListener: View.OnGenericMotionListener? = null

  private fun listGamepads(): List<Map<String, String>>  {
    return devices?.getDevices()?.map { device ->
      mapOf(
        "id" to device.key.toString(),
        "name" to device.value.name
      )
    } ?: emptyList()
  }

  // FlutterPlugin
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "xyz.luan/gamepads")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    detachFromActivity()
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "listGamepads") {
      result.success(listGamepads())
    } else {
      result.notImplemented()
    }
  }

  // Activity Aware
  override fun onAttachedToActivity(activityPluginBinding: ActivityPluginBinding) {
    onAttachedToActivityShared(activityPluginBinding.activity)
  }

  fun onAttachedToActivityShared(activity: Activity) {
    detachFromActivity()

    val attachedActivity = activity as GamepadsCompatibleActivity
    val attachedEvents = EventListener()
    val attachedDevices = DeviceListener(
      isGamepadsInputDevice = { attachedActivity.isGamepadsInputDevice(it) },
      onDeviceReset = attachedEvents::clearDevice,
    )
    compatibleActivity = attachedActivity
    events = attachedEvents
    devices = attachedDevices

    attachedActivity.registerInputDeviceListener(attachedDevices, handler = null)
    attachedActivity.registerKeyEventHandler { event ->
      if (attachedDevices.containsKey(event.deviceId)) {
        attachedEvents.onKeyEvent(event, channel)
      } else {
        false
      }
     }
    attachedActivity.registerMotionEventHandler { event ->
      if (attachedDevices.containsKey(event.deviceId)) {
        attachedEvents.onMotionEvent(event, channel)
      } else {
        false
      }
    }

    // In an embedded FlutterActivity the focused view (FlutterView/
    // FlutterSurfaceView) consumes joystick MotionEvents, so they never reach
    // Activity.dispatchGenericMotionEvent and the handler above can be skipped
    // for analog axes. The decor listener is a fallback. EventListener rejects
    // the same MotionEvent instance and unchanged per-device axis values, so
    // the two paths cannot emit duplicate Flutter events.
    val listener = View.OnGenericMotionListener { _, event ->
      if (attachedDevices.containsKey(event.deviceId)) {
        attachedEvents.onMotionEvent(event, channel)
      } else {
        false
      }
    }
    val decorView = activity.window?.decorView
    decorView?.setOnGenericMotionListener(listener)
    motionDecorView = decorView
    genericMotionListener = listener
  }

  override fun onDetachedFromActivity() {
    detachFromActivity()
  }

  override fun onDetachedFromActivityForConfigChanges() {
    detachFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(activityPluginBinding: ActivityPluginBinding) {
    onAttachedToActivityShared(activityPluginBinding.activity)
  }

  private fun detachFromActivity() {
    if (genericMotionListener != null) {
      motionDecorView?.setOnGenericMotionListener(null)
    }
    motionDecorView = null
    genericMotionListener = null

    val attachedActivity = compatibleActivity
    val attachedDevices = devices
    if (attachedActivity != null && attachedDevices != null) {
      attachedActivity.unregisterInputDeviceListener(attachedDevices)
    }
    attachedActivity?.unregisterKeyEventHandler()
    attachedActivity?.unregisterMotionEventHandler()
    compatibleActivity = null
    devices = null
    events = null
  }
}
