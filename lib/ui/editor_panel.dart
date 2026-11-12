import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/srt.dart';
import '../core/stage.dart';
import '../core/subtitle_ops.dart';
import '../core/theme.dart';
import '../core/sub_presets.dart';
import '../core/timeline.dart';
import '../data/audio_clip.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../data/segment_repo.dart';
import '../platform/audio_channel.dart';
import '../state/project_store.dart';
import 'subtitle_studio_screen.dart';

/// Stage 4: arrange the video pieces, narration, music and subtitles.
/// This only writes an edit description. The original video is never changed;
/// the next stage (Phase 7) renders the description into a new file.
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key, required this.project});

  final Project project;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  final _repo = HandoffRepo();
  final _segRepo = SegmentRepo();
  final _audioRepo = AudioRepo();

  bool _loading = true;
  Timeline _tl = const Timeline();
  List<SrtEntry> _subs = [];
  String? _msg;
  String? _error;

  VideoPlayerController? _vc;
  String? _previewError;
  int? _playingPiece;
  bool _playAll = false;
  bool _switching = false;
  int _posMs = 0;

  int get _pid => widget.project.id!;
  int get _sourceMs => widget.project.videoDurationMs ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vc?.removeListener(_tick);
    _vc?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _tl = Timeline.decode(await _repo.getDoc(_pid, DocKind.timeline));
      final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
      final src = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
      _subs = src == null ? [] : parseSrt(src).entries;
    } catch (e) {
      _error = 'ဖတ်လို့မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _set(Timeline t, {String? msg}) async {
    setState(() {
      _tl = t;
      _msg = msg;
      _error = null;
    });
    try {
      await _repo.setDoc(_pid, DocKind.timeline, t.encode());
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းလို့မရပါ: $e');
    }
  }

  // ---- preview ----

  Future<bool> _ensurePlayer() async {
    if (_vc != null) return true;
    final uri = widget.project.sourceVideoUri;
    if (uri == null) return false;
    try {
      final c = VideoPlayerController.contentUri(Uri.parse(uri));
      await c.initialize();
      c.addListener(_tick);
      if (!mounted) {
        await c.dispose();
        return false;
      }
      setState(() {
        _vc = c;
        _previewError = null;
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _previewError = 'ဒီဗီဒီယိုကို ဖုန်းထဲမှာ preview မပြနိုင်ပါ။ ပြင်ဆင်တာတော့ ရပါတယ်။ ($e)');
      return false;
    }
  }

  void _tick() {
    final c = _vc;
    if (c == null || !mounted) return;
    final pos = c.value.position.inMilliseconds;
    final i = _playingPiece;
    if (i != null && !_switching && c.value.isPlaying && i < _tl.pieces.length && pos >= _tl.pieces[i].endMs) {
      if (_playAll && i + 1 < _tl.pieces.length) {
        _playPiece(i + 1, all: true);
      } else {
        c.pause();
        _playingPiece = null;
      }
    }
    setState(() => _posMs = pos);
  }

  Future<void> _playPiece(int i, {bool all = false}) async {
    if (i < 0 || i >= _tl.pieces.length) return;
    if (!await _ensurePlayer()) return;
    final c = _vc!;
    _switching = true;
    _playAll = all;
    _playingPiece = i;
    await c.seekTo(Duration(milliseconds: _tl.pieces[i].startMs));
    await c.play();
    _switching = false;
  }

  Future<void> _stopPlayback() async {
    _playingPiece = null;
    await _vc?.pause();
    if (mounted) setState(() {});
  }

  String? get _currentSubtitle {
    for (final e in _subs) {
      if (_posMs >= e.startMs && _posMs < e.endMs) return e.text;
    }
    return null;
  }

  // ---- pieces ----

  Future<void> _fromIndex() async {
    final segs = await _segRepo.load(_pid);
    if (segs.isEmpty) {
      setState(() => _error = 'Video Index မှာ အပိုင်း မရှိသေးပါ။ အဆင့် ၁ မှာ အရင်ခွဲပါ');
      return;
    }
    if (_tl.pieces.isNotEmpty) {
      final ok = await _confirm('Video Index က ပြန်ယူမလား?', 'လက်ရှိ အပိုင်းတွေ အစားထိုးမယ်။');
      if (ok != true) return;
    }
    await _set(_tl.copyWith(pieces: piecesFromSegments(segs)), msg: 'အပိုင်း ${segs.length} ခု ထည့်ပြီး');
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('လုပ်မယ်')),
          ],
        ),
      );

  Future<({int s, int e})?> _askRange(int s0, int e0) async {
    final a = TextEditingController(text: formatSrtTime(s0));
    final b = TextEditingController(text: formatSrtTime(e0));
    String? err;
    final r = await showDialog<({int s, int e})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('အပိုင်း အချိန်'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: a, decoration: const InputDecoration(labelText: 'စချိန် (မူရင်းဗီဒီယိုထဲက)')),
            const SizedBox(height: 8),
            TextField(controller: b, decoration: const InputDecoration(labelText: 'ဆုံးချိန်')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: DfColors.danger, fontSize: 13))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်ဘူး')),
            FilledButton(
              onPressed: () {
                final s = parseSrtTime(a.text);
                final e = parseSrtTime(b.text);
                if (s == null || e == null) {
                  set(() => err = 'အချိန်ပုံစံ မမှန်ပါ (00:01:02,500)');
                } else if (e <= s) {
                  set(() => err = 'ဆုံးချိန်က စချိန်ထက် နောက်ကျရမယ်');
                } else if (_sourceMs > 0 && e > _sourceMs) {
                  set(() => err = 'ဗီဒီယိုအရှည် (${formatSrtTime(_sourceMs)}) ထက် မကျော်ရပါ');
                } else {
                  Navigator.pop(ctx, (s: s, e: e));
                }
              },
              child: const Text('အတည်ပြု'),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  Future<void> _editPiece(int i) async {
    final p = _tl.pieces[i];
    final r = await _askRange(p.startMs, p.endMs);
    if (r == null) return;
    final next = trimPiece(_tl.pieces, i, r.s, r.e, _sourceMs > 0 ? _sourceMs : r.e);
    if (next != null) await _set(_tl.copyWith(pieces: next), msg: 'အပိုင်း ${i + 1} ပြင်ပြီး');
  }

  Future<void> _addPiece() async {
    final last = _tl.pieces.isEmpty ? 0 : _tl.pieces.last.endMs;
    final end = _sourceMs > 0 ? (last + 60000 > _sourceMs ? _sourceMs : last + 60000) : last + 60000;
    final r = await _askRange(last, end);
    if (r == null) return;
    await _set(_tl.copyWith(pieces: [..._tl.pieces, VideoPiece(r.s, r.e)]), msg: 'အပိုင်းအသစ် ထည့်ပြီး');
  }

  Future<void> _splitHere(int i) async {
    final c = _vc;
    if (c == null) {
      setState(() => _error = 'ခွဲချင်တဲ့နေရာကို ▶ နဲ့ ဖွင့်ပြီး ရပ်လိုက်ပါ၊ ပြီးမှ ✂ ကို နှိပ်ပါ');
      return;
    }
    final at = c.value.position.inMilliseconds;
    final next = splitPiece(_tl.pieces, i, at);
    if (identical(next, _tl.pieces)) {
      setState(() => _error = 'ဒီနေရာမှာ ခွဲလို့မရပါ (အစ/အဆုံးနဲ့ နီးလွန်း သို့မဟုတ် အပိုင်းအပြင်ဘက်)');
      return;
    }
    await _stopPlayback();
    await _set(_tl.copyWith(pieces: next), msg: 'ခွဲပြီး');
  }

  // ---- voice, music, subtitles ----

  Future<void> _voicesFromStage3() async {
    final clips = await _audioRepo.forProject(_pid);
    if (clips.isEmpty) {
      setState(() => _error = 'အဆင့် ၃ မှာ အသံ မရှိသေးပါ');
      return;
    }
    // One clip per script chunk: the newest one wins.
    final byChunk = <int, AudioClip>{};
    for (final c in clips) {
      byChunk[c.chunkIdx] = c;
    }
    final keys = byChunk.keys.toList()..sort();
    final items = [
      for (final k in keys)
        VoiceItem(source: byChunk[k]!.source, label: byChunk[k]!.label, durationMs: byChunk[k]!.durationMs, offsetMs: 0),
    ];
    await _set(_tl.copyWith(voices: placeVoicesInSequence(items)), msg: 'အသံ ${items.length} ခု အစဉ်လိုက် ထည့်ပြီး');
  }

  Future<double?> _askSeconds(String title, double initial) async {
    final c = TextEditingController(text: initial.toString());
    final r = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          decoration: const InputDecoration(labelText: 'စက္ကန့်'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်ဘူး')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
              if (v != null) Navigator.pop(ctx, v);
            },
            child: const Text('အတည်ပြု'),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _voiceOffset(int i) async {
    final v = await _askSeconds('အသံစမယ့် အချိန် (စက္ကန့်)', _tl.voices[i].offsetMs / 1000);
    if (v == null || v < 0) return;
    final list = [..._tl.voices];
    list[i] = list[i].copyWith(offsetMs: (v * 1000).round());
    await _set(_tl.copyWith(voices: list));
  }

  Future<void> _pickMusic() async {
    try {
      final f = await AudioChannel.pickAudio();
      if (f == null) return;
      await _set(
        _tl.copyWith(music: MusicTrack(source: f.source, name: f.name, durationMs: f.durationMs)),
        msg: 'Music ထည့်ပြီး',
      );
    } catch (e) {
      setState(() => _error = 'Music ယူလို့မရပါ: $e');
    }
  }

  Future<void> _pickLogo() async {
    try {
      final path = await AudioChannel.pickImage();
      if (path == null) return;
      final old = _tl.logo;
      await _set(_tl.copyWith(logo: (old ?? const LogoItem(path: '')).copyWith(path: path)), msg: 'Logo ထည့်ပြီး');
    } catch (e) {
      setState(() => _error = 'ပုံယူလို့မရပါ: $e');
    }
  }

  Future<void> _editCorner(int? i) async {
    final r = await showDialog<CornerText>(
      context: context,
      builder: (_) => _CornerDialog(initial: i == null ? const CornerText(text: '') : _tl.corners[i]),
    );
    if (r == null || r.text.trim().isEmpty) return;
    final list = [..._tl.corners];
    if (i == null) {
      list.add(r);
    } else {
      list[i] = r;
    }
    await _set(_tl.copyWith(corners: list));
  }

  Future<void> _subOffset() async {
    final v = await _askSeconds('စာတန်း အချိန်ရွှေ့ (စက္ကန့်၊ + နောက်ကျ / − စော)', _tl.subtitleOffsetMs / 1000);
    if (v == null) return;
    await _set(_tl.copyWith(subtitleOffsetMs: (v * 1000).round()));
  }

  Future<void> _markDone() async {
    final errors = checkTimeline(_tl, sourceMs: _sourceMs).where((i) => i.severity == Severity.error);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.first.message);
      return;
    }
    final store = context.read<ProjectStore>();
    final p = store.current;
    if (p != null) await store.setStageDone(p, Stage.edit, true);
    if (mounted) setState(() => _msg = 'Editor အဆင့် ပြီးကြောင်း မှတ်ပြီး');
  }

  // ---- build ----

  String _t(int ms) => formatSrtTime(ms).substring(0, 8);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    if (!widget.project.hasVideo) {
      return const Text('အရင် အဆင့် ၁ မှာ ဗီဒီယို ရွေးပါ။', style: TextStyle(color: DfColors.muted));
    }
    final issues = checkTimeline(_tl, sourceMs: _sourceMs);
    final remapped = remapSubtitles(_subs, _tl.pieces, offsetMs: _tl.subtitleOffsetMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။ ဒီမှာ ရွေးထားတာတွေက "ဘယ်လိုထုတ်မလဲ" ဆိုတဲ့ စာရင်းပဲ။ တကယ်ထုတ်တာ အဆင့် ၅ (Render) မှာပါ။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_msg != null || _error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_error != null ? DfColors.danger : DfColors.ok).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error ?? _msg!, style: const TextStyle(fontSize: 13)),
          ),
        _preview(),
        _title('၁။ ဗီဒီယို အပိုင်းများ · ${_t(_tl.videoMs)}'),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _fromIndex, child: const Text('Video Index က ယူ')),
          OutlinedButton(onPressed: _addPiece, child: const Text('+ အပိုင်း')),
          if (_tl.pieces.length > 1)
            FilledButton.tonal(onPressed: () => _playPiece(0, all: true), child: const Text('အကုန် ▶')),
        ]),
        for (var i = 0; i < _tl.pieces.length; i++) _pieceRow(i),
        const SizedBox(height: 12),
        _title('၂။ အသံ (narration) · ${_tl.voices.length} ခု'),
        OutlinedButton(onPressed: _voicesFromStage3, child: const Text('အဆင့် ၃ က အသံတွေ အစဉ်လိုက်ထည့်')),
        for (var i = 0; i < _tl.voices.length; i++) _voiceRow(i),
        const SizedBox(height: 12),
        _title('၃။ Background music'),
        if (_tl.music == null)
          OutlinedButton(onPressed: _pickMusic, child: const Text('Music ရွေး'))
        else ...[
          Text('${_tl.music!.name} · ${_t(_tl.music!.durationMs)}', style: const TextStyle(fontSize: 13)),
          _slider('Music အသံ', _tl.music!.volume, (v) => _set(_tl.copyWith(music: _tl.music!.copyWith(volume: v)))),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('တိုရင် ထပ်ဖွင့်'),
            value: _tl.music!.loop,
            onChanged: (v) => _set(_tl.copyWith(music: _tl.music!.copyWith(loop: v))),
          ),
          TextButton(onPressed: () => _set(_tl.copyWith(clearMusic: true)), child: const Text('Music ဖျက်')),
        ],
        const SizedBox(height: 12),
        _title('၄။ စာတန်း'),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('ဗီဒီယိုထဲ ထည့်ရိုက်'),
          subtitle: Text(_subs.isEmpty ? 'SRT မရှိသေးပါ' : 'ဖြတ်ပြီးနောက် စာတန်း ${remapped.length} ကြောင်း (မူရင်း ${_subs.length})', style: const TextStyle(fontSize: 12)),
          value: _tl.burnSubtitles,
          onChanged: (v) => _set(_tl.copyWith(burnSubtitles: v)),
        ),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _subOffset, child: Text('အချိန်ရွှေ့ (${_tl.subtitleOffsetMs / 1000} စက္ကန့်)')),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubtitleStudioScreen(project: widget.project))).then((_) => _load()),
            child: const Text('Subtitle Studio'),
          ),
        ]),
        const SizedBox(height: 12),
        _title('စာတန်း style'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final pr in subPresets)
            ChoiceChip(
              label: Text(pr.label, style: const TextStyle(fontSize: 12.5)),
              selected: matchingPreset(_tl.style)?.id == pr.id,
              onSelected: (_) => _set(_tl.copyWith(style: pr.style)),
            ),
        ]),
        _slider('အရွယ်', _tl.style.size, (v) => _set(_tl.copyWith(style: _tl.style.copyWith(size: v))), min: 0.03, max: 0.09),
        _ColorRow(selected: _tl.style.color, onPick: (c) => _set(_tl.copyWith(style: _tl.style.copyWith(color: c)))),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('အမည်းနောက်ခံ'),
          value: _tl.style.background,
          onChanged: (v) => _set(_tl.copyWith(style: _tl.style.copyWith(background: v))),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('အပေါ်မှာ ထား (မဟုတ်ရင် အောက်)'),
          value: _tl.style.top,
          onChanged: (v) => _set(_tl.copyWith(style: _tl.style.copyWith(top: v))),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('စာတန်း fade in/out'),
          value: _tl.style.fade,
          onChanged: (v) => _set(_tl.copyWith(style: _tl.style.copyWith(fade: v))),
        ),
        const SizedBox(height: 12),
        _title('Logo (ကိုယ်ပိုင်ပုံ)'),
        if (_tl.logo == null)
          OutlinedButton(onPressed: _pickLogo, child: const Text('Logo ရွေး'))
        else ...[
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(_tl.logo!.path), width: 44, height: 44, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
            const SizedBox(width: 10),
            TextButton(onPressed: _pickLogo, child: const Text('ပြောင်း')),
            TextButton(onPressed: () => _set(_tl.copyWith(clearLogo: true)), child: const Text('ဖျက်')),
          ]),
          _CornerPicker(selected: _tl.logo!.corner, onPick: (c) => _set(_tl.copyWith(logo: _tl.logo!.copyWith(corner: c)))),
          _slider('အရွယ်', _tl.logo!.size, (v) => _set(_tl.copyWith(logo: _tl.logo!.copyWith(size: v))), min: 0.05, max: 0.4),
          _slider('ထင်ရှားမှု', _tl.logo!.opacity, (v) => _set(_tl.copyWith(logo: _tl.logo!.copyWith(opacity: v))), min: 0.1, max: 1),
        ],
        const SizedBox(height: 12),
        _title('ထောင့်စာတမ်း · ${_tl.corners.length} ခု'),
        OutlinedButton(onPressed: () => _editCorner(null), child: const Text('+ စာတမ်းထည့်')),
        for (var i = 0; i < _tl.corners.length; i++)
          Card(
            color: DfColors.surface,
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              dense: true,
              onTap: () => _editCorner(i),
              title: Text(_tl.corners[i].text, style: TextStyle(color: Color(_tl.corners[i].color))),
              subtitle: Text(const ['ဘယ်အပေါ်', 'ညာအပေါ်', 'ဘယ်အောက်', 'ညာအောက်'][_tl.corners[i].corner.index], style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _set(_tl.copyWith(corners: [..._tl.corners]..removeAt(i))),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _title('၅။ မူရင်းဗီဒီယို အသံ'),
        _slider('အသံ', _tl.originalVolume, (v) => _set(_tl.copyWith(originalVolume: v))),
        const SizedBox(height: 12),
        _title('စစ်ဆေးချက်'),
        if (issues.isEmpty)
          const Text('ပြဿနာ မတွေ့ပါ ✓', style: TextStyle(color: DfColors.ok, fontSize: 13))
        else
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${i.severity == Severity.error ? '✗' : '⚠'} ${i.message}',
                style: TextStyle(fontSize: 13, color: i.severity == Severity.error ? DfColors.danger : DfColors.warn),
              ),
            ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _markDone, child: const Text('Editor ပြီးပြီ')),
      ],
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
      );

  Widget _slider(String label, double v, ValueChanged<double> onEnd, {double min = 0, double max = 1}) =>
      _Vol(label: label, value: v, onEnd: onEnd, min: min, max: max);

  Widget _preview() {
    final c = _vc;
    if (_previewError != null) {
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_previewError!, style: const TextStyle(color: DfColors.warn, fontSize: 13)));
    }
    if (c == null) return const SizedBox.shrink();
    final sub = _currentSubtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(alignment: Alignment.bottomCenter, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio, child: VideoPlayer(c)),
        ),
        if (sub != null && _tl.burnSubtitles)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filledTonal(onPressed: _stopPlayback, icon: const Icon(Icons.pause), tooltip: 'ရပ်'),
        ),
      ]),
    );
  }

  Widget _pieceRow(int i) {
    final p = _tl.pieces[i];
    final playing = _playingPiece == i;
    return Card(
      color: playing ? DfColors.accent.withValues(alpha: 0.12) : DfColors.surface,
      margin: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(children: [
          Text('${i + 1}', style: const TextStyle(color: DfColors.muted)),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _editPiece(i),
              child: Text('${_t(p.startMs)} → ${_t(p.endMs)}\nအရှည် ${_t(p.lengthMs)} · edit မှာ ${_t(pieceStartOnTimeline(_tl.pieces, i))}', style: const TextStyle(fontSize: 13)),
            ),
          ),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _playPiece(i), icon: const Icon(Icons.play_arrow)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Zoom',
            onPressed: () => _set(_tl.copyWith(pieces: setZoom(_tl.pieces, i, ZoomMode.values[(p.zoom.index + 1) % ZoomMode.values.length])), msg: 'Zoom: ${const ['မရှိ', 'ဆွဲချဲ့ (in)', 'ပြန်ချုံ့ (out)'][(p.zoom.index + 1) % 3]}'),
            icon: Icon(p.zoom == ZoomMode.zoomIn ? Icons.zoom_in : p.zoom == ZoomMode.zoomOut ? Icons.zoom_out : Icons.crop_free, size: 18, color: p.zoom == ZoomMode.none ? null : DfColors.accent),
          ),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _splitHere(i), icon: const Icon(Icons.content_cut, size: 18)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => _set(_tl.copyWith(pieces: movePiece(_tl.pieces, i, -1))), icon: const Icon(Icons.arrow_upward, size: 18)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: i == _tl.pieces.length - 1 ? null : () => _set(_tl.copyWith(pieces: movePiece(_tl.pieces, i, 1))), icon: const Icon(Icons.arrow_downward, size: 18)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _set(_tl.copyWith(pieces: removePiece(_tl.pieces, i))), icon: const Icon(Icons.close, size: 18)),
        ]),
      ),
    );
  }

  Widget _voiceRow(int i) {
    final v = _tl.voices[i];
    return Card(
      color: DfColors.surface,
      margin: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => _voiceOffset(i),
                child: Text('${v.label} · ${_t(v.offsetMs)} → ${_t(v.endMs)}', style: const TextStyle(fontSize: 13)),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _set(_tl.copyWith(voices: [..._tl.voices]..removeAt(i))),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          _slider('အသံ', v.volume, (x) {
            final list = [..._tl.voices];
            list[i] = v.copyWith(volume: x);
            _set(_tl.copyWith(voices: list));
          }),
        ]),
      ),
    );
  }
}

