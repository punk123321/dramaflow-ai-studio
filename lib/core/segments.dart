/// Pure helpers for time text and video segments. No Flutter imports, so they
/// can be unit tested anywhere.

class SegmentSpec {
  const SegmentSpec(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;

  @override
  bool operator ==(Object other) =>
      other is SegmentSpec && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'SegmentSpec($startMs, $endMs)';
}

/// Splits [durationMs] into equal parts of [segmentMs]. The last part ends
/// exactly at the video end. A leftover shorter than one second is merged
/// into the previous part instead of becoming a tiny segment.
List<SegmentSpec> buildSegments(int durationMs, int segmentMs) {
  if (durationMs <= 0 || segmentMs <= 0) return const [];
  final out = <SegmentSpec>[];
  var start = 0;
  while (start < durationMs) {
    var end = start + segmentMs;
    if (end >= durationMs || durationMs - end < 1000) end = durationMs;
    out.add(SegmentSpec(start, end));
    start = end;
  }
  return out;
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// 0 -> "0:00", 65000 -> "1:05", 3725000 -> "1:02:05".
String formatTime(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(s)}';
  return '$m:${_two(s)}';
}

/// Accepts "90" (seconds), "1:30", or "1:02:03". Returns milliseconds, or
/// null when the text is not a valid time.
int? parseTime(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  var total = 0;
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i].trim();
    final v = int.tryParse(p);
    if (v == null || v < 0) return null;
    final isFirst = i == 0;
    if (!isFirst && v > 59) return null;
    total = total * 60 + v;
  }
  return total * 1000;
}

/// Returns a Burmese error message, or null when the segment is acceptable.
String? validateSegment({
  required int startMs,
  required int endMs,
  required int durationMs,
}) {
  if (startMs < 0) return 'စတင်ချိန်က 0 ထက် နည်းလို့ မရပါဘူး။';
  if (endMs <= startMs) return 'ဆုံးချိန်က စတင်ချိန်ထက် နောက်ကျရပါမယ်။';
  if (endMs > durationMs) {
    return 'ဆုံးချိန်က video ကြာချိန် (${formatTime(durationMs)}) ထက် မကျော်ရပါဘူး။';
  }
  return null;
}

/// Sorts by start time. Does not merge or drop anything.
List<SegmentSpec> sortedSegments(Iterable<SegmentSpec> items) {
  final list = items.toList();
  list.sort((a, b) {
    final c = a.startMs.compareTo(b.startMs);
    return c != 0 ? c : a.endMs.compareTo(b.endMs);
  });
  return list;
}

/// True when two segments share any time. Touching ends do not overlap.
bool hasOverlap(List<SegmentSpec> sorted) {
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMs < sorted[i - 1].endMs) return true;
  }
  return false;
}

/// 1536 -> "1.5 KB", 1288490188 -> "1.2 GB".
String formatSize(int bytes) {
  if (bytes <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final text = u == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$text ${units[u]}';
}
