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

/// A label, arrow or picture to draw, with the operation it came from (the
/// preview uses the id to let the user drag it).
class PreviewMotion {
  const PreviewMotion(this.opId, this.item, {required this.proposed});

  final String opId;
  final MotionItem item;
  final bool proposed;
}

List<PreviewMotion> previewMotions(List<TransformOp> ops, int posMs) {
  final out = <PreviewMotion>[];
  for (final o in opsAt(ops, posMs)) {
    if (o.tool != TransformTool.motionGraphics && o.tool != TransformTool.pictureInPicture) continue;
    final m = motionFromParams(o.params);
    if (m != null) out.add(PreviewMotion(o.id, m, proposed: o.status == OpStatus.proposed));
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
      case TransformTool.soundDesign:
        final n = o.params['name'];
        out.add('♪ ${n is String && n.isNotEmpty ? n : 'Sound effect'}');
      default:
        break;
    }
  }
  return out;
}

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
