import 'te_compile.dart';
import 'timeline.dart';
import 'transformative_plan.dart';

/// What the phone preview can show for the TE operations at one moment of the
/// ORIGINAL video. Pure Dart. The preview is an approximation: the real result
/// is made by the render. Rejected operations are never shown; proposed ones
/// are, so the user can see a suggestion before approving it.

/// A point operation (freeze, sound) has no length of its own, so it is shown
/// for this long after its start.
const previewPointWindowMs = 1500;

bool _isPoint(TransformTool t) => t == TransformTool.freezeFrame || t == TransformTool.soundDesign;

/// Operations that should be visible at [posMs].
List<TransformOp> opsAt(List<TransformOp> ops, int posMs) {
  return [
    for (final o in ops)
      if (o.status != OpStatus.rejected && o.valid)
        if (_isPoint(o.tool) ? (posMs >= o.startMs && posMs < o.startMs + previewPointWindowMs) : (posMs >= o.startMs && posMs < o.endMs)) o,
  ];
}

/// The crop that applies at [posMs] (the latest matching operation wins).
CropFrame? previewCrop(List<TransformOp> ops, int posMs) {
  CropFrame? out;
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.cropReframe) continue;
    final c = cropFromParams(o.params);
    if (c != null) out = c;
  }
  return out;
}

/// The brightness/contrast that applies at [posMs].
LookAdjust? previewLook(List<TransformOp> ops, int posMs) {
  LookAdjust? out;
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.colorGrade) continue;
    final l = lookFromParams(o.params);
    if (l != null) out = l;
  }
  return out;
}

/// The blur strength that applies at [posMs] (the latest operation wins).
double? previewBlur(List<TransformOp> ops, int posMs) {
  double? out;
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.blur) continue;
    final b = blurFromParams(o.params);
    if (b != null) out = b;
  }
  return out;
}

/// The flip that applies at [posMs] (the latest operation wins).
({bool h, bool v})? previewFlip(List<TransformOp> ops, int posMs) {
  ({bool h, bool v})? out;
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.mirrorFlip) continue;
    final f = flipFromParams(o.params);
    if (f != null) out = f;
  }
  return out;
}

/// A label, arrow or picture to draw, with the operation it came from (the
/// preview uses the id to let the user drag it).
class PreviewMotion {
  const PreviewMotion(this.opId, this.item, {required this.proposed, required this.startMs, required this.endMs});

  final String opId;
  final MotionItem item;
  final bool proposed;

  /// Range of the operation on the original video (the item itself has none).
  final int startMs;
  final int endMs;
}

/// How strong a fade is (0 = picture clear, 1 = fully the fade colour) at
/// [posMs] for an effect that runs [startMs]..[endMs]. 'in' goes 1 to 0, 'out'
/// 0 to 1, 'dip' 0 to 1 and back to 0.
double fadeAlpha(String dir, int startMs, int endMs, int posMs) {
  final span = endMs - startMs;
  if (span <= 0) return 0;
  final t = ((posMs - startMs) / span).clamp(0.0, 1.0).toDouble();
  switch (dir) {
    case 'in':
      return 1 - t;
    case 'out':
      return t;
    default:
      return 1 - (2 * t - 1).abs();
  }
}

List<PreviewMotion> previewMotions(List<TransformOp> ops, int posMs) {
  final out = <PreviewMotion>[];
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.motionGraphics && o.tool != TransformTool.pictureInPicture) continue;
    final m = motionFromParams(o.params);
    if (m != null) out.add(PreviewMotion(o.id, m, proposed: o.status == OpStatus.proposed, startMs: o.startMs, endMs: o.endMs));
  }
  return out;
}

/// Playback speed to show at [posMs] (1 when no Speed operation is active). The
/// latest matching operation wins.
double previewSpeed(List<TransformOp> ops, int posMs) {
  var out = 1.0;
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.speedChange) continue;
    final s = speedFromParams(o.params);
    if (s != null) out = s;
  }
  return out;
}

/// Short badges for things that cannot be drawn on one frame (cut, freeze,
/// split, sound).
List<String> previewBadges(List<TransformOp> ops, int posMs) {
  final out = <String>[];
  for (final o in opsAt(ops, posMs)) {
    switch (o.tool) {
      case TransformTool.smartCut:
        out.add('✂ ဖြတ်ထုတ်မယ့် အပိုင်း');
      case TransformTool.freezeFrame:
        final ms = freezeHoldMs(o.params);
        out.add(ms == null ? '⏸ ရပ်မယ်' : '⏸ ရပ်မယ် ${(ms / 1000).toStringAsFixed(1)}s');
      case TransformTool.splitScreen:
        out.add('◫ Split screen (အတိအကျ Render မှာ ကြည့်ပါ)');
      case TransformTool.speedChange:
        final sp = speedFromParams(o.params);
        if (sp != null) out.add(sp > 1 ? '⏩ ×${_fmt(sp)}' : '🐢 ×${_fmt(sp)}');
      case TransformTool.soundDesign:
        final n = o.params['name'];
        out.add('♪ ${n is String && n.isNotEmpty ? n : 'Sound effect'}');
      default:
        break;
    }
  }
  return out;
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// 4x5 colour matrix (Flutter ColorFilter.matrix order) for brightness and
/// contrast. Contrast scales around mid-grey; brightness adds.
List<double> lookMatrix(LookAdjust l) {
  final m = 1 + l.contrast;
  final o = 255 * (0.5 * (1 - m) + l.brightness);
  return [
    m, 0, 0, 0, o, //
    0, m, 0, 0, o, //
    0, 0, m, 0, o, //
    0, 0, 0, 1, 0, //
  ];
}

/// Rows for the timeline view: operations that overlap in time are put in
/// different rows, like tracks in a video editor. Returns the row of each
/// operation id and the number of rows (at least 1).
({Map<String, int> lane, int count}) assignLanes(List<TransformOp> ops) {
  final sorted = [...ops]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final ends = <int>[];
  final lane = <String, int>{};
  for (final o in sorted) {
    final end = _isPoint(o.tool) ? o.startMs + previewPointWindowMs : (o.endMs > o.startMs + 400 ? o.endMs : o.startMs + 400);
    var i = ends.indexWhere((e) => e <= o.startMs);
    if (i < 0) {
      ends.add(end);
      i = ends.length - 1;
    } else {
      ends[i] = end;
    }
    lane[o.id] = i;
  }
  return (lane: lane, count: ends.isEmpty ? 1 : ends.length);
}
