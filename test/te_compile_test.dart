import 'package:aistudio/core/render_plan.dart';
import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TransformOp crop(String id, int s, int e,
        {OpStatus status = OpStatus.approved, Map<String, Object?>? params, TransformTool tool = TransformTool.cropReframe}) =>
    TransformOp(
      id: id,
      tool: tool,
      startMs: s,
      endMs: e,
      status: status,
      params: params ?? const {'zoom': 2.0, 'cx': 0.5, 'cy': 0.5},
    );

void main() {
  const base = [VideoPiece(0, 10000), VideoPiece(20000, 30000)];

  test('CropFrame is fitted inside the picture and survives JSON', () {
    final f = const CropFrame(2.0, 0.0, 1.0).fitted;
    expect(f.cx, 0.25);
    expect(f.cy, 0.75);
    expect(const CropFrame(9, 0.5, 0.5).fitted.zoom, 4.0);
    expect(const CropFrame(0.1, 0.5, 0.5).fitted.zoom, 1.0);
    final p = VideoPiece(0, 1000, ZoomMode.zoomIn, const CropFrame(2, 0.5, 0.5));
    final back = VideoPiece.fromJson(p.toJson());
    expect(back, p);
    expect(VideoPiece.fromJson({'s': 0, 'e': 5}).crop, isNull);
    expect(VideoPiece.fromJson({'s': 0, 'e': 5, 'c': 'bad'}).crop, isNull);
    expect(p.withRange(0, 500).crop, p.crop);
    expect(p.withZoom(ZoomMode.none).crop, p.crop);
  });

  test('no approved operations changes nothing', () {
    final r = compileOps(base, [crop('a', 0, 5000, status: OpStatus.proposed), crop('b', 0, 5000, status: OpStatus.rejected)]);
    expect(r.pieces, base);
    expect(r.applied, isEmpty);
    expect(r.notes, isEmpty);
  });

  test('approved crop splits a piece and keeps total length', () {
    final r = compileOps(base, [crop('a', 3000, 6000)]);
    expect(r.pieces.length, 4);
    expect(r.pieces[0], const VideoPiece(0, 3000));
    expect(r.pieces[1].startMs, 3000);
    expect(r.pieces[1].endMs, 6000);
    expect(r.pieces[1].crop, isNotNull);
    expect(r.pieces[2], const VideoPiece(6000, 10000));
    expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 20000);
    expect(r.applied.length, 1);
  });

  test('operation across a cut applies to both sides', () {
    final r = compileOps(base, [crop('a', 8000, 22000)]);
    expect(r.pieces.where((p) => p.crop != null).length, 2);
    expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 20000);
  });

  test('tiny leftovers are folded in, no clip under the minimum', () {
    final r = compileOps(base, [crop('a', 100, 9950)]);
    expect(r.pieces.length, 2);
    expect(r.pieces.first, const VideoPiece(0, 10000, ZoomMode.none, CropFrame(2.0, 0.5, 0.5)));
    for (final p in r.pieces) {
      expect(p.lengthMs >= minCompiledPieceMs, isTrue);
    }
  });

  test('later operation wins where two overlap', () {
    final r = compileOps(base, [
      crop('a', 0, 10000, params: const {'zoom': 1.5, 'cx': 0.5, 'cy': 0.5}),
      crop('b', 2000, 4000, params: const {'zoom': 3.0, 'cx': 0.5, 'cy': 0.5}),
    ]);
    final mid = r.pieces.firstWhere((p) => p.startMs == 2000);
    expect(mid.crop!.zoom, 3.0);
    expect(r.pieces.first.crop!.zoom, 1.5);
  });

  test('other tools and bad operations are reported, not silently dropped', () {
    final r = compileOps(base, [
      crop('f', 0, 3000, tool: TransformTool.smartCut),
      crop('z', 0, 3000, params: const {'zoom': 9.0, 'cx': 0.5, 'cy': 0.5}),
      crop('x', 12000, 15000), // between the two pieces
      crop('i', 5000, 1000),
    ]);
    expect(r.pieces, base);
    expect(r.applied, isEmpty);
    expect(r.notes.length, 4);
    expect(r.notes.first.contains('Smart Cut'), isTrue);
  });

  test('render job carries the crop and the timeline is untouched', () {
    final r = compileOps(base, [crop('a', 3000, 6000)]);
    final job = buildRenderJob(
      name: 'n',
      videoUri: 'content://v',
      timeline: Timeline(pieces: r.pieces),
      sourceSubtitles: const [],
      settings: const RenderSettings(),
    );
    final pieces = job['pieces'] as List;
    expect(pieces.length, 4);
    expect((pieces[1] as Map)['c'], [2.0, 0.5, 0.5]);
    expect((pieces[0] as Map).containsKey('c'), isFalse);
    expect(base.every((p) => p.crop == null), isTrue);
  });

  TransformOp freeze(String id, int at, {double hold = 3.0, OpStatus status = OpStatus.approved}) => TransformOp(
        id: id,
        tool: TransformTool.freezeFrame,
        startMs: at,
        endMs: at,
        status: status,
        params: {'hold': hold},
      );

  group('freeze frame', () {
    test('splits the piece and inserts a held still; output grows by the hold', () {
      final r = compileOps(base, [freeze('a', 4000)]);
      expect(r.pieces.length, 4);
      expect(r.pieces[0], const VideoPiece(0, 4000));
      expect(r.pieces[1].freeze, isTrue);
      expect(r.pieces[1].startMs, 4000);
      expect(r.pieces[1].lengthMs, 3000);
      expect(r.pieces[2], const VideoPiece(4000, 10000));
      expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 23000);
      expect(r.infos.first.contains('0:04'), isTrue);
      expect(r.infos.first.contains('3.0'), isTrue);
    });

    test('near a piece edge it is inserted without a tiny clip', () {
      final r = compileOps(base, [freeze('a', 100), freeze('b', 29900)]);
      expect(r.pieces.first.freeze, isTrue);
      expect(r.pieces.last.freeze, isTrue);
      expect(r.pieces.where((p) => !p.freeze).length, 2);
    });

    test('a frozen frame keeps the crop of its piece, and a later crop does not change it', () {
      final r = compileOps(base, [
        freeze('a', 4000),
        crop('c', 0, 10000),
      ]);
      final still = r.pieces.firstWhere((p) => p.freeze);
      expect(still.lengthMs, 3000);
      expect(r.pieces.where((p) => !p.freeze && p.startMs < 10000).every((p) => p.crop != null), isTrue);
      expect(still.crop, isNotNull);
    });

    test('bad hold, time outside the pieces, proposals are not applied', () {
      final r = compileOps(base, [
        freeze('a', 4000, hold: 0.1),
        freeze('b', 4000, hold: 99),
        freeze('c', 15000),
        freeze('d', 4000, status: OpStatus.proposed),
      ]);
      expect(r.pieces, base);
      expect(r.applied, isEmpty);
      expect(r.notes.length, 3);
    });

    test('freeze pieces: JSON, render job, subtitles pause during the hold', () {
      final r = compileOps(const [VideoPiece(0, 10000)], [freeze('a', 4000, hold: 2.0)]);
      final job = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: Timeline(pieces: r.pieces),
        sourceSubtitles: [SrtEntry(1, 1000, 9000, 'hello')],
        settings: const RenderSettings(),
      );
      final pieces = job['pieces'] as List;
      expect((pieces[1] as Map)['f'], 1);
      expect((pieces[0] as Map).containsKey('f'), isFalse);
      final subs = job['subtitles'] as List;
      // before the freeze, and after it shifted by the 2 s hold
      expect(subs.length, 2);
      expect((subs[0] as Map)['s'], 1000);
      expect((subs[1] as Map)['s'], 6000);
      expect(VideoPiece.fromJson(r.pieces[1].toJson()), r.pieces[1]);
      expect(outputDurationMs(Timeline(pieces: r.pieces)), 12000);
    });
  });
}
