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
import java.util.UUID

/** Android 端文件系统操作：私有目录管理 + SAF 导入导出。 */
class FileSystemPlugin : FlutterPlugin, ActivityAware {

    private var channel: MethodChannel? = null
    private var privateDir: File? = null
    private var ctx: Context? = null

    private var pickMidiLauncher: ActivityResultLauncher<Array<String>>? = null
    private var exportLauncher: ActivityResultLauncher<String>? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingExportFileId: String? = null
    private var pendingExportResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        privateDir = ctx?.getExternalFilesDir(null)
        channel = MethodChannel(binding.binaryMessenger, "keydrop_piano/file_system")
        channel?.setMethodCallHandler { call, result ->
            try { handleCall(call, result) }
            catch (e: Exception) { result.error("FILE_ERROR", e.message, null) }
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
        exportLauncher = registry.register(
            "export_dk_${hashCode()}",
            ActivityResultContracts.CreateDocument("application/json")
        ) { uri: Uri? ->
            handleExportResult(uri)
        }
    }

    override fun onDetachedFromActivity() {
        pickMidiLauncher?.unregister()
        exportLauncher?.unregister()
        pickMidiLauncher = null
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
            "exportDkScore" -> {
                val fileId = call.argument<String>("fileId") ?: ""
                pendingExportFileId = fileId
                pendingExportResult = result
                // Derive a default filename
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

    private fun listDkScores(): String {
        val dir = ensureDir()
        val files = dir.listFiles { f -> f.name.endsWith(".dk.json") } ?: emptyArray()
        val arr = JSONArray()
        val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
        for (f in files) {
            val obj = JSONObject()
            obj.put("fileId", f.name)
            obj.put("displayName", f.name.removeSuffix(".dk.json"))
            obj.put("sizeBytes", f.length())
            obj.put("modifiedAt", fmt.format(Date(f.lastModified())))
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
        val f = File(dir, safe)
        // if exists, append suffix
        var dest = f
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
