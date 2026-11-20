import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';
import '../state/project_store.dart';
import 'dialogs.dart';
import 'fair_use_screen.dart';
import 'subtitle_studio_screen.dart';
import 'backup_screen.dart';
import 'news_screen.dart';
import 'scene_recap_screen.dart';
import 'video_recap_screen.dart';
import 'publish_screen.dart';
import 'transformative_editor_screen.dart';
import 'widgets.dart';

enum _Action { none, workflow, library, studio, fairUse, transformative, publish, backup, videoRecap, sceneRecap, news }

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
  _Module('ST', 'Subtitle Studio', 'SRT ပြင်၊ အမြန်၊ ခွဲ', Color(0xFF5B8CFF), 4, _Action.studio),
  _Module('TT', 'TTS / MP3', 'အသံ ထုတ်/ဖမ်း', Color(0xFF5B8CFF), 5, _Action.workflow),
  _Module('ED', 'Video Editor', 'Preview · Effect · Timeline', Color(0xFFA46BFF), 6, _Action.transformative),
  _Module('RN', 'Render Center', 'MP4 ထုတ်', Color(0xFFF2C94C), 7, _Action.workflow),
  _Module('DL', 'Drama Library', 'ဇာတ်လမ်း၊ အပိုင်း', Color(0xFFFF9F43), 2, _Action.library),
  _Module('FU', 'Copyright & Fair Use', 'Upload မတင်ခင် စစ်', Color(0xFFF2C94C), 8, _Action.fairUse),
  _Module('VR', 'Video Recap', 'Gemini က ဗီဒီယိုကြည့်ပြီး script', Color(0xFFB36BFF), 13, _Action.videoRecap),
  _Module('SR', 'Scene Recap', 'Scene ခွဲ + contact sheet → Gemini', Color(0xFFFF7A59), 14, _Action.sceneRecap),
  _Module('NW', 'သတင်း (RSS)', 'သတင်းဖတ်၊ script ရေး', Color(0xFF2FA8FF), 14, _Action.news),
  _Module('BK', 'Backup / Restore', 'Project သိမ်း/ပြန်ယူ', Color(0xFF8E9AAF), 12, _Action.backup),
  _Module('UP', 'Upload & Thumbnail', 'ခေါင်းစဉ်၊ hashtag၊ ပုံ', Color(0xFFFF6B9D), 11, _Action.publish),
];


class _Feature {
  const _Feature(this.code, this.icon, this.color, this.step);
  final String code;
  final IconData icon;
  final Color color;
  final int step;
}

/// The studio steps shown as big tiles, in working order. Everything else is a
/// small chip under "Tools".
const _mainFeatures = <_Feature>[
  _Feature('GM', Icons.auto_awesome_rounded, Color(0xFF8B5CF6), 1),
  _Feature('TT', Icons.mic_rounded, Color(0xFFEC4899), 2),
  _Feature('ST', Icons.closed_caption_rounded, Color(0xFF22D3EE), 3),
  _Feature('ED', Icons.movie_filter_rounded, Color(0xFFF59E0B), 4),
  _Feature('RN', Icons.rocket_launch_rounded, Color(0xFF34D399), 5),
];

IconData _toolIcon(String code) => switch (code) {
      'VI' => Icons.view_timeline_rounded,
      'DL' => Icons.video_library_rounded,
      'FU' => Icons.verified_user_rounded,
      'VR' => Icons.smart_display_rounded,
      'SR' => Icons.grid_view_rounded,
      'NW' => Icons.newspaper_rounded,
      'BK' => Icons.cloud_sync_rounded,
      'UP' => Icons.cloud_upload_rounded,
      _ => Icons.apps_rounded,
    };

