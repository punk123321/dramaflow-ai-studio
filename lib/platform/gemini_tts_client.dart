import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/gemini_tts.dart';

class GeminiTtsException implements Exception {
  GeminiTtsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One call to the Gemini API. The text is sent to Google; the key goes in a
/// header (never in the address). Throws [GeminiTtsException].
Future<Uint8List> geminiSpeak(GeminiTtsSettings s, String text) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.postUrl(ttsEndpoint(s.model));
    req.headers.set('x-goog-api-key', s.apiKey.trim());
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    req.add(utf8.encode(jsonEncode(ttsBody(s.model, text, s.voice))));
    final resp = await req.close().timeout(const Duration(seconds: 240));
    final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 240));
    if (resp.statusCode != 200) {
      throw GeminiTtsException(explainTtsHttp(resp.statusCode, body, s.apiKey));
    }
    Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      throw GeminiTtsException('Gemini ပြန်ဖြေချက် ဖတ်လို့မရပါ။');
    }
    final audio = extractAudio(json);
    if (audio == null) {
      throw GeminiTtsException('Gemini ပြန်ဖြေချက်ထဲမှာ အသံ မပါပါ။ Model နာမည် (TTS model ဟုတ်လား) စစ်ပါ။');
    }
    return audio.bytes;
  } on SocketException {
    throw GeminiTtsException('Internet ချိတ်ဆက်မှု မရပါ။');
  } on TimeoutException {
    throw GeminiTtsException('အချိန်ကြာလွန်းလို့ ရပ်လိုက်ပါတယ်။ ပြန်စမ်းပါ။');
  } on HandshakeException {
    throw GeminiTtsException('လုံခြုံရေး ချိတ်ဆက်မှု မအောင်မြင်ပါ။');
  } finally {
    client.close(force: true);
  }
}
