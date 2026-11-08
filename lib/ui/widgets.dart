import 'package:characters/characters.dart';
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
        color: DfColors.danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DfColors.danger.withOpacity(0.5)),
      ),
      child: Text(message, style: const TextStyle(color: DfColors.danger)),
    );
  }
}
