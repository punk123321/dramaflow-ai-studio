import 'package:aistudio/core/script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty text gives no chunks', () {
    expect(splitScript(''), isEmpty);
    expect(splitScript('  \n \n'), isEmpty);
  });

  test('short text stays one chunk', () {
    expect(splitScript('မင်္ဂလာပါ။ နေကောင်းလား။'), ['မင်္ဂလာပါ။ နေကောင်းလား။']);
  });

  test('chunks respect the limit and break on sentence ends', () {
    final text = List.generate(40, (i) => 'ဒါက စာကြောင်း နံပါတ် $i ဖြစ်ပါတယ်။').join(' ');
    final chunks = splitScript(text, maxChars: 120);
    expect(chunks.length, greaterThan(2));
    for (final c in chunks) {
      expect(c.length <= 120, isTrue);
      expect(c.endsWith('။'), isTrue);
    }
  });

  test('no text is lost or reordered', () {
    final text = List.generate(30, (i) => 'Sentence $i here. 第$i句话。နံပါတ် $i။').join('\n');
    final chunks = splitScript(text, maxChars: 90);
    String squash(String s) => s.replaceAll(RegExp(r'\s+'), '');
    expect(squash(chunks.join(' ')), squash(text));
  });

  test('a sentence longer than the limit is cut, nothing dropped', () {
    final long = 'က' * 250;
    final chunks = splitScript(long, maxChars: 100);
    expect(chunks.length, 3);
    expect(chunks.join(), long);
  });

  test('Burmese comma does not end a sentence', () {
    final chunks = splitScript('တစ်၊ နှစ်၊ သုံး။ လေး။', maxChars: 25);
    expect(chunks.first.startsWith('တစ်၊ နှစ်၊ သုံး။'), isTrue);
    expect(chunks.join(' ').contains('တစ်၊ နှစ်၊ သုံး။'), isTrue);
  });

  test('estimateSpeech grows with length', () {
    expect(estimateSpeech('a' * 90), const Duration(seconds: 10));
    expect(estimateSpeech('a' * 180) > estimateSpeech('a' * 90), isTrue);
  });
}
