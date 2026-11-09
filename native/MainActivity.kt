package com.dramaflow.aistudio

import android.app.Activity
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
 * Video picker built on the Storage Access Framework.
 *
 * The video is never copied: only its content URI is kept (with a persistable
 * read permission), plus a small thumbnail saved in the app's own folder.
 * No storage permission is needed.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.dramaflow.aistudio/media"
    private val pickCode = 4101
    private var pending: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideo" -> startPick(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startPick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "The picker is already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, pickCode)
        } catch (e: Exception) {
            pending = null
            result.error("no_picker", e.message ?: "No file picker found", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (e: Exception) {
            // Some providers do not allow persisting. The URI still works now.
        }
        worker.execute {
            try {
                val info = readInfo(uri)
                runOnUiThread { result.success(info) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("read_failed", e.message ?: "Cannot read this video", null)
                }
            }
        }
    }

    private fun readInfo(uri: Uri): HashMap<String, Any?> {
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
