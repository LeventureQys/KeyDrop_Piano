package com.keydrop.keydrop_piano.midi

import android.content.Context
import android.hardware.usb.UsbManager
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiInputPort
import android.media.midi.MidiManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Android 端 USB MIDI 实时输入。EventChannel → Dart 端字节流。 */
class MidiInputPlugin : FlutterPlugin, ActivityAware {

    private var deviceChannel: EventChannel? = null
    private var eventChannel: EventChannel? = null
    private var controlChannel: MethodChannel? = null

    private var deviceSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null

    private var midiManager: MidiManager? = null
    private var currentDevice: MidiDevice? = null
    private var currentInputPort: MidiInputPort? = null
    private var currentDeviceName: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val deviceCallback = object : MidiManager.DeviceCallback() {
        override fun onDeviceAdded(info: MidiDeviceInfo) {
            currentDeviceName = info.properties?.getString(MidiDeviceInfo.PROPERTY_NAME)
                ?: "MIDI Device"
            sendDeviceName()
        }
        override fun onDeviceRemoved(info: MidiDeviceInfo) {
            if (currentDevice?.info?.id == info.id) {
                disconnectDevice()
            }
            sendDeviceName()
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // EventChannel: 设备名变化
        deviceChannel = EventChannel(binding.binaryMessenger, "keydrop_piano/midi_device")
        deviceChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deviceSink = events
                sendDeviceName()
            }
            override fun onCancel(arguments: Any?) { deviceSink = null }
        })

        // EventChannel: MIDI 事件字节流
        eventChannel = EventChannel(binding.binaryMessenger, "keydrop_piano/midi_events")
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })

        // MethodChannel: 控制
        controlChannel = MethodChannel(binding.binaryMessenger, "keydrop_piano/midi_control")
        controlChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "tryConnect" -> {
                    tryConnect()
                    result.success(null)
                }
                "disconnect" -> {
                    disconnectDevice()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disconnectDevice()
        deviceChannel = null
        eventChannel = null
        controlChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        midiManager = binding.activity.getSystemService(Context.MIDI_SERVICE) as? MidiManager
        midiManager?.registerDeviceCallback(deviceCallback, mainHandler)
        updateDeviceName()
    }

    override fun onDetachedFromActivity() {
        midiManager?.unregisterDeviceCallback(deviceCallback)
        disconnectDevice()
        midiManager = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    private fun updateDeviceName() {
        val devices = midiManager?.devices ?: return
        if (devices.isNotEmpty()) {
            currentDeviceName = devices[0].properties?.getString(MidiDeviceInfo.PROPERTY_NAME)
                ?: "MIDI Device"
        } else {
            currentDeviceName = null
        }
        sendDeviceName()
    }

    private fun sendDeviceName() {
        mainHandler.post {
            deviceSink?.success(currentDeviceName?.toByteArray())
        }
    }

    private fun tryConnect() {
        val mm = midiManager ?: return
        val devices = mm.devices ?: return
        if (devices.isEmpty()) return

        val info = devices[0]
        // 检查是否为 USB 设备
        val props = info.properties
        if (props?.containsKey(UsbManager.EXTRA_PERMISSION_GRANTED) == false) {
            // 非 USB 设备，仍尝试连接
        }

        mm.openDevice(info, { device ->
            if (device == null) return@openDevice
            currentDevice = device
            currentDeviceName = info.properties?.getString(MidiDeviceInfo.PROPERTY_NAME) ?: "MIDI Device"
            sendDeviceName()

            val inputPortCount = device.info.inputPortCount
            if (inputPortCount == 0) return@openDevice
            // NOTE: MidiInputPort 的连接逻辑将在真机调试阶段（Stage 7）完善。
            //       当前仅打开设备端口保证编译通过。
            currentInputPort = device.openInputPort(0)
            sendDeviceName()
        }, mainHandler)
    }

    private fun disconnectDevice() {
        try { currentInputPort?.close() } catch (_: Exception) {}
        currentInputPort = null
        try { currentDevice?.close() } catch (_: Exception) {}
        currentDevice = null
        currentDeviceName = null
        sendDeviceName()
    }

    private fun handleMidiData(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
        val sink = eventSink ?: return
        val end = offset + count
        var i = offset
        while (i < end) {
            val status = msg[i].toInt() and 0xFF
            // 跳过系统实时消息 (0xF8–0xFF 除了 0xF0 SysEx start)
            if (status >= 0xF8) {
                i += 1
                continue
            }
            val dataLen = when (status and 0xF0) {
                0x80, 0x90, 0xA0, 0xB0, 0xE0 -> 2
                0xC0, 0xD0 -> 1
                else -> 0
            }
            if (i + 1 + dataLen > end) {
                i += 1
                continue
            }
            val d1 = if (dataLen >= 1) (msg[i + 1].toInt() and 0xFF) else 0
            val d2 = if (dataLen >= 2) (msg[i + 2].toInt() and 0xFF) else 0
            val packet = ByteBuffer.allocate(11).order(ByteOrder.BIG_ENDIAN)
            packet.put(msg[i])
            packet.put(msg[i + 1])
            packet.put(if (i + 2 < end) msg[i + 2] else 0x00)
            packet.putLong(timestamp)
            sink.success(packet.array())
            i += 1 + dataLen
        }
    }

    private fun String.toByteArray(): ByteArray = this.toByteArray(Charsets.UTF_8)
}
