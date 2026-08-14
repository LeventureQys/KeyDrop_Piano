package com.keydrop.keydrop_piano

import android.view.WindowManager
import com.keydrop.keydrop_piano.file.FileSystemPlugin
import com.keydrop.keydrop_piano.midi.MidiInputPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MidiInputPlugin())
        flutterEngine.plugins.add(FileSystemPlugin())

        // 平台生命周期通道（Version 设计文档 2.1 PlatformLifecycle）：
        // 屏幕常亮（进入播放器时开、离开时关）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "keydrop_piano/lifecycle")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
