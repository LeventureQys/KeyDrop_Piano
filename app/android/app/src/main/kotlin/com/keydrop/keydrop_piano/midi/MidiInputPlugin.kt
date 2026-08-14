package com.keydrop.keydrop_piano.midi

import android.content.Context
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
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

/**
 * Android 端 USB MIDI 实时输入（Stage 4.1 + 问题清单 C1）。
 *
 * 数据流（C1）：电钢琴 USB-B → OTG → 手机 → `MidiManager.openDevice`
 * → `MidiDevice.openOutputPort(0)`（**设备的输出端口** = 琴键数据流出方向）
 * → `MidiOutputPort.connect(MidiReceiver)`（经 MidiSender 基类）→ `onSend` 回调
 * → 逐条 MIDI 消息打包为 11 字节固定包（[status, data1, data2, timestampUs 8B 大端]）
 * → EventChannel `keydrop_piano/midi_events` → Dart 端 [AndroidMidiInputAdapter]。
 */
class MidiInputPlugin : FlutterPlugin, ActivityAware {

    private var deviceChannel: EventChannel? = null
    private var eventChannel: EventChannel? = null
    private var controlChannel: MethodChannel? = null

    private var deviceSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null

    private var midiManager: MidiManager? = null
    private var currentDevice: MidiDevice? = null
    private var currentOutputPort: MidiOutputPort? = null
    private var currentDeviceName: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    /** 接在 MidiInputPort 上的接收器：onSend 里拆消息 → 打包 → 推送 Dart。 */
    private val midiReceiver = object : MidiReceiver() {
        override fun onSend(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
            handleMidiData(msg, offset, count, timestamp)
        }
    }

    private val deviceCallback = object : MidiManager.DeviceCallback() {
        override fun onDeviceAdded(info: MidiDeviceInfo) {
            // 设备插入：更新名称；尚无连接时自动连接首个 USB 设备（T4 体验）。
            currentDeviceName = info.properties?.getString(MidiDeviceInfo.PROPERTY_NAME)
                ?: "MIDI Device"
            sendDeviceName()
            if (currentDevice == null) {
                tryConnect()
            }
        }

        override fun onDeviceRemoved(info: MidiDeviceInfo) {
            if (currentDevice?.info?.id == info.id) {
                disconnectDevice()
            } else {
                sendDeviceName()
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        deviceChannel = EventChannel(binding.binaryMessenger, "keydrop_piano/midi_device")
        deviceChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deviceSink = events
                sendDeviceName()
            }

            override fun onCancel(arguments: Any?) {
                deviceSink = null
            }
        })

        eventChannel = EventChannel(binding.binaryMessenger, "keydrop_piano/midi_events")
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        controlChannel = MethodChannel(binding.binaryMessenger, "keydrop_piano/midi_control")
        controlChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "tryConnect" -> {
                    try {
                        tryConnect()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("MIDI_CONNECT_ERROR", e.message, null)
                    }
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
        currentDeviceName = devices.firstOrNull()
            ?.properties?.getString(MidiDeviceInfo.PROPERTY_NAME)
            ?: null
        sendDeviceName()
    }

    private fun sendDeviceName() {
        mainHandler.post {
            deviceSink?.success(currentDeviceName?.toByteArray())
        }
    }

    /**
     * 扫描并打开首个可用 MIDI 设备（优先带名称属性的设备，通常为 USB）。
     * 打开设备的**输出端口**（琴键数据流出方向），经 `MidiSender.connect` 注册
     * [midiReceiver]，事件开始流动。
     */
    private fun tryConnect() {
        val mm = midiManager ?: throw IllegalStateException("MIDI service unavailable")
        val devices = mm.devices ?: emptyArray()
        if (devices.isEmpty()) {
            throw IllegalStateException("未检测到 MIDI 设备")
        }
        val info = devices.firstOrNull { d ->
            d.properties?.containsKey(MidiDeviceInfo.PROPERTY_NAME) == true
        } ?: devices.first()

        mm.openDevice(info, { device ->
            if (device == null) return@openDevice
            disconnectDevice() // 先关旧的，避免泄漏
            currentDevice = device
            currentDeviceName = info.properties?.getString(MidiDeviceInfo.PROPERTY_NAME)
                ?: "MIDI Device"
            sendDeviceName()

            val outputPortCount = device.info.outputPortCount
            if (outputPortCount == 0) return@openDevice
            val port = device.openOutputPort(0)
            port.connect(midiReceiver) // MidiOutputPort → MidiSender.connect
            currentOutputPort = port
        }, mainHandler)
    }

    private fun disconnectDevice() {
        try {
            currentOutputPort?.close()
        } catch (_: Exception) {
        }
        currentOutputPort = null
        try {
            currentDevice?.close()
        } catch (_: Exception) {
        }
        currentDevice = null
        currentDeviceName = null
        sendDeviceName()
    }

    /**
     * 把 onSend 的原始 MIDI 字节按状态字节拆成单条消息，
     * 每条打包为 11 字节：status / data1 / data2 / timestampUs(8B 大端)，
     * 合并到同一 ByteArray 一次性推给 Dart 端。
     */
    private fun handleMidiData(msg: ByteArray, offset: Int, count: Int, timestamp: Long) {
        val sink = eventSink ?: return
        val end = offset + count
        var i = offset
        val out = ByteArrayOutputStream()
        while (i < end) {
            val status = msg[i].toInt() and 0xFF
            // 系统实时消息（0xF8-0xFF）：单字节，跳过（不影响判定）。
            if (status >= 0xF8) {
                i += 1
                continue
            }
            // SysEx（0xF0/0xF7）：按 VLQ 长度整条跳过，不产生事件包。
            if (status == 0xF0 || status == 0xF7) {
                i += 1
                var len = 0
                var shift = 0
                while (i < end) {
                    val b = msg[i].toInt() and 0xFF
                    i += 1
                    len = len or ((b and 0x7F) shl shift)
                    if (b and 0x80 == 0) break
                    shift += 7
                    if (shift > 28) break
                }
                i += len
                continue
            }
            val dataLen = when (status and 0xF0) {
                0x80, 0x90, 0xA0, 0xB0, 0xE0 -> 2
                0xC0, 0xD0 -> 1
                else -> 0
            }
            if (i + dataLen >= end) {
                // 消息不完整（跨包）：本包丢弃，交给下次 onSend。
                i = end
                continue
            }
            val d1 = if (dataLen >= 1) msg[i + 1].toInt() and 0xFF else 0
            val d2 = if (dataLen >= 2) msg[i + 2].toInt() and 0xFF else 0
            val packet = ByteBuffer.allocate(11).order(ByteOrder.BIG_ENDIAN)
            packet.put(msg[i])
            packet.put(d1.toByte())
            packet.put(d2.toByte())
            packet.putLong(timestamp)
            out.write(packet.array())
            i += 1 + dataLen
        }
        if (out.size() > 0) {
            sink.success(out.toByteArray())
        }
    }

    private fun String.toByteArray(): ByteArray = this.toByteArray(Charsets.UTF_8)
}
