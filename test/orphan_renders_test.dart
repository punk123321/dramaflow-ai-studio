import 'package:aistudio/core/orphan_renders.dart';
import 'package:flutter_test/flutter_test.dart';

RenderFile f(String name, {bool partial = false, int mod = 0, String? path}) =>
    RenderFile(path: path ?? '/r/$name.mp4', name: name, sizeBytes: 100, modifiedMs: mod, partial: partial);

void main() {
  test('a finished file that is not in the history is found, newest first', () {
    final r = orphanRenders([f('Show_1', mod: 1), f('Show_2', mod: 5), f('Show_3', mod: 3)], {'/r/Show_3.mp4'}, prefix: 'Show_');
    expect(r.map((e) => e.name), ['Show_2', 'Show_1']);
  });

  test('unfinished files, test pictures and other projects are left out', () {
    final r = orphanRenders([
      f('Show_1', partial: true),
      f('Show_sample_9'),
      f('Other_1'),
      f('Show_4'),
    ], {}, prefix: 'Show_');
    expect(r.map((e) => e.name), ['Show_4']);
  });

  test('an empty prefix matches every project', () {
    expect(orphanRenders([f('A_1'), f('B_1')], {}, prefix: '').length, 2);
  });

  test('unfinished files are listed on their own', () {
    final u = unfinishedRenders([f('Show_1', partial: true), f('Show_2'), f('Other_1', partial: true)], prefix: 'Show_');
    expect(u.map((e) => e.name), ['Show_1']);
  });

  group('pending render', () {
    test('encode and decode keep every field, even a name with a bar in it', () {
      const p = PendingRender(projectId: 7, name: 'a|b_c', height: 1080, durationMs: 7200000);
      final d = PendingRender.decode(p.encode())!;
      expect(d.projectId, 7);
      expect(d.name, 'a|b_c');
      expect(d.height, 1080);
      expect(d.durationMs, 7200000);
    });

    test('empty or damaged text gives null', () {
      expect(PendingRender.decode(null), isNull);
      expect(PendingRender.decode(''), isNull);
      expect(PendingRender.decode('x|1|2|n'), isNull);
      expect(PendingRender.decode('1|2|3'), isNull);
    });

    test('jobDurationMs follows speed and still frames', () {
      expect(
        jobDurationMs({
          'pieces': [
            {'s': 0, 'e': 10000},
            {'s': 0, 'e': 10000, 'sp': 2.0},
            {'s': 5000, 'e': 8000, 'f': 1},
          ]
        }),
        10000 + 5000 + 3000,
      );
      expect(jobDurationMs({}), 0);
    });

    test('findFinished ignores unfinished files; hasUnfinished sees them', () {
      final files = [f('Show_1', partial: true), f('Show_2')];
      expect(findFinished(files, 'Show_1'), isNull);
      expect(findFinished(files, 'Show_2'), isNotNull);
      expect(hasUnfinished(files, 'Show_1'), isTrue);
      expect(hasUnfinished(files, 'Show_2'), isFalse);
    });
  });
}
