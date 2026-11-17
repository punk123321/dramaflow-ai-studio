import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../state/project_store.dart';
import 'audio_panel.dart';
import 'editor_panel.dart';
import 'gemini_panel.dart';
import 'render_panel.dart';
import 'save_panel.dart';
import 'video_index_panel.dart';
import 'widgets.dart';

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({super.key});

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  /// null = follow the project's current stage, -1 = all collapsed.
  int? _open;
  int? _forProject;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final p = store.current;

    if (p != null && _forProject != p.id) {
      _forProject = p.id;
      _open = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recap Workflow')),
      body: p == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Project မရွေးရသေးပါဘူး။ Home မှာ project တစ်ခု ရွေးပါ၊ ဒါမှမဟုတ် အသစ်ဖန်တီးပါ။',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DfColors.muted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (store.error != null) ErrorBanner(store.error!),
                _Header(project: p),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Guided')),
                    ButtonSegment(value: true, label: Text('Free')),
                  ],
                  selected: {store.freeMode},
                  onSelectionChanged: (s) => store.setFreeMode(s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  store.freeMode
                      ? 'Free mode · ဘယ်အဆင့်ကိုမဆို တိုက်ရိုက်ဖွင့်လို့ရပါတယ်'
                      : 'Guided mode · အဆင့်ကို အစဉ်လိုက် လုပ်ပါ',
                  style: const TextStyle(color: DfColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                for (final s in Stage.values) _stepCard(context, store, p, s),
              ],
            ),
    );
  }

  Widget _stepCard(BuildContext context, ProjectStore store, Project p, Stage s) {
    final unlocked = store.freeMode || s.index == 0 || p.isDone(Stage.values[s.index - 1]);
    final done = p.isDone(s);
    final effective = _open ?? p.currentStage.index;
    final open = unlocked && effective == s.index;
    final c = s.color;

    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: DfColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: open ? c : c.withValues(alpha: 0.4), width: open ? 2 : 1.5),
          boxShadow: open ? [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 18)] : null,
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: unlocked ? () => setState(() => _open = open ? -1 : s.index) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: done ? DfColors.ok : c.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: done ? DfColors.ok : c.withValues(alpha: 0.45)),
                      ),
                      child: done
                          ? const Icon(Icons.check, size: 18, color: Color(0xFF06210F))
                          : Text('${s.index + 1}', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          Text(
                            unlocked ? s.subtitle : 'အရင်အဆင့် ပြီးမှ ဖွင့်မယ်',
                            style: const TextStyle(color: DfColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (unlocked) Icon(open ? Icons.expand_less : Icons.expand_more, color: DfColors.muted),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(color: DfColors.line, height: 1),
                    const SizedBox(height: 10),
                    if (!done && (s == Stage.copy || s == Stage.tts || s == Stage.edit))
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => store.setStageDone(p, s, true),
                          icon: const Icon(Icons.skip_next, size: 18),
                          label: const Text('ဒီအဆင့် မလိုဘူး၊ ကျော်မယ်'),
                        ),
                      ),
                    if (s == Stage.videoIndex)
                      VideoIndexPanel(project: p)
                    else if (s == Stage.copy)
                      GeminiPanel(project: p)
                    else if (s == Stage.tts)
                      AudioPanel(project: p)
                    else if (s == Stage.edit)
                      EditorPanel(project: p)
                    else if (s == Stage.render)
                      RenderPanel(project: p)
                    else if (s == Stage.save)
                      SavePanel(project: p)
                    else ...[
                      Text(
                        'ဒီအဆင့်ရဲ့ တကယ့်လုပ်ဆောင်ချက်ကို Phase ${s.phase} မှာ ရေးမယ်။ အခုတော့ ပြီးကြောင်း မှတ်ထားလို့ရပါတယ်။',
                        style: const TextStyle(color: DfColors.muted, fontSize: 13),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: done,
                        onChanged: (v) => store.setStageDone(p, s, v),
                        title: const Text('ဒီအဆင့် ပြီးပြီ'),
                      ),
                      const FilledButton(onPressed: null, child: Text('လုပ်ဆောင်ချက် (မကြာမီ)')),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Poster(title: project.dramaTitle, width: 44, height: 58),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              Text(
                '${project.dramaTitle} · အပိုင်း ${project.episode} · ${project.doneCount}/${Stage.values.length} ပြီး',
                style: const TextStyle(color: DfColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              StageBar(project: project),
            ],
          ),
        ),
      ],
    );
  }
}
