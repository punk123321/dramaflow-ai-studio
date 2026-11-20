import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_preview.dart';
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

  test('whole-picture kinds: strength limits and their own parameters', () {
    expect(motionFromParams({'kind': 'vignette', 'x': 0.5, 'y': 0.5, 'size': 0.6, 'color': 1}), isNotNull);
    expect(motionFromParams({'kind': 'tint', 'x': 0.5, 'y': 0.5, 'size': 0.99, 'color': 1}), isNull);
    expect(motionFromParams({'kind': 'bars', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 1}), isNull);
    final bars = motionFromParams({'kind': 'bars', 'x': 0.5, 'y': 0.5, 'size': 0.1, 'color': 1})!.withTime(0, 1000).toJson();
    expect(bars.containsKey('dir'), isFalse);
    final fade = motionFromParams({'kind': 'fade', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 0xFF000000, 'dir': 'in'})!.withTime(0, 1000).toJson();
    expect(fade['dir'], 'in');
    final badDir = motionFromParams({'kind': 'fade', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 1, 'dir': 'sideways'})!;
    expect(badDir.dir, 'dip');
    final shade = motionFromParams({'kind': 'shade', 'x': 0.5, 'y': 0.5, 'size': 0.4, 'color': 1, 'top': true})!.withTime(0, 1000).toJson();
    expect(shade['top'], true);
    final box = motionFromParams({'kind': 'box', 'x': 0.5, 'y': 0.5, 'size': 0.4, 'color': 1, 'fill': true})!.withTime(0, 1000).toJson();
    expect(box['fill'], true);
  });

  test('fadeAlpha: in, out and dip', () {
    expect(fadeAlpha('in', 0, 1000, 0), 1);
    expect(fadeAlpha('in', 0, 1000, 1000), 0);
    expect(fadeAlpha('out', 0, 1000, 0), 0);
    expect(fadeAlpha('out', 0, 1000, 500), closeTo(0.5, 1e-9));
    expect(fadeAlpha('dip', 0, 1000, 500), closeTo(1, 1e-9));
    expect(fadeAlpha('dip', 0, 1000, 0), closeTo(0, 1e-9));
    expect(fadeAlpha('dip', 0, 1000, 1000), closeTo(0, 1e-9));
    expect(fadeAlpha('in', 500, 500, 500), 0);
  });
}
