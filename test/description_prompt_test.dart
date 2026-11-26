import 'package:aistudio/core/description_prompt.dart';
import 'package:aistudio/core/srt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clockText', () {
    expect(clockText(0), '0:00');
    expect(clockText(65000), '1:05');
    expect(clockText(3725000), '1:02:05');
  });

  List<SrtEntry> many(int n) => [for (var i = 0; i < n; i++) SrtEntry(i + 1, i * 3000, i * 3000 + 2000, 'line number $i of the story')];

  test('a short subtitle list is kept whole', () {
    final s = sampleStory(many(5));
    expect(s.split('\n').length, 5);
    expect(s.startsWith('[0:00] line number 0'), isTrue);
  });

  test('a long list is cut to the budget but covers the whole length', () {
    final s = sampleStory(many(5000), maxChars: 3000);
    expect(s.length, lessThanOrEqualTo(3000));
    final lines = s.split('\n');
    expect(lines.first.contains('line number 0 '), isTrue);
    // The last kept line is near the end of the story, not near the start.
    final lastIdx = int.parse(RegExp(r'line number (\d+)').firstMatch(lines.last)!.group(1)!);
    expect(lastIdx, greaterThan(4000));
  });

  test('empty and one-character lines are ignored', () {
    expect(sampleStory([const SrtEntry(1, 0, 1000, ' '), const SrtEntry(2, 1000, 2000, '-')]), '');
  });

  test('the prompt carries the facts it was given and forbids inventing', () {
    final p = buildDescriptionPrompt(title: 'My Show', part: 'Part 3', channel: 'Chan', script: 'story text here', subtitleSample: '[0:00] hi there');
    expect(p, contains('My Show'));
    expect(p, contains('Part 3'));
    expect(p, contains('Chan'));
    expect(p, contains('story text here'));
    expect(p, contains('[0:00] hi there'));
    expect(p, contains('မဖန်တီးပါနဲ့'));
    expect(p, contains('recap / commentary'));
  });

  test('without any story text the prompt says so', () {
    final p = buildDescriptionPrompt(title: 'X');
    expect(p, contains('ဇာတ်လမ်းစာသား မပါပါ'));
  });

  test('empty optional fields are not printed as blank labels', () {
    final p = buildDescriptionPrompt(title: 'X');
    expect(p, isNot(contains('အပိုင်း:')));
    expect(p, isNot(contains('Channel အမည်:')));
  });
}
