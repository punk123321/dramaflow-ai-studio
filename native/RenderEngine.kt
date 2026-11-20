package com.dramaflow.aistudio

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.util.Size
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.AlignmentSpan
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
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Brightness
import androidx.media3.effect.Contrast
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.OverlayEffect
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
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
import java.io.FileOutputStream
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
    private val tempFrames = ArrayList<File>()

    // Background keep-alive (see RenderService). [keepAlive] holds the service up
    // between the parts of a queue.
    private var keepAlive = false
    private var note = ""
    private var lastPct = -1

    private fun serviceOn() {
        try {
            val i = Intent(activity, RenderService::class.java)
                .putExtra("text", if (note.isNotEmpty()) note else "Render")
                .putExtra("percent", lastPct)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(i) else activity.startService(i)
        } catch (e: Exception) {
            // Not allowed right now: the render still runs while the app stays open.
        }
    }

    private fun serviceOff() {
        if (keepAlive) return
        try {
            activity.stopService(Intent(activity, RenderService::class.java))
        } catch (e: Exception) {
        }
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            // Only decides whether the progress notification is shown; the render does not depend on it.
            activity.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4199)
        }
    }

    private val rendersDir: File
        get() = File(activity.filesDir, "renders").apply { mkdirs() }

    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result): Boolean {
        when (method) {
            "renderStart" -> start(args?.get("job") as? String ?: "", result)
            "renderCancel" -> {
                cancel()
                result.success(null)
            }
            "renderKeepAlive" -> {
                keepAlive = args?.get("on") as? Boolean ?: false
                note = args?.get("text") as? String ?: ""
                if (keepAlive) {
                    askNotificationPermission()
                    serviceOn()
                } else {
                    lastPct = -1
                    serviceOff()
                }
                result.success(null)
            }
            "makeThumbnail" -> makeThumbnail(args, result)
            "uriReadable" -> {
                val u = args?.get("uri") as? String ?: ""
                val ok = try {
                    activity.contentResolver.openFileDescriptor(Uri.parse(u), "r")?.use { true } ?: false
                } catch (e: Exception) {
                    false
                }
                result.success(ok)
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

            clearTempFrames()
            checkInputs(job)
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
                        finish(false, 0L, height, describeError(exportException))
                    }
                })
                .build()
            transformer = t
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            askNotificationPermission()
            lastPct = 0
            serviceOn()
            t.start(composition, part.absolutePath)
            startPolling()
            result.success(null)
        } catch (e: Exception) {
            transformer = null
            clearTempFrames()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            serviceOff()
            result.error("render_failed", e.message ?: e.toString(), null)
        }
    }

    private fun buildComposition(job: JSONObject): Composition {
        val videoUri = Uri.parse(job.getString("videoUri"))
        val height = job.getInt("height")
        val fps = job.optInt("fps", 30)
        val aspect = job.optDouble("aspect", 16.0 / 9.0).let { if (it > 0.2 && it < 5.0) it else 16.0 / 9.0 }
        val outH = job.optInt("outH", height).let { if (it >= 2) it else height }
        val outW = job.optInt("outW", 0).let { if (it >= 2) it else (height * aspect).toInt() }
        // Text sizes follow the shorter side, so a vertical video is not given huge text.
        val base = minOf(outW, outH)
        val fit = job.optString("fit", "orig")
        val blurMode = fit == "blur"
        val fitW: Int
        val fitH: Int
        if (aspect > outW.toDouble() / outH) {
            fitW = outW
            fitH = ((outW / aspect).toInt() / 2 * 2).coerceAtLeast(2)
        } else {
            fitH = outH
            fitW = ((outH * aspect).toInt() / 2 * 2).coerceAtLeast(2)
        }
        val origVol = job.optDouble("originalVolume", 0.0).toFloat()

        // 1. Video pieces, in order.
        val pieces = job.getJSONArray("pieces")
        val vSeq = EditedMediaItemSequence.Builder()

        // Blur boxes (censor): for each one a second picture of the same video, made with the
        // same effects as the main picture, cut down to the rectangle and blurred, drawn over the
        // main picture while the box is on. If anything cannot be done the render stops with an
        // error, so a video that should have been censored is never exported uncensored.
        val censorJson = job.optJSONArray("censors")
        val censorCount = censorJson?.length() ?: 0
        if (censorCount > 0 && blurMode) throw IllegalStateException("Blur box နဲ့ Blur background တပြိုင်နက် မရပါ")
        if (censorCount > 0 && (job.optJSONArray("splits")?.length() ?: 0) > 0) throw IllegalStateException("Blur box နဲ့ Split Screen တပြိုင်နက် မရပါ")
        val cSeqs = ArrayList<EditedMediaItemSequence.Builder>()
        val cWins = ArrayList<CensorWin>()
        val cPendingUs = LongArray(censorCount)
        val cUsed = BooleanArray(censorCount)
        for (k in 0 until censorCount) {
            val c = censorJson!!.getJSONObject(k)
            val wf = c.getDouble("w").coerceIn(0.03, 1.0)
            val hf = (c.getDouble("w") * c.optDouble("ar", 0.5) * aspect).coerceIn(0.03, 1.0)
            val l = (c.getDouble("x") - wf / 2).coerceIn(0.0, 1.0)
            val r = (c.getDouble("x") + wf / 2).coerceIn(0.0, 1.0)
            val t = (c.getDouble("y") - hf / 2).coerceIn(0.0, 1.0)
            val bt = (c.getDouble("y") + hf / 2).coerceIn(0.0, 1.0)
            if (r - l < 0.01 || bt - t < 0.01) throw IllegalStateException("Blur box က ပုံအပြင်ဘက် ရောက်နေပါတယ်")
            cSeqs.add(EditedMediaItemSequence.Builder().experimentalSetForceVideoTrack(true))
            cWins.add(CensorWin(l.toFloat(), t.toFloat(), r.toFloat(), bt.toFloat(), c.optDouble("str", 25.0).toFloat().coerceIn(5f, 60f)))
        }
        var outCursorMs = 0.0

        // Called once for every piece, after its effects are known.
        fun censorPass(p: JSONObject, stillFile: File?, baseFx: List<Effect>, zoomMode: Int, pieceUs: Long) {
            val ps = p.getLong("s")
            val pe = p.getLong("e")
            val freeze = stillFile != null
            val spd = if (freeze) 1.0 else p.optDouble("sp", 1.0).coerceIn(0.25, 4.0)
            val lenMs = (pe - ps) / spd
            for (k in 0 until censorCount) {
                val c = censorJson!!.getJSONObject(k)
                val cs = c.getLong("s")
                val ce = c.getLong("e")
                val lo = maxOf(ps, cs)
                val hi = minOf(pe, ce)
                val hit = if (freeze) (ps >= cs && ps < ce) else (hi - lo >= 40)
                if (!hit) {
                    cPendingUs[k] += (lenMs * 1000).toLong()
                    continue
                }
                val win = cWins[k]
                val fx = ArrayList<Effect>(baseFx)
                if (!freeze && (zoomMode == 1 || zoomMode == 2)) {
                    if (lo != ps || hi != pe) throw IllegalStateException("Blur box က zoom ဖြစ်နေတဲ့ အပိုင်းရဲ့ တစ်ဝက်ပဲ ကျနေလို့ မရပါ")
                    fx.add(zoomEffect(zoomMode == 1, pieceUs))
                }
                fx.add(Crop(win.l * 2f - 1f, win.r * 2f - 1f, 1f - win.b * 2f, 1f - win.t * 2f))
                fx.add(GaussianBlur(win.strength))
                val seq = cSeqs[k]
                if (freeze) {
                    val gap = cPendingUs[k]
                    if (gap > 0) seq.addGap(gap)
                    cPendingUs[k] = 0
                    val holdUs = (pe - ps) * 1000L
                    val st = MediaItem.Builder()
                        .setUri(Uri.fromFile(stillFile))
                        .setMimeType(MimeTypes.IMAGE_JPEG)
                        .setImageDurationMs(pe - ps)
                        .build()
                    seq.addItem(EditedMediaItem.Builder(st).setDurationUs(holdUs).setFrameRate(fps).setEffects(Effects(emptyList<AudioProcessor>(), fx)).build())
                    win.ranges.add(longArrayOf(outCursorMs.toLong(), (outCursorMs + lenMs).toLong() + 50L))
                } else {
                    val gap = cPendingUs[k] + ((lo - ps) / spd * 1000).toLong()
                    if (gap > 0) seq.addGap(gap)
                    cPendingUs[k] = ((pe - hi) / spd * 1000).toLong()
                    val clip = MediaItem.Builder()
                        .setUri(videoUri)
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder().setStartPositionMs(lo).setEndPositionMs(hi).build()
                        )
                        .build()
                    seq.addItem(EditedMediaItem.Builder(clip).setRemoveAudio(true).setEffects(Effects(emptyList<AudioProcessor>(), fx)).build())
                    win.ranges.add(longArrayOf((outCursorMs + (lo - ps) / spd).toLong(), (outCursorMs + (hi - ps) / spd).toLong() + 50L))
                }
                cUsed[k] = true
            }
            outCursorMs += lenMs
        }

        for (i in 0 until pieces.length()) {
            val p = pieces.getJSONObject(i)
            if (p.optInt("f", 0) == 1) {
                // Held still frame: take the picture from the original, show it for a while.
                val file = extractFrame(videoUri, p.getLong("s"))
                validatePicture(file, "Freeze Frame")
                val holdUs = (p.getLong("e") - p.getLong("s")) * 1000L
                // Say it is a JPEG picture, so it is not guessed from the file name.
                val stillItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(file))
                    .setMimeType(MimeTypes.IMAGE_JPEG)
                    .setImageDurationMs((p.getLong("e") - p.getLong("s")))
                    .build()
                val still = EditedMediaItem.Builder(stillItem)
                    .setDurationUs(holdUs)
                    .setFrameRate(fps)
                val stillFx = ArrayList<Effect>()
                val stillLook = p.optJSONArray("l")
                if (stillLook != null && stillLook.length() == 2) {
                    stillFx.add(Brightness(stillLook.getDouble(0).toFloat()))
                    stillFx.add(Contrast(stillLook.getDouble(1).toFloat()))
                }
                val c = p.optJSONArray("c")
                if (c != null && c.length() == 3) {
                    stillFx.add(cropEffect(c.getDouble(0).toFloat(), c.getDouble(1).toFloat(), c.getDouble(2).toFloat()))
                }
                val stillBlur = p.optDouble("bl", 0.0).toFloat()
                if (stillBlur in 0.5f..50f) stillFx.add(GaussianBlur(stillBlur))
                val stillFlipH = p.optInt("fh", 0) == 1
                val stillFlipV = p.optInt("fv", 0) == 1
                if (stillFlipH || stillFlipV) stillFx.add(flipEffect(stillFlipH, stillFlipV))
                if (stillFx.isNotEmpty()) still.setEffects(Effects(emptyList<AudioProcessor>(), stillFx))
                vSeq.addItem(still.build())
                censorPass(p, file, stillFx, 0, holdUs)
                continue
            }
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
            if (origVol <= 0f) b.setRemoveAudio(true)
            // Speed (from approved Speed operations): picture and sound play faster or slower, pitch is kept.
            val pieceSpeed = p.optDouble("sp", 1.0).toFloat()
            val audioFx = ArrayList<AudioProcessor>()
            if (origVol > 0f) {
                if (pieceSpeed != 1f) audioFx.add(androidx.media3.common.audio.SpeedChangingAudioProcessor(constantSpeed(pieceSpeed)))
                audioFx.add(volume(origVol))
            }
            val zoom = p.optInt("z", 0)
            val pieceUs = (p.getLong("e") - p.getLong("s")) * 1000L
            val videoFx = ArrayList<Effect>()
            if (pieceSpeed != 1f) videoFx.add(androidx.media3.effect.SpeedChangeEffect(pieceSpeed))
            val look = p.optJSONArray("l")
            if (look != null && look.length() == 2) {
                videoFx.add(Brightness(look.getDouble(0).toFloat()))
                videoFx.add(Contrast(look.getDouble(1).toFloat()))
            }
            val crop = p.optJSONArray("c")
            if (crop != null && crop.length() == 3) {
                videoFx.add(cropEffect(crop.getDouble(0).toFloat(), crop.getDouble(1).toFloat(), crop.getDouble(2).toFloat()))
            }
            val blur = p.optDouble("bl", 0.0).toFloat()
            if (blur in 0.5f..50f) videoFx.add(GaussianBlur(blur))
            val flipH = p.optInt("fh", 0) == 1
            val flipV = p.optInt("fv", 0) == 1
            if (flipH || flipV) videoFx.add(flipEffect(flipH, flipV))
            val censorBaseFx = ArrayList<Effect>(videoFx)
            if (zoom == 1 || zoom == 2) videoFx.add(zoomEffect(zoom == 1, pieceUs))
            if (blurMode) videoFx.add(Presentation.createForWidthAndHeight(fitW, fitH, Presentation.LAYOUT_STRETCH_TO_FIT))
            if (audioFx.isNotEmpty() || videoFx.isNotEmpty()) b.setEffects(Effects(audioFx, videoFx))
            vSeq.addItem(b.build())
            censorPass(p, null, censorBaseFx, zoom, pieceUs)
        }
        val sequences = ArrayList<EditedMediaItemSequence>()
        var compositor: VideoCompositorSettings? = null
        if (blurMode) {
            // Experimental: a blurred, enlarged copy of the same video is the
            // bottom layer (input 0); the real picture sits on top (input 1).
            val bg = EditedMediaItemSequence.Builder()
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
                val fx = ArrayList<Effect>()
                val bgSpeed = p.optDouble("sp", 1.0).toFloat()
                if (bgSpeed != 1f) fx.add(androidx.media3.effect.SpeedChangeEffect(bgSpeed))
                fx.add(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP))
                fx.add(GaussianBlur(25f))
                bg.addItem(EditedMediaItem.Builder(item).setRemoveAudio(true).setEffects(Effects(emptyList<AudioProcessor>(), fx)).build())
            }
            sequences.add(bg.build())
            compositor = BlurFillCompositor(outW, outH)
        }
        sequences.add(vSeq.build())

        // 1b. Split screen (experimental): a second picture of the same video,
        //     shown only inside the windows. Both pictures are drawn at half size.
        val splits = job.optJSONArray("splits")
        if (splits != null && splits.length() > 0) {
            val sSeq = EditedMediaItemSequence.Builder().experimentalSetForceVideoTrack(true)
            val wins = ArrayList<SplitWin>()
            var cursorMs = 0L
            for (i in 0 until splits.length()) {
                val w = splits.getJSONObject(i)
                val s0 = w.getLong("s")
                val e0 = w.getLong("e")
                val src = w.getLong("src")
                if (s0 > cursorMs) sSeq.addGap((s0 - cursorMs) * 1000L)
                val clip = MediaItem.Builder()
                    .setUri(videoUri)
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(src)
                            .setEndPositionMs(src + (e0 - s0))
                            .build()
                    )
                    .build()
                sSeq.addItem(EditedMediaItem.Builder(clip).setRemoveAudio(true).build())
                cursorMs = e0
                wins.add(SplitWin(s0, e0, w.optString("layout") == "topBottom"))
            }
            sequences.add(sSeq.build())
            compositor = SplitCompositor(wins)
        }

        // 1c. Blur boxes: one extra picture per box, after the main picture (inputs 1, 2 ...).
        if (censorCount > 0) {
            val usedWins = ArrayList<CensorWin>()
            for (k in 0 until censorCount) {
                if (!cUsed[k]) continue
                sequences.add(cSeqs[k].build())
                usedWins.add(cWins[k])
            }
            if (usedWins.isNotEmpty()) compositor = CensorCompositor(usedWins)
        }

        // 2. Narration. Each lane is played one after another with gaps, and
        //    lanes are mixed on top of each other.
        val lanes = job.optJSONArray("voiceLanes") ?: JSONArray()
        for (l in 0 until lanes.length()) {
            val lane = lanes.getJSONArray(l)
            // The lane may start with a gap, so say it is an audio track.
            val seq = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
            var cursorMs = 0L
            for (i in 0 until lane.length()) {
                val v = lane.getJSONObject(i)
                val off = v.getLong("off")
                validateAudio(v.getString("uri"), "အသံ (narration / sound effect)")
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
            validateAudio(music.getString("uri"), "Background music")
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(music.getString("uri"))))
                .setRemoveVideo(true)
                .setEffects(Effects(listOf(volume(music.optDouble("vol", 0.25).toFloat())), emptyList<Effect>()))
                .build()
            val seq = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
            seq.addItem(item)
            seq.setIsLooping(music.optBoolean("loop", true))
            sequences.add(seq.build())
        }

        // 4. Output size, frame rate and burned-in subtitles.
        val videoEffects = ArrayList<Effect>()
        when (fit) {
            "bars" -> videoEffects.add(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT))
            "crop" -> videoEffects.add(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP))
            "blur" -> videoEffects.add(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT))
            else -> videoEffects.add(Presentation.createForHeight(height))
        }
        videoEffects.add(FrameDropEffect.createDefaultFrameDropEffect(fps.toFloat()))
        val overlays = ArrayList<TextureOverlay>()

        val subs = job.optJSONArray("subtitles")
        if (job.optBoolean("burn", true) && subs != null && subs.length() > 0) {
            val list = ArrayList<Sub>()
            val st0 = job.optJSONObject("subStyle")
            val sizePx0 = ((st0?.optDouble("size", 0.05) ?: 0.05) * base).toInt().coerceAtLeast(14)
            for (i in 0 until subs.length()) {
                val s = subs.getJSONObject(i)
                list.add(Sub(s.getLong("s"), s.getLong("e"), wrapText(s.getString("t"), sizePx0, (outW * 0.92f).toInt())))
            }
            val st = job.optJSONObject("subStyle")
            val sizePx = ((st?.optDouble("size", 0.05) ?: 0.05) * base).toInt().coerceAtLeast(14)
            val color = (st?.optLong("color", 0xFFFFFFFFL) ?: 0xFFFFFFFFL).toInt()
            overlays.add(SubtitleOverlay(list, sizePx, color, st?.optBoolean("bg", true) ?: true, st?.optBoolean("top", false) ?: false, st?.optBoolean("fade", false) ?: false))
        }

        val corners = job.optJSONArray("corners")
        if (corners != null) {
            for (i in 0 until corners.length()) {
                val c = corners.getJSONObject(i)
                val text = c.optString("t", "")
                if (text.isBlank()) continue
                val px = (c.optDouble("size", 0.035) * base).toInt().coerceAtLeast(12)
                overlays.add(CornerTextOverlay(wrapText(text, px, (outW * 0.6f).toInt()), c.optLong("color", 0xFFFFFFFFL).toInt(), px, c.optInt("c", 3)))
            }
        }

        // Labels and arrows from approved Motion Graphics operations (output time).
        val motion = job.optJSONArray("overlays")
        // One transparent full-size picture shared by every whole-picture effect when it is not shown.
        val fullBlank by lazy { Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888) }
        if (motion != null) {
            for (i in 0 until motion.length()) {
                val m = motion.getJSONObject(i)
                val startMs = m.getLong("s")
                val endMs = m.getLong("e")
                val cx = m.getDouble("x").toFloat()
                val cy = m.getDouble("y").toFloat()
                val color = m.getLong("color").toInt()
                val px = (m.getDouble("size") * base).toInt().coerceAtLeast(14)
                val settings = centerSettings(cx, cy)
                if (m.optString("k") == "image") {
                    // Picture-in-picture (a picture, not a second video): size is a share of the width.
                    val w = (m.getDouble("size") * outW).toInt()
                    val pic = loadLogo(m.optString("path", ""), w, 1f)
                    if (pic != null) {
                        val blank = Bitmap.createBitmap(pic.width, pic.height, Bitmap.Config.ARGB_8888)
                        overlays.add(WindowedBitmapOverlay(pic, blank, startMs, endMs, settings))
                    }
                } else if (m.optString("k") == "box" || m.optString("k") == "circle") {
                    // Outline to point at something. size = share of the width, ar = height / width.
                    val bw = (m.getDouble("size") * outW).toInt().coerceIn(40, outW)
                    val bh = (bw * m.optDouble("ar", 0.5)).toInt().coerceIn(20, outH)
                    val shape = shapeBitmap(bw, bh, color, m.optString("k") == "circle", m.optBoolean("fill", false))
                    val blank = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
                    overlays.add(WindowedBitmapOverlay(shape, blank, startMs, endMs, settings))
                } else if (m.optString("k") == "frame") {
                    // Border around the whole picture; size = thickness as a share of the short side.
                    val thick = (m.getDouble("size") * base).toFloat().coerceAtLeast(2f)
                    val frame = frameBitmap(outW, outH, thick, color, m.optBoolean("grad", false))
                    overlays.add(WindowedBitmapOverlay(frame, fullBlank, startMs, endMs, centerSettings(0.5f, 0.5f)))
                } else if (m.optString("k") == "spot") {
                    // Everything dimmed except one window.
                    val hw = (m.getDouble("size") * outW).toFloat().coerceIn(40f, outW.toFloat())
                    val hh = (hw * m.optDouble("ar", 0.6).toFloat()).coerceIn(20f, outH.toFloat())
                    val spot = spotBitmap(outW, outH, cx * outW, cy * outH, hw, hh, m.optBoolean("round", true))
                    overlays.add(WindowedBitmapOverlay(spot, fullBlank, startMs, endMs, centerSettings(0.5f, 0.5f)))
                } else if (m.optString("k") in listOf("fade", "vignette", "tint", "bars", "shade")) {
                    // Whole-picture looks. size = strength (see te_compile.dart).
                    val kind = m.optString("k")
                    val sz = m.getDouble("size").toFloat()
                    val whole = when (kind) {
                        "fade" -> solidBitmap(outW, outH, color)
                        "vignette" -> vignetteBitmap(outW, outH, sz)
                        "tint" -> tintBitmap(outW, outH, color, sz)
                        "bars" -> barsBitmap(outW, outH, sz)
                        else -> shadeBitmap(outW, outH, sz, m.optBoolean("top", false))
                    }
                    if (kind == "fade") {
                        overlays.add(FadeOverlay(whole, fullBlank, startMs, endMs, m.optString("dir", "dip")))
                    } else {
                        overlays.add(WindowedBitmapOverlay(whole, fullBlank, startMs, endMs, centerSettings(0.5f, 0.5f)))
                    }
                } else if (m.optString("k") == "arrow") {
                    val n = px.coerceIn(24, 1200)
                    val arrow = arrowBitmap(n, color, m.optDouble("angle", 0.0).toFloat())
                    val blank = Bitmap.createBitmap(n, n, Bitmap.Config.ARGB_8888)
                    overlays.add(WindowedBitmapOverlay(arrow, blank, startMs, endMs, settings))
                } else if (m.optBoolean("grad", false) && m.optString("t", "").isNotBlank()) {
                    // Label on a colourful rounded background, drawn as a picture.
                    val lbl = gradientLabelBitmap(m.optString("t", ""), color, px, (outW * 0.9f).toInt())
                    val blank = Bitmap.createBitmap(lbl.width, lbl.height, Bitmap.Config.ARGB_8888)
                    overlays.add(WindowedBitmapOverlay(lbl, blank, startMs, endMs, settings))
                } else {
                    overlays.add(WindowedTextOverlay(wrapText(m.optString("t", ""), px, (outW * 0.9f).toInt()), color, px, m.optBoolean("bg", true), startMs, endMs, settings))
                }
            }
        }

        val logo = job.optJSONObject("logo")
        if (logo != null) {
            val bmp = loadLogo(logo.getString("path"), (logo.optDouble("size", 0.15) * outW).toInt(), logo.optDouble("op", 0.9).toFloat())
            if (bmp != null) {
                overlays.add(BitmapOverlay.createStaticBitmapOverlay(bmp, cornerSettings(logo.optInt("c", 1))))
            }
        }
        if (overlays.isNotEmpty()) {
            videoEffects.add(OverlayEffect(ImmutableList.copyOf(overlays)))
        }

        val builder = Composition.Builder(sequences)
            .setEffects(Effects(emptyList<AudioProcessor>(), videoEffects))
        if (compositor != null) builder.setVideoCompositorSettings(compositor)
        return builder.build()
    }

    /** Fails early, naming the file, when an audio file cannot be read. */
    private fun validateAudio(uriText: String, what: String) {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(activity, Uri.parse(uriText), null)
            var audio = false
            for (i in 0 until ex.trackCount) {
                val mime = ex.getTrackFormat(i).getString(android.media.MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) audio = true
            }
            if (!audio) throw IllegalStateException("no audio track")
        } catch (e: Exception) {
            throw IllegalStateException("$what ဖတ်မရပါ (${e.message ?: "unsupported"}): $uriText")
        } finally {
            ex.release()
        }
    }

    /** Fails early when the saved still picture cannot be decoded. */
    private fun validatePicture(f: File, what: String) {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.absolutePath, o)
        if (o.outWidth <= 0 || o.outHeight <= 0 || f.length() < 100) {
            throw IllegalStateException("$what ပုံ မမှန်ပါ (${f.length()} bytes): ${f.name}")
        }
    }

    /**
     * Opens every audio file and the video once, before the render, so a file
     * that cannot be read is named in the error instead of a vague loader error.
     */
    private fun checkInputs(job: JSONObject) {
        probe("မူရင်းဗီဒီယို", job.getString("videoUri"), true)
        val lanes = job.optJSONArray("voiceLanes") ?: JSONArray()
        for (l in 0 until lanes.length()) {
            val lane = lanes.getJSONArray(l)
            for (i in 0 until lane.length()) {
                val v = lane.getJSONObject(i)
                probe("အသံ/narration ဖိုင်", v.getString("uri"), false)
            }
        }
        val music = job.optJSONObject("music")
        if (music != null) probe("Background music ဖိုင်", music.getString("uri"), false)
    }

    private fun probe(label: String, uri: String, video: Boolean) {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(activity, Uri.parse(uri), null)
            var found = false
            for (i in 0 until ex.trackCount) {
                val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith(if (video) "video/" else "audio/")) found = true
            }
            if (!found) throw IllegalStateException("$label: ${if (video) "video" else "audio"} track မတွေ့ပါ ($uri)")
        } catch (e: IllegalStateException) {
            throw e
        } catch (e: Exception) {
            throw IllegalStateException("$label ဖွင့်မရပါ: ${e.message} ($uri)")
        } finally {
            ex.release()
        }
    }

    /** One frame of the original, saved as a picture the renderer can hold. */
    private fun extractFrame(videoUri: Uri, atMs: Long): File {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(activity, videoUri)
            val bmp = r.getFrameAtTime(atMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IllegalStateException("Could not read the frame at ${atMs} ms")
            val f = File(activity.cacheDir, "freeze_${System.nanoTime()}.jpg")
            FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
            bmp.recycle()
            tempFrames.add(f)
            return f
        } finally {
            r.release()
        }
    }

    /** The error code and the chain of causes, so the real reason is visible. */
    private fun describeError(e: ExportException): String {
        val parts = ArrayList<String>()
        parts.add(e.errorCodeName)
        var t: Throwable? = e
        var depth = 0
        while (t != null && depth < 4) {
            val m = t.message
            if (!m.isNullOrBlank() && !parts.contains(m)) parts.add(m)
            t = t.cause
            depth++
        }
        return parts.joinToString(" | ")
    }

    private fun clearTempFrames() {
        for (f in tempFrames) f.delete()
        tempFrames.clear()
    }

    /** The same playback speed for the whole item. */
    private fun constantSpeed(speed: Float): androidx.media3.common.audio.SpeedProvider =
        object : androidx.media3.common.audio.SpeedProvider {
            override fun getSpeed(timeUs: Long): Float = speed
            override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = androidx.media3.common.C.TIME_UNSET
        }

    private fun volume(v: Float): AudioProcessor {
        val p = ChannelMixingAudioProcessor()
        for (ch in 1..2) {
            p.putChannelMixingMatrix(ChannelMixingMatrix.create(ch, ch).scaleBy(v))
        }
        return p
    }

    private class Sub(val startMs: Long, val endMs: Long, val text: String)

    /**
     * Still crop: keeps the area of size 1/zoom centred on (cx, cy), both 0..1
     * from the top-left. Screen coordinates here run -1..1 with y up.
     */
    /** Mirrors the picture left-right and/or top-bottom (scale -1 on that axis). */
    private fun flipEffect(h: Boolean, v: Boolean): Effect =
        ScaleAndRotateTransformation.Builder()
            .setScale(if (h) -1f else 1f, if (v) -1f else 1f)
            .build()

    private fun cropEffect(zoom: Float, cx: Float, cy: Float): Effect {
        val z = zoom.coerceIn(1f, 4f)
        val tx = 2f * cx.coerceIn(0f, 1f) - 1f
        val ty = 1f - 2f * cy.coerceIn(0f, 1f)
        return MatrixTransformation {
            Matrix().apply {
                postTranslate(-tx, -ty)
                postScale(z, z)
            }
        }
    }

    /** Slow zoom over one video piece: 100% to 115% (in) or 115% to 100% (out). */
    private fun zoomEffect(zoomIn: Boolean, pieceUs: Long): Effect {
        return MatrixTransformation { us ->
            val p = if (pieceUs > 0) ((us % pieceUs).toFloat() / pieceUs.toFloat()).coerceIn(0f, 1f) else 0f
            val scale = if (zoomIn) 1f + 0.15f * p else 1.15f - 0.15f * p
            Matrix().apply { postScale(scale, scale) }
        }
    }

    /** corner: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right. */
    private fun cornerSettings(corner: Int): StaticOverlaySettings {
        val left = corner == 0 || corner == 2
        val top = corner == 0 || corner == 1
        return StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(if (left) -1f else 1f, if (top) 1f else -1f)
            .setBackgroundFrameAnchor(if (left) -0.96f else 0.96f, if (top) 0.94f else -0.94f)
            .build()
    }

    /** Centre of the overlay at (x, y), 0..1 from the top-left of the picture. */
    private fun centerSettings(x: Float, y: Float): StaticOverlaySettings {
        return StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(0f, 0f)
            .setBackgroundFrameAnchor(2f * x.coerceIn(0f, 1f) - 1f, 1f - 2f * y.coerceIn(0f, 1f))
            .build()
    }

    /** A right-pointing arrow turned by [angle] degrees (90 = down). */
    private fun arrowBitmap(n: Int, color: Int, angle: Float): Bitmap {
        val bmp = Bitmap.createBitmap(n, n, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.rotate(angle, n / 2f, n / 2f)
        val m = n * 0.5f
        val path = android.graphics.Path().apply {
            moveTo(n * 0.08f, m - n * 0.09f)
            lineTo(n * 0.58f, m - n * 0.09f)
            lineTo(n * 0.58f, m - n * 0.24f)
            lineTo(n * 0.94f, m)
            lineTo(n * 0.58f, m + n * 0.24f)
            lineTo(n * 0.58f, m + n * 0.09f)
            lineTo(n * 0.08f, m + n * 0.09f)
            close()
        }
        val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = n * 0.03f
            this.color = Color.BLACK
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            this.color = color
        }
        c.drawPath(path, fill)
        c.drawPath(path, outline)
        return bmp
    }

    /** Outline of a rounded rectangle or an oval on a transparent picture. */
    private fun shapeBitmap(w: Int, h: Int, color: Int, oval: Boolean, fill: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val stroke = (minOf(w, h) * 0.06f).coerceIn(3f, 24f)
        val r = android.graphics.RectF(stroke, stroke, w - stroke, h - stroke)
        val dark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke * 1.6f
            this.color = Color.argb(150, 0, 0, 0)
        }
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            this.color = color
        }
        if (fill) {
            val f = Paint(Paint.ANTI_ALIAS_FLAG)
            f.color = Color.argb(77, Color.red(color), Color.green(color), Color.blue(color))
            if (oval) c.drawOval(r, f) else c.drawRoundRect(r, stroke, stroke, f)
        }
        if (oval) {
            c.drawOval(r, dark)
            c.drawOval(r, line)
        } else {
            c.drawRoundRect(r, stroke, stroke, dark)
            c.drawRoundRect(r, stroke, stroke, line)
        }
        return bmp
    }

    /** A border around the whole picture (rainbow or one colour). */
    private fun frameBitmap(w: Int, h: Int, thick: Float, color: Int, rainbow: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.style = Paint.Style.STROKE
        p.strokeWidth = thick
        if (rainbow) {
            p.shader = android.graphics.LinearGradient(
                0f, 0f, w.toFloat(), h.toFloat(),
                intArrayOf(0xFF2979FF.toInt(), 0xFF00E5FF.toInt(), 0xFF76FF03.toInt(), 0xFFFFEA00.toInt(), 0xFFFF1744.toInt(), 0xFFD500F9.toInt()),
                null, android.graphics.Shader.TileMode.CLAMP
            )
        } else {
            p.color = color
        }
        Canvas(bmp).drawRect(thick / 2f, thick / 2f, w - thick / 2f, h - thick / 2f, p)
        return bmp
    }

    /** The whole picture dimmed except one window (centre cx, cy). */
    private fun spotBitmap(w: Int, h: Int, cx: Float, cy: Float, hw: Float, hh: Float, oval: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.argb(150, 0, 0, 0))
        val clear = Paint(Paint.ANTI_ALIAS_FLAG)
        clear.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR)
        val r = android.graphics.RectF(cx - hw / 2f, cy - hh / 2f, cx + hw / 2f, cy + hh / 2f)
        if (oval) c.drawOval(r, clear) else c.drawRoundRect(r, hw * 0.08f, hw * 0.08f, clear)
        return bmp
    }

    private fun solidBitmap(w: Int, h: Int, color: Int): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.eraseColor(color)
        return bmp
    }

    /** Dark edges, clear middle. strength 0..1. */
    private fun vignetteBitmap(w: Int, h: Int, strength: Float): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val radius = Math.hypot(w.toDouble(), h.toDouble()).toFloat() / 2f
        val edge = Color.argb((strength.coerceIn(0f, 1f) * 0.9f * 255f).toInt(), 0, 0, 0)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = android.graphics.RadialGradient(
            w / 2f, h / 2f, radius,
            intArrayOf(Color.TRANSPARENT, Color.TRANSPARENT, edge),
            floatArrayOf(0f, 0.45f, 1f),
            android.graphics.Shader.TileMode.CLAMP
        )
        Canvas(bmp).drawRect(0f, 0f, w.toFloat(), h.toFloat(), p)
        return bmp
    }

    /** A see-through wash of one colour; opacity 0..1. */
    private fun tintBitmap(w: Int, h: Int, color: Int, opacity: Float): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.eraseColor(Color.argb((opacity.coerceIn(0f, 1f) * 255f).toInt(), Color.red(color), Color.green(color), Color.blue(color)))
        return bmp
    }

    /** Black bars at the top and bottom, each frac of the height. */
    private fun barsBitmap(w: Int, h: Int, frac: Float): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val bar = (h * frac.coerceIn(0f, 0.45f))
        val p = Paint()
        p.color = Color.BLACK
        val c = Canvas(bmp)
        c.drawRect(0f, 0f, w.toFloat(), bar, p)
        c.drawRect(0f, h - bar, w.toFloat(), h.toFloat(), p)
        return bmp
    }

    /** Dark gradient from the top or bottom edge, covering frac of the height. */
    private fun shadeBitmap(w: Int, h: Int, frac: Float, top: Boolean): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cover = h * frac.coerceIn(0.05f, 1f)
        val dark = Color.argb(190, 0, 0, 0)
        val p = Paint()
        if (top) {
            p.shader = android.graphics.LinearGradient(0f, 0f, 0f, cover, dark, Color.TRANSPARENT, android.graphics.Shader.TileMode.CLAMP)
            Canvas(bmp).drawRect(0f, 0f, w.toFloat(), cover, p)
        } else {
            p.shader = android.graphics.LinearGradient(0f, h.toFloat(), 0f, h - cover, dark, Color.TRANSPARENT, android.graphics.Shader.TileMode.CLAMP)
            Canvas(bmp).drawRect(0f, h - cover, w.toFloat(), h.toFloat(), p)
        }
        return bmp
    }

    /** Text on a violet to pink rounded background with a thin gold edge. */
    private fun gradientLabelBitmap(text: String, color: Int, px: Int, maxW: Int): Bitmap {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        paint.color = color
        paint.textSize = px.toFloat()
        paint.typeface = Typeface.DEFAULT_BOLD
        val padX = px * 0.7f
        val padY = px * 0.4f
        val lw = (maxW - 2 * padX).toInt().coerceAtLeast(60)
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, lw)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .build()
        var tw = 0f
        for (i in 0 until layout.lineCount) tw = maxOf(tw, layout.getLineWidth(i))
        val w = (tw + 2 * padX).toInt().coerceAtLeast(2)
        val h = (layout.height + 2 * padY).toInt().coerceAtLeast(2)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val bg = Paint(Paint.ANTI_ALIAS_FLAG)
        bg.shader = android.graphics.LinearGradient(0f, 0f, w.toFloat(), h.toFloat(), 0xFFA44CFF.toInt(), 0xFFFF3D9A.toInt(), android.graphics.Shader.TileMode.CLAMP)
        val r = android.graphics.RectF(2f, 2f, w - 2f, h - 2f)
        val rad = px * 0.45f
        c.drawRoundRect(r, rad, rad, bg)
        val edge = Paint(Paint.ANTI_ALIAS_FLAG)
        edge.style = Paint.Style.STROKE
        edge.strokeWidth = maxOf(2f, px * 0.06f)
        edge.color = 0xFFFFD54F.toInt()
        c.drawRoundRect(r, rad, rad, edge)
        c.translate(padX, padY)
        layout.draw(c)
        return bmp
    }

    private fun loadLogo(path: String, targetW: Int, opacity: Float): Bitmap? {
        return try {
            val src = BitmapFactory.decodeFile(path) ?: return null
            val w = targetW.coerceIn(24, 2000)
            val h = (src.height.toFloat() * w / src.width).toInt().coerceAtLeast(1)
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            paint.alpha = (opacity.coerceIn(0.05f, 1f) * 255).toInt()
            Canvas(out).drawBitmap(src, null, android.graphics.Rect(0, 0, w, h), paint)
            out
        } catch (e: Exception) {
            null
        }
    }

    private class SubtitleOverlay(
        private val subs: List<Sub>,
        private val sizePx: Int,
        private val color: Int,
        private val background: Boolean,
        private val top: Boolean,
        private val fade: Boolean = false
    ) : TextOverlay() {
        override fun getText(presentationTimeUs: Long): SpannableString {
            val ms = presentationTimeUs / 1000L
            val cur = subs.firstOrNull { ms >= it.startMs && ms < it.endMs }
            val line = cur?.text
            // No subtitle now: an invisible space with no background, or the
            // background colour would show as a small dark box.
            if (line == null) return SpannableString(" ")
            // Fade: full strength in the middle, ramping over 250 ms at both ends
            // (in 5 steps, so the picture is not redrawn on every frame).
            var level = 1f
            if (fade && cur != null) {
                val edge = minOf(ms - cur.startMs, cur.endMs - ms).coerceAtLeast(0L)
                if (edge < 250L) level = (((edge * 5) / 250L).toInt() + 1).coerceAtMost(5) / 5f
            }
            val s = SpannableString(line)
            s.setSpan(AbsoluteSizeSpan(sizePx), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            // Every line of a wrapped subtitle is centred (the default is left-aligned).
            s.setSpan(AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            val fg = Color.argb((Color.alpha(color) * level).toInt(), Color.red(color), Color.green(color), Color.blue(color))
            s.setSpan(ForegroundColorSpan(fg), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            if (background) {
                s.setSpan(BackgroundColorSpan(Color.argb((150 * level).toInt(), 0, 0, 0)), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            }
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            return StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(0f, if (top) 1f else -1f)
                .setBackgroundFrameAnchor(0f, if (top) 0.88f else -0.88f)
                .build()
        }
    }

    /**
     * Breaks [text] into lines no wider than [maxW] pixels at [sizePx], so text
     * stays inside a narrow (vertical) picture. Uses the system line breaker, so
     * Burmese, which has no spaces between words, is broken at allowed points.
     */
    private fun wrapText(text: String, sizePx: Int, maxW: Int): String {
        if (maxW <= 0 || text.isEmpty()) return text
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.textSize = sizePx.toFloat()
        val out = StringBuilder()
        for (para in text.split("\n")) {
            if (out.isNotEmpty()) out.append('\n')
            if (paint.measureText(para) <= maxW) {
                out.append(para)
                continue
            }
            val it = java.text.BreakIterator.getLineInstance()
            it.setText(para)
            var line = StringBuilder()
            var start = it.first()
            var end = it.next()
            while (end != java.text.BreakIterator.DONE) {
                val seg = para.substring(start, end)
                if (line.isNotEmpty() && paint.measureText(line.toString() + seg.trimEnd()) > maxW) {
                    out.append(line.toString().trimEnd()).append('\n')
                    line = StringBuilder()
                }
                line.append(seg)
                start = end
                end = it.next()
            }
            out.append(line.toString().trimEnd())
        }
        return out.toString()
    }

    /** Blur-fill layout: input 0 (blurred copy) fills the frame, input 1 is the real picture, centred. */
    private class BlurFillCompositor(private val w: Int, private val h: Int) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>): Size = Size(w, h)

        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings =
            StaticOverlaySettings.Builder().build()
    }

    /** One blur box: the rectangle (shares of the picture) and the output times it is on. */
    private class CensorWin(val l: Float, val t: Float, val r: Float, val b: Float, val strength: Float) {
        val ranges = ArrayList<LongArray>()
    }

    /**
     * Input 0 is the main picture, input 1, 2 ... the blurred rectangles. A rectangle is drawn
     * over its place only while its time range is on; otherwise it is invisible.
     */
    private class CensorCompositor(private val wins: List<CensorWin>) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>): Size = inputSizes[0]

        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
            if (inputId == 0) return StaticOverlaySettings.Builder().build()
            val w = wins.getOrNull(inputId - 1) ?: return StaticOverlaySettings.Builder().setAlphaScale(0f).build()
            val ms = presentationTimeUs / 1000L
            if (w.ranges.none { ms >= it[0] && ms < it[1] }) return StaticOverlaySettings.Builder().setAlphaScale(0f).build()
            val cx = (w.l + w.r) / 2f
            val cy = (w.t + w.b) / 2f
            return StaticOverlaySettings.Builder()
                .setScale(w.r - w.l, w.b - w.t)
                .setOverlayFrameAnchor(0f, 0f)
                .setBackgroundFrameAnchor(2f * cx - 1f, 1f - 2f * cy)
                .build()
        }
    }

    private class SplitWin(val startMs: Long, val endMs: Long, val topBottom: Boolean)

    /**
     * Input 0 is the edit, input 1 the second picture. Inside a window both are
     * drawn at half size side by side (or one above the other); outside it the
     * edit fills the frame and the second picture is invisible.
     */
    private class SplitCompositor(private val wins: List<SplitWin>) : VideoCompositorSettings {
        override fun getOutputSize(inputSizes: List<Size>): Size = inputSizes[0]

        override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
            val ms = presentationTimeUs / 1000L
            val w = wins.firstOrNull { ms >= it.startMs && ms < it.endMs }
            if (w == null) {
                return if (inputId == 0) StaticOverlaySettings.Builder().build()
                else StaticOverlaySettings.Builder().setAlphaScale(0f).build()
            }
            val first = inputId == 0
            val x = if (w.topBottom) 0f else if (first) -0.5f else 0.5f
            val y = if (w.topBottom) (if (first) 0.5f else -0.5f) else 0f
            return StaticOverlaySettings.Builder()
                .setScale(0.5f, 0.5f)
                .setOverlayFrameAnchor(0f, 0f)
                .setBackgroundFrameAnchor(x, y)
                .build()
        }
    }

    private class WindowedTextOverlay(
        private val text: String,
        private val color: Int,
        private val sizePx: Int,
        private val background: Boolean,
        private val startMs: Long,
        private val endMs: Long,
        private val settings: StaticOverlaySettings
    ) : TextOverlay() {
        override fun getText(presentationTimeUs: Long): SpannableString {
            val ms = presentationTimeUs / 1000L
            // Outside the time window: an invisible space, no background.
            if (ms < startMs || ms >= endMs || text.isBlank()) return SpannableString(" ")
            val s = SpannableString(text)
            s.setSpan(AbsoluteSizeSpan(sizePx), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            s.setSpan(AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            s.setSpan(ForegroundColorSpan(color), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            if (background) {
                s.setSpan(BackgroundColorSpan(Color.argb(170, 0, 0, 0)), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            }
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings
    }

    /** A full-picture colour whose strength follows the fade: in (1 to 0), out (0 to 1) or dip (0 to 1 to 0). */
    private class FadeOverlay(
        private val shown: Bitmap,
        private val blank: Bitmap,
        private val startMs: Long,
        private val endMs: Long,
        private val dir: String
    ) : BitmapOverlay() {
        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            val ms = presentationTimeUs / 1000L
            return if (ms >= startMs && ms < endMs) shown else blank
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val span = (endMs - startMs).coerceAtLeast(1L).toFloat()
            val t = (((presentationTimeUs / 1000L) - startMs).toFloat() / span).coerceIn(0f, 1f)
            val a = when (dir) {
                "in" -> 1f - t
                "out" -> t
                else -> 1f - Math.abs(2f * t - 1f)
            }
            return StaticOverlaySettings.Builder().setAlphaScale(a.coerceIn(0f, 1f)).build()
        }
    }

    private class WindowedBitmapOverlay(
        private val shown: Bitmap,
        private val blank: Bitmap,
        private val startMs: Long,
        private val endMs: Long,
        private val settings: StaticOverlaySettings
    ) : BitmapOverlay() {
        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            val ms = presentationTimeUs / 1000L
            return if (ms >= startMs && ms < endMs) shown else blank
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings
    }

    private class CornerTextOverlay(
        private val text: String,
        private val color: Int,
        private val sizePx: Int,
        private val corner: Int
    ) : TextOverlay() {
        private val settings: OverlaySettings by lazy {
            val left = corner == 0 || corner == 2
            val top = corner == 0 || corner == 1
            StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(if (left) -1f else 1f, if (top) 1f else -1f)
                .setBackgroundFrameAnchor(if (left) -0.96f else 0.96f, if (top) 0.94f else -0.94f)
                .build()
        }

        override fun getText(presentationTimeUs: Long): SpannableString {
            val s = SpannableString(text)
            s.setSpan(AbsoluteSizeSpan(sizePx), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            val rightSide = !(corner == 0 || corner == 2)
            s.setSpan(
                AlignmentSpan.Standard(if (rightSide) Layout.Alignment.ALIGN_OPPOSITE else Layout.Alignment.ALIGN_NORMAL),
                0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE
            )
            s.setSpan(ForegroundColorSpan(color), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            s.setSpan(BackgroundColorSpan(Color.argb(110, 0, 0, 0)), 0, s.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            return s
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings
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
                    if (holder.progress != lastPct) {
                        lastPct = holder.progress
                        serviceOn()
                    }
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
            clearTempFrames()
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            serviceOff()
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
        serviceOff()
        partFile?.delete()
        channel.invokeMethod("renderCanceled", null)
    }

    // ---- thumbnail ----

    /**
     * One frame of the original, with optional text at the bottom, saved as a
     * JPEG in Pictures/DramaFlow. The video itself is only read.
     */
    private fun makeThumbnail(args: Map<*, *>?, result: MethodChannel.Result) {
        val uri = Uri.parse(args?.get("videoUri") as? String ?: "")
        val atMs = (args?.get("atMs") as? Number)?.toLong() ?: 0L
        val text = (args?.get("text") as? String ?: "").trim()
        val name = args?.get("name") as? String ?: "thumbnail"
        worker.execute {
            try {
                val imagePath = args?.get("imagePath") as? String
                val frame = if (!imagePath.isNullOrEmpty()) {
                    // The user's own designed picture: read it, never change the original file.
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(imagePath, bounds)
                    var sample = 1
                    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2560) sample *= 2
                    BitmapFactory.decodeFile(imagePath, BitmapFactory.Options().apply { inSampleSize = sample })
                        ?: throw IllegalStateException("Could not read the picture")
                } else {
                    val r = MediaMetadataRetriever()
                    try {
                        r.setDataSource(activity, uri)
                        r.getFrameAtTime(atMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                    } finally {
                        r.release()
                    } ?: throw IllegalStateException("Could not read the frame at $atMs ms")
                }
                val bmp = frame.copy(Bitmap.Config.ARGB_8888, true)
                if (text.isNotEmpty()) {
                    val canvas = Canvas(bmp)
                    val size = minOf(bmp.width, bmp.height) * 0.10f
                    val fill = TextPaint(Paint.ANTI_ALIAS_FLAG)
                    fill.color = Color.WHITE
                    fill.textSize = size
                    fill.typeface = Typeface.DEFAULT_BOLD
                    val edge = TextPaint(fill)
                    edge.color = Color.BLACK
                    edge.style = Paint.Style.STROKE
                    edge.strokeWidth = size * 0.2f
                    edge.strokeJoin = Paint.Join.ROUND
                    val w = (bmp.width * 0.9f).toInt()
                    val back = StaticLayout.Builder.obtain(text, 0, text.length, edge, w)
                        .setAlignment(Layout.Alignment.ALIGN_CENTER).build()
                    val front = StaticLayout.Builder.obtain(text, 0, text.length, fill, w)
                        .setAlignment(Layout.Alignment.ALIGN_CENTER).build()
                    canvas.save()
                    canvas.translate((bmp.width - w) / 2f, bmp.height - front.height - bmp.height * 0.06f)
                    back.draw(canvas)
                    front.draw(canvas)
                    canvas.restore()
                }
                val f = File(activity.cacheDir, "thumb_${System.nanoTime()}.jpg")
                FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                var link: String? = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
                bmp.recycle()
                frame.recycle()
                main.post { result.success(hashMapOf("path" to f.absolutePath, "gallery" to link)) }
            } catch (e: Exception) {
                main.post { result.error("thumb_failed", e.message ?: e.toString(), null) }
            }
        }
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
