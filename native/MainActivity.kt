package com.dramaflow.aistudio

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Native helpers for DramaFlow.
 *
 * - pickVideo: Storage Access Framework video picker. The video is never
 *   copied: only its content URI is kept, plus a small thumbnail.
 * - shareText: Android sharing (ACTION_SEND), the Gemini app first, then the
 *   normal share sheet.
 * - pickTextFile / saveTextFile: import and export text files (SRT and so on)
 *   through the Storage Access Framework.
 *
 * No storage permission is needed. Nothing here talks to the internet.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.dramaflow.aistudio/media"
    private val pickVideoCode = 4101
    private val pickTextCode = 4102
    private val saveTextCode = 4103
    private val geminiPackage = "com.google.android.apps.bard"
    private val maxShareChars = 200_000
    private val maxImportBytes = 5 * 1024 * 1024

    private val pending = HashMap<Int, MethodChannel.Result>()
    private var pendingSaveText: String? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideo" -> startPickVideo(result)
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val gemini = call.argument<Boolean>("gemini") ?: true
                        result.success(shareText(text, gemini))
                    }
                    "pickTextFile" -> startPickText(result)
                    "saveTextFile" -> {
                        val name = call.argument<String>("name") ?: "subtitles.srt"
                        val text = call.argument<String>("text") ?: ""
                        startSaveText(result, name, text)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun claim(code: Int, result: MethodChannel.Result): Boolean {
        if (pending.containsKey(code)) {
            result.error("busy", "The picker is already open", null)
            return false
        }
        pending[code] = result
        return true
    }

    private fun launch(code: Int, intent: Intent) {
        try {
            startActivityForResult(intent, code)
        } catch (e: Exception) {
            val r = pending.remove(code)
            r?.error("no_picker", e.message ?: "No file picker found", null)
        }
    }

    // ---- video ----

    private fun startPickVideo(result: MethodChannel.Result) {
        if (!claim(pickVideoCode, result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        launch(pickVideoCode, intent)
    }

    // ---- share ----

    /** Returns "gemini", "chooser" or "too_large". */
    private fun shareText(text: String, preferGemini: Boolean): String {
        if (text.length > maxShareChars) return "too_large"
        val base = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        if (preferGemini) {
            try {
                startActivity(Intent(base).setPackage(geminiPackage))
                return "gemini"
            } catch (e: ActivityNotFoundException) {
                // Gemini app is not installed. Fall back to the share sheet.
            } catch (e: SecurityException) {
                // Same fallback.
            }
        }
        startActivity(Intent.createChooser(base, null))
        return "chooser"
    }

    // ---- text files ----

    private fun startPickText(result: MethodChannel.Result) {
        if (!claim(pickTextCode, result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("text/plain", "text/*", "application/x-subrip", "application/octet-stream")
            )
        }
        launch(pickTextCode, intent)
    }

    private fun startSaveText(result: MethodChannel.Result, name: String, text: String) {
        if (!claim(saveTextCode, result)) return
        pendingSaveText = text
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        launch(saveTextCode, intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val result = pending.remove(requestCode)
        if (result == null) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val uri = data?.data
        when (requestCode) {
            pickVideoCode -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                keepAccess(uri)
                worker.execute {
                    try {
                        val info = readVideoInfo(uri)
                        runOnUiThread { result.success(info) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("read_failed", e.message ?: "Cannot read this video", null)
                        }
                    }
                }
            }
            pickTextCode -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                worker.execute {
                    try {
                        val info = readTextFile(uri)
                        runOnUiThread { result.success(info) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("read_failed", e.message ?: "Cannot read this file", null)
                        }
                    }
                }
            }
            saveTextCode -> {
                val text = pendingSaveText ?: ""
                pendingSaveText = null
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                worker.execute {
                    try {
                        contentResolver.openOutputStream(uri, "wt")?.use {
                            it.write(text.toByteArray(Charsets.UTF_8))
                        } ?: throw IllegalStateException("Cannot open the file for writing")
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("write_failed", e.message ?: "Cannot save the file", null)
                        }
                    }
                }
            }
            else -> result.success(null)
        }
    }

    private fun keepAccess(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: Exception) {
            // Some providers do not allow persisting. The URI still works now.
        }
    }

    private fun readTextFile(uri: Uri): HashMap<String, Any?> {
        var name = "file.txt"
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (ni >= 0) name = c.getString(ni) ?: name
            }
        }
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Cannot open the file")
        val bytes = input.use { s ->
            val buf = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(16 * 1024)
            var total = 0
            while (true) {
                val n = s.read(chunk)
                if (n < 0) break
                total += n
                if (total > maxImportBytes) {
                    throw IllegalStateException("File is larger than 5 MB")
                }
                buf.write(chunk, 0, n)
            }
            buf.toByteArray()
        }
        return hashMapOf("name" to name, "text" to String(bytes, Charsets.UTF_8))
    }

    private fun readVideoInfo(uri: Uri): HashMap<String, Any?> {
        var name = "video"
        var size = 0L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (ni >= 0) name = c.getString(ni) ?: name
                val si = c.getColumnIndex(OpenableColumns.SIZE)
                if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
            }
        }

        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(this, uri)
            val durationMs =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            if (durationMs <= 0L) {
                throw IllegalStateException("Duration not readable. Try an MP4 file.")
            }
            var w =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val t = w
                w = h
                h = t
            }

            var thumbPath: String? = null
            val atUs = minOf(1_000_000L, durationMs * 500L)
            val frame = r.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (frame != null && frame.width > 0) {
                val tw = 480
                val th = maxOf(1, tw * frame.height / frame.width)
                val scaled = Bitmap.createScaledBitmap(frame, tw, th, true)
                val dir = File(filesDir, "thumbs")
                dir.mkdirs()
                val out = File(dir, "t_" + System.currentTimeMillis() + ".jpg")
                FileOutputStream(out).use { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                thumbPath = out.absolutePath
            }

            return hashMapOf(
                "uri" to uri.toString(),
                "name" to name,
                "sizeBytes" to size,
                "durationMs" to durationMs,
                "width" to w,
                "height" to h,
                "thumbnailPath" to thumbPath
            )
        } finally {
            r.release()
        }
    }
}
