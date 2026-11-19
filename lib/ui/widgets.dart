import 'package:flutter/material.dart';

import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';

/// Small drama "poster": the first character of the drama title on a gradient.
class Poster extends StatelessWidget {
  const Poster({super.key, required this.title, this.width = 44, this.height = 58});

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = title.trim();
    final first = t.isEmpty ? '?' : t.characters.first;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DfColors.line),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2A6E), Color(0xFF0F1D4A), Color(0xFF7A2A5A)],
        ),
      ),
      child: Text(first, style: TextStyle(fontSize: width * 0.42, color: Colors.white)),
    );
  }
}

/// Six segments, one per stage, filled in the stage's own color when done.
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in Stage.values)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: s == Stage.save ? 0 : 4),
              decoration: BoxDecoration(
                color: project.isDone(s) ? s.color : DfColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DfColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DfColors.danger.withValues(alpha: 0.5)),
      ),
      child: Text(message, style: const TextStyle(color: DfColors.danger)),
    );
  }
}

/// Scaffold with the app's indigo page gradient behind it. The gradient is
/// opaque, so a page pushed over another page does not show it through.
class DfScaffold extends StatelessWidget {
  const DfScaffold({super.key, this.appBar, required this.body, this.floatingActionButton, this.bottomNavigationBar});

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: DfGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: body,
      ),
    );
  }
}

/// Wide violet gradient button, used for the main action of a page.
/// With `onPressed: null` it is shown dimmed and does nothing.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: DfGradients.primary,
            boxShadow: on
                ? [BoxShadow(color: DfColors.accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded dark card used to group the parts of a studio page.
class DfCard extends StatelessWidget {
  const DfCard({super.key, required this.child, this.title, this.margin = const EdgeInsets.only(bottom: 12)});

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DfColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DfColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          child,
        ],
      ),
    );
  }
}

/// One line of a checklist: green tick when [ok], grey circle otherwise.
class CheckLine extends StatelessWidget {
  const CheckLine(this.text, {super.key, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: ok ? DfColors.ok : DfColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

/// Big circular progress with the percentage in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.percent, this.size = 104});

  /// 0 means "no progress known yet" (the ring spins).
  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: percent <= 0 ? null : percent / 100,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: DfColors.line,
              color: DfColors.ok,
            ),
          ),
          Text(percent <= 0 ? '…' : '$percent%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Long explanation that stays out of the way: one small line, tap to read it.
class InfoHint extends StatefulWidget {
  const InfoHint(this.text, {super.key, this.label = 'ရှင်းလင်းချက်'});

  final String text;
  final String label;

  @override
  State<InfoHint> createState() => _InfoHintState();
}

class _InfoHintState extends State<InfoHint> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 16, color: DfColors.muted),
                const SizedBox(width: 6),
                Text(widget.label, style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: DfColors.muted),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(widget.text, style: const TextStyle(color: DfColors.muted, fontSize: 12.5, height: 1.4)),
              ),
          ],
        ),
      ),
    );
  }
}
