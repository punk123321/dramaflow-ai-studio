import 'dart:convert';

import 'package:aistudio/core/assembly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings round trip; broken or empty text gives defaults', () {
    const s = AssemblySettings(apiKey: ' abc ', language: 'my');
    final back = AssemblySettings.decode(s.encode());
    expect(back.apiKey, 'abc');
    expect(back.language, 'my');
    expect(AssemblySettings.decode(null).language, 'zh');
    expect(AssemblySettings.decode('not json').hasKey, isFalse);
    expect(AssemblySettings.decode('[1]').hasKey, isFalse);
    expect(const AssemblySettings(apiKey: '  ').hasKey, isFalse);
  });

  test('transcriptBody: language code, or detection when the code is empty; no speech model', () {
    final a = jsonDecode(transcriptBody('https://x/y', 'zh')) as Map;
    expect(a, {'audio_url': 'https://x/y', 'language_code': 'zh'});
    final b = jsonDecode(transcriptBody('https://x/y', '  ')) as Map;
    expect(b, {'audio_url': 'https://x/y', 'language_detection': true});
  });

  test('replies: upload_url, id, status', () {
    expect(uploadUrlFrom('{"upload_url":"https://cdn/u"}'), 'https://cdn/u');
    expect(uploadUrlFrom('{"x":1}'), isNull);
    expect(uploadUrlFrom('nope'), isNull);
    expect(transcriptIdFrom('{"id":"t1","status":"queued"}'), 't1');
    expect(transcriptIdFrom('{}'), isNull);
    expect(parseAsrStatus('{"status":"queued"}').state, AsrState.waiting);
    expect(parseAsrStatus('{"status":"processing"}').state, AsrState.waiting);
    expect(parseAsrStatus('{"status":"completed"}').state, AsrState.done);
    final e = parseAsrStatus('{"status":"error","error":"bad audio"}');
    expect(e.state, AsrState.failed);
    expect(e.error, 'bad audio');
    expect(parseAsrStatus('garbage').state, AsrState.failed);
  });

  test('assemblyHttpError names the common causes and keeps the service message', () {
    expect(assemblyHttpError(401, '{}'), contains('Key'));
    expect(assemblyHttpError(402, '{}'), contains('Credit'));
    expect(assemblyHttpError(500, '{"error":"boom"}'), contains('boom'));
    expect(assemblyHttpError(500, 'x'), 'HTTP 500');
  });
}
