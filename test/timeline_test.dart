import 'package:aistudio/core/segments.dart';
import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

const pieces = [VideoPiece(0, 10000), VideoPiece(20000, 30000), VideoPiece(40000, 45000)];

void main() {
  group('pieces', () {
    test('from segments', () {
      expect(piecesFromSegments(const [SegmentSpec(0, 5), SegmentSpec(5, 9)]), const [VideoPiece(0, 5), VideoPiece(5, 9)]);
    });

    test('trim accepts a valid range and rejects bad ones', () {
      expect(trimPiece(pieces, 0, 1000, 9000, 60000)![0], const VideoPiece(1000, 9000));
      expect(trimPiece(pieces, 0, 5000, 5000, 60000), isNull);
      expect(trimPiece(pieces, 0, -1, 5000, 60000), isNull);
      expect(trimPiece(pieces, 2, 40000, 70000, 60000), isNull);
      expect(trimPiece(pieces, 9, 0, 1, 60000), isNull);
    });

    test('move, remove and split keep the other pieces and never change the input', () {
      expect(movePiece(pieces, 0, 1), [pieces[1], pieces[0], pieces[2]]);
      expect(movePiece(pieces, 0, -1), pieces);
      expect(movePiece(pieces, 2, 1), pieces);
      expect(removePiece(pieces, 1), [pieces[0], pieces[2]]);
      final s = splitPiece(pieces, 1, 25000);
      expect(s.length, 4);
      expect(s[1], const VideoPiece(20000, 25000));
      expect(s[2], const VideoPiece(25000, 30000));
      expect(splitPiece(pieces, 1, 20100), pieces); // too close to the edge
      expect(pieces.length, 3);
    });

    test('timeline positions', () {
      expect(pieceStartOnTimeline(pieces, 0), 0);
      expect(pieceStartOnTimeline(pieces, 1), 10000);
      expect(pieceStartOnTimeline(pieces, 2), 20000);
      expect(timelineToSource(pieces, 0), (piece: 0, sourceMs: 0));
      expect(timelineToSource(pieces, 10000), (piece: 1, sourceMs: 20000));
      expect(timelineToSource(pieces, 24999), (piece: 2, sourceMs: 44999));
      expect(timelineToSource(pieces, 25000), isNull);
      expect(timelineToSource(pieces, -1), isNull);
    });

    test('total video length', () {
      expect(const Timeline(pieces: pieces).videoMs, 25000);
    });
  });

  group('voices', () {
    test('placed in sequence from zero', () {
      const a = VoiceItem(source: 'a', label: 'A', durationMs: 4000, offsetMs: 99);
      const b = VoiceItem(source: 'b', label: 'B', durationMs: 6000, offsetMs: 0);
      final r = placeVoicesInSequence([a, b], gapMs: 500);
      expect(r.map((v) => v.offsetMs), [0, 4500]);
      expect(r.last.endMs, 10500);
    });
  });

  group('subtitle remap', () {
    final subs = [
      const SrtEntry(1, 2000, 4000, 'inside first piece'),
      const SrtEntry(2, 12000, 18000, 'removed part'),
      const SrtEntry(3, 21000, 23000, 'inside second piece'),
      const SrtEntry(4, 9000, 21000, 'crosses a cut'),
      const SrtEntry(5, 44000, 50000, 'runs past the end of the last piece'),
    ];

    test('moves to the edit timeline, drops removed parts, splits across cuts', () {
      final r = remapSubtitles(subs, pieces);
      expect(r.where((e) => e.text == 'removed part'), isEmpty);
      final inside = r.firstWhere((e) => e.text == 'inside first piece');
      expect(inside.startMs, 2000);
      expect(inside.endMs, 4000);
      final second = r.firstWhere((e) => e.text == 'inside second piece');
      expect(second.startMs, 11000); // piece 2 starts at 10000 on the timeline
      expect(second.endMs, 13000);
      final cross = r.where((e) => e.text == 'crosses a cut').toList();
      expect(cross.length, 2);
      expect(cross[0].startMs, 9000);
      expect(cross[0].endMs, 10000);
      expect(cross[1].startMs, 10000);
      expect(cross[1].endMs, 11000);
      final tail = r.firstWhere((e) => e.text.startsWith('runs past'));
      expect(tail.endMs, 25000);
    });

    test('result is numbered, sorted and valid', () {
      final r = remapSubtitles(subs, pieces);
      expect(r.map((e) => e.index), List.generate(r.length, (i) => i + 1));
      for (var i = 1; i < r.length; i++) {
        expect(r[i].startMs >= r[i - 1].startMs, isTrue);
      }
      expect(r.every((e) => e.endMs > e.startMs), isTrue);
    });

    test('reordered pieces reorder the subtitles', () {
      final swapped = movePiece(pieces, 0, 1);
      final r = remapSubtitles([const SrtEntry(1, 21000, 23000, 'x'), const SrtEntry(2, 2000, 4000, 'y')], swapped);
      expect(r[0].text, 'x');
      expect(r[0].startMs, 1000);
      expect(r[1].text, 'y');
      expect(r[1].startMs, 12000);
    });

    test('offset shifts everything and never goes below zero', () {
      final r = remapSubtitles(subs, pieces, offsetMs: 500);
      expect(r.first.startMs, 2500);
      final back = remapSubtitles([const SrtEntry(1, 100, 900, 'a')], const [VideoPiece(0, 5000)], offsetMs: -500);
      expect(back.single.startMs, 0);
      expect(back.single.endMs, 400);
      expect(remapSubtitles([const SrtEntry(1, 100, 400, 'a')], const [VideoPiece(0, 5000)], offsetMs: -500), isEmpty);
    });

    test('text is untouched', () {
      final r = remapSubtitles([const SrtEntry(1, 0, 1000, 'မင်္ဂလာပါ\nနေကောင်းလား')], pieces);
      expect(r.single.text, 'မင်္ဂလာပါ\nနေကောင်းလား');
    });
  });

  group('save and load', () {
    test('round trip', () {
      const t = Timeline(
        pieces: pieces,
        voices: [VoiceItem(source: '/a.wav', label: 'A', durationMs: 5000, offsetMs: 100, volume: 0.8)],
        music: MusicTrack(source: 'content://m', name: 'm.mp3', durationMs: 90000, volume: 0.3, loop: false),
        subtitleOffsetMs: -200,
        burnSubtitles: false,
        originalVolume: 0.1,
      );
      final back = Timeline.decode(t.encode());
      expect(back.pieces, t.pieces);
      expect(back.voices.single.volume, 0.8);
      expect(back.voices.single.offsetMs, 100);
      expect(back.music!.loop, isFalse);
      expect(back.music!.durationMs, 90000);
      expect(back.subtitleOffsetMs, -200);
      expect(back.burnSubtitles, isFalse);
      expect(back.originalVolume, 0.1);
    });

    test('empty or damaged text gives an empty timeline', () {
      expect(Timeline.decode(null).pieces, isEmpty);
      expect(Timeline.decode('').pieces, isEmpty);
      expect(Timeline.decode('{not json').pieces, isEmpty);
      expect(Timeline.decode('{"pieces": "oops"}').pieces, isEmpty);
    });
  });

  group('checks', () {
    test('empty timeline is an error', () {
      final r = checkTimeline(const Timeline(), sourceMs: 60000);
      expect(r.any((i) => i.severity == Severity.error), isTrue);
    });

    test('good timeline has no errors', () {
      const t = Timeline(
        pieces: [VideoPiece(0, 10000)],
        voices: [VoiceItem(source: 'a', label: 'A', durationMs: 5000, offsetMs: 0)],
      );
      expect(checkTimeline(t, sourceMs: 60000), isEmpty);
    });

    test('piece past the video end is an error', () {
      final r = checkTimeline(const Timeline(pieces: [VideoPiece(0, 70000)]), sourceMs: 60000);
      expect(r.any((i) => i.severity == Severity.error), isTrue);
    });

    test('voice longer than video and overlapping voices are warnings', () {
      const t = Timeline(
        pieces: [VideoPiece(0, 5000)],
        voices: [
          VoiceItem(source: 'a', label: 'A', durationMs: 4000, offsetMs: 0),
          VoiceItem(source: 'b', label: 'B', durationMs: 4000, offsetMs: 3000),
        ],
      );
      final r = checkTimeline(t, sourceMs: 60000);
      expect(r.length, 2);
      expect(r.every((i) => i.severity == Severity.warning), isTrue);
    });
  });
}
