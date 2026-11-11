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
      crop('f', 0, 3000, tool: TransformTool.commentaryVoiceOver),
      crop('z', 0, 3000, params: const {'zoom': 9.0, 'cx': 0.5, 'cy': 0.5}),
      crop('x', 12000, 15000), // between the two pieces
      crop('i', 5000, 1000),
    ]);
    expect(r.pieces, base);
    expect(r.applied, isEmpty);
    expect(r.notes.length, 4);
    expect(r.notes.first.contains('Commentary'), isTrue);
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

  TransformOp motion(String id, int s, int e, Map<String, Object?> params, {OpStatus status = OpStatus.approved}) => TransformOp(
        id: id,
        tool: TransformTool.motionGraphics,
        startMs: s,
        endMs: e,
        status: status,
        params: params,
      );
  const label = {'kind': 'label', 'text': 'Key scene', 'x': 0.5, 'y': 0.2, 'size': 0.06, 'color': 0xFFFFEB3B};

  group('motion graphics', () {
    test('a label inside one piece lands on the same output time', () {
      final r = compileOps(base, [motion('m', 2000, 6000, label)]);
      expect(r.overlays.length, 1);
      final o = r.overlays.first;
      expect(o.kind, MotionKind.label);
      expect(o.startMs, 2000);
      expect(o.endMs, 6000);
      expect(o.text, 'Key scene');
      expect(r.applied.length, 1);
    });

    test('time follows the cut: a range in the second piece moves earlier', () {
      // pieces 0-10 s and 20-30 s: source 22 s is output 12 s
      final r = compileOps(base, [motion('m', 22000, 25000, label)]);
      expect(r.overlays.single.startMs, 12000);
      expect(r.overlays.single.endMs, 15000);
    });

    test('a range spanning the gap joins into one output range', () {
      final r = compileOps(base, [motion('m', 8000, 22000, label)]);
      expect(r.overlays.length, 1);
      expect(r.overlays.single.startMs, 8000);
      expect(r.overlays.single.endMs, 12000);
    });

    test('reordered pieces: one operation can show in two places', () {
      final r = compileOps(const [VideoPiece(0, 10000), VideoPiece(20000, 30000), VideoPiece(5000, 8000)], [motion('m', 6000, 7000, label)]);
      expect(r.overlays.length, 2);
      expect(r.overlays[0].startMs, 6000);
      expect(r.overlays[1].startMs, 21000);
    });

    test('a freeze inside the range is covered, and later content shifts', () {
      final r = compileOps(const [VideoPiece(0, 10000)], [freeze('f', 4000, hold: 2.0), motion('m', 3000, 6000, label)]);
      expect(r.overlays.length, 1);
      expect(r.overlays.single.startMs, 3000);
      expect(r.overlays.single.endMs, 8000);
    });

    test('arrow, bad values, proposals and unreachable times', () {
      final arrow = {'kind': 'arrow', 'x': 0.3, 'y': 0.4, 'size': 0.2, 'color': 0xFFFF5252, 'angle': 450};
      final ok = compileOps(base, [motion('a', 1000, 4000, arrow)]);
      expect(ok.overlays.single.kind, MotionKind.arrow);
      expect(ok.overlays.single.angle, 90);
      expect(ok.overlays.single.toJson().containsKey('t'), isFalse);

      final r = compileOps(base, [
        motion('1', 0, 3000, {...label, 'text': '  '}),
        motion('2', 0, 3000, {...label, 'x': 1.5}),
        motion('3', 0, 3000, {...label, 'size': 0.9}),
        motion('4', 0, 3000, {...label, 'kind': 'hologram'}),
        motion('5', 12000, 15000, label),
        motion('6', 0, 3000, label, status: OpStatus.proposed),
      ]);
      expect(r.overlays, isEmpty);
      expect(r.applied, isEmpty);
      expect(r.notes.length, 5);
    });

    test('overlays go into the render job and do not change the video pieces', () {
      final r = compileOps(base, [motion('m', 2000, 6000, label)]);
      final job = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: Timeline(pieces: r.pieces),
        sourceSubtitles: const [],
        settings: const RenderSettings(),
        overlays: [for (final o in r.overlays) o.toJson()],
      );
      expect(r.pieces, base);
      final list = job['overlays'] as List;
      expect(list.length, 1);
      expect((list[0] as Map)['t'], 'Key scene');
      expect((list[0] as Map)['s'], 2000);
      final none = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: Timeline(pieces: base),
        sourceSubtitles: const [],
        settings: const RenderSettings(),
      );
      expect(none.containsKey('overlays'), isFalse);
    });
  });

  TransformOp sfx(String id, int at, {Map<String, Object?>? params, OpStatus status = OpStatus.approved}) => TransformOp(
        id: id,
        tool: TransformTool.soundDesign,
        startMs: at,
        endMs: at,
        status: status,
        params: params ?? const {'src': 'content://a/1', 'name': 'boom.mp3', 'dur': 2000, 'vol': 0.8},
      );

  group('sound design', () {
    test('effect lands on the output time of its source moment', () {
      final r = compileOps(base, [sfx('s', 22000)]);
      expect(r.sounds.length, 1);
      expect(r.sounds.single.offsetMs, 12000);
      expect(r.sounds.single.durationMs, 2000);
      expect(r.sounds.single.volume, 0.8);
      expect(r.sounds.single.source, 'content://a/1');
      expect(r.applied.length, 1);
    });

    test('later content shifts after a held frame', () {
      final r = compileOps(const [VideoPiece(0, 10000)], [freeze('f', 2000, hold: 3.0), sfx('s', 5000)]);
      expect(r.sounds.single.offsetMs, 8000);
    });

    test('bad file, volume, time outside, past the end, proposal: reported or ignored', () {
      final r = compileOps(base, [
        sfx('1', 1000, params: const {'src': '', 'dur': 2000, 'vol': 0.5}),
        sfx('2', 1000, params: const {'src': 'x', 'dur': 2000, 'vol': 5}),
        sfx('3', 12000),
        sfx('4', 19000), // output 19 s, 2 s long: past the 20 s end
        sfx('5', 1000, status: OpStatus.proposed),
      ]);
      expect(r.sounds, isEmpty);
      expect(r.applied, isEmpty);
      expect(r.notes.length, 4);
    });

    test('sound effects join the narration lanes in the render job', () {
      final r = compileOps(base, [sfx('s', 3000)]);
      final voice = VoiceItem(source: '/data/v.wav', label: 'v', durationMs: 5000, offsetMs: 2000);
      final tl = Timeline(pieces: r.pieces, voices: [voice, ...r.sounds]);
      final job = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: tl,
        sourceSubtitles: const [],
        settings: const RenderSettings(),
      );
      final lanes = job['voiceLanes'] as List;
      expect(lanes.length, 2); // overlap, so two lanes mixed together
      expect(r.pieces, base);
    });
  });

  TransformOp cut(String id, int s, int e, {OpStatus status = OpStatus.approved}) =>
      TransformOp(id: id, tool: TransformTool.smartCut, startMs: s, endMs: e, status: status);

  group('smart cut', () {
    test('removes the range, splitting a piece in the middle', () {
      final r = compileOps(base, [cut('c', 3000, 6000)]);
      expect(r.pieces, const [VideoPiece(0, 3000), VideoPiece(6000, 10000), VideoPiece(20000, 30000)]);
      expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 17000);
      expect(r.applied.length, 1);
      expect(r.infos.any((i) => i.contains('Smart Cut')), isTrue);
    });

    test('a cut across two pieces trims both; a whole piece can go', () {
      final r = compileOps(base, [cut('c', 8000, 25000)]);
      expect(r.pieces, const [VideoPiece(0, 8000), VideoPiece(25000, 30000)]);
      final whole = compileOps(base, [cut('c', 0, 10000)]);
      expect(whole.pieces, const [VideoPiece(20000, 30000)]);
    });

    test('tiny leftovers go with the cut; nothing to cut or everything is reported', () {
      final r = compileOps(base, [cut('c', 100, 9900)]);
      expect(r.pieces, const [VideoPiece(20000, 30000)]);
      final none = compileOps(base, [cut('c', 12000, 15000)]);
      expect(none.pieces, base);
      expect(none.notes.length, 1);
      final all = compileOps(const [VideoPiece(0, 5000)], [cut('c', 0, 5000)]);
      expect(all.pieces, const [VideoPiece(0, 5000)]);
      expect(all.notes.length, 1);
      expect(compileOps(base, [cut('c', 3000, 6000, status: OpStatus.proposed)]).pieces, base);
    });

    test('overlapping cuts are counted once in the message', () {
      final r = compileOps(const [VideoPiece(0, 20000)], [cut('a', 2000, 8000), cut('b', 5000, 11000)]);
      expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 11000); // 0-2 s and 11-20 s
      final info = r.infos.firstWhere((i) => i.contains('Smart Cut'));
      expect(info.contains('0:09'), isTrue);
    });

    test('other operations follow the cut: a label after it moves earlier', () {
      final r = compileOps(base, [cut('c', 3000, 6000), motion('m', 7000, 9000, label)]);
      expect(r.overlays.single.startMs, 4000);
      expect(r.overlays.single.endMs, 6000);
    });

    test('a label inside the cut part is left out with a note', () {
      final r = compileOps(base, [cut('c', 3000, 6000), motion('m', 3500, 5500, label)]);
      expect(r.overlays, isEmpty);
      expect(r.notes.length, 1);
    });
  });

  group('picture overlay (picture-in-picture, image only)', () {
    TransformOp pip(String id, int s, int e, Map<String, Object?> params) =>
        TransformOp(id: id, tool: TransformTool.pictureInPicture, startMs: s, endMs: e, status: OpStatus.approved, params: params);

    test('a picture becomes a timed image overlay', () {
      final r = compileOps(base, [
        pip('p', 2000, 5000, const {'kind': 'image', 'path': '/data/logo.png', 'x': 0.8, 'y': 0.2, 'size': 0.3, 'color': 0xFFFFFFFF}),
      ]);
      final o = r.overlays.single;
      expect(o.kind, MotionKind.image);
      expect(o.path, '/data/logo.png');
      final j = o.toJson();
      expect(j['k'], 'image');
      expect(j['path'], '/data/logo.png');
      expect(j.containsKey('t'), isFalse);
      expect(r.applied.length, 1);
    });

    test('no picture, or too large, is reported', () {
      final r = compileOps(base, [
        pip('1', 2000, 5000, const {'kind': 'image', 'path': '', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'color': 0xFFFFFFFF}),
        pip('2', 2000, 5000, const {'kind': 'image', 'path': 'a.png', 'x': 0.5, 'y': 0.5, 'size': 0.9, 'color': 0xFFFFFFFF}),
      ]);
      expect(r.overlays, isEmpty);
      expect(r.notes.length, 2);
    });
  });

  test('missing app files are reported; content links are not checked', () {
    final r = compileOps(base, [
      TransformOp(
        id: 'p',
        tool: TransformTool.pictureInPicture,
        startMs: 1000,
        endMs: 3000,
        status: OpStatus.approved,
        params: const {'kind': 'image', 'path': '/data/gone.png', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'color': 0xFFFFFFFF},
      ),
      TransformOp(
        id: 's1',
        tool: TransformTool.soundDesign,
        startMs: 1000,
        endMs: 1000,
        status: OpStatus.approved,
        params: const {'src': '/data/gone.mp3', 'name': 'a.mp3', 'dur': 1000, 'vol': 0.5},
      ),
      TransformOp(
        id: 's2',
        tool: TransformTool.soundDesign,
        startMs: 2000,
        endMs: 2000,
        status: OpStatus.approved,
        params: const {'src': 'content://x/1', 'name': 'b.mp3', 'dur': 1000, 'vol': 0.5},
      ),
    ]);
    expect(missingFiles(r, (_) => false).length, 2);
    expect(missingFiles(r, (_) => true), isEmpty);
  });

  TransformOp grade(String id, int s, int e, {double b = 0.2, double c = 0.1, OpStatus status = OpStatus.approved}) => TransformOp(
        id: id,
        tool: TransformTool.colorGrade,
        startMs: s,
        endMs: e,
        status: status,
        params: {'brightness': b, 'contrast': c},
      );

  group('brightness and contrast', () {
    test('look is applied to the range only, total length unchanged', () {
      final r = compileOps(base, [grade('g', 3000, 6000)]);
      expect(r.pieces.length, 4);
      expect(r.pieces[0].look, isNull);
      expect(r.pieces[1].look, const LookAdjust(0.2, 0.1));
      expect(r.pieces[2].look, isNull);
      expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 20000);
      expect(r.applied.length, 1);
    });

    test('crop and look on the same range combine; held frames keep the look', () {
      final r = compileOps(base, [crop('c', 0, 10000), grade('g', 0, 10000), freeze('f', 4000)]);
      final moving = r.pieces.where((p) => !p.freeze && p.startMs < 10000);
      expect(moving.every((p) => p.crop != null && p.look != null), isTrue);
      final still = r.pieces.firstWhere((p) => p.freeze);
      expect(still.look, isNotNull);
      expect(still.crop, isNotNull);
    });

    test('neutral, out of range, proposed or outside: nothing applied', () {
      final r = compileOps(base, [
        grade('1', 0, 5000, b: 0, c: 0),
        grade('2', 0, 5000, b: 0.9),
        grade('3', 0, 5000, status: OpStatus.proposed),
        grade('4', 12000, 15000),
      ]);
      expect(r.pieces, base);
      expect(r.applied, isEmpty);
      expect(r.notes.length, 3);
    });

    test('look survives JSON, trim/split helpers and goes into the render job', () {
      const piece = VideoPiece(0, 4000, ZoomMode.none, null, false, LookAdjust(-0.3, 0.2));
      expect(VideoPiece.fromJson(piece.toJson()), piece);
      expect(piece.withRange(0, 2000).look, piece.look);
      expect(piece.withZoom(ZoomMode.zoomIn).look, piece.look);
      expect(VideoPiece.fromJson({'s': 0, 'e': 5, 'l': [0, 0]}).look, isNull);
      expect(VideoPiece.fromJson({'s': 0, 'e': 5, 'l': [9, 9]}).look, const LookAdjust(0.6, 0.6));
      final job = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: const Timeline(pieces: [piece]),
        sourceSubtitles: const [],
        settings: const RenderSettings(),
      );
      expect(((job['pieces'] as List).first as Map)['l'], [-0.3, 0.2]);
    });
  });

  TransformOp split(String id, int s, int e, Map<String, Object?> params, {OpStatus status = OpStatus.approved}) =>
      TransformOp(id: id, tool: TransformTool.splitScreen, startMs: s, endMs: e, status: status, params: params);
  const lr = {'second': 40.0, 'layout': 'leftRight'};

  group('split screen (experimental)', () {
    test('a window on the output time with the second picture start', () {
      final r = compileOps(base, [split('s', 22000, 26000, lr)]);
      final w = r.splits.single;
      expect(w.startMs, 12000);
      expect(w.endMs, 16000);
      expect(w.secondMs, 40000);
      expect(w.layout, SplitLayout.leftRight);
      expect(r.pieces, base);
      expect(r.applied.length, 1);
      expect(r.infos.any((i) => i.contains('Split Screen')), isTrue);
    });

    test('bad values, too short, overlap, cut in the middle, proposal: left out with a note', () {
      final r = compileOps(base, [
        split('1', 1000, 5000, const {'second': -1, 'layout': 'leftRight'}),
        split('2', 1000, 5000, const {'second': 3, 'layout': 'diagonal'}),
        split('3', 1000, 1500, lr),
        split('4', 2000, 6000, lr),
        split('5', 3000, 7000, lr),
        split('6', 1000, 5000, lr, status: OpStatus.proposed),
      ]);
      expect(r.splits.length, 1);
      expect(r.splits.single.startMs, 2000);
      expect(r.notes.length, 4);
      // the same source moment shows up twice (reordered pieces): not one window
      final twice = compileOps(const [VideoPiece(0, 10000), VideoPiece(20000, 30000), VideoPiece(5000, 8000)], [split('s', 6000, 7500, lr)]);
      expect(twice.splits, isEmpty);
      expect(twice.notes.length, 1);
      // a cut that leaves the range touching in the output is still one window
      final joined = compileOps(base, [cut('c', 3000, 6000), split('s', 1000, 9000, lr)]);
      expect(joined.splits.length, 1);
      expect(joined.splits.single.startMs, 1000);
    });

    test('goes into the render job; no splits means no key', () {
      final r = compileOps(base, [split('s', 1000, 4000, const {'second': 12.5, 'layout': 'topBottom'})]);
      final job = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: Timeline(pieces: r.pieces),
        sourceSubtitles: const [],
        settings: const RenderSettings(),
        splits: [for (final x in r.splits) x.toJson()],
      );
      final list = job['splits'] as List;
      expect((list.single as Map)['src'], 12500);
      expect((list.single as Map)['layout'], 'topBottom');
      final none = buildRenderJob(
        name: 'n',
        videoUri: 'content://v',
        timeline: Timeline(pieces: base),
        sourceSubtitles: const [],
        settings: const RenderSettings(),
      );
      expect(none.containsKey('splits'), isFalse);
    });
  });
}
