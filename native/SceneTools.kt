package com.dramaflow.aistudio

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Scene Recap helpers. The original video is only read, never changed.
 *
 *  - analyzeFrames: a tiny colour signature (16 x 9) of frames at a fixed step. The scene
 *    finding itself is done in Dart (core/scenes.dart), where it is unit tested.
 *  - contactSheet: one picture with one numbered tile per scene (middle frame of the scene),
 *    saved in the app cache (for the preview) and in Pictures/DramaFlow (so it can be shared).
 *  - shareImage: sends that picture and a text to the Gemini app (or the share list).
 */
class SceneTools(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val geminiPackage = "com.google.android.apps.bard"

    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result): Boolean {
        when (method) {
            "analyzeFrames" -> analyze(args, result)
            "contactSheet" -> sheet(args, result)
            "shareImage" -> shareImage(args, result)
            else -> return false
        }
        return true
    }

    private fun open(uri: Uri): MediaMetadataRetriever {
        val r = MediaMetadataRetriever()
        r.setDataSource(activity, uri)
        return r
    }

    private fun scaled(r: MediaMetadataRetriever, atMs: Long, w: Int, h: Int): Bitmap? {
        val us = atMs * 1000L
        return if (Build.VERSION.SDK_INT >= 27) {
            r.getScaledFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST, w, h)
        } else {
            val f = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST) ?: return null
            val s = Bitmap.createScaledBitmap(f, w, h, true)
            if (s !== f) f.recycle()
            s
        }
    }

    private fun analyze(args: Map<*, *>?, result: MethodChannel.Result) {
        val uri = Uri.parse(args?.get("uri") as? String ?: "")
        val from = (args?.get("fromMs") as? Number)?.toLong() ?: 0L
        val to = (args?.get("toMs") as? Number)?.toLong() ?: 0L
        val step = ((args?.get("stepMs") as? Number)?.toLong() ?: 1000L).coerceAtLeast(250L)
        worker.execute {
            try {
                val times = ArrayList<Long>()
                var t = from
                while (t < to && times.size < 400) {
                    times.add(t)
                    t += step
                }
                val sig = ByteArray(times.size * 16 * 9 * 3)
                val r = open(uri)
                try {
                    var off = 0
                    for (ms in times) {
                        val b = scaled(r, ms, 16, 9)
                        if (b == null) {
                            // A frame that cannot be read repeats the previous one (no cut there).
                            if (off >= 432) System.arraycopy(sig, off - 432, sig, off, 432)
                            off += 432
                            continue
                        }
                        val px = IntArray(16 * 9)
                        b.getPixels(px, 0, 16, 0, 0, 16, 9)
                        b.recycle()
                        for (p in px) {
                            sig[off++] = Color.red(p).toByte()
                            sig[off++] = Color.green(p).toByte()
                            sig[off++] = Color.blue(p).toByte()
                        }
                    }
                } finally {
                    r.release()
                }
                main.post { result.success(hashMapOf("times" to times.map { it.toInt() }, "sig" to sig)) }
            } catch (e: Exception) {
                main.post { result.error("analyze_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun fmt(ms: Long): String {
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val ss = s % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, ss) else "%d:%02d".format(m, ss)
    }

    private fun sheet(args: Map<*, *>?, result: MethodChannel.Result) {
        val uri = Uri.parse(args?.get("uri") as? String ?: "")
        val name = args?.get("name") as? String ?: ("scenes_" + System.currentTimeMillis())
        val cols = ((args?.get("cols") as? Number)?.toInt() ?: 4).coerceIn(1, 6)
        val toGallery = args?.get("gallery") as? Boolean ?: true
        val cellW = ((args?.get("cellW") as? Number)?.toInt() ?: 384).coerceIn(160, 640)
        @Suppress("UNCHECKED_CAST")
        val items = (args?.get("items") as? List<Map<String, Any?>>) ?: emptyList()
        if (items.isEmpty()) {
            result.error("no_items", "No scenes", null)
            return
        }
        worker.execute {
            try {
                val r = open(uri)
                val tiles = ArrayList<Triple<Int, Long, Bitmap>>()
                var aspect = 16f / 9f
                try {
                    for ((i, it) in items.withIndex()) {
                        val n = (it["n"] as Number).toInt()
                        val at = (it["atMs"] as Number).toLong()
                        val f = r.getFrameAtTime(at * 1000L, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue
                        if (i == 0 || tiles.isEmpty()) aspect = f.width.toFloat() / f.height.toFloat()
                        val h = (cellW / aspect).toInt().coerceAtLeast(90)
                        val s = Bitmap.createScaledBitmap(f, cellW, h, true)
                        if (s !== f) f.recycle()
                        tiles.add(Triple(n, at, s))
                    }
                } finally {
                    r.release()
                }
                if (tiles.isEmpty()) throw IllegalStateException("Could not read any frame")
                val cellH = tiles[0].third.height
                val gap = 6
                val rows = (tiles.size + cols - 1) / cols
                val sheet = Bitmap.createBitmap(cols * cellW + (cols + 1) * gap, rows * cellH + (rows + 1) * gap, Bitmap.Config.ARGB_8888)
                val c = Canvas(sheet)
                c.drawColor(Color.BLACK)
                val badge = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(200, 0, 0, 0) }
                val txt = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textSize = cellH * 0.16f
                    typeface = Typeface.DEFAULT_BOLD
                }
                for ((i, t) in tiles.withIndex()) {
                    val x = gap + (i % cols) * (cellW + gap)
                    val y = gap + (i / cols) * (cellH + gap)
                    c.drawBitmap(t.third, x.toFloat(), y.toFloat(), null)
                    val label = "#${t.first}  ${fmt(t.second)}"
                    val w = txt.measureText(label) + 16f
                    c.drawRoundRect(RectF(x + 6f, y + 6f, x + 6f + w, y + 6f + txt.textSize * 1.4f), 8f, 8f, badge)
                    c.drawText(label, x + 14f, y + 6f + txt.textSize * 1.08f, txt)
                    t.third.recycle()
                }
                val f = File(activity.cacheDir, "sheet_${System.nanoTime()}.jpg")
                FileOutputStream(f).use { sheet.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                sheet.recycle()
                var link: String? = null
                if (toGallery && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = activity.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, "$name.jpg")
                        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                        put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/DramaFlow")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val out = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Gallery refused the picture")
                    try {
                        resolver.openOutputStream(out)?.use { o -> f.inputStream().use { it.copyTo(o) } }
                            ?: throw IllegalStateException("Cannot write to the gallery")
                        resolver.update(out, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
                        link = out.toString()
                    } catch (e: Exception) {
                        resolver.delete(out, null, null)
                        throw e
                    }
                }
                main.post { result.success(hashMapOf("path" to f.absolutePath, "gallery" to link)) }
            } catch (e: Exception) {
                main.post { result.error("sheet_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    /** "gemini", "chooser" or "no_uri" (the phone is too old to share the picture). */
    private fun shareImage(args: Map<*, *>?, result: MethodChannel.Result) {
        val link = args?.get("gallery") as? String
        val text = args?.get("text") as? String ?: ""
        if (link.isNullOrEmpty()) {
            result.success("no_uri")
            return
        }
        try {
            val base = Intent(Intent.ACTION_SEND).apply {
                type = "image/jpeg"
                putExtra(Intent.EXTRA_STREAM, Uri.parse(link))
                putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
                activity.startActivity(Intent(base).setPackage(geminiPackage))
                result.success("gemini")
            } catch (e: ActivityNotFoundException) {
                activity.startActivity(Intent.createChooser(base, "Gemini").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success("chooser")
            }
        } catch (e: Exception) {
            result.error("share_failed", e.message ?: e.toString(), null)
        }
    }
}
