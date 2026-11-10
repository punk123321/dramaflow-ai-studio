package com.dramaflow.aistudio

import android.app.Activity
import android.content.ContentValues
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.Presentation
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Phase 7: renders the edit description made in the Studio Editor into a new
 * MP4 with AndroidX Media3 Transformer. The original video is only read.
 *
 * Output goes to the app's own "renders" folder as NAME.part.mp4 and is
 * renamed to NAME.mp4 only when the export finished, so an interrupted render
 * never leaves something that looks like a finished video.
 *
 * No internet, no API. Nothing leaves the phone.
 */
@OptIn(UnstableApi::class)
class RenderEngine(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var partFile: File? = null
    private var finalFile: File? = null
    private var polling = false

    private val rendersDir: File
        get() = File(activity.filesDir, "renders").apply { mkdirs() }

    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result): Boolean {
        when (method) {
            "renderStart" -> start(args?.get("job") as? String ?: "", result)
            "renderCancel" -> {
                cancel()
                result.success(null)
            }
            "renderFreeBytes" -> result.success(StatFs(rendersDir.path).availableBytes)
            "saveToGallery" -> saveToGallery(
                args?.get("path") as? String ?: "",
                args?.get("name") as? String ?: "dramaflow",
                result
            )
            "deleteRender" -> {
                val path = args?.get("path") as? String ?: ""
                val f = File(path)
                val ok = f.exists() && f.parentFile?.canonicalPath == rendersDir.canonicalPath && f.delete()
                result.success(ok)
            }
            else -> return false
        }
        return true
    }

    // ---- render ----

    private fun start(jobJson: String, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("busy", "A render is already running", null)
            return
        }
        try {
            val job = JSONObject(jobJson)
            val dir = rendersDir
            dir.listFiles()?.forEach { if (it.name.endsWith(".part.mp4")) it.delete() }

            val name = job.getString("name")
            val need = job.optLong("estimateBytes", 0L)
            val free = StatFs(dir.path).availableBytes
            if (free < need + need / 5 + 50L * 1024 * 1024) {
                result.error("low_storage", "Not enough free space: need about ${need / 1048576} MB", null)
                return
            }

            val part = File(dir, "$name.part.mp4")
            val fin = File(dir, "$name.mp4")
            part.delete()
            partFile = part
            finalFile = fin

            val composition = buildComposition(job)
            val height = job.getInt("height")
            val bitrate = job.getInt("bitrate")

            val t = Transformer.Builder(activity)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(
                    DefaultEncoderFactory.Builder(activity)
                        .setRequestedVideoEncoderSettings(
                            VideoEncoderSettings.Builder().setBitrate(bitrate).build()
                        )
                        .build()
                )
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        finish(true, exportResult.durationMs, height, null)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        finish(false, 0L, height, exportException.message ?: "Export failed")
                    }
                })
                .build()
            transformer = t
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            t.start(composition, part.absolutePath)
            startPolling()
            result.success(null)
        } catch (e: Exception) {
            transformer = null
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            result.error("render_failed", e.message ?: e.toString(), null)
        }
    }

    private fun buildComposition(job: JSONObject): Composition {
        val videoUri = Uri.parse(job.getString("videoUri"))
        val height = job.getInt("height")
        val fps = job.optInt("fps", 30)
        val origVol = job.optDouble("originalVolume", 0.0).toFloat()

        // 1. Video pieces, in order.
        val pieces = job.getJSONArray("pieces")
        val vSeq = EditedMediaItemSequence.Builder()
        for (i in 0 until pieces.length()) {
            val p = pieces.getJSONObject(i)
            val item = MediaItem.Builder()
                .setUri(videoUri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(p.getLong("s"))
                        .setEndPositionMs(p.getLong("e"))
                        .build()
                )
                .build()
            val b = EditedMediaItem.Builder(item)
            if (origVol <= 0f) {
                b.setRemoveAudio(true)
            } else {
                b.setEffects(Effects(listOf(volume(origVol)), emptyList<Effect>()))
            }
            vSeq.addItem(b.build())
        }
        val sequences = ArrayList<EditedMediaItemSequence>()
        sequences.add(vSeq.build())

        // 2. Narration. Each lane is played one after another with gaps, and
        //    lanes are mixed on top of each other.
        val lanes = job.optJSONArray("voiceLanes") ?: JSONArray()
        for (l in 0 until lanes.length()) {
            val lane = lanes.getJSONArray(l)
            // The lane may start with a gap, so say it is an audio track.
            val seq = EditedMediaItemSequence.Builder().setForceAudioTrack(true)
            var cursorMs = 0L
            for (i in 0 until lane.length()) {
                val v = lane.getJSONObject(i)
                val off = v.getLong("off")
                if (off > cursorMs) seq.addGap((off - cursorMs) * 1000L)
                val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(v.getString("uri"))))
                    .setRemoveVideo(true)
                    .setEffects(Effects(listOf(volume(v.optDouble("vol", 1.0).toFloat())), emptyList<Effect>()))
                    .build()
                seq.addItem(item)
                cursorMs = off + v.getLong("dur")
            }
            sequences.add(seq.build())
        }

        // 3. Background music, repeated when it is shorter than the video.
        val music = job.optJSONObject("music")
        if (music != null) {
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(music.getString("uri"))))
                .setRemoveVideo(true)
                .setEffects(Effects(listOf(volume(music.optDouble("vol", 0.25).toFloat())), emptyList<Effect>()))
                .build()
            val seq = EditedMediaItemSequence.Builder().setForceAudioTrack(true)
            seq.addItem(item)
            seq.setIsLooping(music.optBoolean("loop", true))
            sequences.add(seq.build())
        }

        // 4. Output size, frame rate and burned-in subtitles.
        val videoEffects = ArrayList<Effect>()
        videoEffects.add(Presentation.createForHeight(height))
        videoEffects.add(FrameDropEffect.createDefaultFrameDropEffect(fps.toFloat()))
        val subs = job.optJSONArray("subtitles")
        if (job.optBoolean("burn", true) && subs != null && subs.length() > 0) {
            val list = ArrayList<Sub>()
            for (i in 0 until subs.length()) {
                val s = subs.getJSONObject(i)
                list.add(Sub(s.getLong("s"), s.getLong("e"), s.getString("t")))
            }
            videoEffects.add(OverlayEffect(ImmutableList.of<TextureOverlay>(SubtitleOverlay(list, height))))
        }

        return Composition.Builder(sequences)
            .setEffects(Effects(emptyList<AudioProcessor>(), videoEffects))
            .build()
    }

    private fun volume(v: Float): AudioProcessor {
        val p = ChannelMixingAudioProcessor()
        for (ch in 1..2) {
            p.putChannelMixingMatrix(ChannelMixingMatrix.create(ch, ch).scaleBy(v))
        }
        return p
    }

    private class Sub(val startMs: Long, val endMs: Long, val text: String)

    private class SubtitleOverlay(private val subs: List<Sub>, private val height: Int) : TextOverlay() {
        override fun getText(presentationTimeUs: Long): SpannableString {
            val ms = presentationTimeUs / 1000L
            val line = subs.firstOrNull { ms >= it.startMs && ms < it.endMs }?.text ?: " "
            val s = SpannableString(line)
            val size = (height / 20).coerceAtLeast(18)
            s.setSpan(AbsoluteSizeSpan(size), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            s.setSpan(ForegroundColorSpan(Color.WHITE), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            s.setSpan(BackgroundColorSpan(Color.argb(150, 0, 0, 0)), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            return OverlaySettings.Builder()
                .setOverlayFrameAnchor(0f, -1f)
                .setBackgroundFrameAnchor(0f, -0.88f)
                .build()
        }
    }

    // ---- progress, finish, cancel ----

    private fun startPolling() {
        if (polling) return
        polling = true
        val holder = ProgressHolder()
        val tick = object : Runnable {
            override fun run() {
                val t = transformer
                if (t == null) {
                    polling = false
                    return
                }
                if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("renderProgress", hashMapOf("percent" to holder.progress))
                }
                main.postDelayed(this, 500)
            }
        }
        main.postDelayed(tick, 500)
    }

    private fun finish(ok: Boolean, durationMs: Long, height: Int, error: String?) {
        main.post {
            val part = partFile
            val fin = finalFile
            transformer = null
            polling = false
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (ok && part != null && fin != null && part.exists() && part.renameTo(fin)) {
                channel.invokeMethod(
                    "renderDone",
                    hashMapOf("path" to fin.absolutePath, "sizeBytes" to fin.length(), "durationMs" to durationMs, "height" to height)
                )
            } else {
                part?.delete()
                channel.invokeMethod("renderError", hashMapOf("message" to (error ?: "Could not finish the file")))
            }
        }
    }

    fun cancel() {
        val t = transformer ?: return
        t.cancel()
        transformer = null
        polling = false
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        partFile?.delete()
        channel.invokeMethod("renderCanceled", null)
    }

    // ---- gallery ----

    private fun saveToGallery(path: String, name: String, result: MethodChannel.Result) {
        val src = File(path)
        if (!src.exists()) {
            result.error("missing", "The video file is gone", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("use_export", "Use 'save as file' on this Android version", null)
            return
        }
        worker.execute {
            try {
                val resolver = activity.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, "$name.mp4")
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/DramaFlow")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Gallery refused the file")
                try {
                    resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
                        ?: throw IllegalStateException("Cannot write to the gallery")
                    val done = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
                    resolver.update(uri, done, null, null)
                } catch (e: Exception) {
                    resolver.delete(uri, null, null)
                    throw e
                }
                main.post { result.success(uri.toString()) }
            } catch (e: Exception) {
                main.post { result.error("save_failed", e.message ?: e.toString(), null) }
            }
        }
    }
}
