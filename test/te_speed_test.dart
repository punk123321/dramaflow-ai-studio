import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_preview.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TransformOp speedOp(int s, int e, double v, {OpStatus st = OpStatus.approved}) =>
    TransformOp(id: '$s-$e', tool: TransformTool.speedChange, startMs: s, endMs: e, params: {'speed': v}, status: st);

void main() {
  test('piece length follows the speed; freeze pieces ignore it', () {
    expect(const VideoPiece(0, 10000).lengthMs, 10000);
    expect(const VideoPiece(0, 10000, ZoomMode.none, null, false, null, 2.0).lengthMs, 5000);
    expect(const VideoPiece(0, 10000, ZoomMode.none, null, false, null, 0.5).lengthMs, 20000);
    expect(const VideoPiece.freezeAt(1000, 3000).lengthMs, 3000);
  });

  test('speed is kept by withRange and survives JSON', () {
    final p = const VideoPiece(0, 10000).withSpeed(2.0).withRange(1000, 5000);
    expect(p.speed, 2.0);
    expect(p.lengthMs, 2000);
    final back = VideoPiece.fromJson(p.toJson());
    expect(back.speed, 2.0);
    expect(const VideoPiece(0, 1000).toJson().containsKey('sp'), isFalse);
    expect(VideoPiece.fromJson({'s': 0, 'e': 1000, 'sp': 99}).speed, 1.0); // out of range is ignored
  });

  test('compile: the middle of a piece gets the speed, the sides stay', () {
    final r = compileOps(const [VideoPiece(0, 20000)], [speedOp(5000, 10000, 2.0)]);
    expect(r.pieces.length, 3);
    expect(r.pieces[0].speed, 1.0);
    expect(r.pieces[1].speed, 2.0);
    expect(r.pieces[1].startMs, 5000);
    expect(r.pieces[1].endMs, 10000);
    expect(r.pieces[2].speed, 1.0);
    final total = r.pieces.fold<int>(0, (a, p) => a + p.lengthMs);
    expect(total, 5000 + 2500 + 10000);
  });

  test('compile: not approved, 1x and out-of-range speeds are ignored', () {
    final base = const [VideoPiece(0, 20000)];
    expect(compileOps(base, [speedOp(5000, 10000, 2.0, st: OpStatus.proposed)]).pieces, base);
    expect(compileOps(base, [speedOp(5000, 10000, 1.0)]).pieces, base);
    expect(compileOps(base, [speedOp(5000, 10000, 9.0)]).pieces, base);
    expect(compileOps(base, [speedOp(5000, 10000, 0.1)]).pieces, base);
  });

  test('outputRanges and subtitles follow the speed', () {
    final pieces = const [VideoPiece(0, 4000), VideoPiece(4000, 8000, ZoomMode.none, null, false, null, 2.0)];
    // Source 4000..8000 plays in 2000 ms starting at output 4000.
    expect(outputRanges(pieces, 4000, 8000), [(4000, 6000)]);
    final subs = remapSubtitles([const SrtEntry(1, 5000, 7000, 'a')], pieces);
    expect(subs.single.startMs, 4500);
    expect(subs.single.endMs, 5500);
    expect(timelineToSource(pieces, 5000)!.sourceMs, 6000);
  });

  test('preview: speed and badge at the playhead', () {
    final ops = [speedOp(1000, 4000, 0.5)];
    expect(previewSpeed(ops, 500), 1.0);
    expect(previewSpeed(ops, 2000), 0.5);
    expect(previewBadges(ops, 2000).single, contains('0.5'));
    expect(previewSpeed([speedOp(1000, 4000, 1.0)], 2000), 1.0);
  });
}
