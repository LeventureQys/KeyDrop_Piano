package com.keydrop.keydrop_piano.file

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Android 端文件系统操作（Stage 4.4 契约）：
 * 私有目录管理（getExternalFilesDir）+ SAF 导入导出 + 临时 MIDI 字节读取。
 */
class FileSystemPlugin : FlutterPlugin, ActivityAware {

    private var channel: MethodChannel? = null
    private var privateDir: File? = null
    private var ctx: Context? = null

    private var pickMidiLauncher: ActivityResultLauncher<Array<String>>? = null
    private var pickDkLauncher: ActivityResultLauncher<Array<String>>? = null
    private var exportLauncher: ActivityResultLauncher<String>? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExportFileId: String? = null
    private var pendingExportResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        privateDir = ctx?.getExternalFilesDir(null)
        channel = MethodChannel(binding.binaryMessenger, "keydrop_piano/file_system")
        channel?.setMethodCallHandler { call, result ->
            try {
                handleCall(call, result)
            } catch (e: Exception) {
                result.error("FILE_ERROR", e.message, null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = null
        privateDir = null
        ctx = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val registry = (binding.activity as ComponentActivity).activityResultRegistry
        pickMidiLauncher = registry.register(
            "pick_midi_${hashCode()}",
            ActivityResultContracts.OpenDocument()
        ) { uri: Uri? ->
            handlePickResult(uri)
        }
        pickDkLauncher = registry.register(
            "pick_dk_${hashCode()}",
            ActivityResultContracts.OpenDocument()
        ) { uri: Uri? ->
            handleImportResult(uri)
        }
        exportLauncher = registry.register(
            "export_dk_${hashCode()}",
            ActivityResultContracts.CreateDocument("application/json")
        ) { uri: Uri? ->
            handleExportResult(uri)
        }
    }

    override fun onDetachedFromActivity() {
        pickMidiLauncher?.unregister()
        pickDkLauncher?.unregister()
        exportLauncher?.unregister()
        pickMidiLauncher = null
        pickDkLauncher = null
        exportLauncher = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDkScores" -> result.success(listDkScores())
            "readDkScore" -> {
                val fileId = call.argument<String>("fileId") ?: ""
                result.success(readDkScore(fileId))
            }
            "writeDkScore" -> {
                val name = call.argument<String>("fileName") ?: "untitled"
                val content = call.argument<String>("content") ?: ""
                result.success(writeDkScore(name, content))
            }
            "deleteDkScore" -> {
                val fileId = call.argument<String>("fileId") ?: ""
                deleteDkScore(fileId)
                result.success(null)
            }
            "renameDkScore" -> {
                val fileId = call.argument<String>("fileId") ?: ""
                val newName = call.argument<String>("newName") ?: fileId
                renameDkScore(fileId, newName)
                result.success(null)
            }
            "pickMidiFile" -> {
                pendingPickResult = result
                pickMidiLauncher?.launch(arrayOf("audio/midi", "audio/x-midi", "*/*"))
            }
            "readMidiFile" -> {
                val path = call.argument<String>("path") ?: ""
                val bytes = readMidiFile(path)
                if (bytes == null) {
                    result.error("READ_MIDI_ERROR", "MIDI file not readable: $path", null)
                } else {
                    result.success(bytes)
                }
            }
            "importDkScore" -> {
                pendingImportResult = result
                pickDkLauncher?.launch(arrayOf("application/json", "*/*"))
            }
            "exportDkScore" -> {
                val fileId = call.argument<String>("fileId") ?: ""
                pendingExportFileId = fileId
                pendingExportResult = result
                val defaultName = resolveExportName(fileId)
                exportLauncher?.launch(defaultName)
            }
            else -> result.notImplemented()
        }
    }

    // ---- Private directory operations ----

    private fun ensureDir(): File {
        val dir = privateDir ?: throw IllegalStateException("privateDir not initialized")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** ISO8601 格式（含时区），Dart 端 `DateTime.tryParse` 可直接解析。 */
    private fun iso8601(date: Date): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(date) + "Z"
    }

    private fun listDkScores(): String {
        val dir = ensureDir()
        val files = dir.listFiles { f -> f.name.endsWith(".dk.json") } ?: emptyArray()
        val arr = JSONArray()
        for (f in files) {
            val obj = JSONObject()
            obj.put("fileId", f.name)
            obj.put("displayName", f.name.removeSuffix(".dk.json"))
            obj.put("sizeBytes", f.length())
            obj.put("modifiedAt", iso8601(Date(f.lastModified())))
            arr.put(obj)
        }
        return arr.toString()
    }

    private fun readDkScore(fileId: String): String {
        val f = File(ensureDir(), fileId)
        if (!f.exists()) throw IllegalStateException("File not found: $fileId")
        return f.readText(Charsets.UTF_8)
    }

    private fun writeDkScore(fileName: String, content: String): String {
        val dir = ensureDir()
        val safe = if (fileName.endsWith(".dk.json")) fileName else "$fileName.dk.json"
        var dest = File(dir, safe)
        // if exists, append suffix
        if (dest.exists()) {
            val base = safe.removeSuffix(".dk.json")
            dest = File(dir, "${base}_${UUID.randomUUID().toString().take(8)}.dk.json")
        }
        dest.writeText(content, Charsets.UTF_8)
        return dest.name
    }

    private fun deleteDkScore(fileId: String) {
        val f = File(ensureDir(), fileId)
        if (f.exists()) f.delete()
    }

    private fun renameDkScore(fileId: String, newName: String) {
        val f = File(ensureDir(), fileId)
        if (!f.exists()) return
        val destName =
            if (newName.endsWith(".dk.json")) newName else "$newName.dk.json"
        f.renameTo(File(ensureDir(), destName))
    }

    private fun readMidiFile(path: String): ByteArray? {
        val f = File(path)
        if (!f.exists() || !f.canRead()) return null
        return f.readBytes()
    }

    // ---- SAF callbacks ----

    private fun handlePickResult(uri: Uri?) {
        val result = pendingPickResult
        pendingPickResult = null
        if (uri == null) {
            result?.success(null)
            return
        }
        try {
            val input = ctx?.contentResolver?.openInputStream(uri)
                ?: throw Exception("Cannot open URI")
            val tmpFile = File(ctx?.cacheDir, "temp_midi_${System.currentTimeMillis()}.mid")
            FileOutputStream(tmpFile).use { output ->
                input.copyTo(output)
            }
            input.close()
            result?.success(tmpFile.absolutePath)
        } catch (e: Exception) {
            result?.error("IMPORT_ERROR", e.message, null)
        }
    }

    /** 导入外部 .dk.json：复制到私有目录并返回新 fileId（V9）。 */
    private fun handleImportResult(uri: Uri?) {
        val result = pendingImportResult
        pendingImportResult = null
        if (uri == null) {
            result?.success(null)
            return
        }
        try {
            val input = ctx?.contentResolver?.openInputStream(uri)
                ?: throw Exception("Cannot open URI")
            val content = input.readBytes().toString(Charsets.UTF_8)
            input.close()
            // 从 JSON 中读取 meta.title 作为展示名；无则用文件显示名。
            val display = displayNameOf(uri)?.removeSuffix(".dk.json") ?: "imported"
            var title = display
            try {
                val meta = JSONObject(content).optJSONObject("meta")
                val t = meta?.optString("title")
                if (!t.isNullOrBlank()) title = t
            } catch (_: Exception) {
            }
            val fileId = writeDkScore(title, content)
            result?.success(fileId)
        } catch (e: Exception) {
            result?.error("IMPORT_ERROR", e.message, null)
        }
    }

    private fun displayNameOf(uri: Uri): String? {
        return try {
            val cursor = ctx?.contentResolver?.query(uri, null, null, null, null)
            cursor?.use {
                val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && it.moveToFirst()) it.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun handleExportResult(uri: Uri?) {
        val result = pendingExportResult
        val fileId = pendingExportFileId
        pendingExportResult = null
        pendingExportFileId = null
        if (uri == null || fileId == null) {
            result?.success(false)
            return
        }
        try {
            val src = File(ensureDir(), fileId)
            if (!src.exists()) {
                result?.success(false)
                return
            }
            val output = ctx?.contentResolver?.openOutputStream(uri)
                ?: throw Exception("Cannot open URI for writing")
            FileInputStream(src).use { input ->
                output.use { input.copyTo(it) }
            }
            result?.success(true)
        } catch (e: Exception) {
            result?.success(false)
        }
    }

    private fun resolveExportName(fileId: String): String {
        val display = if (fileId.endsWith(".dk.json"))
            fileId.removeSuffix(".dk.json") else fileId
        return "${display}.dk.json"
    }
}
