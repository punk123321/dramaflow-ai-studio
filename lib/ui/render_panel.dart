import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/render_plan.dart';
import '../core/srt.dart';
import '../core/stage.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../core/te_compile.dart';
import '../core/transformative_plan.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/render_channel.dart';
import '../state/project_store.dart';
import '../state/render_store.dart';

String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(bytes < 10485760 ? 1 : 0)} MB';

String _dur(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Stage 5: turn the edit made in Stage 4 into a new MP4.
class RenderPanel extends StatefulWidget {
  const RenderPanel({super.key, required this.project});

  final Project project;

  @override
  State<RenderPanel> createState() => _RenderPanelState();
}

class _RenderPanelState extends State<RenderPanel> {
  final _repo = HandoffRepo();
  bool _loading = true;
  Timeline _tl = const Timeline();
  TransformativePlan _plan = const TransformativePlan();
  List<SrtEntry> _subs = [];
  RenderSettings _settings = const RenderSettings();
  int _free = 0;
  bool _markedDone = false;

  int get _pid => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _tl = Timeline.decode(await _repo.getDoc(_pid, DocKind.timeline));
      _plan = TransformativePlan.decode(await _repo.getDoc(_pid, DocKind.transformativePlan));
      final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
      final src = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
      _subs = src == null ? [] : parseSrt(src).entries;
      _free = await RenderChannel.freeBytes();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _start() async {
    final p = widget.project;
    final name = '${safeFileName(p.name)}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final te = compileOps(_tl.pieces, _plan.ops);
    final job = buildRenderJob(
      name: name,
      videoUri: p.sourceVideoUri!,
      // Approved TE operations are applied to a copy; the saved timeline stays as it is.
      timeline: _tl.copyWith(pieces: te.pieces, voices: [..._tl.voices, ...te.sounds]),
      overlays: [for (final o in te.overlays) o.toJson()],
      sourceSubtitles: _subs,
      settings: _settings,
      aspect: (p.videoWidth ?? 0) > 0 && (p.videoHeight ?? 0) > 0 ? p.videoWidth! / p.videoHeight! : 16 / 9,
    );
    await context.read<RenderStore>().start(_pid, name, job);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final rs = context.watch<RenderStore>();
    final p = widget.project;
    final mine = rs.runningProjectId == _pid;
    final otherRunning = rs.running && !mine;
    final blockers = renderBlockers(hasVideo: p.hasVideo, timeline: _tl, sourceMs: p.videoDurationMs ?? 0);
    final te = compileOps(_tl.pieces, _plan.ops);
    final dur = outputDurationMs(_tl.copyWith(pieces: te.pieces));
    final est = estimateBytes(dur, _settings);
    final lowSpace = _free > 0 && est > 0 && _free < est + est ~/ 5 + 50 * 1048576;
    final done = rs.lastDone;

    if (done != null && done.projectId == _pid && !p.isDone(Stage.render) && !_markedDone) {
      _markedDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final store = context.read<ProjectStore>();
        final cur = store.current;
        if (cur != null) store.setStageDone(cur, Stage.render, true);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Stage 4 မှာ စီစဉ်ထားတာကို MP4 အသစ်အဖြစ် ထုတ်မယ်။ မူရင်းဗီဒီယိုကို မထိပါဘူး။ ထုတ်နေတုန်း app ကို ဖွင့်ထားပါ (screen ကို ဖွင့်ထားပေးမယ်)။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        _row('အရှည်', dur > 0 ? _dur(dur) : '—'),
        _row('အပိုင်း', '${_tl.pieces.length}'),
        if (te.applied.isNotEmpty) _row('TE operation', '${te.applied.length} ခု ပါမယ်'),
        for (final n in te.infos)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('TE: $n', style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
          ),
        for (final n in te.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('TE: $n', style: const TextStyle(color: DfColors.warn, fontSize: 12.5)),
          ),
        _row('အသံ / music', '${_tl.voices.length} / ${_tl.music == null ? 'မရှိ' : 'ရှိ'}'),
        _row('စာတန်း', _tl.burnSubtitles ? 'ထည့်ရိုက်မယ်' : 'မထည့်'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('h${_settings.height}'),
              initialValue: _settings.height,
              decoration: const InputDecoration(labelText: 'ပုံအရွယ်'),
              items: const [
                DropdownMenuItem(value: 720, child: Text('720p')),
                DropdownMenuItem(value: 1080, child: Text('1080p')),
              ],
              onChanged: mine ? null : (v) => setState(() => _settings = _settings.copyWith(height: v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('f${_settings.fps}'),
              initialValue: _settings.fps,
              decoration: const InputDecoration(labelText: 'Frame rate'),
              items: const [
                DropdownMenuItem(value: 24, child: Text('24 fps')),
                DropdownMenuItem(value: 25, child: Text('25 fps')),
                DropdownMenuItem(value: 30, child: Text('30 fps')),
              ],
              onChanged: mine ? null : (v) => setState(() => _settings = _settings.copyWith(fps: v)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _row('ခန့်မှန်း ဖိုင်အရွယ်', est > 0 ? '≈ ${_mb(est)}' : '—'),
        _row('ဖုန်းမှာ ကျန်နေရာ', _free > 0 ? _mb(_free) : '—'),
        if (lowSpace)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('⚠ နေရာ မလောက်နိုင်ပါ။ ဖိုင်တွေ ဖျက်ပါ ဒါမှမဟုတ် 720p ရွေးပါ။', style: TextStyle(color: DfColors.warn, fontSize: 13)),
          ),
        const SizedBox(height: 10),
        for (final b in blockers) Text('✗ $b', style: const TextStyle(color: DfColors.danger, fontSize: 13)),
        if (rs.error != null)
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: DfColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(rs.error!, style: const TextStyle(fontSize: 13)),
          ),
        if (rs.canceled && !rs.running)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Render ကို ရပ်လိုက်ပါပြီ။ ဖိုင်အပျက် မကျန်ပါ။', style: TextStyle(fontSize: 13))),
        const SizedBox(height: 8),
        if (mine) ...[
          LinearProgressIndicator(value: rs.percent <= 0 ? null : rs.percent / 100),
          const SizedBox(height: 6),
          Text('ထုတ်နေတယ် ${rs.percent}%', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: rs.cancel, child: const Text('ရပ်မယ်')),
        ] else
          FilledButton.icon(
            onPressed: (blockers.isNotEmpty || otherRunning) ? null : _start,
            icon: const Icon(Icons.movie_creation_outlined, size: 18),
            label: Text(otherRunning ? 'တခြား project render လုပ်နေဆဲ' : 'MP4 ထုတ်မယ်'),
          ),
        if (done != null && done.projectId == _pid && !mine) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: DfColors.ok)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ပြီးပါပြီ ✓', style: TextStyle(fontWeight: FontWeight.w600, color: DfColors.ok)),
              Text('${done.height}p · ${_dur(done.durationMs)} · ${_mb(done.sizeBytes)}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: () => showVideoPreview(context, done.path), child: const Text('ကြည့်မယ်')),
              ]),
              const Text('Gallery ထဲ သိမ်းဖို့ နောက်အဆင့် "Save" ကို သွားပါ။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: DfColors.muted, fontSize: 13))),
          Text(b, style: const TextStyle(fontSize: 13)),
        ]),
      );
}

/// Plays a finished render inside a dialog.
Future<void> showVideoPreview(BuildContext context, String path) {
  return showDialog<void>(context: context, builder: (_) => _PreviewDialog(path: path));
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.path});

  final String path;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  VideoPlayerController? _c;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _err = 'ဖွင့်လို့မရပါ: $e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_err != null) Text(_err!) else if (c == null) const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())) else ...[
            AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            VideoProgressIndicator(c, allowScrubbing: true),
            IconButton(
              onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
          ],
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ပိတ်')),
        ]),
      ),
    );
  }
}
