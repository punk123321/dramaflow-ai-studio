import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/chunk_export.dart';
import '../core/render_plan.dart';
import '../core/srt.dart';
import '../core/srt_split.dart' show partFileName;
import '../core/stage.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../core/te_compile.dart';
import '../core/transformative_plan.dart';
import '../data/export_item.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/part_saver.dart';
import '../platform/render_channel.dart';
import '../state/project_store.dart';
import '../state/render_store.dart';
import 'colab_render_card.dart';
import 'widgets.dart';

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
  RenderSettings get _eff => _settings.copyWith(sourceBps: sourceBitsPerSecond(widget.project.videoSize, widget.project.videoDurationMs));
  int _free = 0;
  bool _videoOk = true;
  bool _markedDone = false;
  DateTime? _t0; // when the running render was first seen, for the time-left guess

  // Long video made in several files, with a rest between them so the phone can cool down.
  static const _lastKind = 'export_chunks_last';
  int _chunkMin = 0; // 0 = one file
  int _restSec = 120;
  int _fromChunk = 1;
  bool _chunkRunning = false;
  bool _chunkStop = false;
  bool _skipRest = false;
  int _chunkDone = 0;
  int _chunkTotal = 0;
  int _restLeft = 0;
  String? _chunkMsg;
  bool _chunkErr = false;

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
      final uri = widget.project.sourceVideoUri;
      if (uri != null) _videoOk = await RenderChannel.uriReadable(uri);
      final last = await _repo.getDoc(_pid, _lastKind);
      if (last != null && last.isNotEmpty && !_chunkRunning) {
        _chunkMsg = 'အရင်တစ်ခါ: $last';
        _chunkErr = last.contains('ရပ်သွား');
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // The finished video the person already put in the Gallery from this panel, and the last answer.
  String? _galleryName;
  String? _galleryMsg;
  bool _galleryErr = false;
  bool _galleryBusy = false;

  Future<void> _saveToGallery(ExportItem done) async {
    setState(() {
      _galleryBusy = true;
      _galleryMsg = null;
    });
    // keepCopy: the file stays in the Save stage's history too, in case it is wanted again.
    final fail = await PartSaver.toGallery(done, done.name, keepCopy: true);
    if (!mounted) return;
    setState(() {
      _galleryBusy = false;
      _galleryErr = fail != null;
      if (fail == null) _galleryName = done.name;
      _galleryMsg = fail ?? 'Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး ✓';
    });
  }

  Future<void> _idle(RenderStore rs) {
    if (!rs.running) return Future.value();
    final c = Completer<void>();
    void l() {
      if (!rs.running && !c.isCompleted) {
        rs.removeListener(l);
        c.complete();
      }
    }

    rs.addListener(l);
    return c.future;
  }

  /// A rest between two files. The service keeps the app alive (and the notification updated).
  Future<void> _rest() async {
    _skipRest = false;
    for (var left = _restSec; left > 0; left--) {
      if (!mounted || _chunkStop || _skipRest) break;
      setState(() => _restLeft = left);
      if (left == _restSec || left % 15 == 0) {
        await RenderChannel.keepAlive(true, text: 'ဖုန်းအေးအောင် နားနေတယ် ${coolDownText(left)}');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _restLeft = 0);
  }

  Future<void> _saveLast(String text) async {
    try {
      await _repo.setDoc(_pid, _lastKind, text);
    } catch (_) {}
  }

  /// Makes the video in several files, one after another. Each file goes to the Gallery as
  /// soon as it is made (and the app's own copy is removed), and the run stops at the first
  /// failure. Effects that sit on the finished video's time are cut to each file; narration
  /// that crosses a cut cannot be kept and is counted.
  Future<void> _runChunks() async {
    final p = widget.project;
    final rs = context.read<RenderStore>();
    final te = compileOps(_tl.pieces, _plan.ops);
    final full = _tl.copyWith(pieces: te.pieces, voices: [..._tl.voices, ...te.sounds]);
    final ranges = chunkRanges(outputDurationMs(full), _chunkMin * 60000);
    if (ranges.length < 2) {
      await _start();
      return;
    }
    final first = (_fromChunk - 1).clamp(0, ranges.length - 1).toInt();
    final overlaysAll = [for (final o in te.overlays) o.toJson()];
    final splitsAll = [for (final x in te.splits) x.toJson()];
    final censors = [for (final x in te.censors) x.toJson()];
    final count = ranges.length - first;
    setState(() {
      _chunkRunning = true;
      _chunkStop = false;
      _chunkDone = 0;
      _chunkTotal = count;
      _chunkMsg = null;
      _chunkErr = false;
    });
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var saved = 0;
    var dropped = 0;
    String? stoppedAt;
    String? why;
    await RenderChannel.keepAlive(true, text: 'ခွဲထုတ် $count ပိုင်း');
    for (var k = first; k < ranges.length; k++) {
      if (!mounted || _chunkStop) break;
      final r = ranges[k];
      final slice = sliceTimeline(full, r.from, r.to);
      dropped += slice.droppedVoices;
      final name = '${partFileName(safeFileName(p.name), k, ranges.length)}_$stamp';
      final job = buildRenderJob(
        name: name,
        videoUri: p.sourceVideoUri!,
        timeline: slice.timeline,
        overlays: sliceWindows(overlaysAll, r.from, r.to),
        splits: sliceWindows(splitsAll, r.from, r.to, minMs: minSplitMs),
        // Blur boxes are on the ORIGINAL video's time, so the cut pieces already limit them.
        censors: censors,
        sourceSubtitles: _subs,
        settings: _eff,
        aspect: (p.videoWidth ?? 0) > 0 && (p.videoHeight ?? 0) > 0 ? p.videoWidth! / p.videoHeight! : 16 / 9,
      );
      await rs.start(_pid, name, job);
      await _idle(rs);
      if (rs.error != null || rs.canceled) {
        stoppedAt = 'အပိုင်း ${k + 1}';
        why = rs.error ?? 'ကိုယ်တိုင်ရပ်လို့';
        break;
      }
      final done = rs.lastDone;
      if (done == null || done.name != name) {
        stoppedAt = 'အပိုင်း ${k + 1}';
        why = 'ထွက်ပြီး ဒါပေမယ့် မှတ်တမ်းသိမ်းလို့ မရဘူး';
        break;
      }
      final fail = await PartSaver.toGallery(done, name);
      if (fail != null) {
        stoppedAt = 'အပိုင်း ${k + 1}';
        why = '$fail (ဖိုင်က app ထဲမှာ ကျန်တယ်၊ Save အဆင့်မှာ ကိုယ်တိုင်သိမ်းနိုင်)';
        break;
      }
      saved++;
      if (mounted) setState(() => _chunkDone = saved);
      if (k < ranges.length - 1 && _restSec > 0 && !_chunkStop) await _rest();
    }
    if (!mounted && stoppedAt == null && saved < count && !_chunkStop) {
      stoppedAt = 'screen ပိတ်သွားလို့';
      why = 'ဒီစာမျက်နှာကို ထွက်သွားတယ်';
    }
    await RenderChannel.keepAlive(false);
    final summary = partsRunSummary(
      total: count,
      saved: saved,
      what: 'အပိုင်း',
      stoppedAt: stoppedAt ?? (_chunkStop && saved < count ? 'ကိုယ်တိုင်ရပ်လို့' : null),
      why: why,
    );
    await _saveLast(summary);
    if (!mounted) return;
    setState(() {
      _chunkRunning = false;
      _restLeft = 0;
      _chunkErr = saved < count;
      _chunkMsg = '$summary${dropped > 0 ? '။ Narration / sound $dropped ခုက ဖြတ်တဲ့နေရာကို ကျော်နေလို့ မပါဘူး' : ''}';
    });
  }

  /// The job the renderer reads: the saved edit plus the approved TE operations (applied to a copy).
  Map<String, Object?> _buildJob(String name, {bool sample = false}) {
    final p = widget.project;
    final te = compileOps(_tl.pieces, _plan.ops);
    var tl = _tl.copyWith(pieces: te.pieces, voices: [..._tl.voices, ...te.sounds]);
    var overlays = [for (final o in te.overlays) o.toJson()];
    var splits = [for (final x in te.splits) x.toJson()];
    final censors = [for (final x in te.censors) x.toJson()];
    if (sample) {
      tl = sampleTimeline(tl);
      overlays = clipWindows(overlays, sampleMs);
      splits = clipWindows(splits, sampleMs, minMs: minSplitMs);
    }
    return buildRenderJob(
      name: name,
      videoUri: p.sourceVideoUri!,
      timeline: tl,
      overlays: overlays,
      splits: splits,
      censors: censors,
      sourceSubtitles: _subs,
      settings: _eff,
      aspect: (p.videoWidth ?? 0) > 0 && (p.videoHeight ?? 0) > 0 ? p.videoWidth! / p.videoHeight! : 16 / 9,
    );
  }

  Future<void> _start({bool sample = false}) async {
    final p = widget.project;
    final rs0 = context.read<RenderStore>();
    final oldSample = rs0.lastSample;
    if (sample && oldSample != null) {
      // Keep only one test file on the phone.
      try {
        await RenderChannel.deleteRender(oldSample.path);
      } catch (_) {}
    }
    final name = '${safeFileName(p.name)}_${sample ? 'sample_' : ''}${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final job = _buildJob(name, sample: sample);
    await context.read<RenderStore>().start(_pid, name, job, sample: sample);
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
    blockers.addAll(missingFiles(te, (f) => File(f).existsSync()));
    blockers.addAll(missingEditFiles(_tl, (f) => File(f).existsSync()));
    if (p.hasVideo && !_videoOk) blockers.add('မူရင်းဗီဒီယိုကို ဖွင့်မရတော့ပါ (ရွှေ့/ဖျက်ထားနိုင်တယ်)။ Stage 1 မှာ ဗီဒီယို ပြန်ရွေးပါ။');
    final est = estimateBytes(dur, _eff);
    final lowSpace = _free > 0 && est > 0 && _free < est + est ~/ 5 + 50 * 1048576;
    final done = rs.lastDone;
    final ranges = chunkRanges(dur, _chunkMin * 60000);
    final fromChunk = ranges.isEmpty ? 1 : _fromChunk.clamp(1, ranges.length).toInt();

    if (done != null && done.projectId == _pid && !p.isDone(Stage.render) && !_markedDone) {
      _markedDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final store = context.read<ProjectStore>();
        final cur = store.current;
        if (cur != null) store.setStageDone(cur, Stage.render, true);
      });
    }

    String? left;
    if (mine) {
      _t0 ??= DateTime.now();
      final pct = rs.percent;
      if (pct >= 5) {
        final ms = (DateTime.now().difference(_t0!).inMilliseconds * (100 - pct) / pct).round();
        left = _dur(ms);
      }
    } else {
      _t0 = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoHint('Stage 4 မှာ စီစဉ်ထားတာကို MP4 အသစ်အဖြစ် ထုတ်မယ်။ မူရင်းဗီဒီယိုကို မထိပါဘူး။ ထုတ်နေတုန်း app ကို ဖွင့်ထားပါ (screen ကို ဖွင့်ထားပေးမယ်)။'),
        const SizedBox(height: 10),
        DfCard(
          title: 'ထုတ်ဖို့ အဆင်သင့်လား',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckLine('မူရင်းဗီဒီယို ဖွင့်လို့ရ', ok: p.hasVideo && _videoOk),
              CheckLine('အပိုင်း ${_tl.pieces.length} ခု', ok: _tl.pieces.isNotEmpty),
              CheckLine('အသံ ${_tl.voices.length} ခု · music ${_tl.music == null ? 'မရှိ' : 'ရှိ'}', ok: _tl.voices.isNotEmpty),
              CheckLine('စာတန်း ${_tl.burnSubtitles ? 'ထည့်ရိုက်မယ်' : 'မထည့်'}', ok: _tl.burnSubtitles),
              const SizedBox(height: 6),
              _row('အရှည်', dur > 0 ? _dur(dur) : '—'),
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
            ],
          ),
        ),
        const Text('Platform အတွက် အမြန်ရွေး', style: TextStyle(color: DfColors.muted, fontSize: 13)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pr in platformPresets)
            ActionChip(
              label: Text(pr.label, style: const TextStyle(fontSize: 12.5)),
              tooltip: pr.note,
              onPressed: mine ? null : () => setState(() => _settings = pr.settings),
            ),
        ]),
        const InfoHint('ဒါတွေက အသုံးများတဲ့ setting တွေပါ။ Platform ရဲ့ လက်ရှိစည်းမျဉ်းကို app က မစစ်ပါဘူး။ တင်ခါနီး ကိုယ်တိုင် စစ်ပါ။', label: 'Preset အကြောင်း'),
        const SizedBox(height: 8),
        DropdownButtonFormField<OutRatio>(
          key: ValueKey('r${_settings.ratio.name}'),
          initialValue: _settings.ratio,
          decoration: const InputDecoration(labelText: 'ဗီဒီယို ပုံသဏ္ဍာန် (ratio)'),
          items: [for (final r in OutRatio.values) DropdownMenuItem(value: r, child: Text(r.label))],
          onChanged: mine ? null : (v) => setState(() => _settings = _settings.copyWith(ratio: v)),
        ),
        if (_settings.ratio != OutRatio.original) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<FillMode>(
            key: ValueKey('fill${_settings.fill.name}'),
            initialValue: _settings.fill,
            decoration: const InputDecoration(labelText: 'ကျန်တဲ့နေရာ ဘယ်လိုဖြည့်မလဲ'),
            items: [for (final f in FillMode.values) DropdownMenuItem(value: f, child: Text(f.label))],
            onChanged: mine ? null : (v) => setState(() => _settings = _settings.copyWith(fill: v)),
          ),
          if (_settings.fill == FillMode.blur)
            InfoHint(
              _tl.pieces.any((p) => p.freeze) || _plan.ops.any((o) => o.tool == TransformTool.splitScreen && o.runnable)
                  ? '⚠ Freeze Frame ဒါမှမဟုတ် Split Screen ပါနေလို့ ဒီတစ်ခါ အနက်ရောင်အကွက်နဲ့ ထုတ်မယ်။'
                  : 'Blur နောက်ခံက မူရင်းဗီဒီယိုရဲ့ ကိုယ်ပိုင်ပုံကို ချဲ့ပြီး မှုန်ထားတာပါ။ အလွတ်နေရာဖြည့်ဖို့ပဲ၊ ဘာကိုမှ ဖုံးဖို့ မဟုတ်ပါ။ စမ်းသပ်အဆင့်ပါ၊ ဖုန်းမှာ မစမ်းရသေးပါ။',
              label: 'Blur အကြောင်း',
            ),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('အဆင့်မြင့် setting', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('${_settings.height}p · ${_settings.fps} fps · ${qualityLabel(_settings.videoKbps)}', style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
            children: [
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('h${_settings.height}'),
              initialValue: _settings.height,
              decoration: const InputDecoration(labelText: 'ပုံအရွယ် (အတိုဘက်)'),
              items: const [
                DropdownMenuItem(value: 480, child: Text('480p')),
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
        DropdownButtonFormField<int>(
          key: ValueKey('q${_settings.videoKbps}'),
          initialValue: _settings.videoKbps,
          decoration: const InputDecoration(labelText: 'အရည်အသွေး (ဖိုင်အရွယ်ကို ထိန်း)'),
          items: [for (final k in qualityChoices) DropdownMenuItem(value: k, child: Text(qualityLabel(k)))],
          onChanged: mine ? null : (v) => setState(() => _settings = _settings.copyWith(videoKbps: v)),
        ),
        InfoHint(
          _eff.sourceBps > 0
              ? 'မူရင်းဖိုင် ≈ ${(_eff.sourceBps / 1000000).toStringAsFixed(1)} Mbps။ Auto က ဒါနဲ့ ကပ်ပြီး ထုတ်မယ်၊ ဖိုင်ကြီးမသွားဘူး။ ဂဏန်းနိမ့်လေ ဖိုင်သေးလေ (ပုံကြည်လင်မှု ကျနိုင်)။'
              : 'မူရင်းဖိုင် bitrate မသိလို့ Auto က အရွယ်အလိုက် ပုံမှန်တန်ဖိုး သုံးမယ်။',
          label: 'အရည်အသွေး အကြောင်း',
        ),
        const SizedBox(height: 8),
            ],
          ),
        ),
        if (!mine && !_chunkRunning && dur >= 20 * 60000)
          DfCard(
            title: 'ရှည်တဲ့ video ကို ခွဲထုတ် (ဖုန်းမပူအောင်)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('cm$_chunkMin'),
                    initialValue: _chunkMin,
                    decoration: const InputDecoration(labelText: 'တစ်ဖိုင်ကို'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('တစ်ဖိုင်တည်း')),
                      DropdownMenuItem(value: 20, child: Text('၂၀ မိနစ်')),
                      DropdownMenuItem(value: 30, child: Text('၃၀ မိနစ်')),
                      DropdownMenuItem(value: 45, child: Text('၄၅ မိနစ်')),
                      DropdownMenuItem(value: 60, child: Text('၁ နာရီ')),
                    ],
                    onChanged: (v) => setState(() {
                      _chunkMin = v ?? 0;
                      _fromChunk = 1;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('rs$_restSec'),
                    initialValue: _restSec,
                    decoration: const InputDecoration(labelText: 'ကြားမှာ နား'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('မနား')),
                      DropdownMenuItem(value: 60, child: Text('၁ မိနစ်')),
                      DropdownMenuItem(value: 120, child: Text('၂ မိနစ်')),
                      DropdownMenuItem(value: 180, child: Text('၃ မိနစ်')),
                      DropdownMenuItem(value: 300, child: Text('၅ မိနစ်')),
                    ],
                    onChanged: _chunkMin == 0 ? null : (v) => setState(() => _restSec = v ?? 0),
                  ),
                ),
              ]),
              if (ranges.length > 1) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('fc$fromChunk${ranges.length}'),
                  initialValue: fromChunk,
                  decoration: const InputDecoration(labelText: 'ဘယ်အပိုင်းကနေ စမလဲ (ရပ်သွားရင် ကျန်တာကို ဆက်လုပ်ဖို့)'),
                  items: [for (var i = 1; i <= ranges.length; i++) DropdownMenuItem(value: i, child: Text('အပိုင်း $i / ${ranges.length}'))],
                  onChanged: (v) => setState(() => _fromChunk = v ?? 1),
                ),
                const SizedBox(height: 6),
                Text(
                  'ဖိုင် ${ranges.length} ခု ထွက်မယ်၊ တစ်ခုပြီးတိုင်း Gallery ထဲ အလိုအလျောက် သိမ်းပြီး app ထဲက ကော်ပီ ဖျက်မယ်။ '
                  'Narration / sound က ဖြတ်တဲ့နေရာကို ကျော်နေရင် အဲ့ဒါ မပါဘူး၊ Zoom က ဖြတ်တဲ့နေရာမှာ အစကပြန်စမယ်၊ Music က ဖိုင်တိုင်း အစကနေ စမယ်။',
                  style: const TextStyle(color: DfColors.muted, fontSize: 12),
                ),
              ],
            ]),
          ),
        if (_chunkMsg != null && !_chunkRunning && !mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_chunkMsg!, style: TextStyle(fontSize: 12.5, color: _chunkErr ? DfColors.danger : DfColors.ok)),
          ),
        _row('ခန့်မှန်း ဖိုင်အရွယ်', est > 0 ? '≈ ${_mb(est)}' : '—'),
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
        if (_chunkRunning && !mine)
          DfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_restLeft > 0 ? 'ဖုန်းအေးအောင် နားနေတယ်' : 'နောက်အပိုင်း ပြင်နေတယ်…', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('ပြီးပြီ $_chunkDone / $_chunkTotal${_restLeft > 0 ? ' · ကျန် ${coolDownText(_restLeft)}' : ''}', style: const TextStyle(color: DfColors.muted)),
              const SizedBox(height: 8),
              Row(children: [
                if (_restLeft > 0)
                  Expanded(child: OutlinedButton(onPressed: () => _skipRest = true, child: const Text('နားတာ ကျော်'))),
                if (_restLeft > 0) const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => setState(() => _chunkStop = true), child: const Text('ရပ်မယ်'))),
              ]),
            ]),
          )
        else if (mine) ...[
          DfCard(
            child: Row(
              children: [
                ProgressRing(percent: rs.percent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ထုတ်နေတယ်…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(_chunkRunning ? 'အပိုင်း ${_chunkDone + 1} / $_chunkTotal' : 'ခဏစောင့်ပါ', style: const TextStyle(color: DfColors.muted)),
                      if (left != null) ...[
                        const SizedBox(height: 6),
                        Text('ကျန်ခန့် $left (ခန့်မှန်းချက်)', style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              _chunkStop = true;
              rs.cancel();
            },
            child: const Text('ရပ်မယ်'),
          ),
        ] else
          GradientButton(
            onPressed: (blockers.isNotEmpty || otherRunning) ? null : () => ranges.length > 1 ? _runChunks() : _start(),
            icon: Icons.movie_creation_outlined,
            label: otherRunning ? 'တခြား project render လုပ်နေဆဲ' : (ranges.length > 1 ? 'ခွဲထုတ်မယ် (${ranges.length - fromChunk + 1} ပိုင်း)' : 'MP4 ထုတ်မယ်'),
          ),
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: (blockers.isNotEmpty || otherRunning) ? null : () => _start(sample: true),
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('အစ ၈ စက္ကန့် စမ်းထုတ်ကြည့်မယ်'),
            ),
          ),
        if (p.hasVideo && p.sourceVideoUri != null && blockers.isEmpty)
          ColabRenderCard(project: p, buildJob: _buildJob, busyElsewhere: rs.running),
        if (rs.lastSample != null && rs.lastSample!.projectId == _pid && !mine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(
                child: Text('စမ်းထုတ်ထားတာ ${_dur(rs.lastSample!.durationMs)} · ${_mb(rs.lastSample!.sizeBytes)} (history ထဲ မသိမ်းပါ)', style: const TextStyle(fontSize: 12.5)),
              ),
              TextButton(onPressed: () => showVideoPreview(context, rs.lastSample!.path), child: const Text('ကြည့်မယ်')),
            ]),
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
                FilledButton.icon(
                  onPressed: (_galleryBusy || _galleryName == done.name) ? null : () => _saveToGallery(done),
                  icon: Icon(_galleryName == done.name ? Icons.check : Icons.photo_library_outlined, size: 18),
                  label: Text(_galleryName == done.name ? 'Gallery ထဲ ရောက်ပြီ' : 'Gallery ထဲ သိမ်းမယ်'),
                ),
              ]),
              if (_galleryBusy) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
              if (_galleryMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_galleryMsg!, style: TextStyle(fontSize: 12.5, color: _galleryErr ? DfColors.danger : DfColors.ok)),
                ),
              const Text('ဖိုင်အဖြစ် သိမ်းချင်ရင် (ဒါမှမဟုတ် Gallery မရရင်) နောက်အဆင့် "Save" မှာ ရပါတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
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
