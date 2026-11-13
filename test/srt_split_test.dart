import 'package:aistudio/core/srt.dart';
import 'package:aistudio/core/srt_split.dart';
import 'package:flutter_test/flutter_test.dart';

List<SrtEntry> _lines() => [
      for (var i = 0; i < 10; i++) SrtEntry(i + 1, i * 10000, i * 10000 + 8000, 'မြန်မာ $i'),
    ];

void main() {
  test('no breaks gives one part covering the whole video', () {
    final p = buildParts(_lines(), {}, 120000);
    expect(p.length, 1);
    expect(p.single.startMs, 0);
    expect(p.single.endMs, 120000);
    expect(p.single.lines, 10);
  });

  test('parts are continuous: each one ends exactly where the next begins, at a line start', () {
    final l = _lines();
    final p = buildParts(l, {3, 7}, 100000);
    expect(p.length, 3);
    expect(p[0].startMs, 0);
    expect(p[0].endMs, l[3].startMs);
    expect(p[1].startMs, l[3].startMs);
    expect(p[1].endMs, l[7].startMs);
    expect(p[2].startMs, l[7].startMs);
    expect(p[2].endMs, 100000);
    expect([p[0].lines, p[1].lines, p[2].lines], [3, 4, 3]);
    expect(p[1].firstLine, 3);
    expect(p[1].lastLine, 6);
  });

  test('bad breaks are ignored', () {
    expect(buildParts(_lines(), {0, 10, 99, -1}, 100000).length, 1);
    expect(buildParts(const [], {1}, 1000), isEmpty);
  });

  test('video shorter than the last line still covers it', () {
    expect(buildParts(_lines(), {}, 1000).single.endMs, 98000);
  });

  test('every N lines and every M ms', () {
    expect(breaksEveryLines(10, 4), {4, 8});
    expect(breaksEveryLines(10, 0), isEmpty);
    expect(breaksEveryLines(3, 5), isEmpty);
    final l = _lines();
    // lines start every 10 s; target 25 s -> breaks at line 3 (30 s) and 6 (60 s) and 9
    expect(breaksEveryMs(l, 25000), {3, 6, 9});
    expect(breaksEveryMs(l, 500), isEmpty);
  });

  test('part SRT counts from zero and keeps the text', () {
    final l = _lines();
    final p = buildParts(l, {3}, 100000);
    final second = parseSrt(partSrt(l, p[1])).entries;
    expect(second.first.startMs, 0);
    expect(second.first.text, 'မြန်မာ 3');
    expect(second.length, 7);
    expect(second.first.index, 1);
    final first = parseSrt(partSrt(l, p[0])).entries;
    expect(first.length, 3);
  });

  test('a line crossing the cut is shortened in the part that ends, and noted', () {
    final l = [
      const SrtEntry(1, 0, 6000, 'a'),
      const SrtEntry(2, 5000, 9000, 'b'),
    ];
    expect(overlappingBreaks(l, {1}), [1]);
    final p = buildParts(l, {1}, 20000);
    final first = parseSrt(partSrt(l, p[0])).entries;
    expect(first.single.endMs, 5000);
    final second = parseSrt(partSrt(l, p[1])).entries;
    expect(second.first.startMs, 0);
    expect(second.first.text, 'b');
  });

  test('file names are numbered with enough digits', () {
    expect(partFileName('x', 0, 5), 'x_part01');
    expect(partFileName('x', 11, 120), 'x_part012');
  });
}
