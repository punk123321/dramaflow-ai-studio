import 'dart:convert';

import 'package:aistudio/core/render_plan.dart';
import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_frames.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every template draws something, with finite numbers, for landscape and portrait', () {
    for (final t in frameTemplates) {
      for (final size in const [(1280.0, 720.0), (720.0, 1280.0), (1080.0, 1080.0)]) {
        final prims = framePrims(t.id, t.defaultColor, t.defaultThick, size.$1, size.$2);
        expect(prims, isNotEmpty, reason: t.name);
        expect(prims.length, lessThan(200), reason: t.name);
        for (final m in prims) {
          expect(const {'r', 'l', 'o'}.contains(m['t']), isTrue, reason: t.name);
          for (final v in m.values) {
            if (v is num) expect(v.isFinite, isTrue, reason: t.name);
          }
        }
        // It must survive being sent to the render as JSON.
        expect(jsonDecode(jsonEncode(prims)), isA<List<Object?>>());
      }
    }
  });

  test('ids are unique, 1..12, and unknown ids draw nothing', () {
    expect({for (final t in frameTemplates) t.id}.length, frameTemplates.length);
    expect(frameTemplates.map((t) => t.id).reduce((a, b) => a < b ? a : b), 1);
    expect(frameTemplateById(3)!.name, 'Gold');
    expect(frameTemplateById(99), isNull);
    expect(framePrims(99, 0xFFFFFFFF, 0.01, 100, 100), isEmpty);
    expect(framePrims(1, 0xFFFFFFFF, 0.01, 0, 100), isEmpty);
  });

  test('frames stay inside the picture (short-side units)', () {
    for (final t in frameTemplates) {
      final prims = framePrims(t.id, t.defaultColor, t.defaultThick, 1280, 720);
      final w = 1280 / 720;
      for (final m in prims) {
        if (m['t'] != 'r') continue;
        final x = (m['x'] as num).toDouble();
        final y = (m['y'] as num).toDouble();
        final rw = (m['w'] as num).toDouble();
        final rh = (m['h'] as num).toDouble();
        expect(x, greaterThanOrEqualTo(-1e-9), reason: t.name);
        expect(y, greaterThanOrEqualTo(-1e-9), reason: t.name);
        expect(x + rw, lessThanOrEqualTo(w + 1e-9), reason: t.name);
        expect(y + rh, lessThanOrEqualTo(1 + 1e-9), reason: t.name);
      }
    }
  });

  test('the film strip has more holes on a taller picture and is capped', () {
    final a = framePrims(5, 0, 0.014, 720, 1280).length;
    final b = framePrims(5, 0, 0.014, 1280, 720).length;
    expect(a, greaterThan(b));
    expect(framePrims(5, 0, 0.004, 720, 4000).length, lessThanOrEqualTo(2 + 120));
  });

  test('frame template parameter is kept; an unknown one falls back to the plain border', () {
    Map<String, Object?> p(Object? tpl) => {'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.014, 'color': 0xFFFFFFFF, 'tpl': tpl};
    expect(motionFromParams(p(3))!.template, 3);
    expect(motionFromParams(p(3))!.toJson()['tpl'], 3);
    expect(motionFromParams(p(99))!.template, 0);
    expect(motionFromParams(p('x'))!.template, 0);
    expect(motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.014, 'color': 0xFFFFFFFF})!.toJson().containsKey('tpl'), isFalse);
  });

  test('the render job carries the primitives for the real output size', () {
    final item = motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.014, 'color': 0xFFFFFFFF, 'tpl': 2})!.withTime(0, 5000);
    final job = buildRenderJob(
      name: 'x',
      videoUri: 'v',
      timeline: const Timeline(pieces: [VideoPiece(0, 10000)]),
      sourceSubtitles: const [],
      settings: const RenderSettings(),
      overlays: [item.toJson()],
    );
    final o = (job['overlays'] as List).single as Map;
    expect((o['prims'] as List), isNotEmpty);
    // A plain border gets none.
    final plain = motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.014, 'color': 0xFFFFFFFF})!.withTime(0, 5000);
    final job2 = buildRenderJob(
      name: 'x',
      videoUri: 'v',
      timeline: const Timeline(pieces: [VideoPiece(0, 10000)]),
      sourceSubtitles: const [],
      settings: const RenderSettings(),
      overlays: [plain.toJson()],
    );
    expect(((job2['overlays'] as List).single as Map).containsKey('prims'), isFalse);
  });
}
