import 'package:flutter/material.dart';

import '../data/project.dart';
import 'editor_panel.dart';
import 'widgets.dart';

/// The Video Editor and the Transformative Editor (TE) are one screen now: a
/// preview with the effects drawn on it, the effect list (cut, zoom, freeze,
/// text, sound ...) and the usual pieces / narration / subtitles. The same
/// panel is also Stage 4 of the workflow. Effects are saved as the TE plan,
/// the rest as the timeline; the original video is never changed.
class TransformativeEditorScreen extends StatelessWidget {
  const TransformativeEditorScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return DfScaffold(
      appBar: AppBar(title: Text('Editor · ${project.name}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: EditorPanel(project: project),
      ),
    );
  }
}
