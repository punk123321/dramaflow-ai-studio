import 'package:aistudio/core/te_preview.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TransformOp op(String id, TransformTool t, int s, int e, Map<String, Object?> p, {OpStatus st = OpStatus.approved}) =>
    TransformOp(id: id, tool: t, startMs: s, endMs: e, params: p, status: st);

void main() {
  test('opsAt: range ops are active inside their range only', () {
    final ops = [op('a', TransformTool.colorGrade, 1000, 3000, {'brightness': 0.2, 'contrast': 0.0})];
    expect(opsAt(ops, 999), isEmpty);
    expect(opsAt(ops, 1000).length, 1);
    expect(opsAt(ops, 2999).length, 1);
    expect(opsAt(ops, 3000), isEmpty);
  });

  test('opsAt: point ops show for a short window; rejected are hidden', () {
    final ops = [
      op('f', TransformTool.freezeFrame, 5000, 5000, {'hold': 3.0}),
      op('r', TransformTool.smartCut, 0, 9000, {}, st: OpStatus.rejected),
    ];
    expect(opsAt(ops, 5000).map((o) => o.id), ['f']);
    expect(opsAt(ops, 5000 + previewPointWindowMs), isEmpty);
    expect(opsAt(ops, 4999), isEmpty);
  });

  test('proposed ops are shown (so a suggestion can be previewed)', () {
    final ops = [op('p', TransformTool.cropReframe, 0, 4000, {'zoom': 2.0, 'cx': 0.5, 'cy': 0.5}, st: OpStatus.proposed)];
    expect(previewCrop(ops, 1000)?.zoom, 2.0);
  });

  test('previewCrop: fitted, latest wins, null outside', () {
    final ops = [
      op('a', TransformTool.cropReframe, 0, 5000, {'zoom': 1.5, 'cx': 0.5, 'cy': 0.5}),
      op('b', TransformTool.cropReframe, 2000, 4000, {'zoom': 2.0, 'cx': 0.0, 'cy': 0.5}),
    ];
    expect(previewCrop(ops, 1000)?.zoom, 1.5);
    final c = previewCrop(ops, 3000)!;
    expect(c.zoom, 2.0);
    expect(c.cx, 0.25); // pushed inside so no empty border shows
    expect(previewCrop(ops, 6000), isNull);
  });

  test('previewLook: neutral values give null', () {
    final ops = [op('a', TransformTool.colorGrade, 0, 5000, {'brightness': 0.0, 'contrast': 0.0})];
    expect(previewLook(ops, 1000), isNull);
  });

  test('previewMotions: label and arrow come out, bad params are skipped', () {
    final ops = [
      op('l', TransformTool.motionGraphics, 0, 4000, {'kind': 'label', 'x': 0.5, 'y': 0.2, 'size': 0.06, 'color': 0xFFFFEB3B, 'text': 'Hi'}),
      op('bad', TransformTool.motionGraphics, 0, 4000, {'kind': 'label', 'x': 2.0, 'y': 0.2, 'size': 0.06, 'color': 1, 'text': 'x'}),
    ];
    final m = previewMotions(ops, 1000);
    expect(m.length, 1);
    expect(m.first.opId, 'l');
    expect(m.first.item.text, 'Hi');
  });

  test('previewBadges: cut, freeze with seconds', () {
    final ops = [
      op('c', TransformTool.smartCut, 0, 4000, {}),
      op('f', TransformTool.freezeFrame, 1000, 1000, {'hold': 2.5}),
    ];
    final b = previewBadges(ops, 1200);
    expect(b.length, 2);
    expect(b.any((s) => s.contains('2.5s')), isTrue);
  });

  test('lookMatrix: neutral is identity, brightness adds', () {
    final m = lookMatrix(const LookAdjust(0, 0));
    expect(m[0], 1);
    expect(m[4], 0);
    final b = lookMatrix(const LookAdjust(0.2, 0));
    expect(b[4], closeTo(51, 0.001));
  });

  test('TransformOp.copyWith keeps id/tool/extra; replaceOp swaps by id', () {
    final a = op('a', TransformTool.freezeFrame, 1000, 1000, {'hold': 2.0});
    final plan = TransformativePlan(ops: [a, op('b', TransformTool.smartCut, 0, 1, {})]);
    final edited = plan.replaceOp(a.copyWith(params: {'hold': 4.0}, note: 'n'));
    expect(edited.ops.length, 2);
    expect(edited.ops.first.params['hold'], 4.0);
    expect(edited.ops.first.note, 'n');
    expect(edited.ops.first.tool, TransformTool.freezeFrame);
    expect(edited.ops.last.id, 'b');
  });

  test('assignLanes: overlapping ops get different rows, later ones reuse a free row', () {
    final ops = [
      op('a', TransformTool.smartCut, 0, 5000, {}),
      op('b', TransformTool.colorGrade, 2000, 4000, {'brightness': 0.1, 'contrast': 0.0}),
      op('c', TransformTool.smartCut, 6000, 8000, {}),
    ];
    final r = assignLanes(ops);
    expect(r.count, 2);
    expect(r.lane['a'], 0);
    expect(r.lane['b'], 1);
    expect(r.lane['c'], 0);
  });

  test('assignLanes: empty list still has one row; a point op occupies a short window', () {
    expect(assignLanes(const []).count, 1);
    final r = assignLanes([
      op('f', TransformTool.freezeFrame, 1000, 1000, {'hold': 2.0}),
      op('g', TransformTool.smartCut, 1500, 3000, {}),
    ]);
    expect(r.lane['f'], 0);
    expect(r.lane['g'], 1);
  });
}
