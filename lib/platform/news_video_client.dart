import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/news_video.dart';

class NewsVideoCanceled implements Exception {
  const NewsVideoCanceled();
}

/// Talks to the user's own backend: start a job, ask how far it is, download the MP4.
class NewsVideoClient {
  NewsVideoClient(this.settings);

  final NewsVideoSettings settings;
  bool _canceled = false;
  HttpClient? _http;

  bool get canceled => _canceled;

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
      req.write(json);
    }
    final resp = await req.close().timeout(const Duration(seconds: 40));
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body);
  }

  static String _httpError(int code, String body) {
    String? detail;
    try {
      final m = jsonDecode(body);
      if (m is Map && m['detail'] is String) detail = m['detail'] as String;
    } catch (_) {}
    final why = switch (code) {
      401 => 'Token မမှန်ဘူး (Colab ကို ပြန် run ထားရင် token အသစ် ယူပါ)',
      404 => 'မတွေ့ပါ — ဒီ URL က News Video backend မဟုတ်ဘူးနိုင်တယ် (Recap backend URL ကို ထည့်ထားလား၊ News notebook run ထားလား စစ်ပါ)',
      409 => 'Backend မှာ တခြား job လုပ်နေတုန်း',
      502 || 503 || 504 || 524 => 'Backend မရောက်ဘူး (Colab ပိတ်နေလား၊ tunnel ပြတ်နေလား)',
      _ => 'HTTP $code',
    };
    return detail == null ? why : '$why ($detail)';
  }

  /// The "service" name the backend gives at /health ("" when it gives none),
  /// or null when it does not answer.
  Future<String?> healthService() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(_uri('/health'));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return null;
      try {
        final m = jsonDecode(body);
        final sv = m is Map ? m['service'] : null;
        return sv is String ? sv : '';
      } catch (_) {
        return '';
      }
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  /// True when the backend answers /health.
  Future<bool> ping() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(_uri('/health'));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  /// Starts the job and waits for it. [onUpdate] gets every status.
  /// Throws [HttpException] with a Burmese reason, or [NewsVideoCanceled].
  Future<NewsJob> run(Map<String, Object?> request, void Function(NewsJob) onUpdate) async {
    try {
      var r = await _call('POST', '/jobs', json: jsonEncode(request));
      if (_canceled) throw const NewsVideoCanceled();
      if (r.$1 != 200) throw HttpException(_httpError(r.$1, r.$2));
      final id = (jsonDecode(r.$2) as Map)['job_id'];
      if (id is! String) throw const HttpException('Job id မရ');
      final started = DateTime.now();
      var failures = 0;
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (_canceled) throw const NewsVideoCanceled();
        try {
          r = await _call('GET', '/jobs/$id');
          failures = 0;
        } on SocketException {
          if (++failures >= 5) throw const HttpException('Backend နဲ့ ဆက်သွယ်လို့မရတော့ဘူး');
          continue;
        } on TimeoutException {
          if (++failures >= 5) throw const HttpException('Backend ပြန်မဖြေတော့ဘူး');
          continue;
        }
        if (r.$1 != 200) throw HttpException(_httpError(r.$1, r.$2));
        final job = parseNewsJob(r.$2);
        onUpdate(job);
        if (job.state == JobState.error) throw HttpException(job.error);
        if (job.state == JobState.done) return job;
        if (DateTime.now().difference(started).inMinutes > 40) throw const HttpException('အချိန်ကြာလွန်းလို့ ရပ်လိုက်တယ်');
      }
    } on NewsVideoCanceled {
      rethrow;
    } catch (e) {
      if (_canceled) throw const NewsVideoCanceled();
      rethrow;
    }
  }

  /// Saves the finished MP4 into [dest].
  Future<void> download(String path, File dest, void Function(int received, int total) onBytes) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _http = c;
    try {
      final req = await c.getUrl(_uri(path));
      req.headers.set('x-app-token', settings.token);
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        final body = await resp.transform(utf8.decoder).join();
        throw HttpException(_httpError(resp.statusCode, body));
      }
      final sink = dest.openWrite();
      var got = 0;
      try {
        await for (final chunk in resp) {
          got += chunk.length;
          sink.add(chunk);
          onBytes(got, resp.contentLength);
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (_canceled) throw const NewsVideoCanceled();
      rethrow;
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
