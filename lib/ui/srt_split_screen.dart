import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/render_plan.dart';
import '../core/segments.dart';
import '../core/srt.dart';
import '../core/srt_split.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/handoff_channel.dart';
import '../platform/render_channel.dart';
import '../state/render_store.dart';
import 'widgets.dart';

/// Cuts the video into parts exactly at subtitle lines, saves the matching SRT
/// for each part (times counted from the start of the part) and can make an MP4
/// for every part, one after another. The original video is never changed.
class SrtSplitScreen extends StatefulWidget {
  const SrtSplitScreen({super.key, required this.project});

  final Project project;

  @override
  State<SrtSplitScreen> createState() => _SrtSplitScreenState();
}

class _SrtSplitScreenState extends State<SrtSplitScreen> {
  final _repo = HandoffRepo();
  final _linesC = TextEditingController(text: '40');
  final _minC = TextEditingController(text: '5');
  List<SrtEntry> _lines = [];
  Set<int> _breaks = {};
  Timeline _tl = const Timeline();
  RenderSettings _settings = const RenderSettings();
  RenderSettings get _eff => _settings.copyWith(sourceBps: sourceBitsPerSecond(widget.project.videoSize, widget.project.videoDurationMs));
  bool _keepSound = true;
  bool _toGallery = true;
  bool _loading = true;
  bool _running = false;
  bool _stop = false;
  int _doneParts = 0;
  int _runTotal = 0;
  String _runLabel = '';
  Set<int> _finished = {};
  String? _msg;
  bool _err = false;

