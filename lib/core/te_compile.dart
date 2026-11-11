import 'timeline.dart';
import 'transformative_plan.dart';

/// Turns APPROVED Transformative Editor operations into the existing edit
/// description (video pieces). Pure Dart. The stored timeline is never
/// changed: this runs when a render is prepared.
///
/// Only Smart Cut (remove a range), Crop & Reframe, Freeze Frame, Picture-in-
/// Picture (a picture, not a second video), Motion Graphics (text label, arrow) and
/// Sound Design (one sound effect at a moment) are compiled today. Every other approved operation is
/// reported as "not rendered" so nothing is silently skipped.

class CompileResult {
  const CompileResult(this.pieces, this.applied, this.notes, [this.infos = const [], this.overlays = const [], this.sounds = const []]);

  final List<VideoPiece> pieces;

  /// Operations that changed the output.
  final List<TransformOp> applied;

  /// Operations that were left out, with the reason (Burmese, for the user).
  final List<String> notes;

  /// What the render will contain that the user cannot see in the Studio
  /// timeline, such as where each held frame lands on the output time.
  final List<String> infos;

  /// Labels and arrows, already placed on the OUTPUT time.
  final List<MotionItem> overlays;

  /// Sound effects placed on the OUTPUT time. The render mixes them in with
  /// the narration lanes.
  final List<VoiceItem> sounds;
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

enum MotionKind { label, arrow, image }

/// A text label, arrow or picture (picture-in-picture, image only) shown on the finished video between [startMs] and
/// [endMs] of the OUTPUT time. [x], [y]: centre, 0 to 1 from the top-left.
/// [size] is a fraction of the video height (for a picture: of the width). [angle] is degrees, 0 = pointing
/// right, 90 = pointing down. [color] is ARGB.
class MotionItem {
  const MotionItem({
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    this.text = '',
    this.path = '',
    this.angle = 0,
    this.background = true,
  });

  final MotionKind kind;
  final int startMs;
  final int endMs;
  final double x;
  final double y;
  final double size;
  final int color;
  final String text;

  /// Picture file inside the app (kind image).
  final String path;
  final double angle;
  final bool background;

  MotionItem withTime(int s, int e) => MotionItem(
        kind: kind,
        startMs: s,
        endMs: e,
        x: x,
        y: y,
        size: size,
        color: color,
        text: text,
        path: path,
        angle: angle,
        background: background,
      );

