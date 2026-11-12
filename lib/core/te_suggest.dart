import 'srt.dart';
import 'transformative_plan.dart';

/// Rule-based Smart Cut suggestions from the subtitles. No AI, no audio
/// analysis: a stretch with no subtitle for a long time is only a GUESS that
/// nothing is being said there (music, action, or a missing subtitle).
/// Every suggestion is proposed; the user decides.

class GapSuggestion {
  const GapSuggestion(this.startMs, this.endMs);
  final int startMs;
  final int endMs;
  int get lengthMs => endMs - startMs;
}

/// Quiet stretches between subtitles (also before the first and after the
/// last). [padMs] is kept on each side so the cut does not clip speech.
List<GapSuggestion> findSubtitleGaps(
  List<SrtEntry> subs, {
  required int sourceMs,
  int minGapMs = 4000,
  int padMs = 500,
}) {
  if (sourceMs <= 0 || minGapMs <= 0) return const [];
  final sorted = [...subs]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <GapSuggestion>[];
  var cursor = 0;
  void gap(int from, int to) {
    final s = from == 0 ? 0 : from + padMs;
    final e = to >= sourceMs ? sourceMs : to - padMs;
    if (e - s >= minGapMs - 2 * padMs && to - from >= minGapMs && e > s) out.add(GapSuggestion(s, e));
  }

  for (final s in sorted) {
    if (s.startMs > cursor) gap(cursor, s.startMs);
    if (s.endMs > cursor) cursor = s.endMs;
  }
  if (sourceMs > cursor) gap(cursor, sourceMs);
  return out;
}

String _sec(int ms) => (ms / 1000).toStringAsFixed(1);

/// Proposed Smart Cut operations for the biggest gaps, at most [limit].
List<TransformOp> gapProposals(List<GapSuggestion> gaps, {required int idSeed, int limit = 20}) {
  final top = [...gaps]..sort((a, b) => b.lengthMs.compareTo(a.lengthMs));
  final chosen = top.take(limit).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
  var n = 0;
  return [
    for (final g in chosen)
      TransformOp.proposal(
        id: 'gap-$idSeed-${n++}',
        tool: TransformTool.smartCut,
        startMs: g.startMs,
        endMs: g.endMs,
        note: 'စာတန်း မရှိတဲ့ ${_sec(g.lengthMs)} စက္ကန့် (ခန့်မှန်းချက်သာ)',
        source: OpSource.manual,
      ),
  ];
}
