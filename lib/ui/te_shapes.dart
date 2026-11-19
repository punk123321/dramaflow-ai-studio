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
  const ShapePainter({required this.color, required this.oval});

  final Color color;
  final bool oval;

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
  bool shouldRepaint(ShapePainter old) => old.color != color || old.oval != oval;
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
