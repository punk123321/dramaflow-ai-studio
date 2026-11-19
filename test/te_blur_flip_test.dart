import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_preview.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

TransformOp blurOp(int s, int e, double v, {OpStatus st = OpStatus.approved}) =>
    TransformOp(id: 'b$s-$e', tool: TransformTool.blur, startMs: s, endMs: e, params: {'strength': v}, status: st);

TransformOp flipOp(int s, int e, {bool h = true, bool v = false, OpStatus st = OpStatus.approved}) => TransformOp(
    id: 'f$s-$e', tool: TransformTool.mirrorFlip, startMs: s, endMs: e, params: {'horizontal': h, 'vertical': v}, status: st);

void main() {
  test('parameter checks', () {
    expect(blurFromParams({'strength': 10}), 10.0);
    expect(blurFromParams({'strength': 0.1}), isNull);
    expect(blurFromParams({'strength': 80}), isNull);
    expect(blurFromParams({'strength': double.nan}), isNull);
    expect(blurFromParams({}), isNull);
    expect(flipFromParams({'horizontal': true})!.h, isTrue);
    expect(flipFromParams({'vertical': true})!.v, isTrue);
    expect(flipFromParams({'horizontal': false, 'vertical': false}), isNull);
    expect(flipFromParams({}), isNull);
  });

  test('compile: blur and flip apply only to their range and keep the other values', () {
    final r = compileOps(const [VideoPiece(0, 20000)], [blurOp(5000, 10000, 12), flipOp(5000, 10000, v: true)]);
    expect(r.pieces.length, 3);
    expect(r.pieces[0].blur, isNull);
    expect(r.pieces[1].blur, 12.0);
    expect(r.pieces[1].flipH, isTrue);
    expect(r.pieces[1].flipV, isTrue);
    expect(r.pieces[2].blur, isNull);
    expect(r.pieces[2].flipH, isFalse);
    expect(r.pieces.fold<int>(0, (a, p) => a + p.lengthMs), 20000);
  });

  test('compile: blur keeps a crop and a speed on the same piece', () {
    final crop = TransformOp(id: 'c', tool: TransformTool.cropReframe, startMs: 0, endMs: 20000, params: {'zoom': 1.5, 'cx': 0.5, 'cy': 0.5}, status: OpStatus.approved);
    final speed = TransformOp(id: 's', tool: TransformTool.speedChange, startMs: 5000, endMs: 10000, params: {'speed': 2.0}, status: OpStatus.approved);
    final r = compileOps(const [VideoPiece(0, 20000)], [crop, blurOp(5000, 10000, 8), speed]);
    final mid = r.pieces.firstWhere((p) => p.blur != null);
    expect(mid.crop, isNotNull);
    expect(mid.speed, 2.0);
  });

  test('compile: not approved or invalid values are ignored', () {
    final base = const [VideoPiece(0, 20000)];
    expect(compileOps(base, [blurOp(5000, 10000, 12, st: OpStatus.proposed)]).pieces, base);
    expect(compileOps(base, [blurOp(5000, 10000, 99)]).pieces, base);
    expect(compileOps(base, [flipOp(5000, 10000, h: false, v: false)]).pieces, base);
  });

  test('a freeze frame made after a blur keeps the blur and flip', () {
    final freeze = TransformOp(id: 'z', tool: TransformTool.freezeFrame, startMs: 7000, endMs: 7000, params: {'hold': 2.0}, status: OpStatus.approved);
    final r = compileOps(const [VideoPiece(0, 20000)], [blurOp(5000, 10000, 12), flipOp(5000, 10000), freeze]);
    final still = r.pieces.firstWhere((p) => p.freeze);
    expect(still.blur, 12.0);
    expect(still.flipH, isTrue);
  });

  test('piece JSON round trip; the saved plain timeline has no blur/flip keys', () {
    final p = const VideoPiece(0, 5000).withBlur(7.5).withFlip(true, false);
    final back = VideoPiece.fromJson(p.toJson());
    expect(back.blur, 7.5);
    expect(back.flipH, isTrue);
    expect(back.flipV, isFalse);
    final plain = const VideoPiece(0, 5000).toJson();
    expect(plain.containsKey('bl'), isFalse);
    expect(plain.containsKey('fh'), isFalse);
    expect(plain.containsKey('fv'), isFalse);
    expect(VideoPiece.fromJson({'s': 0, 'e': 1000, 'bl': 500}).blur, isNull); // out of range is ignored
    expect(const VideoPiece(0, 5000).withBlur(5) == const VideoPiece(0, 5000), isFalse);
  });

  test('withRange keeps blur and flip', () {
    final p = const VideoPiece(0, 10000).withBlur(9).withFlip(false, true).withRange(1000, 2000);
    expect(p.blur, 9.0);
    expect(p.flipV, isTrue);
  });

  test('preview helpers follow the playhead', () {
    final ops = [blurOp(1000, 3000, 20), flipOp(2000, 4000, h: false, v: true)];
    expect(previewBlur(ops, 500), isNull);
    expect(previewBlur(ops, 1500), 20.0);
    expect(previewFlip(ops, 1500), isNull);
    expect(previewFlip(ops, 2500)!.v, isTrue);
    expect(previewBlur([blurOp(1000, 3000, 20, st: OpStatus.rejected)], 1500), isNull);
  });

  test('tools have names and are saved by name', () {
    expect(TransformTool.blur.title, 'Blur');
    expect(TransformTool.mirrorFlip.title, 'Mirror / Flip');
    expect(TransformTool.blur.status, ToolStatus.experimental);
  });
}
