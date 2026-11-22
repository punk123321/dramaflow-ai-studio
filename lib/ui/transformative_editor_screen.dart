import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../state/project_store.dart';
import 'editor_panel.dart';
import 'stage_screen.dart';
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
      appBar: AppBar(
        title: Text('Editor · ${project.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Pressable(
              onTap: () {
                context.read<ProjectStore>().open(project);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => StageScreen(project: project, stage: Stage.render, title: 'Export Video'),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(gradient: DfGradients.primary, borderRadius: BorderRadius.circular(14)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Export Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: EditorPanel(project: project, pinned: true),
      ),
    );
  }
}