_Module _moduleFor(String code) => _modules.firstWhere((m) => m.code == code);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenWorkflow, required this.onOpenLibrary});

  final VoidCallback onOpenWorkflow;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final resume = store.resumeCandidate;
    final mainCodes = _mainFeatures.map((f) => f.code).toSet();
    final tools = _modules.where((m) => !mainCodes.contains(m.code)).toList();
    final steps = _mainFeatures.where((f) => f.code != 'RN').toList();
    final render = _mainFeatures.firstWhere((f) => f.code == 'RN');

    return DfScaffold(
      body: SafeArea(
        bottom: false,
        child: store.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Reveal(child: _Header(onBackup: () => _openModule(context, _moduleFor('BK'), onOpenWorkflow, onOpenLibrary))),
                  const SizedBox(height: 16),
                  if (store.error != null) ErrorBanner(store.error!),
                  Reveal(
                    index: 1,
                    child: resume != null
                        ? _ResumeCard(
                            project: resume,
                            onResume: () {
                              store.open(resume);
                              onOpenWorkflow();
                            },
                          )
                        : const _StartCard(),
                  ),
                  if (resume != null) ...[
                    const SizedBox(height: 10),
                    Reveal(index: 2, child: const _NewProjectRow()),
                  ],
                  const SectionTitle('Studio'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: steps.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 128,
                    ),
                    itemBuilder: (_, i) {
                      final f = steps[i];
                      final m = _moduleFor(f.code);
                      return Reveal(
                        index: i + 2,
                        child: _StudioTile(
                          title: m.title,
                          sub: m.sub,
                          icon: f.icon,
                          color: f.color,
                          step: f.step,
                          onTap: () => _openModule(context, m, onOpenWorkflow, onOpenLibrary),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Reveal(
                    index: 6,
                    child: _WideTile(
                      title: _moduleFor(render.code).title,
                      sub: _moduleFor(render.code).sub,
                      icon: render.icon,
                      color: render.color,
                      onTap: () => _openModule(context, _moduleFor(render.code), onOpenWorkflow, onOpenLibrary),
                    ),
                  ),
                  const SectionTitle('Tools'),
                  Reveal(
                    index: 7,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in tools)
                          _ToolChip(
                            title: m.title,
                            icon: _toolIcon(m.code),
                            color: m.color,
                            onTap: () => _openModule(context, m, onOpenWorkflow, onOpenLibrary),
                          ),
                      ],
                    ),
                  ),
                  if (store.items.isNotEmpty) ...[
                    const SectionTitle('Project များ'),
                    for (final p in store.items) _ProjectTile(project: p, onOpenWorkflow: onOpenWorkflow),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBackup});

  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: DfGradients.aurora,
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(color: DfColors.accent.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFC4B5FD), DfColors.cyan]).createShader(r),
                child: const Text('DramaFlow', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white)),
              ),
              const Text('AI Studio · recap ဗီဒီယို ဖုန်းထဲမှာတင်', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: DfColors.muted)),
            ],
          ),
        ),
        Pressable(
          onTap: onBackup,
          radius: 14,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: DfGradients.glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DfColors.glassEdge),
            ),
            child: const Icon(Icons.cloud_sync_rounded, color: Colors.white70, size: 22),
          ),
        ),
      ],
    );
  }
}