/// A volume slider that moves smoothly while dragging and saves once, when
/// the finger lifts.
class _Vol extends StatefulWidget {
  const _Vol({required this.label, required this.value, required this.onEnd, this.min = 0, this.max = 1});

  final String label;
  final double value;
  final ValueChanged<double> onEnd;
  final double min;
  final double max;

  @override
  State<_Vol> createState() => _VolState();
}

class _VolState extends State<_Vol> {
  late double _v = widget.value.clamp(widget.min, widget.max);

  @override
  void didUpdateWidget(_Vol old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.clamp(widget.min, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 84, child: Text(widget.label, style: const TextStyle(fontSize: 13))),
      Expanded(child: Slider(value: _v, min: widget.min, max: widget.max, onChanged: (x) => setState(() => _v = x), onChangeEnd: widget.onEnd)),
      Text('${(_v * 100).round()}%', style: const TextStyle(fontSize: 12, color: DfColors.muted)),
    ]);
  }
}

const _palette = <int>[0xFFFFFFFF, 0xFFFFE066, 0xFF7CFC9A, 0xFF66E0FF, 0xFFFF8AD8, 0xFFFFA94D, 0xFFFF5C5C, 0xFF000000];

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(spacing: 10, children: [
        for (final c in _palette)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? DfColors.accent : DfColors.line, width: c == selected ? 3 : 1),
              ),
            ),
          ),
      ]),
    );
  }
}

