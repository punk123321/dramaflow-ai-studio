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
  const DfScaffold({super.key, this.appBar, required this.body, this.floatingActionButton});

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: DfGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: body,
      ),
    );
  }
}

/// Wide violet gradient button, used for the main action of a page.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: DfGradients.primary,
          boxShadow: [
            BoxShadow(color: DfColors.accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
