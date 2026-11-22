import 'package:aistudio/core/script.dart';
import 'package:aistudio/core/segments.dart';
import 'package:aistudio/core/video_recap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prompt lists parts and the part marker', () {
    final p = buildVideoRecapPrompt(
      dramaTitle: 'T',
      episode: 3,
      parts: const [SegmentSpec(0, 60000), SegmentSpec(60000, 120000), SegmentSpec(120000, 150000)],
      from: 2,
      to: 3,
    );
    expect(p, contains('Part 2: 1:00 - 2:00'));
    expect(p, contains('Part 3: 2:00 - 2:30'));
    expect(p, isNot(contains('Part 1:')));
    expect(p, contains('=== PART n ==='));
  });

  test('reply is split by part, code fences ignored', () {
    final r = parseVideoRecapReply('Here\n```\n=== PART 1 ===\nပထမ။\n=== PART 2 ===\nဒုတိယ။\nနောက်ထပ်။\n```');
    expect(r.keys, [1, 2]);
    expect(r[1], 'ပထမ။');
    expect(r[2], contains('နောက်ထပ်'));
  });

  test('empty or unmarked reply gives nothing', () {
    expect(parseVideoRecapReply('just text'), isEmpty);
    expect(parseVideoRecapReply('=== PART 1 ===\n'), isEmpty);
  });

  test('one part stays one chunk even when short', () {
    final s = scriptFromParts({2: 'ဒုတိယ။', 1: 'ပထမ။'});
    final c = splitScript(s);
    expect(c, ['ပထမ။', 'ဒုတိယ။']);
  });

  test('script without the break marker still joins as before', () {
    expect(splitScript('က။ ခ။'), ['က။ ခ။']);
  });

  test('prompt carries the dialogue of each part when given, and warns it may be wrong', () {
    final withD = buildVideoRecapPrompt(
      dramaTitle: 'T',
      episode: 1,
      parts: const [SegmentSpec(0, 60000), SegmentSpec(60000, 120000)],
      from: 1,
      to: 2,
      dialogue: const ['မင်္ဂလာပါ / နေကောင်းလား', ''],
    );
    expect(withD, contains('Dialogue (subtitles): မင်္ဂလာပါ / နေကောင်းလား'));
    expect(withD, contains('speech recognition'));
    expect('Dialogue (subtitles):'.allMatches(withD).length, 1); // the empty part has no line
    final without = buildVideoRecapPrompt(
      dramaTitle: 'T',
      episode: 1,
      parts: const [SegmentSpec(0, 60000)],
      from: 1,
      to: 1,
    );
    expect(without, isNot(contains('Dialogue')));
    expect(without, isNot(contains('speech recognition')));
  });
}
