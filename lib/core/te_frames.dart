import 'dart:math' as math;

/// Ready-made frames (borders) for the whole picture. A frame is a short list
/// of drawing primitives in "short-side units" (the short side of the picture
/// is 1). The editor preview and the render both draw the same list, so the
/// two look alike. Pure Dart: no widgets.
///
/// Primitive maps (all numbers in short-side units):
/// - rect:   {t:'r', x, y, w, h, sw, c, rad?, dash?:[on, off], glow?, g?:[colours]}   (sw 0 = filled)
/// - line:   {t:'l', x1, y1, x2, y2, sw, c}
/// - circle: {t:'o', x, y, r, sw, c}                                                 (sw 0 = filled)
class FrameTemplate {
  const FrameTemplate(this.id, this.name, {this.usesColor = false, this.defaultColor = 0xFFFFFFFF, this.defaultThick = 0.02});

  final int id;
  final String name;

  /// The user's colour is used (otherwise the frame has its own colours).
  final bool usesColor;
  final int defaultColor;

  /// Thickness unit that looks good by default (share of the short side).
  final double defaultThick;
}

const frameTemplates = <FrameTemplate>[
  FrameTemplate(1, 'Classic', usesColor: true, defaultThick: 0.012),
  FrameTemplate(2, 'Double', usesColor: true, defaultThick: 0.012),
  FrameTemplate(3, 'Gold', defaultThick: 0.014),
  FrameTemplate(4, 'Neon', usesColor: true, defaultColor: 0xFF00E5FF, defaultThick: 0.012),
  FrameTemplate(5, 'Film', defaultThick: 0.014),
  FrameTemplate(6, 'Polaroid', defaultThick: 0.014),
  FrameTemplate(7, 'Viewfinder', usesColor: true, defaultThick: 0.01),
  FrameTemplate(8, 'Cinema', defaultThick: 0.012),
  FrameTemplate(9, 'Rounded', usesColor: true, defaultColor: 0xFFFF80AB, defaultThick: 0.012),
  FrameTemplate(10, 'Dotted', usesColor: true, defaultColor: 0xFFFFEB3B, defaultThick: 0.012),
  FrameTemplate(11, 'Vintage', defaultThick: 0.012),
  FrameTemplate(12, 'Rainbow glow', defaultThick: 0.012),
];

