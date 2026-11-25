import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/news_video.dart';
import '../core/studio.dart';

class StudioCanceled implements Exception {
  const StudioCanceled();
}

/// Talks to the Creator Studio part of the user's own backend (the Recap notebook
/// with the Studio files). Jobs run there; this only starts them, asks how far
/// they are and brings finished files back to the phone.
class StudioClient {
  StudioClient(this.settings);

  final NewsVideoSettings settings;
  bool _canceled = false;
  HttpClient? _http;

  /// Stops waiting / downloading on the phone. A job that is already running on the backend is stopped with [control].
  void cancel() {
    _canceled = true;
    _http?.close(force: true);
  }

  Uri _uri(String path) => Uri.parse('${settings.url}$path');

  Future<(int, String)> _call(String method, String path, {String? json, Duration timeout = const Duration(seconds: 60)}) async {
    final c = _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final HttpClientRequest req;
    if (method == 'GET') {
      req = await c.getUrl(_uri(path));
    } else if (method == 'DELETE') {
      req = await c.deleteUrl(_uri(path));
    } else {
      req = await c.postUrl(_uri(path));
    }
    req.headers.set('x-app-token', settings.token);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      final bytes = utf8.encode(json);
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body);
  }

  static String httpError(int code, String body) {
    String? detail;
    try {
      final m = jsonDecode(body);
      if (m is Map && m['detail'] is String) detail = m['detail'] as String;
    } catch (_) {}
    if (detail != null && code >= 400 && code < 500 && code != 401 && code != 404) return detail;
    final why = switch (code) {
      401 => 'Token မမှန်ဘူး (Colab ကို ပြန် run ထားရင် token အသစ် ယူပါ)',
      404 => 'မတွေ့ပါ — Backend က Studio မပါတဲ့ version အဟောင်း ဖြစ်နိုင်တယ် (notebook အသစ်ကို Cell အားလုံး run ပါ)',
      409 => 'Backend မှာ တခြား job လုပ်နေတုန်း (ပြီးမှ ပြန်စမ်းပါ)',
      413 => 'ပို့တဲ့ ဖိုင်ကြီးလွန်းတယ်',
      502 || 503 || 504 || 524 => 'Backend မရောက်ဘူး (Colab ပိတ်နေလား၊ tunnel ပြတ်နေလား)',
      _ => 'HTTP $code',
    };
    return detail == null ? why : '$why ($detail)';
  }

  Map<String, Object?> _ok((int, String) r) {
    if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
    final m = jsonDecode(r.$2);
    return m is Map ? m.cast<String, Object?>() : const {};
  }

  Future<StudioLibrary> library() async {
    final r = await _call('GET', '/studio/files');
    if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
    return parseStudioLibrary(r.$2);
  }

  /// Starts a job and answers with its id. 409 when the backend is busy.
  Future<String> start(Map<String, Object?> request) async {
    final m = _ok(await _call('POST', '/studio/jobs', json: jsonEncode(request)));
    final id = m['job_id'];
    if (id is! String) throw const HttpException('Job id မရ');
    return id;
  }

  Future<StudioJob> status(String id) async {
    final r = await _call('GET', '/studio/jobs/$id', timeout: const Duration(seconds: 30));
    if (r.$1 == 404) throw const HttpException('ဒီ job ကို Backend မှာ မတွေ့တော့ဘူး (Backend ပြန်စထားလား၊ ၂ နာရီကျော်သွားလား)');
    if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
    return parseStudioJob(r.$2);
  }

  /// 'cancel' | 'pause' | 'resume'.
  Future<void> control(String id, String action) async {
    final r = await _call('POST', '/studio/jobs/$id/$action', timeout: const Duration(seconds: 20));
    if (r.$1 != 200 && r.$1 != 409) throw HttpException(httpError(r.$1, r.$2));
  }

  /// Polls until the job is finished. A lost connection is tolerated for a while (the job goes on
  /// in the backend); after that it throws and the job id can be picked up again.
  Future<StudioJob> wait(String id, void Function(StudioJob) onUpdate, {Duration every = const Duration(seconds: 2), int maxHours = 8}) async {
    final started = DateTime.now();
    var failures = 0;
    while (true) {
      if (_canceled) throw const StudioCanceled();
      StudioJob job;
      try {
        job = await status(id);
        failures = 0;
      } on SocketException {
        if (++failures >= 8) throw const HttpException('Backend နဲ့ ဆက်သွယ်လို့မရတော့ဘူး (job က Backend မှာ ဆက်လုပ်နေနိုင်တယ်)');
        await Future<void>.delayed(every);
        continue;
      } on TimeoutException {
        if (++failures >= 8) throw const HttpException('Backend ပြန်မဖြေတော့ဘူး (job က Backend မှာ ဆက်လုပ်နေနိုင်တယ်)');
        await Future<void>.delayed(every);
        continue;
      } on HttpException catch (e) {
        if (_canceled) throw const StudioCanceled();
        // A gateway hiccup is not the end of the job.
        if (e.message.contains('Backend မရောက်ဘူး') && ++failures < 8) {
          await Future<void>.delayed(every);
          continue;
        }
        rethrow;
      }
      onUpdate(job);
      if (job.finished) return job;
      if (DateTime.now().difference(started).inHours >= maxHours) throw const HttpException('အချိန်ကြာလွန်းလို့ စောင့်တာ ရပ်လိုက်တယ် (job က Backend မှာ ဆက်လုပ်နေနိုင်တယ်)');
      await Future<void>.delayed(every);
    }
  }

  /// Starts the job and waits for it. [onId] gets the job id as soon as it exists.
  Future<StudioJob> run(Map<String, Object?> request, void Function(StudioJob) onUpdate, {void Function(String id)? onId}) async {
    try {
      final id = await start(request);
      onId?.call(id);
      return await wait(id, onUpdate);
    } catch (e) {
      if (_canceled) throw const StudioCanceled();
      rethrow;
    }
  }

  /// A small file (.srt or a picture, 8 MB at most) from the phone into the library. Answers with the stored name.
  Future<String> upload(String name, Uint8List bytes) async {
    final m = _ok(await _call('POST', '/studio/upload', json: jsonEncode({'name': name, 'data_b64': base64Encode(bytes)}), timeout: const Duration(seconds: 120)));
    final n = m['name'];
    if (n is! String) throw const HttpException('ဖိုင်နာမည် မရ');
    return n;
  }

  Future<void> delete(String name) async {
    final r = await _call('DELETE', '/studio/files/${Uri.encodeComponent(name)}');
    if (r.$1 != 200) throw HttpException(httpError(r.$1, r.$2));
  }

  /// Brings a library file to the phone. When [dest] already holds the first part (a download that was cut),
  /// it carries on from there if the backend allows it, otherwise it starts again.
  Future<void> downloadFile(String name, File dest, void Function(int received, int total) onBytes) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _http = c;
    try {
      var have = dest.existsSync() ? dest.lengthSync() : 0;
      final req = await c.getUrl(_uri('/studio/files/${Uri.encodeComponent(name)}'));
      req.headers.set('x-app-token', settings.token);
      if (have > 0) req.headers.set('range', 'bytes=$have-');
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        final body = await resp.transform(utf8.decoder).join();
        throw HttpException(httpError(resp.statusCode, body));
      }
      final resumed = resp.statusCode == 206;
      if (!resumed) have = 0;
      final total = resp.contentLength > 0 ? resp.contentLength + have : -1;
      final sink = dest.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var got = have;
      try {
        await for (final chunk in resp) {
          got += chunk.length;
          sink.add(chunk);
          onBytes(got, total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got < total) throw const HttpException('ဖိုင် တစ်ဝက်မှာ ပြတ်သွားတယ် — ပြန်နှိပ်ရင် ဆက်ယူမယ်');
    } catch (e) {
      if (_canceled) throw const StudioCanceled();
      rethrow;
    } finally {
      c.close(force: true);
      if (identical(_http, c)) _http = null;
    }
  }

  // ---- YouTube login (the secret and the token stay on the backend) ----

  Future<({bool secret, bool linked})> youtubeStatus() async {
    final m = _ok(await _call('GET', '/studio/youtube/status'));
    return (secret: m['secret'] == true, linked: m['linked'] == true);
  }

  Future<String> youtubeAuthLink() async {
    final m = _ok(await _call('POST', '/studio/youtube/auth-link', json: '{}'));
    final u = m['url'];
    if (u is! String) throw const HttpException('Login link မရ');
    return u;
  }

  Future<bool> youtubeAuthComplete(String pasted) async {
    final m = _ok(await _call('POST', '/studio/youtube/auth-complete', json: jsonEncode({'pasted': pasted})));
    return m['linked'] == true;
  }

  Future<void> youtubeUnlink() async {
    _ok(await _call('POST', '/studio/youtube/unlink', json: '{}'));
  }
}
