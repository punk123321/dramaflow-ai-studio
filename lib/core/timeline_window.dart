import 'srt.dart';

/// The subtitles that touch the time window [fromMs, toMs]. The timeline draws
/// a block for each one, and a long drama has thousands, so only the ones on
/// (or next to) the screen are built.
List<SrtEntry> subsInWindow(List<SrtEntry> subs, int fromMs, int toMs) {
  return [for (final e in subs) if (e.endMs >= fromMs && e.startMs <= toMs) e];
}
