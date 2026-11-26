import 'package:aistudio/core/chunk_export.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chunkRanges', () {
    test('0 or a short video gives one range', () {
      expect(chunkRanges(100000, 0), [(from: 0, to: 100000)]);
      expect(chunkRanges(3600000, 3600000), [(from: 0, to: 3600000)]);
      expect(chunkRanges(0, 600000), isEmpty);
    });

    test('two hours in one-hour chunks', () {
      final r = chunkRanges(7200000, 3600000);
      expect(r, [(from: 0, to: 3600000), (from: 3600000, to: 7200000)]);
    });

    test('a small leftover is joined to the last chunk', () {
      final r = chunkRanges(3600000 * 2 + 30000, 3600000);
      expect(r.length, 2);
      expect(r.last.to, 7230000);
    });

    test('a big leftover becomes its own chunk and the ranges cover everything without gaps', () {
      final r = chunkRanges(5400000, 3600000, minLastMs: 60000);
      expect(r, [(from: 0, to: 3600000), (from: 3600000, to: 5400000)]);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].from, r[i - 1].to);
      }
    });
  });

  group('sliceTimeline', () {
    const tl = Timeline(pieces: [VideoPiece(0, 100000)]);

    test('one piece is cut to the chunk', () {
      final s = sliceTimeline(tl, 30000, 70000).timeline;
      expect(s.pieces.length, 1);
      expect(s.pieces.first.startMs, 30000);
      expect(s.pieces.first.endMs, 70000);
    });

    test('a piece fully inside is kept as it is, one fully outside is dropped', () {
      const t = Timeline(pieces: [VideoPiece(0, 10000), VideoPiece(50000, 60000)]);
      final s = sliceTimeline(t, 10000, 20000).timeline;
      expect(s.pieces.length, 1);
      expect(s.pieces.first.startMs, 50000);
      expect(s.pieces.first.endMs, 60000);
    });

    test('the source range follows the piece speed', () {
      const t = Timeline(pieces: [VideoPiece(0, 100000, ZoomMode.none, null, false, null, 2.0)]);
      // Output length is 50 s; the chunk 10..20 s of output is 20..40 s of source.
      final s = sliceTimeline(t, 10000, 20000).timeline;
      expect(s.pieces.first.startMs, 20000);
      expect(s.pieces.first.endMs, 40000);
      expect(s.pieces.first.lengthMs, 10000);
    });

    test('a held still frame keeps its frame and is held for less time', () {
      const t = Timeline(pieces: [VideoPiece.freezeAt(5000, 10000)]);
      final s = sliceTimeline(t, 2000, 6000).timeline;
      expect(s.pieces.first.freeze, isTrue);
      expect(s.pieces.first.startMs, 5000);
      expect(s.pieces.first.lengthMs, 4000);
    });

    test('chunk lengths add up to the whole video', () {
      const t = Timeline(pieces: [VideoPiece(0, 40000), VideoPiece(60000, 130000)]);
      final total = t.videoMs;
      var sum = 0;
      for (final r in chunkRanges(total, 30000, minLastMs: 1000)) {
        sum += sliceTimeline(t, r.from, r.to).timeline.videoMs;
      }
      expect(sum, total);
    });

    test('narration inside is moved to 0, one crossing a cut is dropped and counted', () {
      const v1 = VoiceItem(source: '/a.wav', label: 'a', durationMs: 5000, offsetMs: 12000);
      const v2 = VoiceItem(source: '/b.wav', label: 'b', durationMs: 8000, offsetMs: 25000);
      const v3 = VoiceItem(source: '/c.wav', label: 'c', durationMs: 4000, offsetMs: 80000);
      final t = tl.copyWith(voices: [v1, v2, v3]);
      final r = sliceTimeline(t, 10000, 30000);
      expect(r.timeline.voices.length, 1);
      expect(r.timeline.voices.first.offsetMs, 2000);
      expect(r.droppedVoices, 1);
    });
  });

  group('sliceWindows', () {
    test('windows are cut to the chunk and moved to 0', () {
      final r = sliceWindows([
        {'s': 5000, 'e': 15000, 'k': 'a'},
        {'s': 25000, 'e': 40000, 'k': 'b'},
        {'s': 50000, 'e': 60000, 'k': 'c'},
      ], 10000, 30000);
      expect(r.length, 2);
      expect(r[0]['s'], 0);
      expect(r[0]['e'], 5000);
      expect(r[0]['k'], 'a');
      expect(r[1]['s'], 15000);
      expect(r[1]['e'], 20000);
    });

    test('a window left too short is dropped', () {
      expect(sliceWindows([{'s': 9900, 'e': 10100}], 10000, 20000), isEmpty);
    });
  });

  test('coolDownText', () {
    expect(coolDownText(45), '45 စက္ကန့်');
    expect(coolDownText(125), '2 မိနစ် 05 စက္ကန့်');
  });
}
