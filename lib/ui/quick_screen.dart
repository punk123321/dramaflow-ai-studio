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
/// The video is the whole original with the subtitles burned in. The original
/// sound can stay on. Everything else (ratio, presets, look, logo) is still
/// reachable in the normal stages.
class QuickScreen extends StatefulWidget {
  const QuickScreen({super.key, required this.projectId});

  final int projectId;

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
    if (p == null) return const Scaffold(body: Center(child: Text('Project မတွေ့ပါ')));
    final dur = p.videoDurationMs ?? 0;
    final lastEnd = _entries.isEmpty ? 0 : _entries.map((e) => e.endMs).reduce((a, b) => a > b ? a : b);
    final tooLong = dur > 0 && lastEnd > dur + 2000;

    return Scaffold(
      appBar: AppBar(title: const Text('အမြန်လမ်း (SRT ရှိပြီးသား)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'မြန်မာ SRT ရှိပြီးသားဆိုရင် Gemini၊ အသံ chunk၊ edit အဆင့်တွေ မလိုဘဲ ဗီဒီယိုတန်း ထုတ်လို့ရတယ်။ '
          'မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။ စာတန်းကို ပုံပေါ်ရိုက်ထည့်ပေးမယ်။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        const SectionTitle('၁။ ဗီဒီယို'),
        if (p.hasVideo)
          Text('${p.videoName ?? 'ဗီဒီယို'} · ${formatTime(dur)}', style: const TextStyle(fontSize: 13))
        else
          const Text('ဗီဒီယို မရွေးရသေးပါ', style: TextStyle(color: DfColors.warn, fontSize: 13)),
        OutlinedButton.icon(
          onPressed: () => _pickVideo(store, p),
          icon: const Icon(Icons.video_file_outlined, size: 18),
          label: Text(p.hasVideo ? 'တခြားဗီဒီယို ရွေးမယ်' : 'ဗီဒီယို ရွေးမယ်'),
        ),
        const SectionTitle('၂။ မြန်မာ SRT'),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.folder_open, size: 18), label: const Text('SRT ဖိုင် ရွေး'))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) {
                  _paste.text = d!.text!;
                  await _useText(d.text!);
                }
              },
              icon: const Icon(Icons.paste, size: 18),
              label: const Text('Clipboard က ထည့်'),
            ),
          ),
        ]),
        if (_hasSrt)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('✓ စာတန်း ${_entries.length} ကြောင်း · နောက်ဆုံး ${formatTime(lastEnd)}${_bad > 0 ? ' · ဖတ်မရတာ $_bad' : ''}', style: const TextStyle(fontSize: 13, color: DfColors.ok)),
          ),
        if (tooLong)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('⚠ SRT က ဗီဒီယိုထက် ရှည်နေတယ်။ ဗီဒီယိုနဲ့ ကိုက်တဲ့ SRT လားစစ်ပါ။', style: TextStyle(color: DfColors.warn, fontSize: 12.5)),
          ),
        const SectionTitle('၃။ အသံ'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _keepSound,
          onChanged: (v) => setState(() {
            _keepSound = v;
            _prepared = 0;
          }),
          title: const Text('မူရင်းဗီဒီယိုရဲ့ အသံ ထည့်မယ်'),
          subtitle: const Text('ပိတ်ရင် အသံမပါဘဲ ထွက်မယ်'),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: (!p.hasVideo || !_hasSrt || _busy) ? null : () => _prepare(p),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('ပြင်ဆင်မယ်'),
        ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13)),
          ),
        if (_prepared > 0) ...[
          const SectionTitle('၄။ ဗီဒီယို ထုတ်'),
          const Text('Ratio (9:16 စသည်)၊ Platform preset၊ ၈ စက္ကန့် စမ်းထုတ်တာတွေလည်း ဒီမှာ ရွေးလို့ရတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          RenderPanel(key: ValueKey('quick-render-$_prepared'), project: p),
          const SectionTitle('၅။ Gallery ထဲ သိမ်း'),
          SavePanel(key: ValueKey('quick-save-$_prepared'), project: p),
        ],
      ]),
    );
  }
}
