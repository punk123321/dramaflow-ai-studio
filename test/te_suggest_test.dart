import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_suggest.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

SrtEntry e(int s, int en) => SrtEntry(1, s, en, 't');

void main() {
  test('finds quiet stretches with padding, ignoring short gaps', () {
    final gaps = findSubtitleGaps([e(0, 2000), e(3000, 4000), e(12000, 14000)], sourceMs: 15000);
    expect(gaps.length, 1);
    expect(gaps.single.startMs, 4500);
    expect(gaps.single.endMs, 11500);
  });

  test('before the first and after the last subtitle count too', () {
    final gaps = findSubtitleGaps([e(8000, 9000)], sourceMs: 20000);
    expect(gaps.length, 2);
    expect(gaps.first.startMs, 0);
    expect(gaps.first.endMs, 7500);
    expect(gaps.last.startMs, 9500);
    expect(gaps.last.endMs, 20000);
  });

  test('overlapping or unsorted subtitles do not create false gaps', () {
    final gaps = findSubtitleGaps([e(5000, 20000), e(0, 6000), e(7000, 9000)], sourceMs: 21000);
    expect(gaps, isEmpty);
  });

  test('no video length or no subtitles', () {
    expect(findSubtitleGaps([e(0, 1000)], sourceMs: 0), isEmpty);
    final g = findSubtitleGaps(const [], sourceMs: 30000);
    expect(g.length, 1);
    expect(g.single.startMs, 0);
    expect(g.single.endMs, 30000);
  });

  test('proposals are the biggest gaps, in time order, proposed only, and compile after approval', () {
    final gaps = [
      const GapSuggestion(0, 5000),
      const GapSuggestion(10000, 30000),
      const GapSuggestion(40000, 50000),
    ];
    final props = gapProposals(gaps, idSeed: 1, limit: 2);
    expect(props.length, 2);
    expect(props[0].startMs, 10000);
    expect(props[1].startMs, 40000);
    expect(props.every((p) => p.status == OpStatus.proposed && p.tool == TransformTool.smartCut), isTrue);
    expect(props.map((p) => p.id).toSet().length, 2);
    expect(compileOps(const [VideoPiece(0, 60000)], props).applied, isEmpty);
    final ok = props.map((p) => p.withStatus(OpStatus.approved)).toList();
    final r = compileOps(const [VideoPiece(0, 60000)], ok);
    expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 60000 - 20000 - 10000);
  });
}
