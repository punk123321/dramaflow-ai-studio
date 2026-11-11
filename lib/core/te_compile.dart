import 'timeline.dart';
import 'transformative_plan.dart';

/// Turns APPROVED Transformative Editor operations into the existing edit
/// description (video pieces). Pure Dart. The stored timeline is never
/// changed: this runs when a render is prepared.
///
/// Only Crop & Reframe and Freeze Frame are compiled today. Every other approved operation is
/// reported as "not rendered" so nothing is silently skipped.

class CompileResult {
  const CompileResult(this.pieces, this.applied, this.notes, [this.infos = const []]);

  final List<VideoPiece> pieces;

  /// Operations that changed the output.
  final List<TransformOp> applied;

  /// Operations that were left out, with the reason (Burmese, for the user).
  final List<String> notes;

  /// What the render will contain that the user cannot see in the Studio
  /// timeline, such as where each held frame lands on the output time.
  final List<String> infos;
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

const minFreezeMs = 500;
const maxFreezeMs = 30000;

/// Hold time in ms from the operation parameters, or null when not valid.
int? freezeHoldMs(Map<String, Object?> params) {
  final h = params['hold'];
  if (h is! num) return null;
  final ms = (h * 1000).round();
  return ms < minFreezeMs || ms > maxFreezeMs ? null : ms;
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Crop operations first, then freeze frames, so a freeze never gets cut up by
/// a crop. Within each group, later operations win where two overlap.
CompileResult compileOps(List<VideoPiece> pieces, List<TransformOp> ops) {
  var cur = [...pieces];
  final applied = <TransformOp>[];
  final notes = <String>[];

  final approved = [for (final o in ops) if (o.status == OpStatus.approved) o];
  final crops = <TransformOp>[];
  final freezes = <TransformOp>[];
  for (final op in approved) {
    final name = op.tool.title;
    if (!op.valid) {
      notes.add('$name — အချိန် မမှန်လို့ ချန်ထားတယ်');
    } else if (op.tool == TransformTool.cropReframe) {
      crops.add(op);
    } else if (op.tool == TransformTool.freezeFrame) {
      freezes.add(op);
    } else {
      notes.add('$name — render မချိတ်ရသေးလို့ မပါပါ');
    }
  }

  for (final op in crops) {
    final name = op.tool.title;
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
      if (p.freeze || e - s < minCompiledPieceMs) {
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

  for (final op in freezes) {
    final name = op.tool.title;
    final hold = freezeHoldMs(op.params);
    if (hold == null) {
      notes.add('$name — ကြာချိန် မမှန်ပါ (၀.၅ မှ ၃၀ စက္ကန့်) လို့ ချန်ထားတယ်');
      continue;
    }
    final t = op.startMs;
    final i = cur.indexWhere((p) => !p.freeze && t >= p.startMs && t < p.endMs);
    if (i < 0) {
      notes.add('$name — ဗီဒီယိုအပိုင်းထဲ မကျတဲ့ အချိန်မို့ ချန်ထားတယ်');
      continue;
    }
    final p = cur[i];
    final still = VideoPiece.freezeAt(t, hold, p.crop);
    final next = [...cur];
    if (t - p.startMs < minCompiledPieceMs) {
      next.insert(i, still);
    } else if (p.endMs - t < minCompiledPieceMs) {
      next.insert(i + 1, still);
    } else {
      next
        ..[i] = p.withRange(p.startMs, t)
        ..insert(i + 1, still)
        ..insert(i + 2, p.withRange(t, p.endMs));
    }
    cur = next;
    applied.add(op);
  }

  final infos = <String>[];
  var at = 0;
  for (final p in cur) {
    if (p.freeze) {
      infos.add('Freeze Frame: မူရင်း ${_clock(p.startMs)} → edit ${_clock(at)} မှာ ${(p.lengthMs / 1000).toStringAsFixed(1)} စက္ကန့် ရပ်မယ်');
    }
    at += p.lengthMs;
  }
  if (infos.isNotEmpty) {
    infos.add('ရပ်တဲ့ အချိန်ကြောင့် နောက်ပိုင်း အပိုင်းတွေ နောက်ကျသွားမယ်။ Narration အချိန်ကို ကိုယ်တိုင် ညှိပါ');
  }
  return CompileResult(cur, applied, notes, infos);
}