/// A big glass tile for one step of the studio.
class _StudioTile extends StatelessWidget {
  const _StudioTile({required this.title, required this.sub, required this.icon, required this.color, required this.step, required this.onTap});

  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final int step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: DfGradients.glass,
          color: DfColors.surface.withValues(alpha: 0.5),
          border: Border.all(color: DfColors.glassEdge),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 8))],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -34,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0)]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GlowChip(icon: icon, color: color, size: 42),
                      const Spacer(),
                      Text('0$step', style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 22, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const Spacer(),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: DfColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width glass tile (the last step, Render).
class _WideTile extends StatelessWidget {
  const _WideTile({required this.title, required this.sub, required this.icon, required this.color, required this.onTap});

  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.06)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            GlowChip(icon: icon, color: color, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: DfColors.muted)),
                ],
              ),
            ),
            Text('05', style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.title, required this.icon, required this.color, required this.onTap});

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: DfGradients.glass,
          color: DfColors.surface.withValues(alpha: 0.4),
          border: Border.all(color: DfColors.glassEdge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Shown when there is no project to continue.
class _StartCard extends StatelessWidget {
  const _StartCard();

  @override
  Widget build(BuildContext context) {
    final empty = context.select<ProjectStore, bool>((s) => s.items.isEmpty);
    return Glass(
      tint: DfColors.accent,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recap · Voice · Subtitle · Render', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            empty ? 'Project မရှိသေးပါဘူး။ ပထမဆုံး project ကို စလိုက်ပါ။' : 'Project တစ်ခု ရွေးပါ၊ ဒါမှမဟုတ် အသစ်စပါ။',
            style: const TextStyle(fontSize: 12.5, color: DfColors.muted),
          ),
          const SizedBox(height: 14),
          GradientButton(label: 'Project အသစ်', icon: Icons.add_rounded, onPressed: () => showNewProjectSheet(context)),
        ],
      ),
    );
  }
}

class _NewProjectRow extends StatelessWidget {
  const _NewProjectRow();

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => showNewProjectSheet(context),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: DfGradients.glass,
          border: Border.all(color: DfColors.accent.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: DfColors.accent, size: 22),
            SizedBox(width: 6),
            Text('Project အသစ်', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
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
    return Glass(
      tint: DfColors.accent,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Poster(title: project.dramaTitle, width: 58, height: 78),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                      child: const Text('ဆက်လုပ်ရန်', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${project.dramaTitle} · အပိုင်း ${project.episode} · ${formatWhen(project.updatedAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: DfColors.muted, fontSize: 12.5),
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
                decoration: BoxDecoration(color: stage.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: stage.color, blurRadius: 8)]),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('အဆင့် ${stage.index + 1} · ${stage.title}', style: const TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'ဆက်လုပ်မယ်', icon: Icons.play_arrow_rounded, onPressed: onResume),
        ],
      ),
    );
  }
}

/// Opens one module. Used by the studio tiles, the tool chips and the header.
void _openModule(BuildContext context, _Module module, VoidCallback onOpenWorkflow, VoidCallback onOpenLibrary) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();

  void push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  if (module.action == _Action.library) {
    onOpenLibrary();
    return;
  }
  if (module.action == _Action.backup) {
    // Works without a project, so a fresh install can restore.
    push(const BackupScreen());
    return;
  }
  if (module.action == _Action.news) {
    push(const NewsScreen());
    return;
  }
  if (module.action == _Action.none) {
    messenger.showSnackBar(SnackBar(
      content: Text('${module.title} ကို Phase ${module.phase} မှာ ရေးမယ်။ အခု မရသေးပါဘူး။'),
    ));
    return;
  }
  final store = context.read<ProjectStore>();
  final target = store.current ?? store.resumeCandidate ?? (store.items.isNotEmpty ? store.items.first : null);
  if (target == null || target.id == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Project တစ်ခု အရင်ဖန်တီးပါ။')));
    return;
  }
  switch (module.action) {
    case _Action.workflow:
      store.open(target);
      onOpenWorkflow();
    case _Action.studio:
      push(SubtitleStudioScreen(project: target));
    case _Action.fairUse:
      push(FairUseScreen(project: target));
    case _Action.transformative:
      push(TransformativeEditorScreen(project: target));
    case _Action.sceneRecap:
      push(SceneRecapScreen(project: target));
    case _Action.videoRecap:
      push(VideoRecapScreen(project: target));
    case _Action.publish:
      push(PublishScreen(project: target));
    case _Action.library:
    case _Action.news:
    case _Action.backup:
    case _Action.none:
      break;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () {
          context.read<ProjectStore>().open(project);
          onOpenWorkflow();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: DfGradients.glass,
            color: DfColors.surface.withValues(alpha: 0.45),
            border: Border.all(color: DfColors.glassEdge),
          ),
          child: Row(
            children: [
              Poster(title: project.dramaTitle, width: 44, height: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
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
