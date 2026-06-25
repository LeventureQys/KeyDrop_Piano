package com.keydrop.keydrop_piano

import com.keydrop.keydrop_piano.file.FileSystemPlugin
import com.keydrop.keydrop_piano.midi.MidiInputPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MidiInputPlugin())
        flutterEngine.plugins.add(FileSystemPlugin())
    }
}
