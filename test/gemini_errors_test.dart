import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/gemini_errors.dart';

void main() {
  const loc = 'User location is not supported for the API use.';

  test('a location refusal is explained as a place problem, whatever the code', () {
    for (final code in [400, 403, 412]) {
      final t = geminiUploadHint(code, loc);
      expect(t, contains('VPN'), reason: '$code');
      expect(t, isNot(contains('mkv')), reason: 'must not blame the video format');
    }
  });

  test('upload hints by code', () {
    expect(geminiUploadHint(400, ''), contains('mkv'));
    expect(geminiUploadHint(403, ''), contains('API key'));
    expect(geminiUploadHint(429, ''), contains('quota'));
    expect(geminiUploadHint(503, ''), contains('လူသုံးများ'));
    expect(geminiUploadHint(418, ''), 'Gemini HTTP 418');
    expect(geminiUploadHint(400, 'x' * 300).length, lessThan(300));
  });

  test('preflight stops only for place or key problems', () {
    expect(geminiPreflightProblem(200, ''), isNull);
    expect(geminiPreflightProblem(400, loc), contains('VPN'));
    expect(geminiPreflightProblem(400, 'API key not valid. Please pass a valid API key.'), contains('API key'));
    expect(geminiPreflightProblem(403, 'Permission denied'), contains('API key'));
    expect(geminiPreflightProblem(429, 'quota'), isNull); // busy: let the upload try
    expect(geminiPreflightProblem(503, 'overloaded'), isNull);
    expect(geminiPreflightProblem(400, 'something else'), isNull);
  });

  test('backend hint names the next step', () {
    expect(geminiBackendHint("404 NOT_FOUND model"), contains('model'));
    expect(geminiBackendHint('429 RESOURCE_EXHAUSTED'), contains('quota'));
    expect(geminiBackendHint("503 UNAVAILABLE. {'error': {'code': 503}}"), contains('လူသုံးများ'));
    expect(geminiBackendHint('API key not valid'), contains('key'));
    expect(geminiBackendHint(loc), contains('Colab'));
    expect(geminiBackendHint('???'), 'မသိတဲ့ အမှား');
  });
}
