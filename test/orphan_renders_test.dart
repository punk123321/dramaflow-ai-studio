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
}
