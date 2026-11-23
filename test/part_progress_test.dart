import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/part_progress.dart';

void main() {
  test('a part is known by its time range and settings, not its number', () {
    expect(partKey(0, 600000), '0-600000');
    expect(partKey(0, 600000, tag: 's'), '0-600000|s');
    expect(partKey(0, 600000, tag: 's') == partKey(0, 600000, tag: 'm'), isFalse);
  });

  test('only the parts that are not finished are left', () {
    expect(pendingParts(5, {0, 1}), [2, 3, 4]);
    expect(pendingParts(3, {}), [0, 1, 2]);
    expect(pendingParts(3, {0, 1, 2}), isEmpty);
    expect(pendingParts(0, {}), isEmpty);
  });

  test('saved progress survives a round trip and bad data is ignored', () {
    final keys = {'0-10|s', '10-20|s'};
    expect(decodeDone(encodeDone(keys)), keys);
    expect(decodeDone(null), isEmpty);
    expect(decodeDone(''), isEmpty);
    expect(decodeDone('not json'), isEmpty);
    expect(decodeDone('{"a":1}'), isEmpty);
    expect(decodeDone('["a", 3, "b"]'), {'a', 'b'});
  });
}
