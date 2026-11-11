import 'timeline.dart';
import 'transformative_plan.dart';

/// Turns APPROVED Transformative Editor operations into the existing edit
/// description (video pieces). Pure Dart. The stored timeline is never
/// changed: this runs when a render is prepared.
///
/// Only Crop & Reframe is compiled today. Every other approved operation is
/// reported as "not rendered" so nothing is silently skipped.

class CompileResult {
  const CompileResult(this.pieces, this.applied, this.notes);

  final List<VideoPiece> pieces;

  /// Operations that changed the output.
  final List<TransformOp> applied;

  /// Operations that were left out, with the reason (Burmese, for the user).
  final List<String> notes;
}

/// Shortest piece the compiler will create. Anything shorter is folded into
/// its neighbour so the renderer never gets a tiny clip.
const minCompiledPieceMs = 200;

CropFrame? cropFromParams(Map<String, Object?> params) {
  final z = params['zoom'];
  final x = params['cx'];
  final y = params['cy'];
  if (z is! num || x is! num || y is! num) return null;
  if (z < CropFrame.minZoom || z > CropFrame.maxZoom) return null;
  if (x < 0 || x > 1 || y < 0 || y > 1) return null;
  return CropFrame(z.toDouble(), x.toDouble(), y.toDouble()).fitted;
}

/// Later operations win where two overlap.
CompileResult compileOps(List<VideoPiece> pieces, List<TransformOp> ops) {
  var cur = [...pieces];
  final applied = <TransformOp>[];
  final notes = <String>[];

  for (final op in ops) {
    if (op.status != OpStatus.approved) continue;
    final name = op.tool.title;
    if (!op.valid) {
      notes.add('$name — အချိန် မမှန်လို့ ချန်ထားတယ်');
      continue;
    }
    if (op.tool != TransformTool.cropReframe) {
      notes.add('$name — render မချိတ်ရသေးလို့ မပါပါ');
      continue;
    }
    final crop = cropFromParams(op.params);
    if (crop == null) {
      notes.add('$name — zoom/နေရာ တန်ဖိုး မမှန်လို့ ချန်ထားတယ်');
      continue;
    }
    final next = <VideoPiece>[];
    var touched = false;
    for (final p in cur) {
      final s = op.startMs > p.startMs ? op.startMs : p.startMs;
      final e = op.endMs < p.endMs ? op.endMs : p.endMs;
      if (e - s < minCompiledPieceMs) {
        next.add(p);
        continue;
      }
      touched = true;
      var from = s;
      var to = e;
      // A tiny leftover at either side joins the cropped part.
      if (from - p.startMs < minCompiledPieceMs) from = p.startMs;
      if (p.endMs - to < minCompiledPieceMs) to = p.endMs;
      if (from > p.startMs) next.add(p.withRange(p.startMs, from));
      next.add(p.withRange(from, to).withCrop(crop));
      if (to < p.endMs) next.add(p.withRange(to, p.endMs));
    }
    if (touched) {
      cur = next;
      applied.add(op);
    } else {
      notes.add('$name — ဗီဒီယိုအပိုင်းနဲ့ မထိတဲ့ အချိန်မို့ ချန်ထားတယ်');
    }
  }
  return CompileResult(cur, applied, notes);
}