FrameTemplate? frameTemplateById(int id) {
  for (final t in frameTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

const _white = 0xFFFFFFFF;
const _black = 0xFF000000;

Map<String, Object?> _r(double x, double y, double w, double h, double sw, int c, {double rad = 0, List<double>? dash, double glow = 0, List<int>? g}) => {
      't': 'r',
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'sw': sw,
      'c': c,
      if (rad > 0) 'rad': rad,
      if (dash != null) 'dash': dash,
      if (glow > 0) 'glow': glow,
      if (g != null) 'g': g,
    };

Map<String, Object?> _l(double x1, double y1, double x2, double y2, double sw, int c) => {'t': 'l', 'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'sw': sw, 'c': c};

Map<String, Object?> _o(double x, double y, double r, double sw, int c) => {'t': 'o', 'x': x, 'y': y, 'r': r, 'sw': sw, 'c': c};

/// The primitives of frame [id] for a picture of [w] x [h] pixels (only the
/// proportions matter). [t] is the thickness unit as a share of the short
/// side; [color] is used by the frames that take a colour. Empty for an
/// unknown id.
List<Map<String, Object?>> framePrims(int id, int color, double t, double w, double h) {
  if (w <= 0 || h <= 0 || !t.isFinite) return const [];
  final tt = t.clamp(0.004, 0.06).toDouble();
  final short = math.min(w, h);
  final W = w / short;
  final H = h / short;
  switch (id) {
    case 1:
      return [_r(2 * tt, 2 * tt, W - 4 * tt, H - 4 * tt, tt, color)];
    case 2:
      return [
        _r(1.5 * tt, 1.5 * tt, W - 3 * tt, H - 3 * tt, 0.9 * tt, color),
        _r(4 * tt, 4 * tt, W - 8 * tt, H - 8 * tt, 0.45 * tt, color),
      ];
    case 3:
      const gold = [0xFFFFE082, 0xFFFFB300, 0xFFFFF3B0, 0xFFC68400];
      return [
        _r(1.5 * tt, 1.5 * tt, W - 3 * tt, H - 3 * tt, 1.4 * tt, 0, g: gold),
        _r(4.2 * tt, 4.2 * tt, W - 8.4 * tt, H - 8.4 * tt, 0.5 * tt, 0, g: gold),
        for (final p in [(4.2 * tt, 4.2 * tt), (W - 4.2 * tt, 4.2 * tt), (4.2 * tt, H - 4.2 * tt), (W - 4.2 * tt, H - 4.2 * tt)]) _o(p.$1, p.$2, 1.3 * tt, 0, 0xFFFFC107),
      ];
    case 4:
      return [
        _r(2 * tt, 2 * tt, W - 4 * tt, H - 4 * tt, 0.9 * tt, color, rad: tt, glow: 3 * tt),
        _r(2 * tt, 2 * tt, W - 4 * tt, H - 4 * tt, 0.3 * tt, _white, rad: tt),
      ];
    case 5:
      final s = 4 * tt;
      final n = math.min(60, (H / (2.4 * tt)).floor());
      final step = n > 0 ? H / n : 1.0;
      return [
        _r(0, 0, s, H, 0, _black),
        _r(W - s, 0, s, H, 0, _black),
        for (var i = 0; i < n; i++) ...[
          _r(s / 2 - 0.7 * tt, i * step + step / 2 - 0.5 * tt, 1.4 * tt, tt, 0, 0xFFEEEEEE, rad: 0.25 * tt),
          _r(W - s / 2 - 0.7 * tt, i * step + step / 2 - 0.5 * tt, 1.4 * tt, tt, 0, 0xFFEEEEEE, rad: 0.25 * tt),
        ],
      ];
    case 6:
      final side = 3.5 * tt;
      final bottom = 12 * tt;
      const paper = 0xFFFAFAFA;
      return [
        _r(0, 0, W, side, 0, paper),
        _r(0, 0, side, H, 0, paper),
        _r(W - side, 0, side, H, 0, paper),
        _r(0, H - bottom, W, bottom, 0, paper),
        _r(side, side, W - 2 * side, H - side - bottom, 0.25 * tt, 0x55000000),
      ];
    case 7:
      final len = 8 * tt;
      final i = 3 * tt;
      final sw = 0.8 * tt;
      return [
        _l(i, i, i + len, i, sw, color),
        _l(i, i, i, i + len, sw, color),
        _l(W - i, i, W - i - len, i, sw, color),
        _l(W - i, i, W - i, i + len, sw, color),
        _l(i, H - i, i + len, H - i, sw, color),
        _l(i, H - i, i, H - i - len, sw, color),
        _l(W - i, H - i, W - i - len, H - i, sw, color),
        _l(W - i, H - i, W - i, H - i - len, sw, color),
        _l(W / 2 - 2 * tt, H / 2, W / 2 + 2 * tt, H / 2, 0.4 * tt, color),
        _l(W / 2, H / 2 - 2 * tt, W / 2, H / 2 + 2 * tt, 0.4 * tt, color),
      ];
    case 8:
      final bar = 9 * tt;
      return [
        _r(0, 0, W, bar, 0, _black),
        _r(0, H - bar, W, bar, 0, _black),
        _l(0, bar, W, bar, 0.3 * tt, 0xFFFFC107),
        _l(0, H - bar, W, H - bar, 0.3 * tt, 0xFFFFC107),
      ];
    case 9:
      return [
        _r(1.2 * tt, 1.2 * tt, W - 2.4 * tt, H - 2.4 * tt, 2.2 * tt, color, rad: 5 * tt),
        _r(4.5 * tt, 4.5 * tt, W - 9 * tt, H - 9 * tt, 0.4 * tt, _white, rad: 3.5 * tt),
      ];
    case 10:
      return [_r(2.5 * tt, 2.5 * tt, W - 5 * tt, H - 5 * tt, tt, color, dash: [0.1 * tt, 2.4 * tt])];
    case 11:
      const cream = 0xFFF3E5C8;
      const brown = 0xFF8D6E63;
      final b = 3.2 * tt;
      return [
        _r(0, 0, W, b, 0, cream),
        _r(0, H - b, W, b, 0, cream),
        _r(0, b, b, H - 2 * b, 0, cream),
        _r(W - b, b, b, H - 2 * b, 0, cream),
        _r(b, b, W - 2 * b, H - 2 * b, 0.5 * tt, brown),
        _r(tt, tt, W - 2 * tt, H - 2 * tt, 0.3 * tt, brown),
      ];
    case 12:
      const rainbow = [0xFFFF5252, 0xFFFFEB3B, 0xFF69F0AE, 0xFF40C4FF, 0xFFB388FF, 0xFFFF80AB];
      return [_r(2 * tt, 2 * tt, W - 4 * tt, H - 4 * tt, 1.6 * tt, 0, rad: 4 * tt, glow: 2.5 * tt, g: rainbow)];
    default:
      return const [];
  }
}
