import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/srt.dart';
import '../core/stage.dart';
import '../core/subtitle_ops.dart';
import '../core/te_compile.dart';
import '../core/te_preview.dart';
import '../core/theme.dart';
import '../core/sub_presets.dart';
import '../core/timeline.dart';
import '../core/transformative_plan.dart';
import '../core/voice_fit.dart';
import '../data/audio_clip.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../data/segment_repo.dart';
import '../platform/audio_channel.dart';
import '../state/project_store.dart';
import 'subtitle_studio_screen.dart';
import 'te_dialogs.dart';
import 'te_inline_editor.dart';
import 'te_ops_section.dart';
import 'te_shapes.dart';
import 'te_timeline.dart';
import 'widgets.dart';

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
  TransformativePlan _plan = const TransformativePlan();
  Future<bool>? _initFuture;
  String? _selId;
  TransformativePlan _basePlan = const TransformativePlan();
  final List<TransformativePlan> _undo = [];
  final List<TransformativePlan> _redo = [];
  CropFrame? _cropStart;
  double _curSpeed = 1.0;
  Offset _cropFocal0 = Offset.zero;

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
      _plan = TransformativePlan.decode(await _repo.getDoc(_pid, DocKind.transformativePlan));
      _basePlan = _plan;
    } catch (e) {
      _error = 'ဖတ်လို့မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
    // Show the first frame right away so effects can be previewed without pressing play.
    if (mounted && widget.project.hasVideo) _ensurePlayer();
  }

  /// Every change to the TE plan is saved at once (no separate save button).
  Future<void> _setPlan(TransformativePlan p, {bool record = true}) async {
    // Undo history: one step per saved change of the effect list (typing in the
    // instructions box does not count).
    String key(TransformativePlan x) => jsonEncode([for (final o in x.ops) o.toJson()]);
    if (record && key(p) != key(_basePlan)) {
      _undo.add(_basePlan);
      if (_undo.length > 50) _undo.removeAt(0);
      _redo.clear();
    }
    _basePlan = p;
    setState(() {
      _plan = p;
      _error = null;
      if (_selId != null && !p.ops.any((o) => o.id == _selId)) _selId = null;
    });
    try {
      await _repo.setDoc(_pid, DocKind.transformativePlan, p.encode());
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းလို့မရပါ: $e');
    }
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

  Future<bool> _ensurePlayer() {
    if (_vc != null) return Future.value(true);
    return _initFuture ??= _initPlayer().then((ok) {
      if (!ok) _initFuture = null;
      return ok;
    });
  }

  Future<bool> _initPlayer() async {
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
    // Speed operations: play the preview at that speed while the playhead is inside one.
    final sp = previewSpeed(_plan.ops, pos);
    if (sp != _curSpeed) {
      _curSpeed = sp;
      c.setPlaybackSpeed(sp).catchError((Object _) {});
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

  Future<void> _seek(int ms) async {
    if (!await _ensurePlayer()) return;
    final c = _vc!;
    final dur = c.value.duration.inMilliseconds;
    final to = ms < 0 ? 0 : (dur > 0 && ms > dur ? dur : ms);
    await c.seekTo(Duration(milliseconds: to));
    if (mounted) setState(() => _posMs = to);
  }

  Future<void> _togglePlay() async {
    if (!await _ensurePlayer()) return;
    final c = _vc!;
    if (c.value.isPlaying) {
      await _stopPlayback();
      return;
    }
    _playingPiece = null;
    _playAll = false;
    final dur = c.value.duration.inMilliseconds;
    if (dur > 0 && c.value.position.inMilliseconds >= dur - 200) await c.seekTo(Duration.zero);
    await c.play();
    if (mounted) setState(() {});
  }

  Future<void> _undoOp() async {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    _redo.add(_basePlan);
    await _setPlan(prev.copyWith(instructions: _plan.instructions), record: false);
  }

  Future<void> _redoOp() async {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _undo.add(_basePlan);
    await _setPlan(next.copyWith(instructions: _plan.instructions), record: false);
  }

  Future<void> _addViaDialog(TransformTool tool) async {
    final s = _posMs / 1000;
    final op = await showDialog<TransformOp>(context: context, builder: (_) => TeOpDialog(tool: tool, startSec: s, endSec: s + 5));
    if (op == null) return;
    setState(() => _selId = op.id);
    await _setPlan(_plan.copyWith(ops: [..._plan.ops, op]));
  }

  TransformOp? get _selected {
    final id = _selId;
    if (id == null) return null;
    return _plan.ops.where((o) => o.id == id).firstOrNull;
  }

  /// Slider moves change the plan in memory (the preview follows at once);
  /// [save] writes it.
  void _changeOp(TransformOp o, bool save) {
    if (save) {
      _setPlan(_plan.replaceOp(o));
    } else {
      setState(() => _plan = _plan.replaceOp(o));
    }
  }

  Future<void> _selectedDetails(TransformOp o) async {
    final next = await showDialog<TransformOp>(context: context, builder: (_) => TeOpDialog(initial: o));
    if (next != null) _setPlan(_plan.replaceOp(next));
  }

  /// One tap adds an effect at the playhead with sensible values and selects
  /// it, so it can be adjusted right under the preview.
  void _quickAdd(TransformTool tool, {String kind = '', String text = ''}) {
    final pos = _posMs < 0 ? 0 : _posMs;
    final vd = _vc?.value.duration.inMilliseconds ?? 0;
    final dur = vd > 0 ? vd : _sourceMs;
    final end = dur > 0 && pos + 5000 > dur ? dur : pos + 5000;
    Map<String, Object?> params;
    var e = end;
    switch (tool) {
      case TransformTool.cropReframe:
        params = {'zoom': 1.5, 'cx': 0.5, 'cy': 0.5};
      case TransformTool.colorGrade:
        params = {'brightness': 0.15, 'contrast': 0.0};
      case TransformTool.speedChange:
        params = {'speed': 2.0};
      case TransformTool.blur:
        params = {'strength': 10.0};
      case TransformTool.mirrorFlip:
        params = {'horizontal': true, 'vertical': false};
      case TransformTool.freezeFrame:
        params = {'hold': 3.0};
        e = pos;
      case TransformTool.motionGraphics:
        params = switch (kind) {
          'arrow' => {'kind': 'arrow', 'x': 0.5, 'y': 0.5, 'size': 0.08, 'color': 0xFFFF5252, 'angle': 90.0},
          'box' => {'kind': 'box', 'x': 0.5, 'y': 0.5, 'size': 0.4, 'ar': 0.5, 'color': 0xFFFF5252},
          'circle' => {'kind': 'circle', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'ar': 1.0, 'color': 0xFFFFEB3B},
          'spot' => {'kind': 'spot', 'x': 0.5, 'y': 0.5, 'size': 0.45, 'ar': 0.6, 'round': true, 'color': 0xFF000000},
          'frame' => {'kind': 'frame', 'x': 0.5, 'y': 0.5, 'size': 0.012, 'color': 0xFFFFFFFF, 'grad': true},
          'fadein' => {'kind': 'fade', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 0xFF000000, 'dir': 'in'},
          'fadeout' => {'kind': 'fade', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 0xFF000000, 'dir': 'out'},
          'flash' => {'kind': 'fade', 'x': 0.5, 'y': 0.5, 'size': 0.5, 'color': 0xFFFFFFFF, 'dir': 'dip'},
          'tint' => {'kind': 'tint', 'x': 0.5, 'y': 0.5, 'size': 0.2, 'color': 0xFFFF9800},
          'vignette' => {'kind': 'vignette', 'x': 0.5, 'y': 0.5, 'size': 0.6, 'color': 0xFF000000},
          'bars' => {'kind': 'bars', 'x': 0.5, 'y': 0.5, 'size': 0.1, 'color': 0xFF000000},
          'blurbox' => {'kind': 'blurBox', 'x': 0.5, 'y': 0.5, 'size': 0.3, 'ar': 0.5, 'strength': 30.0, 'color': 0xFFFFFFFF},
          'shade' => {'kind': 'shade', 'x': 0.5, 'y': 0.5, 'size': 0.4, 'color': 0xFF000000, 'top': false},
          'sticker' => {'kind': 'label', 'x': 0.5, 'y': 0.5, 'size': 0.12, 'color': 0xFFFFFFFF, 'text': text, 'bg': false},
          _ => {'kind': 'label', 'x': 0.5, 'y': 0.15, 'size': 0.06, 'color': 0xFFFFEB3B, 'text': 'စာသား', 'bg': true},
        };
        if (_wholeVideo.contains(kind)) e = dur > 0 ? dur : pos + 5000;
        if (kind == 'fadein' || kind == 'fadeout') e = pos + 1000;
        if (kind == 'flash') e = pos + 400;
      default:
        params = const {};
    }
    final op = TransformOp(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      tool: tool,
      startMs: _wholeVideo.contains(kind) ? 0 : pos,
      endMs: e < pos ? pos : e,
      params: params,
      status: OpStatus.approved,
    );
    setState(() => _selId = op.id);
    _setPlan(_plan.copyWith(ops: [..._plan.ops, op]));
  }

  static const _wholeVideo = {'frame', 'vignette', 'tint', 'bars', 'shade'};

  Future<void> _stickers() async {
    const emojis = ['👉', '👆', '👇', '🔥', '❗', '❓', '😱', '😂', '😭', '😡', '👀', '💔', '✅', '❌', '⭐', '💯', '🤔', '😲', '👍', '🙏'];
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DfColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 14, runSpacing: 14, children: [
            for (final e in emojis) InkWell(onTap: () => Navigator.pop(ctx, e), child: Text(e, style: const TextStyle(fontSize: 34))),
          ]),
        ),
      ),
    );
    if (pick != null) _quickAdd(TransformTool.motionGraphics, kind: 'sticker', text: pick);
  }

  Widget _toolRow() {
    Widget tool(String label, IconData icon, VoidCallback f) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: f,
          child: SizedBox(
            width: 68,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 24),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 62,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          tool('Text', Icons.title, () => _quickAdd(TransformTool.motionGraphics, kind: 'label')),
          tool('Arrow', Icons.arrow_forward, () => _quickAdd(TransformTool.motionGraphics, kind: 'arrow')),
          tool('Box', Icons.crop_square, () => _quickAdd(TransformTool.motionGraphics, kind: 'box')),
          tool('Circle', Icons.circle_outlined, () => _quickAdd(TransformTool.motionGraphics, kind: 'circle')),
          tool('Spot', Icons.highlight_alt, () => _quickAdd(TransformTool.motionGraphics, kind: 'spot')),
          tool('Border', Icons.border_outer, () => _quickAdd(TransformTool.motionGraphics, kind: 'frame')),
          tool('Sticker', Icons.emoji_emotions_outlined, _stickers),
          tool('Zoom', Icons.zoom_in, () => _quickAdd(TransformTool.cropReframe)),
          tool('Filter', Icons.brightness_6, () => _quickAdd(TransformTool.colorGrade)),
          tool('Speed', Icons.speed, () => _quickAdd(TransformTool.speedChange)),
          tool('Censor', Icons.visibility_off, () => _quickAdd(TransformTool.motionGraphics, kind: 'blurbox')),
          tool('Blur', Icons.blur_on, () => _quickAdd(TransformTool.blur)),
          tool('Flip', Icons.flip, () => _quickAdd(TransformTool.mirrorFlip)),
          tool('Freeze', Icons.pause_circle_outline, () => _quickAdd(TransformTool.freezeFrame)),
          tool('Cut', Icons.content_cut, () => _quickAdd(TransformTool.smartCut)),
          tool('Fade in', Icons.vertical_align_bottom, () => _quickAdd(TransformTool.motionGraphics, kind: 'fadein')),
          tool('Fade out', Icons.vertical_align_top, () => _quickAdd(TransformTool.motionGraphics, kind: 'fadeout')),
          tool('Flash', Icons.flash_on, () => _quickAdd(TransformTool.motionGraphics, kind: 'flash')),
          tool('Tint', Icons.invert_colors, () => _quickAdd(TransformTool.motionGraphics, kind: 'tint')),
          tool('Vignette', Icons.vignette, () => _quickAdd(TransformTool.motionGraphics, kind: 'vignette')),
          tool('Bars', Icons.movie_outlined, () => _quickAdd(TransformTool.motionGraphics, kind: 'bars')),
          tool('Shade', Icons.gradient, () => _quickAdd(TransformTool.motionGraphics, kind: 'shade')),
          tool('Picture', Icons.image_outlined, () => _addViaDialog(TransformTool.pictureInPicture)),
          tool('Sound', Icons.audiotrack, () => _addViaDialog(TransformTool.soundDesign)),
        ]),
      ),
    );
  }

  Widget _transport(int pos, int dur) {
    final c = _vc;
    String clock(int ms) {
      final s = ms / 1000;
      final m = s ~/ 60;
      return '${m.toString().padLeft(2, '0')}:${(s - m * 60).toStringAsFixed(1).padLeft(4, '0')}';
    }

    return Row(children: [
      IconButton(tooltip: 'နောက်ပြန်', onPressed: _undo.isEmpty ? null : _undoOp, icon: const Icon(Icons.undo)),
      IconButton(tooltip: 'ရှေ့ပြန်', onPressed: _redo.isEmpty ? null : _redoOp, icon: const Icon(Icons.redo)),
      Expanded(
        child: Center(
          child: IconButton.filled(
            iconSize: 28,
            onPressed: _togglePlay,
            icon: Icon(c != null && c.value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ),
      ),
      Text('${clock(pos)} / ${clock(dur)}', style: const TextStyle(fontSize: 12.5, color: DfColors.muted)),
      const SizedBox(width: 4),
    ]);
  }

  /// Moving a label/arrow/picture on the preview: updates the plan in memory
  /// while dragging; [_dragEnd] saves it.
  void _dragMotion(String opId, double dx, double dy) {
    final o = _plan.ops.where((e) => e.id == opId).firstOrNull;
    if (o == null) return;
    final x = o.params['x'];
    final y = o.params['y'];
    if (x is! num || y is! num) return;
    final nx = (x + dx).clamp(0.0, 1.0).toDouble();
    final ny = (y + dy).clamp(0.0, 1.0).toDouble();
    setState(() => _plan = _plan.replaceOp(o.copyWith(params: {...o.params, 'x': nx, 'y': ny})));
  }

  Widget _resizeHandle(String opId, double w, double h) {
    return Positioned(
      right: -4,
      bottom: -4,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _selId = opId),
        onPanUpdate: (d) => _resizeMotion(opId, d.delta.dx, d.delta.dy, w),
        onPanEnd: (_) => _dragEnd(opId),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: DfColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        ),
      ),
    );
  }

  /// Dragging the corner handle of a box / circle / spot. The shape is centred
  /// on its point, so one pixel of drag changes the width by two.
  void _resizeMotion(String opId, double dx, double dy, double w) {
    final o = _plan.ops.where((e) => e.id == opId).firstOrNull;
    if (o == null || w <= 0) return;
    final size = o.params['size'];
    final ar = o.params['ar'];
    if (size is! num) return;
    final curW = size * w;
    final curH = curW * (ar is num ? ar.toDouble() : 0.5);
    final nw = (curW + 2 * dx).clamp(w * 0.05, w * 0.95).toDouble();
    final nh = (curH + 2 * dy).clamp(nw * 0.1, nw * 4).toDouble();
    setState(() => _plan = _plan.replaceOp(o.copyWith(params: {...o.params, 'size': nw / w, 'ar': nh / nw})));
  }

  void _dragEnd(String opId) {
    final o = _plan.ops.where((e) => e.id == opId).firstOrNull;
    if (o == null) return;
    double r(Object? v) => double.parse(((v as num).toDouble()).toStringAsFixed(3));
    final fixed = {...o.params};
    for (final k in const ['x', 'y', 'size', 'ar']) {
      if (fixed[k] is num) fixed[k] = r(fixed[k]);
    }
    _setPlan(_plan.replaceOp(o.copyWith(params: fixed)));
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

  Timeline? _beforeFit;

  Future<void> _fitToVoices() async {
    final ok = await _confirm(
      'ဗီဒီယိုကို အသံအတိုင်း ညှိမလား?',
      'ဗီဒီယိုအပိုင်း ၁ ↔ အသံ ၁၊ အပိုင်း ၂ ↔ အသံ ၂ ... အစဉ်လိုက် တွဲမယ်။\n'
      'အပိုင်းတစ်ခုချင်းရဲ့ အဆုံးကို အသံအရှည်အတိုင်း တိုး/လျှော့မယ်၊ အသံကို သူ့အပိုင်းစတဲ့နေရာမှာ စစေမယ်။\n'
      'မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။ ပြီးရင် "နောက်ပြန်" နဲ့ ပြန်ယူလို့ရတယ်။\n\n'
      'အရင်ဆုံး အပိုင်းတွေကို ဇာတ်ဝင်ခန်းအလိုက် ဖြတ်ထားပြီး၊ အသံတစ်ခုချင်း အစဉ်တူဖြစ်နေရမယ်။',
    );
    if (ok != true) return;
    await _stopPlayback();
    final r = fitVideoToVoices(_tl, sourceMs: _sourceMs);
    _beforeFit = _tl;
    await _set(r.timeline, msg: 'အပိုင်း/အသံ ${r.fitted} စုံ ညှိပြီး။${r.notes.isEmpty ? '' : '\n${r.notes.join('\n')}'}');
  }

  Future<void> _undoFit() async {
    final b = _beforeFit;
    if (b == null) return;
    _beforeFit = null;
    await _stopPlayback();
    await _set(b, msg: 'ညှိတာ နောက်ပြန်ပြီး');
  }

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
        const InfoHint(
          'မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။ ဒီမှာ ရွေးထားတာတွေက "ဘယ်လိုထုတ်မလဲ" ဆိုတဲ့ စာရင်းပဲ။ တကယ်ထုတ်တာ အဆင့် ၅ (Render) မှာပါ။ '
          'Preview ကို လိုတဲ့နေရာ ရွှေ့ပြီး effect (ဖြတ်၊ zoom၊ freeze၊ စာသား၊ အသံ …) ထည့်၊ ချက်ချင်းကြည့်၊ ပြင်လို့ရတယ်။',
          label: 'ဘယ်လိုအလုပ်လုပ်လဲ',
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
        _toolRow(),
        TeTimeline(
          durMs: (_vc?.value.duration.inMilliseconds ?? 0) > 0 ? _vc!.value.duration.inMilliseconds : _sourceMs,
          posMs: _posMs,
          playing: _vc?.value.isPlaying ?? false,
          ops: _plan.ops,
          subs: _subs,
          pieces: _tl.pieces,
          selectedId: _selId,
          onSeek: _seek,
          onSelect: (id) => setState(() => _selId = id),
        ),
        if (_selected case final o?)
          TeInlineEditor(
            key: ValueKey(o.id),
            op: o,
            posMs: _posMs,
            onChange: _changeOp,
            onStatus: (st) => _setPlan(_plan.setOpStatus(o.id, st)),
            onDelete: () => _setPlan(_plan.removeOp(o.id)),
            onClose: () => setState(() => _selId = null),
            onDetails: () => _selectedDetails(o),
          ),
        _title('Effect စာရင်း · ${_plan.ops.length} ခု'),
        TeOpsSection(
          project: widget.project,
          plan: _plan,
          posMs: _posMs,
          onPlan: _setPlan,
          onSeek: _seek,
          onSelect: (id) => setState(() => _selId = id),
          selectedId: _selId,
        ),
        const SizedBox(height: 14),
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
        if (_tl.pieces.isNotEmpty && _tl.voices.isNotEmpty)
          Wrap(spacing: 8, children: [
            FilledButton.tonal(onPressed: _fitToVoices, child: const Text('ဗီဒီယိုကို အသံအတိုင်း ညှိ')),
            if (_beforeFit != null) OutlinedButton(onPressed: _undoFit, child: const Text('နောက်ပြန်')),
          ]),
        for (var i = 0; i < _tl.voices.length; i++) _voiceRow(i),
        const SizedBox(height: 12),
        _title('၃။ စာတန်း'),
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
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Music · စာတန်း style · Logo · မူရင်းအသံ', style: TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('၄။ Background music'),
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
              ]),
            ],
          ),
        ),
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
    if (c == null) {
      return const Padding(padding: EdgeInsets.only(bottom: 10), child: SizedBox(height: 160, child: Center(child: CircularProgressIndicator())));
    }
    final ops = _plan.ops;
    final crop = previewCrop(ops, _posMs);
    final look = previewLook(ops, _posMs);
    final blur = previewBlur(ops, _posMs);
    final flip = previewFlip(ops, _posMs);
    final motions = previewMotions(ops, _posMs);
    final badges = previewBadges(ops, _posMs);
    final cutting = opsAt(ops, _posMs).any((o) => o.tool == TransformTool.smartCut);
    final sel = _selected;
    // Crop is edited by pinching/dragging the preview itself, but only while
    // the playhead is inside that effect (that is when the crop is visible).
    final cropEdit = (sel != null && sel.tool == TransformTool.cropReframe && opsAt([sel], _posMs).isNotEmpty) ? sel : null;
    final sub = _currentSubtitle;
    final dur = c.value.duration.inMilliseconds > 0 ? c.value.duration.inMilliseconds : _sourceMs;
    final pos = _posMs < 0 ? 0 : (dur > 0 && _posMs > dur ? dur : _posMs);

    Widget video = VideoPlayer(c);
    if (look != null) video = ColorFiltered(colorFilter: ColorFilter.matrix(lookMatrix(look)), child: video);
    if (crop != null) {
      video = FractionalTranslation(
        translation: Offset((0.5 - crop.cx) * crop.zoom, (0.5 - crop.cy) * crop.zoom),
        child: Transform.scale(scale: crop.zoom, child: video),
      );
    }
    // The preview is smaller than the output, so the blur strength is scaled down (an estimate; the render is the real result).
    if (blur != null) video = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur * 0.4, sigmaY: blur * 0.4), child: video);
    if (flip != null) video = Transform.scale(scaleX: flip.h ? -1.0 : 1.0, scaleY: flip.v ? -1.0 : 1.0, child: video);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: LayoutBuilder(builder: (ctx, bc) {
              final w = bc.maxWidth;
              final h = bc.maxHeight;
              return ClipRect(
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Colors.black),
                  video,
                  if (cropEdit != null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onScaleStart: (d) {
                          _cropStart = previewCrop([cropEdit], _posMs) ?? CropFrame(1.5, 0.5, 0.5);
                          _cropFocal0 = d.focalPoint;
                        },
                        onScaleUpdate: (d) {
                          final st = _cropStart;
                          if (st == null) return;
                          final z = (st.zoom * d.scale).clamp(1.0, 3.0).toDouble();
                          final mv = d.focalPoint - _cropFocal0;
                          final f = CropFrame(z, st.cx - mv.dx / (w * z), st.cy - mv.dy / (h * z)).fitted;
                          double r(double v) => double.parse(v.toStringAsFixed(3));
                          _changeOp(cropEdit.copyWith(params: {...cropEdit.params, 'zoom': r(f.zoom), 'cx': r(f.cx), 'cy': r(f.cy)}), false);
                        },
                        onScaleEnd: (_) {
                          _cropStart = null;
                          final cur = _selected;
                          if (cur != null) _changeOp(cur, true);
                        },
                      ),
                    ),
                  if (cutting) const ColoredBox(color: Color(0x99000000)),
                  for (final m in motions) _motionOverlay(m, w, h),
                  if (sub != null && _tl.burnSubtitles)
                    Align(
                      alignment: _tl.style.top ? Alignment.topCenter : Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(10, _tl.style.top ? 30 : 4, 10, 8),
                        child: Text(
                          sub,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 14, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                        ),
                      ),
                    ),
                  if (badges.isNotEmpty)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final b in badges)
                          Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: DfColors.accentDeep.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
                            child: Text(b, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                          ),
                      ]),
                    ),
                ]),
              );
            }),
          ),
        ),
        _transport(pos, dur),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Preview က နီးစပ်တဲ့ပုံ သက်သက် — တကယ့်ရလဒ်ကို Render မှာ ထုတ်မယ်။ Effect ကို ရွေးရင် အောက်မှာ တန်ဖိုးညှိလို့ရတယ်၊ Zoom ကို preview ပေါ်မှာ ညှပ်ချဲ့/ဆွဲရွှေ့၊ စာသား/မြား/ပုံကို ဆွဲရွှေ့။ အစိမ်း = ခွင့်ပြုပြီး၊ လိမ္မော် = စောင့်ဆိုင်း။',
            style: TextStyle(fontSize: 11.5, color: DfColors.muted),
          ),
        ),
      ]),
    );
  }

  Widget _motionOverlay(PreviewMotion pm, double w, double h) {
    final m = pm.item;
    final Widget child;
    switch (m.kind) {
      case MotionKind.label:
        final fs = (m.size * h).clamp(9.0, 90.0).toDouble();
        child = Container(
          padding: m.gradient ? EdgeInsets.symmetric(horizontal: fs * 0.7, vertical: fs * 0.4) : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: m.gradient
              ? BoxDecoration(gradient: labelGradient, borderRadius: BorderRadius.circular(fs * 0.45), border: Border.all(color: const Color(0xFFFFD54F), width: 1.2))
              : (m.background ? BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)) : null),
          child: Text(
            m.text,
            style: TextStyle(
              color: Color(m.color),
              fontSize: (m.size * h).clamp(9.0, 90.0).toDouble(),
              fontWeight: FontWeight.w700,
              shadows: m.background ? null : const [Shadow(blurRadius: 3, color: Colors.black)],
            ),
          ),
        );
      case MotionKind.arrow:
        child = Transform.rotate(
          angle: m.angle * math.pi / 180,
          child: Icon(Icons.arrow_forward, size: (m.size * h * 2).clamp(18.0, 140.0).toDouble(), color: Color(m.color)),
        );
      case MotionKind.image:
        child = Image.file(
          File(m.path),
          width: m.size * w,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70),
        );
      case MotionKind.box:
      case MotionKind.circle:
        final bw = m.size * w;
        final bh = bw * m.aspect;
        child = SizedBox(
          width: bw,
          height: bh,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: ShapePainter(color: Color(m.color), oval: m.kind == MotionKind.circle, fill: m.fill))),
            if (_selId == pm.opId) _resizeHandle(pm.opId, w, h),
          ]),
        );
      case MotionKind.blurBox:
        // The rectangle shows the real blur of what is behind it (the preview strength is scaled down; the render is the real result).
        final bw = m.size * w;
        final bh = bw * m.aspect;
        final sel = _selId == pm.opId;
        return Positioned(
          left: m.x * w,
          top: m.y * h,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: GestureDetector(
              onTap: () => setState(() => _selId = pm.opId),
              onPanStart: (_) => setState(() => _selId = pm.opId),
              onPanUpdate: (d) => _dragMotion(pm.opId, d.delta.dx / w, d.delta.dy / h),
              onPanEnd: (_) => _dragEnd(pm.opId),
              child: SizedBox(
                width: bw,
                height: bh,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: m.strength * 0.4, sigmaY: m.strength * 0.4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: sel ? DfColors.accent : Colors.white54, width: sel ? 2 : 1)),
                        ),
                      ),
                    ),
                  ),
                  if (sel) _resizeHandle(pm.opId, w, h),
                ]),
              ),
            ),
          ),
        );
      case MotionKind.frame:
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: FramePainter(color: Color(m.color), thick: m.size * math.min(w, h), rainbow: m.gradient)),
          ),
        );
      case MotionKind.fade:
        final a = fadeAlpha(m.dir, pm.startMs, pm.endMs, _posMs);
        return Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(m.color).withValues(alpha: a))));
      case MotionKind.tint:
        return Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(m.color).withValues(alpha: m.size.clamp(0.0, 1.0).toDouble()))));
      case MotionKind.vignette:
        return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: VignettePainter(m.size))));
      case MotionKind.bars:
        return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: BarsPainter(m.size))));
      case MotionKind.shade:
        return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: ShadePainter(frac: m.size, top: m.top))));
      case MotionKind.spot:
        final sw = m.size * w;
        final sh = sw * m.aspect;
        return Positioned.fill(
          child: Stack(clipBehavior: Clip.none, children: [
            IgnorePointer(child: CustomPaint(size: Size.infinite, painter: SpotPainter(cx: m.x * w, cy: m.y * h, hw: sw, hh: sh, oval: m.round))),
            Positioned(
              left: m.x * w - 14,
              top: m.y * h - 14,
              child: GestureDetector(
                onTap: () => setState(() => _selId = pm.opId),
                onPanStart: (_) => setState(() => _selId = pm.opId),
                onPanUpdate: (d) => _dragMotion(pm.opId, d.delta.dx / w, d.delta.dy / h),
                onPanEnd: (_) => _dragEnd(pm.opId),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), shape: BoxShape.circle, border: Border.all(color: DfColors.accent, width: 2)),
                  child: const Icon(Icons.open_with, size: 15, color: DfColors.accentDeep),
                ),
              ),
            ),
            if (_selId == pm.opId)
              Positioned(
                left: m.x * w + sw / 2 - 11,
                top: m.y * h + sh / 2 - 11,
                child: _resizeHandle(pm.opId, w, h),
              ),
          ]),
        );
    }
    return Positioned(
      left: m.x * w,
      top: m.y * h,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () => setState(() => _selId = pm.opId),
          onPanStart: (_) => setState(() => _selId = pm.opId),
          onPanUpdate: (d) => _dragMotion(pm.opId, d.delta.dx / w, d.delta.dy / h),
          onPanEnd: (_) => _dragEnd(pm.opId),
          child: Opacity(
            opacity: pm.proposed ? 0.7 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _selId == pm.opId && m.kind != MotionKind.box && m.kind != MotionKind.circle ? Border.all(color: DfColors.accent, width: 1.5) : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: child,
            ),
          ),
        ),
      ),
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
