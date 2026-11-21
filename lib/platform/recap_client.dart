import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/news_video.dart';
import '../core/recap_auto.dart';

class RecapCanceled implements Exception {
  const RecapCanceled();
}

/// Talks to the user's own backend (tools/dramaflow_backend): start a recap
/// job, ask how far it is, download the voice files.
class RecapClient {
  RecapClient(this.settings);

  final NewsVideoSettings settings;
  bool _canceled = false;
  HttpClient? _http;

  void cancel() {
    _canceled = true;
    _http?.close(force: true);
  }

  Uri _uri(String path) => Uri.parse('${settings.url}$path');

  Future<(int, String)> _call(String method, String path, {String? json}) async {
    final c = _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final req = await (method == 'GET' ? c.getUrl(_uri(path)) : c.postUrl(_uri(path)));
    req.headers.set('x-app-token', settings.token);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      final bytes = utf8.encode(json);
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final resp = await req.close().timeout(const Duration(seconds: 90));
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body);
  }

  static String httpError(int code, String body) {
    String? detail;
    try {
      final m = jsonDecode(body);
      if (m is Map && m['detail'] is String) detail = m['detail'] as String;
    } catch (_) {}
    final why = switch (code) {
      401 => 'Token မမှန်ဘူး (APP_TOKEN ကို စစ်ပါ)',
      404 => 'မတွေ့ပါ (Backend က Recap version အသစ် မဟုတ်ဘူးနိုင်တယ်)',
      409 => 'Backend မှာ တခြား job လုပ်နေတုန်း',
      413 => 'ပို့တဲ့ အရွယ်အစား ကြီးလွန်းတယ်',
      502 || 503 || 504 || 524 => 'Backend မရောက်ဘူး (ပိတ်နေလား၊ ပြတ်နေလား)',
      _ => 'HTTP $code',
    };
    return detail == null ? why : '$why ($detail)';
  }

  /// Starts the job and waits for it. Throws [HttpException] (Burmese reason)
  /// or [RecapCanceled].
  Future<RecapJob> run(Map<String, Object?> request, void Function(RecapJob) onUpdate) async {
    try {
      var r = await _call('POST', '/recap/jobs', json: jsonEncode(request));
      if (_canceled) throw const RecapCanceled();
      if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
      final id = (jsonDecode(r.$2) as Map)['job_id'];
      if (id is! String) throw const HttpException('Job id မရ');
      final started = DateTime.now();
      var failures = 0;
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (_canceled) throw const RecapCanceled();
        try {
          r = await _call('GET', '/recap/jobs/$id');
          failures = 0;
        } on SocketException {
          if (++failures >= 5) throw const HttpException('Backend နဲ့ ဆက်သွယ်လို့မရတော့ဘူး');
          continue;
        } on TimeoutException {
          if (++failures >= 5) throw const HttpException('Backend ပြန်မဖြေတော့ဘူး');
          continue;
        }
        if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
        final job = parseRecapJob(r.$2);
        onUpdate(job);
        if (job.state == JobState.error) throw HttpException(job.error);
        if (job.state == JobState.done) return job;
        if (DateTime.now().difference(started).inMinutes > 60) throw const HttpException('အချိန်ကြာလွန်းလို့ ရပ်လိုက်တယ်');
      }
    } on RecapCanceled {
      rethrow;
    } catch (e) {
      if (_canceled) throw const RecapCanceled();
      rethrow;
    }
  }

  /// The voice file (WAV bytes) at [path] from a finished job.
  Future<Uint8List> downloadAudio(String path) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _http = c;
    try {
      final req = await c.getUrl(_uri(path));
      req.headers.set('x-app-token', settings.token);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        final body = await resp.transform(utf8.decoder).join();
        throw HttpException(httpError(resp.statusCode, body));
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        b.add(chunk);
      }
      return b.takeBytes();
    } catch (e) {
      if (_canceled) throw const RecapCanceled();
      rethrow;
    } finally {
      c.close(force: true);
      _http = null;
    }
  }

  /// One piece of narration as WAV bytes from the backend's /tts (Edge TTS).
  /// [ratePercent] 0 = normal, +20 faster, -20 slower. Throws [HttpException].
  Future<Uint8List> speak(String text, String voice, int ratePercent) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _http = c;
    try {
      final req = await c.postUrl(_uri('/tts'));
      req.headers.set('x-app-token', settings.token);
      req.headers.contentType = ContentType.json;
      final r = ratePercent.clamp(-50, 100);
      final body = utf8.encode(jsonEncode({'text': text, 'voice': voice, 'rate': '${r >= 0 ? '+' : '-'}${r.abs()}%'}));
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        final err = await resp.transform(utf8.decoder).join();
        throw HttpException(httpError(resp.statusCode, err));
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        b.add(chunk);
      }
      final bytes = b.takeBytes();
      if (bytes.isEmpty) throw const HttpException('အသံ မပါလာဘူး');
      return bytes;
    } on SocketException {
      throw const HttpException('Backend နဲ့ ဆက်သွယ်လို့မရဘူး (Colab/Altare ပွင့်နေလား၊ URL မှန်လား)');
    } on TimeoutException {
      throw const HttpException('Backend ပြန်မဖြေဘူး (အချိန်ကြာလွန်းတယ်)');
    } finally {
      c.close(force: true);
      _http = null;
    }
  }

  void dispose() {
    _http?.close(force: true);
    _http = null;
  }
}
