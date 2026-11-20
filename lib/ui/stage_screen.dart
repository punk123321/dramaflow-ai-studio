import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../state/project_store.dart';
import 'audio_panel.dart';
import 'gemini_panel.dart';
import 'render_panel.dart';
import 'video_index_panel.dart';
import 'widgets.dart';

/// One workflow stage as its own full page (Video Index, Recap Studio, Voice,
/// Render Center), opened straight from Home like Subtitle Studio. It shows the
/// same panel the Workflow tab shows for that stage, so both stay in step.
class StageScreen extends StatelessWidget {
  const StageScreen({super.key, required this.project, required this.stage, this.title});

  final Project project;
  final Stage stage;
  final String? title;

  Widget _panel(Project p) => switch (stage) {
        Stage.videoIndex => VideoIndexPanel(project: p),
        Stage.copy => GeminiPanel(project: p),
        Stage.tts => AudioPanel(project: p),
        Stage.render => RenderPanel(project: p),
        _ => const SizedBox.shrink(),
      };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    // Newest copy of the project, so the panel sees changes it makes itself.
    final p = store.items.where((x) => x.id == project.id).firstOrNull ?? project;
    final done = p.isDone(stage);
    return DfScaffold(
      appBar: AppBar(title: Text(title ?? stage.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (store.error != null) ErrorBanner(store.error!),
          DfCard(
            margin: EdgeInsets.zero,
            child: Row(children: [
              Poster(title: p.dramaTitle, width: 40, height: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${p.dramaTitle} · အပိုင်း ${p.episode}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  StageBar(project: p),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          DfCard(margin: EdgeInsets.zero, child: _panel(p)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: done,
            onChanged: (v) => store.setStageDone(p, stage, v),
            title: const Text('ဒီအဆင့် ပြီးပြီ'),
            subtitle: const Text('Workflow tab မှာ အဆင့်ပြီးကြောင်း မှတ်မယ်', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
