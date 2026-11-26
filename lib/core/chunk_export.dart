import 'timeline.dart';

/// One piece of a long export, on the OUTPUT timeline.
typedef ChunkRange = ({int from, int to});

/// Cuts [totalMs] into chunks of about [chunkMs]. A last bit shorter than
/// [minLastMs] is joined to the chunk before it, so there is no tiny file at the
/// end. [chunkMs] of 0 (or a video that is not longer than one chunk plus the
/// leftover) gives a single range.
List<ChunkRange> chunkRanges(int totalMs, int chunkMs, {int minLastMs = 60000}) {
  if (totalMs <= 0) return const [];
  if (chunkMs <= 0 || totalMs <= chunkMs + minLastMs) return [(from: 0, to: totalMs)];
  final out = <ChunkRange>[];
  var at = 0;
  while (at < totalMs) {
    final end = at + chunkMs;
    if (totalMs - end < minLastMs) {
      out.add((from: at, to: totalMs));
      break;
    }
    out.add((from: at, to: end));
    at = end;
  }
  return out;
}

/// The part of a timeline between [fromMs] and [toMs] of the finished video.
class TimelineSlice {
  const TimelineSlice(this.timeline, this.droppedVoices);

  final Timeline timeline;

  /// Narration / sound clips that straddle the cut and so could not be kept.
  final int droppedVoices;
}

/// The timeline of one chunk. Pieces are cut at the chunk edges (the source
/// range follows the piece's speed). Narration that lies fully inside the chunk
/// is kept and moved to start at 0; one that crosses a cut is dropped and counted.
/// Music is kept whole (it starts again in every chunk). A zoom piece cut across
/// a chunk edge starts its zoom again at the edge.
TimelineSlice sliceTimeline(Timeline t, int fromMs, int toMs) {
  final pieces = <VideoPiece>[];
  var pos = 0;
  for (final p in t.pieces) {
    final len = p.lengthMs;
    final s = pos;
    final e = pos + len;
    pos = e;
    final a = s > fromMs ? s : fromMs;
    final b = e < toMs ? e : toMs;
    if (b - a <= 0) continue;
    if (a == s && b == e) {
      pieces.add(p);
      continue;
    }
    if (b - a < 200) continue;
    if (p.freeze) {
      // The same still frame, held for less time.
      pieces.add(p.withRange(p.startMs, p.startMs + (b - a)));
    } else {
      final ss = p.startMs + ((a - s) * p.speed).round();
      final ee = p.startMs + ((b - s) * p.speed).round();
      pieces.add(p.withRange(ss, ee > ss ? ee : ss + 1));
    }
  }
  final voices = <VoiceItem>[];
  var dropped = 0;
  for (final v in t.voices) {
    if (v.endMs <= fromMs || v.offsetMs >= toMs) continue;
    if (v.offsetMs >= fromMs && v.endMs <= toMs + 300) {
      voices.add(v.copyWith(offsetMs: v.offsetMs - fromMs));
    } else {
      dropped++;
    }
  }
  return TimelineSlice(t.copyWith(pieces: pieces, voices: voices), dropped);
}

/// Windows (maps with 's' and 'e' in OUTPUT milliseconds) that touch the chunk,
/// cut to it and moved to start at 0. Windows left shorter than [minMs] go.
List<Map<String, Object?>> sliceWindows(List<Map<String, Object?>> items, int fromMs, int toMs, {int minMs = 300}) {
  final out = <Map<String, Object?>>[];
  for (final m in items) {
    final s = m['s'] as int;
    final e = m['e'] as int;
    if (e <= fromMs || s >= toMs) continue;
    final s2 = (s > fromMs ? s : fromMs) - fromMs;
    final e2 = (e < toMs ? e : toMs) - fromMs;
    if (e2 - s2 < minMs) continue;
    out.add({...m, 's': s2, 'e': e2});
  }
  return out;
}

/// A short Burmese line for the cool-down countdown.
String coolDownText(int secondsLeft) {
  final m = secondsLeft ~/ 60;
  final s = secondsLeft % 60;
  return m > 0 ? '$m မိနစ် ${s.toString().padLeft(2, '0')} စက္ကန့်' : '$s စက္ကန့်';
}
