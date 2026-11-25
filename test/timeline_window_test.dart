import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/timeline_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final subs = [for (var i = 0; i < 100; i++) SrtEntry(i + 1, i * 1000, i * 1000 + 800, 's$i')];

  test('keeps only subtitles that touch the window', () {
    final r = subsInWindow(subs, 10000, 12500);
    expect(r.map((e) => e.index), [11, 12, 13]);
  });

  test('a subtitle that starts before the window but ends inside it is kept', () {
    final r = subsInWindow([const SrtEntry(1, 0, 5000, 'long')], 4000, 6000);
    expect(r.length, 1);
  });

  test('window edges are inclusive and an empty window gives nothing outside', () {
    expect(subsInWindow(subs, 800, 1000).map((e) => e.index), [1, 2]);
    expect(subsInWindow(subs, 200000, 300000), isEmpty);
  });

  test('thousands of subtitles reduce to a screenful', () {
    final big = [for (var i = 0; i < 5000; i++) SrtEntry(i + 1, i * 2000, i * 2000 + 1500, 'x')];
    expect(subsInWindow(big, 100000, 160000).length, lessThan(40));
  });

  test('does not change the input', () {
    final copy = List.of(subs);
    subsInWindow(subs, 0, 5000);
    expect(subs, copy);
  });
}
