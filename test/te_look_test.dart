import 'package:aistudio/core/te_compile.dart';
import 'package:aistudio/core/te_preview.dart';
import 'package:aistudio/core/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saturation: JSON keeps two numbers when colour is untouched, three when changed', () {
    expect(const LookAdjust(0.1, 0.2).toJson(), [0.1, 0.2]);
    expect(const LookAdjust(0.1, 0.2, -1).toJson(), [0.1, 0.2, -1]);
    expect(LookAdjust.fromJson([0.1, 0.2, -1]), const LookAdjust(0.1, 0.2, -1));
    expect(LookAdjust.fromJson([0.1, 0.2]), const LookAdjust(0.1, 0.2));
    expect(LookAdjust.fromJson([0, 0, 0]), isNull);
    expect(LookAdjust.fromJson([0, 0, 9]), const LookAdjust(0, 0, 1));
    expect(LookAdjust.fromJson([0, 0, 0, 0]), isNull);
  });

  test('lookFromParams: saturation is optional, B&W alone is a look, out of range is refused', () {
    expect(lookFromParams({'brightness': 0.0, 'contrast': 0.0}), isNull);
    expect(lookFromParams({'brightness': 0.0, 'contrast': 0.0, 'saturation': -1}), const LookAdjust(0, 0, -1));
    expect(lookFromParams({'brightness': 0.0, 'contrast': 0.0, 'saturation': 1.5}), isNull);
    expect(lookFromParams({'brightness': 0.0, 'contrast': 0.0, 'saturation': 'x'}), isNull);
  });

  test('lookMatrix: saturation -1 makes all colour rows equal (grey), 0 changes nothing', () {
    final bw = lookMatrix(const LookAdjust(0, 0, -1));
    expect(bw.sublist(0, 3), bw.sublist(5, 8));
    expect(bw.sublist(0, 3), bw.sublist(10, 13));
    expect(bw[0] + bw[1] + bw[2], closeTo(1, 1e-9));
    final same = lookMatrix(const LookAdjust(0, 0, 0));
    expect([same[0], same[1], same[6], same[12]], [1, 0, 1, 1]);
  });

  test('a piece with a B&W look survives the saved timeline', () {
    const piece = VideoPiece(0, 4000, ZoomMode.none, null, false, LookAdjust(0, 0, -1));
    expect(VideoPiece.fromJson(piece.toJson()).look, const LookAdjust(0, 0, -1));
  });
}
