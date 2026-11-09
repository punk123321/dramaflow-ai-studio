import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/subtitle_ops.dart';
import 'package:flutter_test/flutter_test.dart';

List<SrtEntry> sample() => const [
      SrtEntry(1, 1000, 3000, 'မင်္ဂလာပါ'),
      SrtEntry(2, 3000, 5000, 'second line'),
      SrtEntry(3, 6000, 8000, 'third'),
    ];

void main() {
  test('operations do not modify their input', () {
    final a = sample();
    mergeWithNext(a, 0);
    deleteAt(a, 1);
    shift(a, 500);
    splitAt(a, 1, 3);
    expect(a, sample());
  });

  group('merge, delete, split', () {
    test('merge joins text and spans both times, then renumbers', () {
      final r = mergeWithNext(sample(), 0);
      expect(r.length, 2);
      expect(r[0].startMs, 1000);
      expect(r[0].endMs, 5000);
      expect(r[0].text, 'မင်္ဂလာပါ\nsecond line');
      expect(r.map((e) => e.index), [1, 2]);
      expect(r[1].text, 'third');
    });

    test('merge on the last entry does nothing', () {
      expect(mergeWithNext(sample(), 2), sample());
    });

    test('delete renumbers', () {
      final r = deleteAt(sample(), 0);
      expect(r.map((e) => e.index), [1, 2]);
      expect(r.first.text, 'second line');
    });

    test('split divides time by text length and keeps the total range', () {
      final r = splitAt(sample(), 1, 6); // "second" | "line"
      expect(r.length, 4);
      expect(r[1].text, 'second');
      expect(r[2].text, 'line');
      expect(r[1].startMs, 3000);
      expect(r[1].endMs, r[2].startMs);
      expect(r[2].endMs, 5000);
      expect(r.map((e) => e.index), [1, 2, 3, 4]);
      expect(validateSrt(r), isEmpty);
    });

    test('split with nothing on one side does nothing', () {
      expect(splitAt(sample(), 1, 0), sample());
      expect(splitAt(sample(), 1, 999), sample());
    });
  });

  group('shift', () {
    test('moves everything and keeps spacing', () {
      final r = shift(sample(), 500);
      expect(r.map((e) => e.startMs), [1500, 3500, 6500]);
      expect(r.map((e) => e.endMs), [3500, 5500, 8500]);
    });
    test('from a position only moves the later entries', () {
      final r = shift(sample(), 1000, from: 2);
      expect(r[0], sample()[0]);
      expect(r[2].startMs, 7000);
    });
    test('never goes below zero and keeps spacing', () {
      final r = shift(sample(), -5000);
      expect(r[0].startMs, 0);
      expect(r[1].startMs - r[0].startMs, 2000);
      expect(r.every((e) => e.startMs >= 0), isTrue);
    });
  });

  group('overlaps', () {
    test('fixOverlaps trims the end to the next start', () {
      final e = [const SrtEntry(1, 0, 3000, 'a'), const SrtEntry(2, 2000, 4000, 'b')];
      final r = fixOverlaps(e);
      expect(r.fixed, 1);
      expect(r.entries[0].endMs, 2000);
      expect(validateSrt(r.entries), isEmpty);
    });
    test('clean file reports zero', () {
      expect(fixOverlaps(sample()).fixed, 0);
    });
  });

  group('time parsing', () {
    test('formats', () {
      expect(parseSrtTime('00:01:02,500'), 62500);
      expect(parseSrtTime('01:02.5'), 62500);
      expect(parseSrtTime('7'), 7000);
      expect(parseSrtTime('1:02:03.456'), 3723456);
    });
    test('rejects nonsense', () {
      expect(parseSrtTime('abc'), isNull);
      expect(parseSrtTime('00:99:00,000'), isNull);
      expect(parseSrtTime(''), isNull);
    });
    test('round trip with formatSrtTime', () {
      for (final ms in [0, 999, 61000, 3723456]) {
        expect(parseSrtTime(formatSrtTime(ms)), ms);
      }
    });
  });

  group('problems', () {
    test('Burmese marks are not counted as characters', () {
      // 4 base letters, plus vowel signs and tone marks
      expect(visibleLength('မင်္ဂလာပါ') < 'မင်္ဂလာပါ'.runes.length, isTrue);
      expect(visibleLength('a b\nc'), 3);
    });

    test('finds fast, short, empty, overlap, long line and bad range', () {
      final e = [
        SrtEntry(1, 0, 1000, 'x' * 40), // 40 cps: too fast
        const SrtEntry(2, 900, 1200, 'ok'), // overlap with 1, 300ms: too short
        const SrtEntry(3, 2000, 4000, ' '), // empty
        SrtEntry(4, 5000, 9000, 'y' * 50), // long line
        const SrtEntry(5, 9000, 9000, 'z'), // bad range
      ];
      final kinds = findProblems(e).map((p) => p.kind).toSet();
      expect(kinds, containsAll(ProblemKind.values));
    });

    test('a clean file has no problems', () {
      expect(findProblems(sample()), isEmpty);
    });
  });

  group('terms', () {
    test('parse accepted separators and ignore junk', () {
      final t = parseTerms('林凡 = လင်ဖန်း\na->b\n# comment\nno separator\nx → y\n= bad');
      expect(t.map((e) => '${e.from}>${e.to}'), ['林凡>လင်ဖန်း', 'a>b', 'x>y']);
    });

    test('apply replaces text only, longest term first, and counts', () {
      final e = [const SrtEntry(1, 100, 900, '林凡来了，林凡走了'), const SrtEntry(2, 1000, 2000, '林凡师兄')];
      final r = applyTerms(e, parseTerms('林凡 = လင်ဖန်း\n林凡师兄 = ဆရာကြီးလင်ဖန်း'));
      expect(r.replaced, 3);
      expect(r.entries[0].text, 'လင်ဖန်း来了，လင်ဖန်း走了');
      expect(r.entries[1].text, 'ဆရာကြီးလင်ဖန်း');
      expect(r.entries[0].startMs, 100);
      expect(r.entries[1].endMs, 2000);
    });

    test('no terms or no match changes nothing', () {
      expect(applyTerms(sample(), const []).replaced, 0);
      expect(applyTerms(sample(), const [Term('zzz', 'y')]).entries, sample());
    });
  });
}
