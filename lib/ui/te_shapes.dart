import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Preview drawings for the shape effects (box, circle, spot, frame) and the
/// colourful label background. They mimic what the render draws; the render
/// is the real thing.

const labelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFA44CFF), Color(0xFFFF3D9A)],
);

const rainbowColors = [
  Color(0xFF2979FF),
  Color(0xFF00E5FF),
  Color(0xFF76FF03),
  Color(0xFFFFEA00),
  Color(0xFFFF1744),
  Color(0xFFD500F9),
];

/// Outline of a rounded rectangle or an oval.
class ShapePainter extends CustomPainter {
  const ShapePainter({required this.color, required this.oval, this.fill = false});

  final Color color;
  final bool oval;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.shortestSide * 0.06).clamp(2.0, 8.0).toDouble();
    final r = Rect.fromLTRB(stroke, stroke, size.width - stroke, size.height - stroke);
    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.6
      ..color = const Color(0x96000000);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;
    if (fill) {
      final f = Paint()..color = color.withValues(alpha: 0.3);
      if (oval) {
        canvas.drawOval(r, f);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(stroke)), f);
      }
    }
    if (oval) {
      canvas.drawOval(r, dark);
      canvas.drawOval(r, line);
    } else {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(stroke));
      canvas.drawRRect(rr, dark);
      canvas.drawRRect(rr, line);
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) => old.color != color || old.oval != oval || old.fill != fill;
}

/// A border around the whole picture. [thick] is in logical pixels.
class FramePainter extends CustomPainter {
  const FramePainter({required this.color, required this.thick, required this.rainbow});

  final Color color;
  final double thick;
  final bool rainbow;

  @override
  void paint(Canvas canvas, Size size) {
    final t = thick < 1.5 ? 1.5 : thick;
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t;
    if (rainbow) {
      p.shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: rainbowColors).createShader(rect);
    } else {
      p.color = color;
    }
    canvas.drawRect(Rect.fromLTRB(t / 2, t / 2, size.width - t / 2, size.height - t / 2), p);
  }

  @override
  bool shouldRepaint(FramePainter old) => old.color != color || old.thick != thick || old.rainbow != rainbow;
}

/// Everything dimmed except one window (centre [cx], [cy], size [hw] x [hh]).
class SpotPainter extends CustomPainter {
  const SpotPainter({required this.cx, required this.cy, required this.hw, required this.hh, required this.oval});

  final double cx;
  final double cy;
  final double hw;
  final double hh;
  final bool oval;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x96000000));
    final r = Rect.fromCenter(center: Offset(cx, cy), width: hw, height: hh);
    final clear = Paint()..blendMode = BlendMode.clear;
    if (oval) {
      canvas.drawOval(r, clear);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(hw * 0.08)), clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpotPainter old) => old.cx != cx || old.cy != cy || old.hw != hw || old.hh != hh || old.oval != oval;
}

/// Dark edges, clear in the middle. [strength] 0..1.
class VignettePainter extends CustomPainter {
  const VignettePainter(this.strength);

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = RadialGradient(
      radius: 0.9,
      colors: [const Color(0x00000000), const Color(0x00000000), Colors.black.withValues(alpha: (strength * 0.9).clamp(0.0, 1.0).toDouble())],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(VignettePainter old) => old.strength != strength;
}

/// Black bars at the top and the bottom, each [frac] of the height.
class BarsPainter extends CustomPainter {
  const BarsPainter(this.frac);

  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height * frac;
    final p = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), p);
    canvas.drawRect(Rect.fromLTWH(0, size.height - h, size.width, h), p);
  }

  @override
  bool shouldRepaint(BarsPainter old) => old.frac != frac;
}

/// A dark gradient from the top or bottom edge, [frac] of the height.
class ShadePainter extends CustomPainter {
  const ShadePainter({required this.frac, required this.top});

  final double frac;
  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height * frac;
    final rect = top ? Rect.fromLTWH(0, 0, size.width, h) : Rect.fromLTWH(0, size.height - h, size.width, h);
    final dark = Colors.black.withValues(alpha: 0.75);
    final shader = LinearGradient(
      begin: top ? Alignment.topCenter : Alignment.bottomCenter,
      end: top ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [dark, const Color(0x00000000)],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(ShadePainter old) => old.frac != frac || old.top != top;
}

/// Draws a frame template (see core/te_frames.dart): the same list of
/// primitives the render draws, scaled by the short side of [size].
class PrimPainter extends CustomPainter {
  const PrimPainter(this.prims);

  final List<Map<String, Object?>> prims;

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    for (final m in prims) {
      final sw = _n(m['sw']) * s;
      final c = Color((m['c'] as num?)?.toInt() ?? 0xFFFFFFFF);
      final paint = Paint()..isAntiAlias = true;
      if (sw <= 0) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw;
      }
      paint.color = c;
      switch (m['t']) {
        case 'l':
          canvas.drawLine(Offset(_n(m['x1']) * s, _n(m['y1']) * s), Offset(_n(m['x2']) * s, _n(m['y2']) * s), paint);
        case 'o':
          canvas.drawCircle(Offset(_n(m['x']) * s, _n(m['y']) * s), _n(m['r']) * s, paint);
        case 'r':
          final rect = Rect.fromLTWH(_n(m['x']) * s, _n(m['y']) * s, _n(m['w']) * s, _n(m['h']) * s);
          final g = m['g'];
          if (g is List && g.length >= 2) {
            paint.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [for (final x in g) Color((x as num).toInt())]).createShader(rect);
          }
          final rad = _n(m['rad']) * s;
          final rr = RRect.fromRectAndRadius(rect, Radius.circular(rad));
          final glow = _n(m['glow']) * s;
          if (glow > 0) {
            final gp = Paint()
              ..style = paint.style
              ..strokeWidth = paint.strokeWidth
              ..color = paint.color
              ..shader = paint.shader
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow * 0.5);
            canvas.drawRRect(rr, gp);
          }
          final dash = m['dash'];
          if (dash is List && dash.length == 2 && sw > 0) {
            paint.strokeCap = StrokeCap.round;
            _dashed(canvas, Path()..addRRect(rr), paint, _n(dash[0]) * s, _n(dash[1]) * s);
          } else {
            canvas.drawRRect(rr, paint);
          }
      }
    }
  }

  static void _dashed(Canvas canvas, Path path, Paint paint, double on, double off) {
    final step = on + off;
    if (step <= 0) return;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + math.max(on, 0.01), metric.length)), paint);
        d += step;
      }
    }
  }

  @override
  bool shouldRepaint(PrimPainter old) => old.prims != prims;
}