  int get _pid => widget.project.id!;
  int get _dur => widget.project.videoDurationMs ?? 0;
  List<SplitPart> get _parts => buildParts(_lines, _breaks, _dur);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _linesC.dispose();
    _minC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
      final raw = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
      if (raw != null) _lines = sortedLines(parseSrt(raw).entries);
      _tl = Timeline.decode(await _repo.getDoc(_pid, DocKind.timeline));
    } catch (e) {
      _say('ဖတ်လို့မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  Future<void> _saveSrt(SplitPart part, int i, int total) async {
    final name = partFileName(safeFileName(widget.project.name), i, total);
    try {
      final ok = await HandoffChannel.saveTextFile('$name.srt', partSrt(_lines, part));
      if (ok == true) _say('$name.srt သိမ်းပြီးပါပြီ။');
    } catch (e) {
      _say('SRT မသိမ်းနိုင်ပါ: $e', error: true);
    }
  }

  /// Waits until the renderer is free again.
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

  /// Renders the given parts one after another (one part for the per-part button).
  /// [indexes] are positions in [parts].
  Future<void> _renderParts(List<SplitPart> parts, List<int> indexes) async {
    final rs = context.read<RenderStore>();
    final p = widget.project;
    if (!p.hasVideo) {
      _say('ဗီဒီယို မရွေးရသေးပါ။', error: true);
      return;
    }
    setState(() {
      _running = true;
      _stop = false;
      _doneParts = 0;
      _runTotal = indexes.length;
      _runLabel = indexes.length == 1 ? 'အပိုင်း ${indexes.first + 1}' : '';
      _finished = {..._finished}..removeAll(indexes);
      _msg = null;
    });
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var saved = 0;
    var ok = 0;
    for (final i in indexes) {
      if (!mounted || _stop) break;
      final part = parts[i];
      final name = '${partFileName(safeFileName(p.name), i, parts.length)}_$stamp';
      final tl = _tl.copyWith(
        pieces: [VideoPiece(part.startMs, part.endMs)],
        voices: const [],
        clearMusic: true,
        originalVolume: _keepSound ? 1.0 : 0.0,
        burnSubtitles: true,
        subtitleOffsetMs: 0,
      );
      final job = buildRenderJob(
        name: name,
        videoUri: p.sourceVideoUri!,
        timeline: tl,
        sourceSubtitles: _lines,
        settings: _eff,
        aspect: (p.videoWidth ?? 0) > 0 && (p.videoHeight ?? 0) > 0 ? p.videoWidth! / p.videoHeight! : 16 / 9,
      );
      await rs.start(_pid, name, job);
      await _idle(rs);
      if (rs.error != null || rs.canceled) {
        _say('အပိုင်း ${i + 1} မှာ ရပ်သွားတယ်: ${rs.error ?? 'ရပ်လိုက်တယ်'}', error: true);
        break;
      }
      ok++;
      _doneParts = ok;
      _finished = {..._finished, i};
      final done = rs.lastDone;
      if (_toGallery && done != null) {
        try {
          await RenderChannel.saveToGallery(done.path, name);
          saved++;
        } catch (_) {
          _say('အပိုင်း ${i + 1} ကို Gallery ထဲ မသိမ်းနိုင်ပါ (Android 9 ဒါမှမဟုတ် နေရာမလောက်)။ Stage "Save" မှာ ကိုယ်တိုင် သိမ်းပါ။', error: true);
        }
      }
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() => _running = false);
      if (ok == indexes.length) {
        _say(indexes.length == 1
            ? 'အပိုင်း ${indexes.first + 1} ထုတ်ပြီးပါပြီ။${_toGallery ? (saved > 0 ? ' Gallery ထဲ သိမ်းပြီး။' : '') : ' Stage "Save" မှာ သိမ်းနိုင်တယ်။'}'
            : 'အပိုင်း $ok ခု ထုတ်ပြီးပါပြီ။${_toGallery ? ' Gallery ထဲ $saved ခု သိမ်းပြီး။' : ''}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.watch<RenderStore>();
    final parts = _parts;
    final overlaps = overlappingBreaks(_lines, _breaks);
    return Scaffold(
      appBar: AppBar(title: const Text('SRT နဲ့ ဗီဒီယို အပိုင်းခွဲ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lines.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('SRT မရှိသေးပါ။ အမြန်လမ်း ဒါမှမဟုတ် Subtitle Studio မှာ SRT အရင်ထည့်ပါ။', style: TextStyle(color: DfColors.warn)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lines.length + 1,
                  itemBuilder: (context, k) {
                    if (k == 0) return _header(rs, parts, overlaps);
                    final i = k - 1;
                    final e = _lines[i];
                    final starts = _breaks.contains(i);
                    return Container(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: starts ? DfColors.ok : DfColors.line, width: starts ? 2 : 0.5))),
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${formatTime(e.startMs)} → ${formatTime(e.endMs)}${starts ? ' · အပိုင်းအသစ် စတဲ့နေရာ' : ''}', style: TextStyle(fontSize: 11.5, color: starts ? DfColors.ok : DfColors.muted)),
                        trailing: i == 0
                            ? null
                            : IconButton(
                                tooltip: 'ဒီလိုင်းကနေ အပိုင်းအသစ်စ',
                                icon: Icon(starts ? Icons.content_cut : Icons.content_cut_outlined, size: 18, color: starts ? DfColors.ok : DfColors.muted),
                                onPressed: _running
                                    ? null
                                    : () => setState(() {
                                          final b = {..._breaks};
                                          if (!b.remove(i)) b.add(i);
                                          _breaks = b;
                                          _finished = {};
                                        }),
                              ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _header(RenderStore rs, List<SplitPart> parts, List<int> overlaps) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'ဗီဒီယိုကို စာတန်းလိုင်းရဲ့ စချိန်မှာ အတိအကျ ဖြတ်မယ်၊ အပိုင်းတိုင်းအတွက် SRT ကိုလည်း အဲဒီအပိုင်းရဲ့ အစကနေ (0:00) ပြန်ရေးပေးမယ်။ မူရင်းဗီဒီယိုကို မပြင်ပါဘူး။',
        style: TextStyle(color: DfColors.muted, fontSize: 13),
      ),
      const SectionTitle('အလိုအလျောက် ခွဲ'),
      Row(children: [
        Expanded(
          child: TextField(controller: _linesC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'လိုင်း ဘယ်နှစ်ကြောင်းတိုင်း')),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _running
              ? null
              : () {
                  final n = int.tryParse(_linesC.text.trim()) ?? 0;
                  setState(() {
                    _breaks = breaksEveryLines(_lines.length, n);
                    _finished = {};
                  });
                },
          child: const Text('ခွဲ'),
        ),
      ]),
      Row(children: [
        Expanded(
          child: TextField(controller: _minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'မိနစ် ဘယ်လောက်ပတ်လည်')),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _running
              ? null
              : () {
                  final m = double.tryParse(_minC.text.trim()) ?? 0;
                  setState(() {
                    _breaks = breaksEveryMs(_lines, (m * 60000).round());
                    _finished = {};
                  });
                },
          child: const Text('ခွဲ'),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('မိနစ်နဲ့ခွဲရင် စာကြောင်းအလယ်မှာ မဖြတ်ဘူး၊ ပစ်မှတ်ထက် နည်းနည်းရှည်နိုင်တယ်။ အောက်ကလိုင်းတိုင်းက ✂ ကို နှိပ်ပြီး ကိုယ်တိုင်လည်း ခွဲ/ပြန်ဖြုတ်လို့ရတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
      ),
      if (_breaks.isNotEmpty)
        TextButton(onPressed: _running ? null : () => setState(() {
                  _breaks = {};
                  _finished = {};
                }), child: const Text('ခွဲထားတာ အားလုံး ဖျက်')),
      SectionTitle('အပိုင်း ${parts.length} ခု'),
      if (overlaps.isNotEmpty)
        Text('⚠ ${overlaps.length} နေရာမှာ ရှေ့စာကြောင်း ဆက်ပြောနေတုန်း ဖြတ်ရတယ်။ အဲဒီစာကြောင်းက အပိုင်းနှစ်ခုလုံးမှာ ပါမယ် (ရှေ့မှာ အဖြတ်ထိ၊ နောက်မှာ ကျန်တဲ့အပိုင်း)။', style: const TextStyle(color: DfColors.warn, fontSize: 12.5)),
      for (var i = 0; i < parts.length; i++)
        Card(
          child: ListTile(
            dense: true,
            title: Text('အပိုင်း ${i + 1} · ${formatTime(parts[i].startMs)} → ${formatTime(parts[i].endMs)} (${formatTime(parts[i].lengthMs)})', style: const TextStyle(fontSize: 13)),
            subtitle: Text('စာတန်း ${parts[i].lines} ကြောင်း${_finished.contains(i) ? ' · MP4 ထုတ်ပြီး ✓' : ''}', style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: _running ? null : () => _saveSrt(parts[i], i, parts.length), child: const Text('SRT')),
              TextButton(onPressed: (_running || rs.running) ? null : () => _renderParts(parts, [i]), child: const Text('MP4')),
            ]),
          ),
        ),
      const SectionTitle('အပိုင်းတိုင်း MP4 ထုတ်'),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<OutRatio>(
            key: ValueKey('sr${_settings.ratio.name}'),
            initialValue: _settings.ratio,
            decoration: const InputDecoration(labelText: 'ပုံသဏ္ဍာန်'),
            items: [for (final r in OutRatio.values) DropdownMenuItem(value: r, child: Text(r.label, style: const TextStyle(fontSize: 13)))],
            onChanged: _running ? null : (v) => setState(() => _settings = _settings.copyWith(ratio: v)),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: DropdownButtonFormField<int>(
            key: ValueKey('sh${_settings.height}'),
            initialValue: _settings.height,
            decoration: const InputDecoration(labelText: 'အရွယ်'),
            items: const [DropdownMenuItem(value: 480, child: Text('480p')), DropdownMenuItem(value: 720, child: Text('720p')), DropdownMenuItem(value: 1080, child: Text('1080p'))],
            onChanged: _running ? null : (v) => setState(() => _settings = _settings.copyWith(height: v)),
          ),
        ),
      ]),
      DropdownButtonFormField<int>(
        key: ValueKey('sq${_settings.videoKbps}'),
        initialValue: _settings.videoKbps,
        decoration: const InputDecoration(labelText: 'အရည်အသွေး (ဖိုင်အရွယ်ကို ထိန်း)'),
        items: [for (final k in qualityChoices) DropdownMenuItem(value: k, child: Text(qualityLabel(k)))],
        onChanged: _running ? null : (v) => setState(() => _settings = _settings.copyWith(videoKbps: v)),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: _keepSound,
        onChanged: _running ? null : (v) => setState(() => _keepSound = v),
        title: const Text('မူရင်းဗီဒီယိုရဲ့ အသံ ထည့်မယ်'),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: _toGallery,
        onChanged: _running ? null : (v) => setState(() => _toGallery = v),
        title: const Text('တစ်ပိုင်းပြီးတိုင်း Gallery ထဲ တန်းသိမ်း'),
      ),
      const Text(
        'သုံးမယ့် စာတန်း style၊ logo၊ ထောင့်စာသားက Editor မှာ သတ်မှတ်ထားတာကို သုံးမယ်။ အသံ (narration) နဲ့ TE operation တွေ မပါပါဘူး။ ဖုန်းမှာ အပိုင်းတွေ အများကြီးဆို အချိန်ကြာမယ်၊ app ဖွင့်ထားပါ။',
        style: TextStyle(color: DfColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      if (_running) ...[
        LinearProgressIndicator(value: _runTotal == 0 ? null : (_doneParts + rs.percent / 100) / _runTotal),
        const SizedBox(height: 4),
        Text(_runTotal == 1 ? '$_runLabel ထုတ်နေတယ် ${rs.percent}%' : 'အပိုင်း ${_doneParts + 1}/$_runTotal ထုတ်နေတယ် ${rs.percent}%', style: const TextStyle(fontSize: 13)),
        OutlinedButton(
          onPressed: () {
            setState(() => _stop = true);
            rs.cancel();
          },
          child: const Text('ရပ်မယ်'),
        ),
      ] else
        FilledButton.icon(
          onPressed: (parts.isEmpty || rs.running) ? null : () => _renderParts(parts, [for (var i = 0; i < parts.length; i++) i]),
          icon: const Icon(Icons.movie_creation_outlined, size: 18),
          label: Text('အပိုင်း ${parts.length} ခုလုံး MP4 ထုတ်မယ်'),
        ),
      if (_msg != null)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
      const SectionTitle('စာတန်းလိုင်းတွေ'),
    ]);
  }
}