  Map<String, Object?> toJson() => {
        'k': kind.name,
        's': startMs,
        'e': endMs,
        'x': x,
        'y': y,
        'size': size,
        'color': color,
        if (kind == MotionKind.label) 't': text,
        if (kind == MotionKind.image) 'path': path,
        if (kind == MotionKind.label) 'bg': background,
        if (kind == MotionKind.arrow) 'angle': angle,
      };
}

const maxLabelChars = 120;

/// Null when the parameters are not usable. Time is filled in later.
MotionItem? motionFromParams(Map<String, Object?> p) {
  final kind = MotionKind.values.where((k) => k.name == p['kind']).firstOrNull;
  final x = p['x'];
  final y = p['y'];
  final size = p['size'];
  final color = p['color'];
  if (kind == null || x is! num || y is! num || size is! num || color is! int) return null;
  if (x < 0 || x > 1 || y < 0 || y > 1) return null;
  if (size < 0.03 || size > (kind == MotionKind.image ? 0.6 : 0.4)) return null;
  var text = '';
  var path = '';
  if (kind == MotionKind.image) {
    final f = p['path'];
    if (f is! String || f.trim().isEmpty) return null;
    path = f;
  }
  if (kind == MotionKind.label) {
    final t = p['text'];
    if (t is! String || t.trim().isEmpty || t.length > maxLabelChars) return null;
    text = t.trim();
  }
  final a = p['angle'];
  return MotionItem(
    kind: kind,
    startMs: 0,
    endMs: 0,
    x: x.toDouble(),
    y: y.toDouble(),
    size: size.toDouble(),
    color: color,
    text: text,
    path: path,
    angle: a is num ? a.toDouble() % 360 : 0,
    background: p['bg'] != false,
  );
}

/// Where the source range [s, e) shows up on the output time. A held frame
/// inside the range is included. Touching ranges are joined.
List<(int, int)> outputRanges(List<VideoPiece> pieces, int s, int e) {
  final out = <(int, int)>[];
  var at = 0;
  for (final p in pieces) {
    int? a;
    int? b;
    if (p.freeze) {
      if (p.startMs >= s && p.startMs < e) {
        a = at;
        b = at + p.lengthMs;
      }
    } else {
      final lo = s > p.startMs ? s : p.startMs;
      final hi = e < p.endMs ? e : p.endMs;
      if (hi > lo) {
        a = at + (lo - p.startMs);
        b = at + (hi - p.startMs);
      }
    }
    if (a != null && b != null) {
      if (out.isNotEmpty && out.last.$2 == a) {
        out[out.length - 1] = (out.last.$1, b);
      } else {
        out.add((a, b));
      }
    }
    at += p.lengthMs;
  }
  return out;
}

/// A label or arrow shorter than this on the output is not worth showing.
const minMotionMs = 300;

/// Longest sound effect file accepted (10 minutes).
const maxSoundMs = 600000;

/// A sound effect from operation parameters, placed at [offsetMs]. Null when
/// the parameters are not usable.
VoiceItem? soundFromParams(Map<String, Object?> p, int offsetMs) {
  final src = p['src'];
  final dur = p['dur'];
  final vol = p['vol'];
  if (src is! String || src.isEmpty || dur is! int || dur <= 0 || dur > maxSoundMs) return null;
  if (vol is! num || vol < 0.05 || vol > 1.0) return null;
  final name = p['name'];
  return VoiceItem(
    source: src,
    label: name is String && name.isNotEmpty ? name : 'Sound effect',
    durationMs: dur,
    offsetMs: offsetMs,
    volume: vol.toDouble(),
  );
}

/// Shortest cut the compiler will make.
const minCutMs = 100;

/// Brightness and contrast from operation parameters. Null when not usable
/// or when both are 0 (nothing to do).
LookAdjust? lookFromParams(Map<String, Object?> p) {
  final b = p['brightness'];
  final c = p['contrast'];
  if (b is! num || c is! num) return null;
  if (b < -LookAdjust.limit || b > LookAdjust.limit || c < -LookAdjust.limit || c > LookAdjust.limit) return null;
  final l = LookAdjust(b.toDouble(), c.toDouble());
  return l.isNeutral ? null : l;
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
  var cutMs = 0;
  final crops = <TransformOp>[];
  final freezes = <TransformOp>[];
  final motions = <TransformOp>[];
  final cuts = <TransformOp>[];
  final sounds = <TransformOp>[];
  for (final op in approved) {
    final name = op.tool.title;
    if (!op.valid) {
      notes.add('$name — အချိန် မမှန်လို့ ချန်ထားတယ်');
    } else if (op.tool == TransformTool.cropReframe || op.tool == TransformTool.colorGrade) {
      crops.add(op);
    } else if (op.tool == TransformTool.freezeFrame) {
      freezes.add(op);
    } else if (op.tool == TransformTool.motionGraphics || op.tool == TransformTool.pictureInPicture) {
      motions.add(op);
    } else if (op.tool == TransformTool.smartCut) {
      cuts.add(op);
    } else if (op.tool == TransformTool.soundDesign) {
      sounds.add(op);
    } else {
      notes.add('$name — render မချိတ်ရသေးလို့ မပါပါ');
    }
  }

  // Cuts first. Everything else is placed on what is left.
  for (final op in cuts) {
    final name = op.tool.title;
    final next = <VideoPiece>[];
    var touched = false;
    for (final p in cur) {
      final s = op.startMs > p.startMs ? op.startMs : p.startMs;
      final e = op.endMs < p.endMs ? op.endMs : p.endMs;
      if (p.freeze || e - s < minCutMs) {
        next.add(p);
        continue;
      }
      touched = true;
      // A leftover shorter than the minimum is dropped with the cut part.
      if (s - p.startMs >= minCompiledPieceMs) next.add(p.withRange(p.startMs, s));
      if (p.endMs - e >= minCompiledPieceMs) next.add(p.withRange(e, p.endMs));
    }
    if (!touched) {
      notes.add('$name — ဗီဒီယိုအပိုင်းနဲ့ မထိတဲ့ အချိန်မို့ ချန်ထားတယ်');
    } else if (next.isEmpty) {
      notes.add('$name — ဗီဒီယိုအားလုံး ပျောက်သွားမှာမို့ ချန်ထားတယ်');
    } else {
      applied.add(op);
      // What was really removed (overlapping cuts are not counted twice).
      cutMs += cur.where((p) => !p.freeze).fold<int>(0, (a, p) => a + p.lengthMs) -
          next.where((p) => !p.freeze).fold<int>(0, (a, p) => a + p.lengthMs);
      cur = next;
    }
  }

  for (final op in crops) {
    final name = op.tool.title;
    final isLook = op.tool == TransformTool.colorGrade;
    final crop = isLook ? null : cropFromParams(op.params);
    final look = isLook ? lookFromParams(op.params) : null;
    if (isLook ? look == null : crop == null) {
      notes.add(isLook
          ? '$name — အလင်း/contrast တန်ဖိုး မမှန်ပါ (သို့) ၀ ဖြစ်နေလို့ ချန်ထားတယ်'
          : '$name — zoom/နေရာ တန်ဖိုး မမှန်လို့ ချန်ထားတယ်');
      continue;
    }
    VideoPiece mark(VideoPiece p) => isLook ? p.withLook(look) : p.withCrop(crop);
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
      next.add(mark(p.withRange(from, to)));
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
    final still = VideoPiece.freezeAt(t, hold, p.crop, p.look);
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

  // Labels and arrows last, once the final order and length are known.
  final overlays = <MotionItem>[];
  for (final op in motions) {
    final name = op.tool.title;
    final base = motionFromParams(op.params);
    if (base == null) {
      notes.add('$name — စာသား/နေရာ/အရွယ် တန်ဖိုး မမှန်လို့ ချန်ထားတယ်');
      continue;
    }
    final ranges = [for (final r in outputRanges(cur, op.startMs, op.endMs)) if (r.$2 - r.$1 >= minMotionMs) r];
    if (ranges.isEmpty) {
      notes.add('$name — ဗီဒီယိုအပိုင်းနဲ့ မထိတဲ့ အချိန်မို့ ချန်ထားတယ်');
      continue;
    }
    for (final r in ranges) {
      overlays.add(base.withTime(r.$1, r.$2));
    }
    applied.add(op);
  }

  // Sound effects, placed on the final output time.
  final soundItems = <VoiceItem>[];
  final total = cur.fold<int>(0, (a, p) => a + p.lengthMs);
  for (final op in sounds) {
    final name = op.tool.title;
    final ranges = outputRanges(cur, op.startMs, op.startMs + 1);
    if (ranges.isEmpty) {
      notes.add('$name — ဗီဒီယိုအပိုင်းထဲ မကျတဲ့ အချိန်မို့ ချန်ထားတယ်');
      continue;
    }
    final item = soundFromParams(op.params, ranges.first.$1);
    if (item == null) {
      notes.add('$name — အသံဖိုင်/အသံတိုး တန်ဖိုး မမှန်လို့ ချန်ထားတယ်');
      continue;
    }
    if (item.endMs > total) {
      notes.add('$name — အသံက ဗီဒီယိုအဆုံးကျော်နေလို့ ချန်ထားတယ် (အချိန်စောစော ထားပါ)');
      continue;
    }
    soundItems.add(item);
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
  if (cutMs > 0) {
    infos.add('Smart Cut: မူရင်းအချိန် ${_clock(cutMs)} လောက် ဖြတ်ထုတ်မယ်။ နောက်ပိုင်း အပိုင်းတွေ စောလာမယ်၊ Narration အချိန်ကို ကိုယ်တိုင် ညှိပါ');
  }
  return CompileResult(cur, applied, notes, infos, overlays, soundItems);
}

/// Files that the compiled result needs but that are not there. Only app
/// files (paths starting with "/") can be checked; a `content://` link to the
/// user's own file cannot, so it is left to the renderer.
List<String> missingFiles(CompileResult r, bool Function(String path) exists) {
  final out = <String>[];
  for (final o in r.overlays) {
    if (o.kind == MotionKind.image && o.path.startsWith('/') && !exists(o.path)) {
      out.add('Picture-in-Picture ပုံ ပျောက်နေတယ် — ပုံကို ပြန်ရွေးပါ');
    }
  }
  for (final v in r.sounds) {
    if (v.source.startsWith('/') && !exists(v.source)) {
      out.add('Sound effect "${v.label}" ဖိုင် ပျောက်နေတယ်');
    }
  }
  return out;
}
