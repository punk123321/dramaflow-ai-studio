import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/segments.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/handoff_channel.dart';
import '../platform/video_import.dart';
import '../state/project_store.dart';
import 'render_panel.dart';
import 'save_panel.dart';
import 'widgets.dart';

/// Fast lane for someone who already has Burmese subtitles (an .srt) for the
/// video: pick the video, bring in the SRT, and go straight to making the MP4.
/// No Gemini recap, no narration chunks, no editing stage needed.
///
/// Shown as a tab of Subtitle Studio (`embedded`), so it has no scaffold of its own.
///
/// The video is the whole original with the subtitles burned in. The original
/// sound can stay on. Everything else (ratio, presets, look, logo) is still
/// reachable in the normal stages.
class QuickScreen extends StatefulWidget {
  const QuickScreen({super.key, required this.projectId, this.embedded = false, this.onSrtChanged});

  final int projectId;

  /// Inside Subtitle Studio: no AppBar / scaffold.
  final bool embedded;

  /// Called after a new SRT has been brought in.
  final VoidCallback? onSrtChanged;

  @override
  State<QuickScreen> createState() => _QuickScreenState();
}

class _QuickScreenState extends State<QuickScreen> {
  final _repo = HandoffRepo();
  final _paste = TextEditingController();
  List<SrtEntry> _entries = [];
  int _bad = 0;
  bool _hasSrt = false;
  bool _keepSound = true;
  bool _busy = false;
  int _prepared = 0; // changes every time the edit is (re)prepared, so the render panel reloads
  String? _msg;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _loadSrt();
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _loadSrt() async {
    final raw = await _repo.getDoc(widget.projectId, DocKind.studioSrt);
    if (raw != null && raw.trim().isNotEmpty) {
      final r = parseSrt(raw);
      if (mounted) {
        setState(() {
          _entries = r.entries;
          _bad = r.badBlocks;
          _hasSrt = r.entries.isNotEmpty;
        });
      }
    }
  }

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _err = error;
      });

  Project? _project(ProjectStore store) {
    for (final p in store.items) {
      if (p.id == widget.projectId) return p;
    }
    return null;
  }

  Future<void> _pickVideo(ProjectStore store, Project p) async {
    try {
      final v = await VideoImport.pick();
      if (v != null) await store.attachVideo(p, v);
    } catch (e) {
      _say('ဗီဒီယို ရွေးမရပါ: $e', error: true);
    }
  }

  Future<void> _useText(String text) async {
    final r = parseSrt(text);
    if (r.entries.isEmpty) {
      _say('SRT ဖတ်လို့မရပါ (အချိန်လိုင်း "00:00:01,000 --> 00:00:03,000" မတွေ့ဘူး)။', error: true);
      return;
    }
    await _repo.setDoc(widget.projectId, DocKind.studioSrt, serializeSrt(r.entries));
    setState(() {
      _entries = r.entries;
      _bad = r.badBlocks;
      _hasSrt = true;
      _prepared = 0;
    });
    widget.onSrtChanged?.call();
    _say('စာတန်း ${r.entries.length} ကြောင်း ထည့်ပြီးပါပြီ။${r.badBlocks > 0 ? ' (ဖတ်မရလို့ ${r.badBlocks} ခု ချန်ထားတယ်)' : ''}');
  }

  Future<void> _pickFile() async {
    try {
      final f = await HandoffChannel.pickTextFile();
      if (f != null) await _useText(f.text);
    } catch (e) {
      _say('ဖိုင် ဖတ်မရပါ: $e', error: true);
    }
  }

  Future<void> _prepare(Project p) async {
    setState(() => _busy = true);
    try {
      var tl = Timeline.decode(await _repo.getDoc(widget.projectId, DocKind.timeline));
      // Keep the user's own cuts if they made any; otherwise the whole video.
      if (tl.pieces.isEmpty) tl = tl.copyWith(pieces: [VideoPiece(0, p.videoDurationMs!)]);
      tl = tl.copyWith(originalVolume: _keepSound ? 1.0 : 0.0, burnSubtitles: true, subtitleOffsetMs: tl.pieces.length == 1 && tl.pieces.first.startMs == 0 ? 0 : tl.subtitleOffsetMs);
      await _repo.setDoc(widget.projectId, DocKind.timeline, tl.encode());
      setState(() => _prepared++);
      _say('အဆင်သင့်ပါ။ အောက်က "MP4 ထုတ်မယ်" ကို နှိပ်ပါ။');
    } catch (e) {
      _say('ပြင်ဆင်လို့ မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final p = _project(store);
    if (p == null) return const DfScaffold(body: Center(child: Text('Project မတွေ့ပါ')));
    final dur = p.videoDurationMs ?? 0;
    final lastEnd = _entries.isEmpty ? 0 : _entries.map((e) => e.endMs).reduce((a, b) => a > b ? a : b);
    final tooLong = dur > 0 && lastEnd > dur + 2000;

    final body = ListView(padding: const EdgeInsets.all(16), children: [
      const InfoHint('SRT ရှိပြီးသားဆိုရင် ဗီဒီယိုတန်း ထုတ်လို့ရတယ်။ မူရင်းဗီဒီယိုကို မပြင်ပါ။'),
      const SizedBox(height: 10),
      DfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(p.hasVideo ? Icons.movie_outlined : Icons.movie_creation_outlined, color: p.hasVideo ? DfColors.ok : DfColors.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.hasVideo ? '${p.videoName ?? 'ဗီဒီယို'} · ${formatTime(dur)}' : 'ဗီဒီယို မရွေးရသေးပါ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: p.hasVideo ? null : DfColors.warn),
              ),
            ),
            IconButton.outlined(
              onPressed: () => _pickVideo(store, p),
              icon: Icon(p.hasVideo ? Icons.swap_horiz : Icons.video_file_outlined),
              tooltip: p.hasVideo ? 'တခြားဗီဒီယို' : 'ဗီဒီယို ရွေး',
            ),
          ]),
          const Divider(height: 22),
          Row(children: [
            Icon(Icons.subtitles_outlined, color: _hasSrt ? DfColors.ok : DfColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _hasSrt ? '${_entries.length} · ${formatTime(lastEnd)}${_bad > 0 ? ' · ⚠$_bad' : ''}' : 'SRT မရှိသေးပါ',
                style: TextStyle(fontSize: 13.5, color: _hasSrt ? null : DfColors.muted),
              ),
            ),
            IconButton.outlined(onPressed: _pickFile, icon: const Icon(Icons.folder_open), tooltip: 'SRT ဖိုင်ရွေး'),
            const SizedBox(width: 6),
            IconButton.outlined(
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) {
                  _paste.text = d!.text!;
                  await _useText(d.text!);
                }
              },
              icon: const Icon(Icons.content_paste),
              tooltip: 'Clipboard က ထည့်',
            ),
          ]),
          if (tooLong)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.warning_amber, size: 16, color: DfColors.warn),
                SizedBox(width: 6),
                Expanded(child: Text('SRT က ဗီဒီယိုထက် ရှည်နေတယ်', style: TextStyle(color: DfColors.warn, fontSize: 12.5))),
              ]),
            ),
          const Divider(height: 22),
          Row(children: [
            Icon(_keepSound ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: _keepSound ? DfColors.ok : DfColors.muted),
            const SizedBox(width: 10),
            const Expanded(child: Text('မူရင်းအသံ', style: TextStyle(fontSize: 13.5))),
            Switch(
              value: _keepSound,
              onChanged: (v) => setState(() {
                _keepSound = v;
                _prepared = 0;
              }),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (!p.hasVideo || !_hasSrt || _busy) ? null : () => _prepare(p),
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('ပြင်ဆင်မယ်'),
      ),
      if (_msg != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13)),
        ),
      if (_prepared > 0) ...[
        const SizedBox(height: 14),
        const Row(children: [
          Icon(Icons.movie_filter_outlined, size: 18, color: DfColors.muted),
          SizedBox(width: 8),
          Text('ထုတ်', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        RenderPanel(key: ValueKey('quick-render-$_prepared'), project: p),
        const SizedBox(height: 14),
        const Row(children: [
          Icon(Icons.save_alt, size: 18, color: DfColors.muted),
          SizedBox(width: 8),
          Text('Gallery သိမ်း', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        SavePanel(key: ValueKey('quick-save-$_prepared'), project: p),
      ],
    ]);

    if (widget.embedded) return body;
    return DfScaffold(appBar: AppBar(title: const Text('အမြန်လမ်း')), body: body);
  }
}
