import 'package:aistudio/core/te_compile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('box / circle / spot accept wide sizes and an aspect', () {
    final b = motionFromParams({'kind': 'box', 'x': 0.5, 'y': 0.5, 'size': 0.8, 'ar': 0.4, 'color': 0xFFFF0000});
    expect(b, isNotNull);
    expect(b!.kind, MotionKind.box);
    expect(b.aspect, 0.4);
    expect(motionFromParams({'kind': 'label', 'x': 0.5, 'y': 0.5, 'size': 0.8, 'color': 1, 'text': 'x'}), isNull);
    final c = motionFromParams({'kind': 'circle', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'color': 1});
    expect(c!.aspect, 1.0); // a circle defaults to round
  });

  test('aspect outside 0.1..4 is refused', () {
    expect(motionFromParams({'kind': 'box', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'ar': 9.0, 'color': 1}), isNull);
    expect(motionFromParams({'kind': 'box', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'ar': 'a', 'color': 1}), isNull);
  });

  test('frame allows a thin border only', () {
    expect(motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.012, 'color': 1, 'grad': true}), isNotNull);
    expect(motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'color': 1}), isNull);
    expect(motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.001, 'color': 1}), isNull);
  });

  test('toJson carries only what each kind needs', () {
    final spot = motionFromParams({'kind': 'spot', 'x': 0.4, 'y': 0.6, 'size': 0.4, 'ar': 0.6, 'round': false, 'color': 1})!.withTime(1000, 3000).toJson();
    expect(spot['k'], 'spot');
    expect(spot['ar'], 0.6);
    expect(spot['round'], false);
    expect(spot.containsKey('t'), isFalse);
    final frame = motionFromParams({'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.012, 'color': 1, 'grad': true})!.withTime(0, 5000).toJson();
    expect(frame['grad'], true);
    expect(frame.containsKey('ar'), isFalse);
    final label = motionFromParams({'kind': 'label', 'x': 0.5, 'y': 0.5, 'size': 0.06, 'color': 1, 'text': 'hi', 'grad': true})!.withTime(0, 1000).toJson();
    expect(label['grad'], true);
    expect(label['t'], 'hi');
  });

  test('old label/arrow parameters still work', () {
    final l = motionFromParams({'kind': 'label', 'x': 0.5, 'y': 0.2, 'size': 0.06, 'color': 0xFFFFEB3B, 'text': 'a'})!;
    expect(l.gradient, isFalse);
    expect(l.background, isTrue);
    final a = motionFromParams({'kind': 'arrow', 'x': 0.5, 'y': 0.5, 'size': 0.08, 'color': 1, 'angle': 90})!;
    expect(a.toJson().containsKey('grad'), isFalse);
  });
}
