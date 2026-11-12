import 'dart:convert';
import 'dart:typed_data';

import 'package:aistudio/core/gemini_tts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings: no key means not ready; round trip; bad values fall back', () {
    expect(const GeminiTtsSettings().ready, isFalse);
    final s = const GeminiTtsSettings(apiKey: ' k ', voice: 'Puck').copyWith(model: 'm');
    final back = GeminiTtsSettings.decode(s.encode());
    expect(back.apiKey, 'k');
    expect(back.voice, 'Puck');
    expect(back.ready, isTrue);
    final bad = GeminiTtsSettings.decode('{"key":"a","model":"","voice":"Nope"}');
    expect(bad.model, defaultTtsModel);
    expect(bad.voice, defaultTtsVoice);
    expect(GeminiTtsSettings.decode('junk').ready, isFalse);
    expect(GeminiTtsSettings.decode(null).ready, isFalse);
  });

  test('endpoint and body follow the model family; key is never in the address', () {
    expect(ttsEndpoint('gemini-3.8-flash-tts').path, '/v1beta/interactions');
    expect(ttsEndpoint('gemini-2.5-flash-preview-tts').path, '/v1beta/models/gemini-2.5-flash-preview-tts:generateContent');
    final n = ttsBody('gemini-3.8-flash-tts', 'မင်္ဂလာပါ', 'Kore');
    expect(jsonEncode(n), contains('မင်္ဂလာပါ'));
    expect(jsonEncode(n), contains('"voice":"Kore"'));
    final o = ttsBody('gemini-2.5-flash-preview-tts', 'x', 'Puck');
    expect(jsonEncode(o), contains('"responseModalities":["AUDIO"]'));
    expect(jsonEncode(o), contains('"voiceName":"Puck"'));
    expect(ttsEndpoint('gemini-3.8-flash-tts').toString(), isNot(contains('key')));
  });

  test('raw PCM gets a WAV header; an existing WAV is untouched', () {
    final pcm = Uint8List.fromList(List.filled(480, 1));
    final w = ensureWav(pcm, sampleRate: 24000);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 16)), 'WAVEfmt ');
    expect(w.length, 44 + 480);
    expect(ByteData.sublistView(w).getUint32(24, Endian.little), 24000);
    expect(ensureWav(w), same(w));
  });

  test('audio is found in both reply shapes', () {
    final pcm = base64Encode(List.filled(400, 3));
    final a = extractAudio({
      'candidates': [
        {
          'content': {
            'parts': [
              {'inlineData': {'mimeType': 'audio/L16;codec=pcm;rate=24000', 'data': pcm}}
            ]
          }
        }
      ]
    });
    expect(a, isNotNull);
    expect(a!.sampleRate, 24000);
    expect(String.fromCharCodes(a.bytes.sublist(0, 4)), 'RIFF');
    final b = extractAudio({
      'steps': [
        {
          'content': [
            {'type': 'text', 'data': 'hello'},
            {'type': 'audio', 'data': pcm}
          ]
        }
      ]
    });
    expect(b, isNotNull);
  });

  test('no audio, broken base64 and tiny data give null', () {
    expect(extractAudio({'candidates': []}), isNull);
    expect(extractAudio({'type': 'audio', 'data': '!!!' * 60}), isNull);
    expect(extractAudio({'type': 'audio', 'data': 'AAAA'}), isNull);
    expect(extractAudio('x'), isNull);
  });

  test('errors are explained in Burmese and never show the key', () {
    final m = explainTtsHttp(403, '{"error":"bad key SECRET123"}', 'SECRET123');
    expect(m, contains('403'));
    expect(m, isNot(contains('SECRET123')));
    expect(explainTtsHttp(429, '', 'k'), contains('quota'));
    expect(explainTtsHttp(404, '', 'k'), contains('Model'));
    expect(explainTtsHttp(500, 'x' * 1000, 'k').length, lessThan(450));
  });
}
