import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/assembly.dart';

/// Sound taken out of the original video (the video file itself is never changed).
class AudioForAsr {
  const AudioForAsr(this.path, this.wholeFile);

  /// A temporary file in the app's cache.
  final String path;

  /// True when the sound could not be cut out alone and the whole video was copied.
  final bool wholeFile;
}

class AsrCanceled implements Exception {
  const AsrCanceled();
}

/// Runs the whole job: sound out of the video (Android side), upload, wait,
/// download the SRT. Only the sound is sent, never the picture, unless the
/// sound could not be cut out alone.
class AssemblyClient {
  AssemblyClient(this.apiKey);

  static const _channel = MethodChannel('com.dramaflow.aistudio/media');

  final String apiKey;
  bool _canceled = false;
  HttpClient? _http;

  bool get canceled => _canceled;

  void cancel() {
    _canceled = true;
    _http?.close(force: true);
  }

  void _check() {
    if (_canceled) throw const AsrCanceled();
  }

  static Future<AudioForAsr> extractAudio(String videoUri) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('extractAudio', {'uri': videoUri});
    final path = raw?['path'];
    if (path is! String) throw const FormatException('sound file missing');
    return AudioForAsr(path, raw?['whole'] == true);
  }

  Future<(int, String)> _send(String method, String url, {String? json, File? file}) async {
    final c = _http!;
    final req = await (method == 'GET' ? c.getUrl(Uri.parse(url)) : c.postUrl(Uri.parse(url)));
    req.headers.set(HttpHeaders.authorizationHeader, apiKey); // no "Bearer"
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(json);
    } else if (file != null) {
      req.headers.contentType = ContentType('application', 'octet-stream');
      req.contentLength = await file.length();
      await req.addStream(file.openRead());
    }
    final resp = await req.close().timeout(const Duration(minutes: 30));
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body);
  }

  /// Returns the SRT text. [onStage] gets a short Burmese line for the screen.
  Future<String> transcribe(File audio, String language, void Function(String) onStage) async {
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      onStage('အသံကို တင်နေတယ် …');
      var r = await _send('POST', '$assemblyBase/v2/upload', file: audio);
      _check();
      if (r.$1 != 200) throw HttpException(assemblyHttpError(r.$1, r.$2));
      final uploadUrl = uploadUrlFrom(r.$2);
      if (uploadUrl == null) throw const HttpException('Upload ပြန်ကြားချက်မှာ upload_url မပါ');

      onStage('စာပြောင်းဖို့ တောင်းနေတယ် …');
      r = await _send('POST', '$assemblyBase/v2/transcript', json: transcriptBody(uploadUrl, language));
      _check();
      if (r.$1 != 200) throw HttpException(assemblyHttpError(r.$1, r.$2));
      final id = transcriptIdFrom(r.$2);
      if (id == null) throw const HttpException('Transcript id မရ');

      final started = DateTime.now();
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 3));
        _check();
        r = await _send('GET', '$assemblyBase/v2/transcript/$id');
        _check();
        if (r.$1 != 200) throw HttpException(assemblyHttpError(r.$1, r.$2));
        final st = parseAsrStatus(r.$2);
        if (st.state == AsrState.done) break;
        if (st.state == AsrState.failed) throw HttpException(st.error);
        final mins = DateTime.now().difference(started).inSeconds;
        if (mins > 45 * 60) throw const HttpException('အချိန်ကြာလွန်းလို့ ရပ်လိုက်တယ်');
        onStage('စာပြောင်းနေတယ် … ${mins}s');
      }

      onStage('SRT ယူနေတယ် …');
      r = await _send('GET', '$assemblyBase/v2/transcript/$id/srt?chars_per_caption=28');
      _check();
      if (r.$1 != 200) throw HttpException(assemblyHttpError(r.$1, r.$2));
      return r.$2;
    } finally {
      _http?.close(force: true);
      _http = null;
    }
  }
}
