import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/recap_queue.dart';
import 'package:aistudio/ui/recap_step_bar.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: w)));

void main() {
  testWidgets('step bar shows every step label with the right icon', (tester) async {
    await tester.pumpWidget(_wrap(const RecapStepBar(
      current: QStep.ask,
      running: true,
      done: {QStep.upload},
      skipped: {QStep.subtitles},
    )));
    await tester.pump();
    for (final st in videoQSteps) {
      expect(find.text(qStepLabels[st]!), findsOneWidget);
    }
    expect(find.text(qStepLabels[QStep.scenes]!), findsNothing); // only in a Scene Recap bar
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // upload
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget); // subtitles skipped
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // ask is running
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2)); // save, audio
  });

  testWidgets('a failed step shows the error icon and no spinner', (tester) async {
    await tester.pumpWidget(_wrap(const RecapStepBar(current: QStep.ask, failed: QStep.ask, done: {QStep.subtitles, QStep.upload})));
    await tester.pump();
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('a custom list of steps shows only those', (tester) async {
    await tester.pumpWidget(_wrap(const RecapStepBar(steps: [QStep.subtitles, QStep.ask])));
    await tester.pump();
    expect(find.text(qStepLabels[QStep.subtitles]!), findsOneWidget);
    expect(find.text(qStepLabels[QStep.upload]!), findsNothing);
  });

  testWidgets('a scene bar shows the scene step instead of upload', (tester) async {
    await tester.pumpWidget(_wrap(const RecapStepBar(steps: sceneQSteps, current: QStep.scenes, running: true, done: {QStep.subtitles})));
    await tester.pump();
    expect(find.text(qStepLabels[QStep.scenes]!), findsOneWidget);
    expect(find.text(qStepLabels[QStep.upload]!), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
