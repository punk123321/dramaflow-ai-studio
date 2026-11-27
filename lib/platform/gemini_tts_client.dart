import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/gemini_text.dart';
import '../core/gemini_tts.dart';
import '../core/news_video.dart' show defaultTextModel;

class GeminiTtsException implements Exception {
  GeminiTtsException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Object?> _post(GeminiTtsSettings s, Uri uri, Map<String, Object?> body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.postUrl(uri);
    req.headers.set('x-goog-api-key', s.apiKey.trim());
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close().timeout(const Duration(seconds: 240));
    final text = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 240));
    if (resp.statusCode != 200) {
      throw GeminiTtsException(explainTtsHttp(resp.statusCode, text, s.apiKey));
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      throw GeminiTtsException('Gemini ပြန်ဖြေချက် ဖတ်လို့မရပါ။');
    }
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

/// Narration audio (a WAV). The text is sent to Google; the key goes in a
/// header, never in the address. Throws [GeminiTtsException].
Future<Uint8List> geminiSpeak(GeminiTtsSettings s, String text) async {
  final json = await _post(s, ttsEndpoint(s.model), ttsBody(s.model, text, s.voice));
  final audio = extractAudio(json);
  if (audio == null) {
    throw GeminiTtsException('Gemini ပြန်ဖြေချက်ထဲမှာ အသံ မပါပါ။ Model နာမည် (TTS model ဟုတ်လား) စစ်ပါ။');
  }
  return audio.bytes;
}

/// A picture drawn by Gemini from [prompt]. Throws [GeminiTtsException].
Future<GeneratedImage> geminiDraw(GeminiTtsSettings s, String prompt, String aspect) async {
  final json = await _post(s, imageEndpoint(s.imageModel), imageBody(prompt, aspect));
  final img = extractImage(json);
  if (img == null) {
    throw GeminiTtsException('Gemini က ပုံ မပေးပါ။ Prompt ကို ပြောင်းစမ်းပါ (လုံခြုံရေး စည်းကမ်းကြောင့် ပယ်တာ ဖြစ်နိုင်တယ်) ဒါမှမဟုတ် ပုံ model နာမည် စစ်ပါ။');
  }
  return img;
}

/// A written answer (a description, for example). The prompt is sent to Google with
/// the person's own key. Throws [GeminiTtsException].
Future<String> geminiWrite(GeminiTtsSettings s, String prompt, {String model = defaultTextModel}) async {
  final json = await _post(s, textEndpoint(model), textBody(prompt));
  final t = extractText(json);
  if (t == null) {
    final why = blockReason(json);
    throw GeminiTtsException(why != null
        ? 'Gemini က မဖြေဘူး ($why)။ ဇာတ်လမ်းစာသား / prompt ကို ပြင်ပြီး ပြန်စမ်းပါ။'
        : 'Gemini က စာသား မပေးပါ။ Model နာမည် (${model.trim()}) ကို စစ်ပါ။');
  }
  return t;
}
