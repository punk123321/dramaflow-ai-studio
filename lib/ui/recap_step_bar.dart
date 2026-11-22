import 'package:flutter/material.dart';

import '../core/recap_queue.dart';
import '../core/theme.dart';

/// One row that shows where an episode is: each step is done (✓), skipped (–),
/// running (spinner), failed (!) or still waiting (○). Used by the queue and
/// by the Auto card, so both look the same.
class RecapStepBar extends StatelessWidget {
  const RecapStepBar({
    super.key,
    this.steps = QStep.values,
    this.current,
    this.done = const {},
    this.skipped = const {},
    this.failed,
    this.running = false,
  });

  final List<QStep> steps;
  final QStep? current;
  final Set<QStep> done;
  final Set<QStep> skipped;
  final QStep? failed;

  /// True while [current] is really being worked on (shows the spinner).
  final bool running;

  Widget _icon(QStep s) {
    const size = 18.0;
    if (failed == s) return const Icon(Icons.error, size: size, color: DfColors.danger);
    if (done.contains(s)) return const Icon(Icons.check_circle, size: size, color: DfColors.ok);
    if (skipped.contains(s)) return const Icon(Icons.remove_circle_outline, size: size, color: DfColors.muted);
    if (current == s && running) {
      return const SizedBox(width: size, height: size, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.2)));
    }
    return const Icon(Icons.radio_button_unchecked, size: size, color: DfColors.line);
  }

  Color _color(QStep s) {
    if (failed == s) return DfColors.danger;
    if (current == s && running) return DfColors.ink;
    if (done.contains(s)) return DfColors.ok;
    return DfColors.muted;
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final s in steps)
        Expanded(
          child: Column(children: [
            _icon(s),
            const SizedBox(height: 3),
            Text(
              qStepLabels[s] ?? s.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 10.5, height: 1.2, color: _color(s), fontWeight: current == s ? FontWeight.w700 : FontWeight.w400),
            ),
          ]),
        ),
    ]);
  }
}
