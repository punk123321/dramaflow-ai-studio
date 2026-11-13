package com.dramaflow.aistudio

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
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
 * - Audio (Phase 5): Android text-to-speech to a WAV file, microphone
 *   recording to M4A, audio file import, playback and export.
 *
 * No storage permission is needed. Nothing here talks to the internet.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.dramaflow.aistudio/media"
    private val pickVideoCode = 4101
    private val pickTextCode = 4102
    private val saveTextCode = 4103
    private val pickAudioCode = 4104
    private val exportFileCode = 4105
    private val pickImageCode = 4106
    private val micPermissionCode = 4201
    private val geminiPackage = "com.google.android.apps.bard"
    private val maxShareChars = 200_000
    private val maxImportBytes = 50 * 1024 * 1024

    private val pending = HashMap<Int, MethodChannel.Result>()
    private var pendingSaveText: String? = null
    private var pendingExportPath: String? = null
    private var pendingMicResult: MethodChannel.Result? = null
    private var pendingMicName: String? = null
    private var channel: MethodChannel? = null
    private var render: RenderEngine? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var player: MediaPlayer? = null
    private var recorder: MediaRecorder? = null
    private var recordPath: String? = null
    private var recordStartedAt = 0L
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        val rch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.dramaflow.aistudio/render")
        val engine = RenderEngine(this, rch)
        render = engine
        rch.setMethodCallHandler { call, result ->
            if (!engine.handle(call.method, call.arguments as? Map<*, *>, result)) result.notImplemented()
        }
        ch.setMethodCallHandler { call, result ->
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
                    "ttsStatus" -> ttsStatus(result)
                    "ttsSynthesize" -> ttsSynthesize(
                        result,
                        call.argument<String>("text") ?: "",
                        call.argument<String>("name") ?: "tts_" + System.currentTimeMillis(),
                        (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        (call.argument<Double>("pitch") ?: 1.0).toFloat()
                    )
                    "pickAudio" -> startPickAudio(result)
                    "pickImage" -> startPickImage(result)
                    "playAudio" -> playAudio(result, call.argument<String>("source") ?: "")
                    "stopAudio" -> {
                        stopPlayer()
                        result.success(true)
                    }
                    "recordStart" -> recordStart(result, call.argument<String>("name") ?: "mic_" + System.currentTimeMillis())
                    "recordStop" -> recordStop(result)
                    "exportFile" -> startExport(
                        result,
                        call.argument<String>("path") ?: "",
                        call.argument<String>("name") ?: "audio.wav",
                        call.argument<String>("mime") ?: "application/octet-stream"
                    )
                    "saveAudioBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val safe = (call.argument<String>("name") ?: "api_" + System.currentTimeMillis()).replace(Regex("[^A-Za-z0-9_.-]"), "_")
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("empty", "No audio", null)
                        } else {
                            worker.execute {
                                try {
                                    val out = File(audioDir(), "$safe.wav")
                                    out.writeBytes(bytes)
                                    val d = durationOf(out.absolutePath)
                                    runOnUiThread {
                                        if (d > 0L) result.success(hashMapOf("path" to out.absolutePath, "durationMs" to d, "sizeBytes" to out.length()))
                                        else {
                                            out.delete()
                                            result.error("empty_audio", "The audio could not be read", null)
                                        }
                                    }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("save_failed", e.message ?: e.toString(), null) }
                                }
                            }
                        }
                    }
                    "deleteFile" -> {
                        val f = File(call.argument<String>("path") ?: "")
                        val ok = f.absolutePath.startsWith(File(filesDir, "audio").absolutePath) && f.delete()
                        result.success(ok)
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
                arrayOf("*/*", "text/plain", "text/*", "application/json", "application/x-subrip", "application/octet-stream")
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
            pickAudioCode -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                keepAccess(uri)
                worker.execute {
                    try {
                        val info = readAudioInfo(uri)
                        runOnUiThread { result.success(info) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("read_failed", e.message ?: "Cannot read this audio", null)
                        }
                    }
                }
            }
            pickImageCode -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                worker.execute {
                    try {
                        val path = copyLogo(uri)
                        runOnUiThread { result.success(path) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("read_failed", e.message ?: "Cannot read this picture", null) }
                    }
                }
            }
            exportFileCode -> {
                val src = pendingExportPath
                pendingExportPath = null
                if (resultCode != Activity.RESULT_OK || uri == null || src == null) {
                    result.success(null)
                    return
                }
                worker.execute {
                    try {
                        contentResolver.openOutputStream(uri, "wt")?.use { out ->
                            File(src).inputStream().use { it.copyTo(out) }
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

    // ---- audio ----

    private fun audioDir(): File {
        val d = File(filesDir, "audio")
        d.mkdirs()
        return d
    }

    private fun startPickAudio(result: MethodChannel.Result) {
        if (!claim(pickAudioCode, result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        launch(pickAudioCode, intent)
    }

    private fun startPickImage(result: MethodChannel.Result) {
        if (!claim(pickImageCode, result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        launch(pickImageCode, intent)
    }

    /** Keeps a small copy of the picked picture inside the app, so the logo still works later. */
    private fun copyLogo(uri: Uri): String {
        val dir = File(filesDir, "logos").apply { mkdirs() }
        val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, opts) }
        var sample = 1
        while (opts.outWidth / sample > 1024) sample *= 2
        val dec = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
        val bmp = contentResolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, dec) }
            ?: throw IllegalStateException("Cannot read this picture")
        val out = File(dir, "logo_" + System.currentTimeMillis() + ".png")
        FileOutputStream(out).use { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        return out.absolutePath
    }

    private fun startExport(result: MethodChannel.Result, path: String, name: String, mime: String) {
        if (!File(path).exists()) {
            result.error("missing", "Audio file not found", null)
            return
        }
        if (!claim(exportFileCode, result)) return
        pendingExportPath = path
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        launch(exportFileCode, intent)
    }

    private fun readAudioInfo(uri: Uri): HashMap<String, Any?> {
        var name = "audio"
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
            if (durationMs <= 0L) throw IllegalStateException("Duration not readable. Try an MP3 or M4A file.")
            return hashMapOf(
                "source" to uri.toString(),
                "name" to name,
                "sizeBytes" to size,
                "durationMs" to durationMs
            )
        } finally {
            r.release()
        }
    }

    private fun durationOf(path: String): Long {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        } finally {
            r.release()
        }
    }

    // text to speech

    private fun burmeseLocale(t: TextToSpeech): Locale? {
        val candidates = listOf(Locale("my", "MM"), Locale("my"))
        for (l in candidates) {
            val r = t.isLanguageAvailable(l)
            if (r >= TextToSpeech.LANG_AVAILABLE) return l
        }
        return null
    }

    private fun withTts(onReady: (TextToSpeech?) -> Unit) {
        val existing = tts
        if (existing != null && ttsReady) {
            onReady(existing)
            return
        }
        var created: TextToSpeech? = null
        created = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts = created
                onReady(created)
            } else {
                try {
                    created?.shutdown()
                } catch (e: Exception) {
                }
                onReady(null)
            }
        }
    }

    private fun ttsStatus(result: MethodChannel.Result) {
        withTts { t ->
            if (t == null) {
                result.success(hashMapOf("engineReady" to false, "burmese" to false, "engine" to null))
            } else {
                val l = burmeseLocale(t)
                result.success(
                    hashMapOf(
                        "engineReady" to true,
                        "burmese" to (l != null),
                        "engine" to t.defaultEngine
                    )
                )
            }
        }
    }

    private fun ttsSynthesize(result: MethodChannel.Result, text: String, name: String, rate: Float, pitch: Float) {
        if (text.isBlank()) {
            result.error("empty", "No text", null)
            return
        }
        if (text.length > TextToSpeech.getMaxSpeechInputLength()) {
            result.error("too_long", "Text is longer than the engine allows", null)
            return
        }
        withTts { t ->
            if (t == null) {
                result.error("no_engine", "No text-to-speech engine", null)
                return@withTts
            }
            val locale = burmeseLocale(t)
            if (locale == null) {
                result.error("no_burmese", "Burmese voice is not installed on this phone", null)
                return@withTts
            }
            t.language = locale
            t.setSpeechRate(rate)
            t.setPitch(pitch)
            val safe = name.replace(Regex("[^A-Za-z0-9_.-]"), "_")
            val out = File(audioDir(), "$safe.wav")
            val id = "df_" + System.currentTimeMillis()
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    if (utteranceId != id) return
                    worker.execute {
                        val d = durationOf(out.absolutePath)
                        runOnUiThread {
                            if (d > 0L) {
                                result.success(hashMapOf("path" to out.absolutePath, "durationMs" to d, "sizeBytes" to out.length()))
                            } else {
                                result.error("empty_audio", "The engine produced no audio", null)
                            }
                        }
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    if (utteranceId != id) return
                    runOnUiThread { result.error("tts_failed", "Speech synthesis failed", null) }
                }
            })
            val rc = t.synthesizeToFile(text, null, out, id)
            if (rc != TextToSpeech.SUCCESS) {
                result.error("tts_failed", "Speech synthesis could not start", null)
            }
        }
    }

    // playback

    private fun stopPlayer() {
        try {
            player?.stop()
        } catch (e: Exception) {
        }
        try {
            player?.release()
        } catch (e: Exception) {
        }
        player = null
    }

    private fun playAudio(result: MethodChannel.Result, source: String) {
        stopPlayer()
        try {
            val p = MediaPlayer()
            if (source.startsWith("content://") || source.startsWith("file://")) {
                p.setDataSource(this, Uri.parse(source))
            } else {
                p.setDataSource(source)
            }
            p.setOnCompletionListener {
                stopPlayer()
                channel?.invokeMethod("playbackEnded", null)
            }
            p.setOnErrorListener { _, _, _ ->
                stopPlayer()
                channel?.invokeMethod("playbackEnded", null)
                true
            }
            p.prepare()
            p.start()
            player = p
            result.success(true)
        } catch (e: Exception) {
            stopPlayer()
            result.error("play_failed", e.message ?: "Cannot play this audio", null)
        }
    }

    // microphone

    private fun recordStart(result: MethodChannel.Result, name: String) {
        if (recorder != null) {
            result.error("busy", "Already recording", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            if (pendingMicResult != null) {
                result.error("busy", "Permission request in progress", null)
                return
            }
            pendingMicResult = result
            pendingMicName = name
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), micPermissionCode)
            return
        }
        beginRecording(result, name)
    }

    private fun beginRecording(result: MethodChannel.Result, name: String) {
        stopPlayer()
        val safe = name.replace(Regex("[^A-Za-z0-9_.-]"), "_")
        val out = File(audioDir(), "$safe.m4a")
        try {
            @Suppress("DEPRECATION")
            val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioEncodingBitRate(96000)
            r.setAudioSamplingRate(44100)
            r.setOutputFile(out.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            recordPath = out.absolutePath
            recordStartedAt = System.currentTimeMillis()
            result.success(true)
        } catch (e: Exception) {
            recorder = null
            result.error("record_failed", e.message ?: "Cannot start recording", null)
        }
    }

    private fun recordStop(result: MethodChannel.Result) {
        val r = recorder
        val path = recordPath
        if (r == null || path == null) {
            result.error("not_recording", "Not recording", null)
            return
        }
        recorder = null
        recordPath = null
        try {
            r.stop()
        } catch (e: RuntimeException) {
            // Stopped too quickly: no usable audio.
            try {
                r.release()
            } catch (x: Exception) {
            }
            File(path).delete()
            result.error("too_short", "Recording was too short", null)
            return
        }
        r.release()
        worker.execute {
            val d = durationOf(path)
            runOnUiThread {
                result.success(hashMapOf("path" to path, "durationMs" to d, "sizeBytes" to File(path).length()))
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != micPermissionCode) return
        val res = pendingMicResult
        val name = pendingMicName
        pendingMicResult = null
        pendingMicName = null
        if (res == null || name == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            beginRecording(res, name)
        } else {
            res.error("no_permission", "Microphone permission was not granted", null)
        }
    }

    override fun onDestroy() {
        stopPlayer()
        try {
            recorder?.release()
        } catch (e: Exception) {
        }
        try {
            tts?.shutdown()
        } catch (e: Exception) {
        }
        super.onDestroy()
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
                    throw IllegalStateException("File is larger than 50 MB")
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
