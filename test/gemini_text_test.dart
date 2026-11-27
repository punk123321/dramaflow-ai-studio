import 'package:aistudio/core/gemini_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the endpoint has the model and no key', () {
    final u = textEndpoint(' some-model ');
    expect(u.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/some-model:generateContent');
    expect(u.query, isEmpty);
  });

  test('the body carries the prompt as one user message', () {
    final b = textBody('hello');
    final c = (b['contents'] as List).single as Map;
    expect(c['role'], 'user');
    expect(((c['parts'] as List).single as Map)['text'], 'hello');
  });

  test('the answer text is joined from all text parts', () {
    final json = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'Hello '},
              {'text': 'world'}
            ]
          }
        }
      ]
    };
    expect(extractText(json), 'Hello world');
  });

  test('nothing usable gives null', () {
    expect(extractText(null), isNull);
    expect(extractText({'candidates': []}), isNull);
    expect(extractText({'candidates': [{'content': {'parts': [{'text': '  '}]}}]}), isNull);
    expect(extractText({'candidates': [{'content': {}}]}), isNull);
  });

  test('a block reason is reported', () {
    expect(blockReason({'promptFeedback': {'blockReason': 'SAFETY'}}), 'SAFETY');
    expect(blockReason({'candidates': [{'finishReason': 'RECITATION'}]}), 'RECITATION');
    expect(blockReason({'candidates': [{'finishReason': 'STOP'}]}), isNull);
    expect(blockReason(null), isNull);
  });
}
