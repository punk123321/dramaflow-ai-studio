import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../state/project_store.dart';
import 'dialogs.dart';
import 'fair_use_screen.dart';
import 'transformative_editor_screen.dart';
import 'subtitle_studio_screen.dart';
import 'widgets.dart';

enum _Action { none, workflow, library, studio, fairUse, transformative }

class _Module {
  const _Module(this.code, this.title, this.sub, this.color, this.phase, [this.action = _Action.none]);
  final String code;
  final String title;
  final String sub;
  final Color color;
  final int phase;
  final _Action action;
}

const _modules = <_Module>[
  _Module('VI', 'Video Index', 'အပိုင်းခွဲ', Color(0xFFFF9F43), 2, _Action.workflow),
  _Module('GM', 'Recap Studio', 'Gemini handoff', Color(0xFF3DDC84), 3, _Action.workflow),
  _Module('ST', 'Subtitle Studio', 'SRT ပြင်၊ စစ်', Color(0xFF5B8CFF), 4, _Action.studio),
  _Module('TT', 'TTS / MP3', 'အသံ ထုတ်/ဖမ်း', Color(0xFF5B8CFF), 5, _Action.workflow),
  _Module('ED', 'Video Editor', 'Timeline', Color(0xFFA46BFF), 6, _Action.workflow),
  _Module('RN', 'Render Center', 'MP4 ထုတ်', Color(0xFFF2C94C), 7, _Action.workflow),
  _Module('DL', 'Drama Library', 'ဇာတ်လမ်း၊ အပိုင်း', Color(0xFFFF9F43), 2, _Action.library),
  _Module('FU', 'Copyright & Fair Use', 'Upload မတင်ခင် စစ်', Color(0xFFF2C94C), 8, _Action.fairUse),
  _Module('TE', 'Transformative Editor', 'Manual · AI · Hybrid', Color(0xFF00C2A8), 9, _Action.transformative),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenWorkflow, required this.onOpenLibrary});

  final VoidCallback onOpenWorkflow;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final resume = store.resumeCandidate;

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Drama'),
              TextSpan(text: 'Flow', style: TextStyle(color: DfColors.accent)),
            ],
          ),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewProjectSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Project အသစ်'),
      ),
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (store.error != null) ErrorBanner(store.error!),
                if (resume != null)
                  _ResumeCard(
                    project: resume,
                    onResume: () {
                      store.open(resume);
                      onOpenWorkflow();
                    },
                  )
                else if (store.items.isEmpty)
                  const _EmptyHint(),
                const SectionTitle('Studio'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _modules.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 112,
                  ),
                  itemBuilder: (_, i) => _ModuleTile(
                    module: _modules[i],
                    onOpenWorkflow: onOpenWorkflow,
                    onOpenLibrary: onOpenLibrary,
                  ),
                ),
                if (store.items.isNotEmpty) ...[
                  const SectionTitle('Project များ'),
                  for (final p in store.items) _ProjectTile(project: p, onOpenWorkflow: onOpenWorkflow),
                ],
              ],
            ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DfColors.line),
      ),
      child: const Text(
        'Project မရှိသေးပါဘူး။ အောက်ခြေက “Project အသစ်” ကို နှိပ်ပြီး စပါ။',
        textAlign: TextAlign.center,
        style: TextStyle(color: DfColors.muted),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.project, required this.onResume});

  final Project project;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final stage = project.currentStage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DfColors.accent.withValues(alpha: 0.5)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DfColors.accent.withValues(alpha: 0.22), DfColors.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Poster(title: project.dramaTitle, width: 56, height: 76),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ဆက်လုပ်ရန်', style: TextStyle(color: DfColors.muted, fontSize: 13)),
                    Text(
                      project.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${project.dramaTitle} · အပိုင်း ${project.episode} · ${formatWhen(project.updatedAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DfColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StageBar(project: project),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stage.color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: stage.color, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'အဆင့် ${stage.index + 1} · ${stage.title}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              FilledButton(onPressed: onResume, child: const Text('ဆက်လုပ်မယ်')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.onOpenWorkflow,
    required this.onOpenLibrary,
  });

  final _Module module;
  final VoidCallback onOpenWorkflow;
  final VoidCallback onOpenLibrary;

  void _tap(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    switch (module.action) {
      case _Action.library:
        onOpenLibrary();
      case _Action.workflow:
        final store = context.read<ProjectStore>();
        final target = store.current ?? store.resumeCandidate ?? (store.items.isNotEmpty ? store.items.first : null);
        if (target == null) {
          messenger.showSnackBar(const SnackBar(content: Text('Project တစ်ခု အရင်ဖန်တီးပါ။')));
        } else {
          store.open(target);
          onOpenWorkflow();
        }
      case _Action.studio:
        final store = context.read<ProjectStore>();
        final target = store.current ?? store.resumeCandidate ?? (store.items.isNotEmpty ? store.items.first : null);
        if (target == null || target.id == null) {
          messenger.showSnackBar(const SnackBar(content: Text('Project တစ်ခု အရင်ဖန်တီးပါ။')));
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubtitleStudioScreen(project: target)));
        }
      case _Action.fairUse:
        final store = context.read<ProjectStore>();
        final target = store.current ?? store.resumeCandidate ?? (store.items.isNotEmpty ? store.items.first : null);
        if (target == null || target.id == null) {
          messenger.showSnackBar(const SnackBar(content: Text('Project တစ်ခု အရင်ဖန်တီးပါ။')));
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FairUseScreen(project: target)));
        }
      case _Action.transformative:
        final store = context.read<ProjectStore>();
        final target = store.current ?? store.resumeCandidate ?? (store.items.isNotEmpty ? store.items.first : null);
        if (target == null || target.id == null) {
          messenger.showSnackBar(const SnackBar(content: Text('Project တစ်ခု အရင်ဖန်တီးပါ။')));
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransformativeEditorScreen(project: target)));
        }
      case _Action.none:
        messenger.showSnackBar(SnackBar(
          content: Text('${module.title} ကို Phase ${module.phase} မှာ ရေးမယ်။ အခု မရသေးပါဘူး။'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = module.color;
    return Material(
      color: DfColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: DfColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _tap(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.withValues(alpha: 0.45)),
                    ),
                    child: Text(module.code, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  Text(module.action == _Action.none ? 'Phase ${module.phase}' : 'သုံးလို့ရ', style: TextStyle(color: module.action == _Action.none ? DfColors.muted : DfColors.ok, fontSize: 11)),
                ],
              ),
              const Spacer(),
              Text(module.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(module.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DfColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onOpenWorkflow});

  final Project project;
  final VoidCallback onOpenWorkflow;

  Future<void> _menu(BuildContext context, String action) async {
    final store = context.read<ProjectStore>();
    if (action == 'rename') {
      final name = await askText(context, 'နာမည်ပြောင်းမယ်', project.name);
      if (name != null) await store.rename(project, name);
    } else if (action == 'duplicate') {
      await store.duplicate(project);
    } else if (action == 'delete') {
      final ok = await confirmDelete(context, project.name);
      if (ok) await store.delete(project);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = project.currentStage;
    final label = project.finished ? 'ပြီး' : stage.title;
    final color = project.finished ? DfColors.ok : stage.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DfColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DfColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          context.read<ProjectStore>().open(project);
          onOpenWorkflow();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Poster(title: project.dramaTitle, width: 42, height: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${project.dramaTitle} · EP ${project.episode} · ${formatWhen(project.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DfColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    StageBar(project: project),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 12)),
              ),
              PopupMenuButton<String>(
                onSelected: (a) => _menu(context, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('နာမည်ပြောင်း')),
                  PopupMenuItem(value: 'duplicate', child: Text('ကူးယူ')),
                  PopupMenuItem(value: 'delete', child: Text('ဖျက်')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
