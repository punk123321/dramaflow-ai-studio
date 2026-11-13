import 'srt.dart';
import 'timeline.dart';

/// Cutting a video into parts AT subtitle lines, and writing the matching SRT
/// for each part. Pure Dart.
///
/// A part runs from the start of its first line to the start of the next
/// part's first line, so no picture is lost between parts. The first part
/// starts at 0 and the last one ends at the end of the video.

class SplitPart {
  const SplitPart({required this.startMs, required this.endMs, required this.firstLine, required this.lastLine});

  final int startMs;
  final int endMs;

  /// Indexes into the sorted line list (inclusive).
  final int firstLine;
  final int lastLine;

  int get lines => lastLine - firstLine + 1;
  int get lengthMs => endMs - startMs;
}

List<SrtEntry> sortedLines(List<SrtEntry> e) => [...e]..sort((a, b) => a.startMs.compareTo(b.startMs));

/// [breaks] holds the indexes (1 or more) of lines that START a new part.
/// Breaks that would make an empty or backwards part are ignored.
List<SplitPart> buildParts(List<SrtEntry> sorted, Set<int> breaks, int durationMs) {
  if (sorted.isEmpty) return const [];
  final last = sorted.map((e) => e.endMs).reduce((a, b) => a > b ? a : b);
  final total = durationMs > 0 ? (durationMs > last ? durationMs : last) : last;
  // First line of each part. The first part starts at 0.
  final starts = <int>[0];
  for (final b in ([...breaks]..sort())) {
    if (b < 1 || b >= sorted.length) continue;
    final prevStartMs = starts.length == 1 ? 0 : sorted[starts.last].startMs;
    if (sorted[b].startMs <= prevStartMs) continue;
    starts.add(b);
  }
  final parts = <SplitPart>[];
  for (var i = 0; i < starts.length; i++) {
    final startMs = i == 0 ? 0 : sorted[starts[i]].startMs;
    final endMs = i + 1 < starts.length ? sorted[starts[i + 1]].startMs : total;
    final lastLine = (i + 1 < starts.length ? starts[i + 1] : sorted.length) - 1;
    if (endMs <= startMs) continue;
    parts.add(SplitPart(startMs: startMs, endMs: endMs, firstLine: starts[i], lastLine: lastLine));
  }
  return parts;
}

/// A new part every [n] lines.
Set<int> breaksEveryLines(int count, int n) {
  if (n < 1) return {};
  return {for (var i = n; i < count; i += n) i};
}

/// A new part at the first line that starts at least [targetMs] after the
/// previous part started. Parts are therefore a little longer than the target,
/// never cut in the middle of a line.
Set<int> breaksEveryMs(List<SrtEntry> sorted, int targetMs) {
  if (targetMs < 1000) return {};
  final out = <int>{};
  var partStart = 0;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMs - partStart >= targetMs) {
      out.add(i);
      partStart = sorted[i].startMs;
    }
  }
  return out;
}

/// Break points where the line before still runs past the cut, so it will be
/// shortened in its part. Shown as a warning.
List<int> overlappingBreaks(List<SrtEntry> sorted, Set<int> breaks) => [
      for (final b in breaks)
        if (b >= 1 && b < sorted.length && sorted[b - 1].endMs > sorted[b].startMs) b
    ];

/// The SRT of one part, with times counted from the start of that part. A line
/// that crosses the cut is shortened to the part. Text is never changed.
String partSrt(List<SrtEntry> sorted, SplitPart part) =>
    serializeSrt(remapSubtitles(sorted, [VideoPiece(part.startMs, part.endMs)]));

/// "name_part01.srt"
String partFileName(String base, int index, int total) {
  final width = total >= 100 ? 3 : 2;
  return '${base}_part${(index + 1).toString().padLeft(width, '0')}';
}
