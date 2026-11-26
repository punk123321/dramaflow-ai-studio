import 'dart:typed_data';

import 'package:aistudio/core/scenes.dart';
import 'package:aistudio/core/srt.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List sig(int v) => Uint8List.fromList(List.filled(sigBytes, v));

void main() {
  test('diff series: same frames 0, a hard cut is large', () {
    final all = Uint8List.fromList([...sig(10), ...sig(10), ...sig(240)]);
    final d = diffSeries(all);
    expect(d[0], 0);
    expect(d[1], 0);
    expect(d[2], closeTo(230 / 255, 1e-9));
  });

  test('scenes are found at strong cuts and cover the range', () {
    final times = [for (var i = 0; i < 20; i++) i * 1000];
    final diffs = List<double>.filled(20, 0.01);
    diffs[7] = 0.6;
    diffs[14] = 0.5;
    final s = pickScenes(timesMs: times, diffs: diffs, rangeStartMs: 0, rangeEndMs: 20000);
    expect(s, [const SceneSpan(0, 7000), const SceneSpan(7000, 14000), const SceneSpan(14000, 20000)]);
  });

  test('cuts closer than the minimum length are dropped, strongest kept', () {
    final times = [for (var i = 0; i < 20; i++) i * 1000];
    final diffs = List<double>.filled(20, 0.01);
    diffs[8] = 0.5;
    diffs[9] = 0.7;
    final s = pickScenes(timesMs: times, diffs: diffs, rangeStartMs: 0, rangeEndMs: 20000);
    expect(s.length, 2);
    expect(s.first.endMs, 9000);
  });

  test('never more scenes than the limit; strongest cuts win', () {
    final times = [for (var i = 0; i < 100; i++) i * 3000];
    final diffs = [for (var i = 0; i < 100; i++) i % 5 == 0 ? 0.2 + i / 1000 : 0.01];
    final s = pickScenes(timesMs: times, diffs: diffs, rangeStartMs: 0, rangeEndMs: 300000, maxScenes: 5, maxSceneMs: 0);
    expect(s.length, lessThanOrEqualTo(5));
    expect(s.first.startMs, 0);
    expect(s.last.endMs, 300000);
  });

  test('a still scene longer than the maximum is split evenly', () {
    final s = pickScenes(timesMs: const [0, 1000], diffs: const [0, 0], rangeStartMs: 0, rangeEndMs: 100000, maxSceneMs: 45000);
    expect(s.length, 3);
    expect(s.first.startMs, 0);
    expect(s.last.endMs, 100000);
    for (var i = 0; i + 1 < s.length; i++) {
      expect(s[i].endMs, s[i + 1].startMs);
    }
  });

  test('no samples gives one scene; empty range gives none', () {
    expect(pickScenes(timesMs: const [], diffs: const [], rangeStartMs: 0, rangeEndMs: 30000), [const SceneSpan(0, 30000)]);
    expect(pickScenes(timesMs: const [], diffs: const [], rangeStartMs: 5, rangeEndMs: 5), isEmpty);
  });

  test('range that does not start at zero', () {
    final times = [for (var i = 0; i < 10; i++) 60000 + i * 1000];
    final diffs = List<double>.filled(10, 0.01);
    diffs[5] = 0.8;
    final s = pickScenes(timesMs: times, diffs: diffs, rangeStartMs: 60000, rangeEndMs: 70000);
    expect(s, [const SceneSpan(60000, 65000), const SceneSpan(65000, 70000)]);
  });

  test('merge with previous', () {
    final m = mergeWithPrevious(const [SceneSpan(0, 5), SceneSpan(5, 9), SceneSpan(9, 12)], 1);
    expect(m, [const SceneSpan(0, 9), const SceneSpan(9, 12)]);
    expect(mergeWithPrevious(const [SceneSpan(0, 5)], 0), [const SceneSpan(0, 5)]);
  });

  test('sheet groups of twelve', () {
    expect(sheetGroups(30), [(1, 12), (13, 24), (25, 30)]);
    expect(sheetGroups(0), isEmpty);
  });

  test('dialogue per scene from overlapping lines', () {
    final e = [SrtEntry(1, 1000, 2000, 'a'), SrtEntry(2, 6000, 7000, 'b'), SrtEntry(3, 4900, 5100, 'c')];
    expect(dialogueFor(e, const SceneSpan(0, 5000)), 'a / c');
    expect(dialogueFor(e, const SceneSpan(5000, 8000)), 'b / c');
    expect(dialogueFor(e, const SceneSpan(9000, 10000)), '');
  });

  test('prompt lists scenes with dialogue, marks missing dialogue, asks for part markers', () {
    final p = buildSceneRecapPrompt(
      dramaTitle: 'T',
      episode: 2,
      scenes: const [SceneSpan(0, 30000), SceneSpan(30000, 60000), SceneSpan(60000, 90000)],
      dialogue: const ['hello', '', 'bye'],
      from: 2,
      to: 3,
    );
    expect(p, contains('Scene 2: 0:30 - 1:00'));
    expect(p, contains('Dialogue: (none given'));
    expect(p, contains('Dialogue: bye'));
    expect(p, isNot(contains('Scene 1:')));
    expect(p, contains('=== PART n ==='));
    expect(p, contains('contact sheet'));
  });

  group('scene plan', () {
    test('round trip', () {
      final l = [const SceneSpan(0, 4000), const SceneSpan(4000, 9500)];
      expect(parseScenePlan(encodeScenePlan(l)), l);
    });

    test('empty, broken or impossible plans give an empty list', () {
      expect(parseScenePlan(null), isEmpty);
      expect(parseScenePlan('  '), isEmpty);
      expect(parseScenePlan('not json'), isEmpty);
      expect(parseScenePlan('{"a":1}'), isEmpty);
      expect(parseScenePlan('[[0]]'), isEmpty);
      expect(parseScenePlan('[["a","b"]]'), isEmpty);
      expect(parseScenePlan('[[5000,5000]]'), isEmpty);
      expect(parseScenePlan('[[0,1000],[3000,2000]]'), isEmpty);
      expect(parseScenePlan('[[-1,1000]]'), isEmpty);
    });
  });
}
