import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/video_type.dart';

class GeminiUploadException implements Exception {
  GeminiUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiFile {
  const GeminiFile(this.uri, this.mime);
  final String uri;
  final String mime;
}

/// Puts the video into the user's own Gemini account (Files API) so Gemini can
/// watch it. The video is only read; a temporary copy lives in the app cache
/// during the upload and is deleted after. The key goes in a header.
class GeminiFiles {
  static const _channel = MethodChannel('com.dramaflow.aistudio/media');
  static const _base = 'https://generativelanguage.googleapis.com';

  /// Copies the video the user picked into the app cache (Android side).
  static Future<File> copyToCache(String videoUri) async {
    final r = await _channel.invokeMapMethod<Object?, Object?>('copyVideo', {'uri': videoUri});
    final p = r?['path'];
    if (p is! String) throw GeminiUploadException('ဗီဒီယို ကူးလို့မရဘူး');
    return File(p);
  }

  /// Uploads [file] and waits until Gemini has processed it.
  static Future<GeminiFile> upload(
    String apiKey,
    File file, {
    String? mime,
    required void Function(String stage, double? fraction) onStage,
    bool Function()? canceled,
  }) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final size = await file.length();
      if (mime == null) {
        final raf = await file.open();
        try {
          mime = sniffVideoKind(await raf.read(16)).mime;
        } finally {
          await raf.close();
        }
      }
      final videoMime = mime;
      onStage('Gemini ဆီ upload စတင်နေတယ်', null);
      final start = await c.postUrl(Uri.parse('$_base/upload/v1beta/files'));
      start.headers
        ..set('x-goog-api-key', apiKey.trim())
        ..set('X-Goog-Upload-Protocol', 'resumable')
        ..set('X-Goog-Upload-Command', 'start')
        ..set('X-Goog-Upload-Header-Content-Length', '$size')
        ..set('X-Goog-Upload-Header-Content-Type', videoMime)
        ..contentType = ContentType.json;
      final meta = utf8.encode(jsonEncode({'file': {'display_name': 'dramaflow_recap'}}));
      start.contentLength = meta.length;
      start.add(meta);
      final sr = await start.close().timeout(const Duration(seconds: 60));
      final startBody = await sr.transform(utf8.decoder).join();
      if (sr.statusCode != 200) throw GeminiUploadException(_explain(sr.statusCode, startBody, apiKey));
      final url = sr.headers.value('x-goog-upload-url');
      if (url == null) throw GeminiUploadException('Gemini က upload လိပ်စာ မပေးဘူး');

      final up = await c.postUrl(Uri.parse(url));
      up.headers
        ..set('X-Goog-Upload-Offset', '0')
        ..set('X-Goog-Upload-Command', 'upload, finalize');
      up.contentLength = size;
      var sent = 0;
      await for (final chunk in file.openRead()) {
        if (canceled?.call() ?? false) {
          up.abort();
          throw GeminiUploadException('ရပ်လိုက်ပြီ');
        }
        up.add(chunk);
        sent += chunk.length;
        onStage('Gemini ဆီ upload ${(sent * 100 / size).round()}%', sent / size);
        await up.flush();
      }
      final ur = await up.close().timeout(const Duration(minutes: 10));
      final upBody = await ur.transform(utf8.decoder).join();
      if (ur.statusCode != 200) throw GeminiUploadException(_explain(ur.statusCode, upBody, apiKey));
      final f = (jsonDecode(upBody) as Map)['file'] as Map;
      final name = f['name'] as String;
      final uri = f['uri'] as String;
      var state = f['state'] as String? ?? 'PROCESSING';
      var waited = 0;
      while (state == 'PROCESSING') {
        if (canceled?.call() ?? false) throw GeminiUploadException('ရပ်လိုက်ပြီ');
        if (waited > 600) throw GeminiUploadException('Gemini က ဗီဒီယိုကို မပြီးသေးဘူး (၁၀ မိနစ်ကျော်)');
        onStage('Gemini က ဗီဒီယိုကို ပြင်ဆင်နေတယ်', null);
        await Future<void>.delayed(const Duration(seconds: 5));
        waited += 5;
        final greq = await c.getUrl(Uri.parse('$_base/v1beta/$name'));
        greq.headers.set('x-goog-api-key', apiKey.trim());
        final gr = await greq.close().timeout(const Duration(seconds: 30));
        final gb = await gr.transform(utf8.decoder).join();
        if (gr.statusCode != 200) throw GeminiUploadException(_explain(gr.statusCode, gb, apiKey));
        state = ((jsonDecode(gb) as Map)['state'] as String?) ?? 'PROCESSING';
      }
      if (state != 'ACTIVE') throw GeminiUploadException('Gemini က ဗီဒီယိုကို လက်မခံဘူး ($state)');
      return GeminiFile(uri, videoMime);
    } on SocketException {
      throw GeminiUploadException('Internet ချိတ်ဆက်မှု ပြတ်သွားတယ်');
    } on TimeoutException {
      throw GeminiUploadException('အချိန်ကြာလွန်းလို့ ရပ်လိုက်တယ်');
    } on HandshakeException {
      throw GeminiUploadException('လုံခြုံရေး ချိတ်ဆက်မှု မအောင်မြင်ဘူး');
    } finally {
      c.close(force: true);
    }
  }

  static String _explain(int code, String body, String key) {
    var detail = '';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map) detail = ((m['error'] as Map)['message'] as String?) ?? '';
    } catch (_) {}
    if (key.length >= 8) detail = detail.replaceAll(key, '***');
    final why = switch (code) {
      400 => 'Gemini က ဗီဒီယိုကို လက်မခံဘူး (mp4/mov/webm/avi လို ပုံစံ လိုတယ်၊ mkv မရဘူး)',
      401 || 403 => 'API key မမှန်ဘူး (သို့) ခွင့်မရှိဘူး',
      429 => 'Gemini quota ပြည့်နေတယ် (နောက်မှ ပြန်စမ်း)',
      _ => 'Gemini HTTP $code',
    };
    return detail.isEmpty ? why : '$why: ${detail.length > 160 ? detail.substring(0, 160) : detail}';
  }
}
