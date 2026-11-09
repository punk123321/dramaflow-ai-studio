import 'package:aistudio/core/segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSegments', () {
    test('splits 48:20 into 10 minute parts, last part ends at the video end', () {
      const dur = (48 * 60 + 20) * 1000;
      final s = buildSegments(dur, 10 * 60000);
      expect(s.length, 5);
      expect(s.first, const SegmentSpec(0, 600000));
      expect(s[3], const SegmentSpec(1800000, 2400000));
      expect(s.last, const SegmentSpec(2400000, dur));
    });

    test('parts touch with no gap and no overlap, and cover the whole video', () {
      const dur = 3725000;
      final s = buildSegments(dur, 900000);
      expect(s.first.startMs, 0);
      expect(s.last.endMs, dur);
      for (var i = 1; i < s.length; i++) {
        expect(s[i].startMs, s[i - 1].endMs);
      }
      expect(hasOverlap(s), false);
    });

    test('video shorter than one segment gives one segment', () {
      expect(buildSegments(120000, 600000), [const SegmentSpec(0, 120000)]);
    });

    test('a leftover under one second is merged into the previous part', () {
      final s = buildSegments(600500, 300000);
      expect(s.length, 2);
      expect(s.last, const SegmentSpec(300000, 600500));
    });

    test('exact multiple has no empty last part', () {
      final s = buildSegments(1200000, 600000);
      expect(s, [const SegmentSpec(0, 600000), const SegmentSpec(600000, 1200000)]);
    });

    test('bad input gives an empty list', () {
      expect(buildSegments(0, 1000), isEmpty);
      expect(buildSegments(1000, 0), isEmpty);
      expect(buildSegments(-5, 1000), isEmpty);
    });
  });

  group('time text', () {
    test('formatTime', () {
      expect(formatTime(0), '0:00');
      expect(formatTime(65000), '1:05');
      expect(formatTime(600000), '10:00');
      expect(formatTime(3725000), '1:02:05');
      expect(formatTime(-10), '0:00');
    });

    test('parseTime accepts seconds, m:ss and h:mm:ss', () {
      expect(parseTime('90'), 90000);
      expect(parseTime('1:30'), 90000);
      expect(parseTime(' 1:02:03 '), 3723000);
      expect(parseTime('0:00'), 0);
    });

    test('parseTime rejects bad text', () {
      expect(parseTime(''), isNull);
      expect(parseTime('abc'), isNull);
      expect(parseTime('1:75'), isNull);
      expect(parseTime('1:2:3:4'), isNull);
      expect(parseTime('-5'), isNull);
    });

    test('format then parse gives the same time', () {
      for (final ms in [0, 1000, 59000, 60000, 3599000, 3600000, 7325000]) {
        expect(parseTime(formatTime(ms)), ms);
      }
    });
  });

  group('validateSegment', () {
    test('accepts a normal segment', () {
      expect(validateSegment(startMs: 0, endMs: 1000, durationMs: 5000), isNull);
      expect(validateSegment(startMs: 4000, endMs: 5000, durationMs: 5000), isNull);
    });

    test('rejects end before start, equal times, and end past the video', () {
      expect(validateSegment(startMs: 2000, endMs: 1000, durationMs: 5000), isNotNull);
      expect(validateSegment(startMs: 1000, endMs: 1000, durationMs: 5000), isNotNull);
      expect(validateSegment(startMs: 0, endMs: 5001, durationMs: 5000), isNotNull);
      expect(validateSegment(startMs: -1, endMs: 1000, durationMs: 5000), isNotNull);
    });
  });

  group('sorting and overlap', () {
    test('sortedSegments orders by start and keeps every item', () {
      final out = sortedSegments(const [SegmentSpec(5000, 6000), SegmentSpec(0, 1000), SegmentSpec(2000, 3000)]);
      expect(out.map((e) => e.startMs).toList(), [0, 2000, 5000]);
    });

    test('touching ends are not an overlap, shared time is', () {
      expect(hasOverlap(const [SegmentSpec(0, 1000), SegmentSpec(1000, 2000)]), false);
      expect(hasOverlap(const [SegmentSpec(0, 1500), SegmentSpec(1000, 2000)]), true);
    });
  });

  test('formatSize', () {
    expect(formatSize(0), '-');
    expect(formatSize(512), '512 B');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(1288490188), '1.2 GB');
  });
}
