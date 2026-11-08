import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Honest stand-in for a module that is not built yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.phase});

  final String title;
  final int phase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title ကို Phase $phase မှာ ရေးမယ်။ အခု မရသေးပါဘူး။',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DfColors.muted),
        ),
      ),
    );
  }
}
