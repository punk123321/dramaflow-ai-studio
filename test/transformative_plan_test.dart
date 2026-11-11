import 'package:aistudio/core/transformative_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TE plan round-trips mode, tools and instructions', () {
    const plan = TransformativePlan(
      mode: TransformMode.aiAssisted,
      enabledTools: {TransformTool.smartCut, TransformTool.pictureInPicture},
      instructions: 'Explain key scenes.',
    );
    final decoded = TransformativePlan.decode(plan.encode());
    expect(decoded.mode, TransformMode.aiAssisted);
    expect(decoded.enabledTools, plan.enabledTools);
    expect(decoded.instructions, 'Explain key scenes.');
    expect(decoded.version, 1);
  });

  test('unknown values and malformed JSON safely fall back', () {
    final decoded = TransformativePlan.decode('{"mode":"future","tools":["unknown"]}');
    expect(decoded.mode, TransformMode.hybrid);
    expect(decoded.enabledTools, isEmpty);
    expect(TransformativePlan.decode('{bad json').mode, TransformMode.hybrid);
  });
}