class _CornerPicker extends StatelessWidget {
  const _CornerPicker({required this.selected, required this.onPick});

  final Corner selected;
  final ValueChanged<Corner> onPick;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Corner>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: Corner.topLeft, label: Text('↖')),
        ButtonSegment(value: Corner.topRight, label: Text('↗')),
        ButtonSegment(value: Corner.bottomLeft, label: Text('↙')),
        ButtonSegment(value: Corner.bottomRight, label: Text('↘')),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onPick(s.first),
    );
  }
}

class _CornerDialog extends StatefulWidget {
  const _CornerDialog({required this.initial});

  final CornerText initial;

  @override
  State<_CornerDialog> createState() => _CornerDialogState();
}

class _CornerDialogState extends State<_CornerDialog> {
  late final _text = TextEditingController(text: widget.initial.text);
  late Corner _corner = widget.initial.corner;
  late int _color = widget.initial.color;
  late double _size = widget.initial.size;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ထောင့်စာတမ်း'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _text, decoration: const InputDecoration(hintText: 'ဥပမာ: translate by brutal knock out')),
          const SizedBox(height: 10),
          _CornerPicker(selected: _corner, onPick: (c) => setState(() => _corner = c)),
          _ColorRow(selected: _color, onPick: (c) => setState(() => _color = c)),
          Row(children: [
            const Text('အရွယ်', style: TextStyle(fontSize: 13)),
            Expanded(child: Slider(value: _size, min: 0.02, max: 0.08, onChanged: (v) => setState(() => _size = v))),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်ဘူး')),
        FilledButton(
          onPressed: () => Navigator.pop(context, CornerText(text: _text.text.trim(), corner: _corner, color: _color, size: _size)),
          child: const Text('အတည်ပြု'),
        ),
      ],
    );
  }
}
