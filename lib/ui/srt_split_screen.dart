import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/part_progress.dart';
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
  const SrtSplitScreen({super.key, required this.project, this.embedded = false, this.refresh = 0});

  final Project project;

  /// Inside Subtitle Studio: no AppBar / scaffold.
  final bool embedded;

  /// Changes when the SRT was edited elsewhere: the lines are read again
  /// (not while parts are being made).
  final int refresh;

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
  bool _paused = false;
  int _doneParts = 0;
  int _runTotal = 0;
  String _runLabel = '';
  // Parts already made (kept on the phone, so a stop or a crash does not start over).
  // A part is known by its time range, sound setting and subtitle count, so moving a cut
  // elsewhere does not make the finished parts look unfinished.
  Set<String> _doneKeys = {};
  static const _doneKind = 'parts_done_split';
  String _keyOfPart(SplitPart p) => partKey(p.startMs, p.endMs, tag: '${_keepSound ? 's' : 'm'}${_lines.length}');
  Set<int> get _finished {
    final parts = _parts;
    return {for (var i = 0; i < parts.length; i++) if (_doneKeys.contains(_keyOfPart(parts[i]))) i};
  }

  Future<void> _saveDone() async {
    try {
      await _repo.setDoc(_pid, _doneKind, encodeDone(_doneKeys));
    } catch (_) {}
  }
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
  void didUpdateWidget(SrtSplitScreen old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh && !_running) {
      _breaks = {};
      _load();
    }
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
      _doneKeys = decodeDone(await _repo.getDoc(_pid, _doneKind));
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
      _paused = false;
      _doneParts = 0;
      _runTotal = indexes.length;
      _runLabel = indexes.length == 1 ? 'အပိုင်း ${indexes.first + 1}' : '';
      _doneKeys = {..._doneKeys}..removeAll([for (final i in indexes) _keyOfPart(parts[i])]);
      _msg = null;
    });
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var saved = 0;
    var ok = 0;
    if (indexes.length > 1) await RenderChannel.keepAlive(true, text: 'အပိုင်း ${indexes.length} ခု');
    for (final i in indexes) {
      // Pause: the part being made finishes first, then we wait here.
      if (_paused && mounted && !_stop) {
        await RenderChannel.keepAlive(true, text: 'ခဏရပ်ထားတယ် (အပိုင်း ${i + 1} မစသေး)');
      }
      while (_paused && mounted && !_stop) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
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
      _doneKeys = {..._doneKeys, _keyOfPart(part)};
      await _saveDone();
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
    await RenderChannel.keepAlive(false);
    if (mounted) {
      setState(() {
        _running = false;
        _paused = false;
      });
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
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _lines.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.subtitles_off_outlined, size: 44, color: DfColors.muted),
                    SizedBox(height: 10),
                    Text('SRT မရှိသေးပါ', style: TextStyle(color: DfColors.muted)),
                  ]),
                ),
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
                      subtitle: Text('${formatTime(e.startMs)} → ${formatTime(e.endMs)}', style: TextStyle(fontSize: 11.5, color: starts ? DfColors.ok : DfColors.muted)),
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
                                      }),
                            ),
                    ),
                  );
                },
              );
    if (widget.embedded) return body;
    return DfScaffold(appBar: AppBar(title: const Text('အပိုင်းခွဲ')), body: body);
  }

  Widget _label(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: DfColors.muted),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _autoRow(TextEditingController c, IconData icon, String hint, VoidCallback onGo) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: DfColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(isDense: true, suffixText: hint),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(onPressed: _running ? null : onGo, icon: const Icon(Icons.content_cut), tooltip: 'ခွဲ'),
        ]),
      );

  Widget _header(RenderStore rs, List<SplitPart> parts, List<int> overlaps) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const InfoHint('စာတန်းလိုင်းရဲ့ စချိန်မှာ အတိအကျ ဖြတ်မယ်။ အပိုင်းတိုင်း SRT ကို 0:00 က ပြန်ရေးပေးမယ်။ မူရင်းဗီဒီယို မပြင်ပါ။'),
      _label(Icons.auto_awesome_outlined, 'အလိုအလျောက်'),
      _autoRow(_linesC, Icons.format_list_numbered, 'လိုင်း', () {
        final n = int.tryParse(_linesC.text.trim()) ?? 0;
        setState(() {
          _breaks = breaksEveryLines(_lines.length, n);
        });
      }),
      _autoRow(_minC, Icons.timer_outlined, 'မိနစ်', () {
        final m = double.tryParse(_minC.text.trim()) ?? 0;
        setState(() {
          _breaks = breaksEveryMs(_lines, (m * 60000).round());
        });
      }),
      Row(children: [
        const Icon(Icons.touch_app_outlined, size: 16, color: DfColors.muted),
        const SizedBox(width: 6),
        const Expanded(child: Text('အောက်က ✂ နဲ့ ကိုယ်တိုင်လည်း ခွဲ/ဖြုတ်လို့ရတယ်', style: TextStyle(color: DfColors.muted, fontSize: 12))),
        if (_breaks.isNotEmpty)
          IconButton(
            onPressed: _running
                ? null
                : () => setState(() {
                      _breaks = {};
                    }),
            icon: const Icon(Icons.layers_clear_outlined, size: 20),
            tooltip: 'ခွဲထားတာ အားလုံး ဖျက်',
          ),
      ]),
      _label(Icons.view_agenda_outlined, '${parts.length}'),
      if (overlaps.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.warning_amber, size: 16, color: DfColors.warn),
            const SizedBox(width: 6),
            Expanded(child: Text('${overlaps.length} နေရာမှာ စာကြောင်းက အပိုင်းနှစ်ခုလုံးမှာ ပါမယ်', style: const TextStyle(color: DfColors.warn, fontSize: 12.5))),
          ]),
        ),
      for (var i = 0; i < parts.length; i++)
        Card(
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _finished.contains(i) ? DfColors.ok.withValues(alpha: 0.2) : DfColors.line,
              child: _finished.contains(i) ? const Icon(Icons.check, size: 16, color: DfColors.ok) : Text('${i + 1}', style: const TextStyle(fontSize: 12)),
            ),
            title: Text('${formatTime(parts[i].startMs)} → ${formatTime(parts[i].endMs)}', style: const TextStyle(fontSize: 13)),
            subtitle: Text('${formatTime(parts[i].lengthMs)} · ${parts[i].lines}', style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: _running ? null : () => _saveSrt(parts[i], i, parts.length),
                icon: const Icon(Icons.subtitles_outlined),
                tooltip: 'SRT သိမ်း',
              ),
              IconButton(
                onPressed: (_running || rs.running) ? null : () => _renderParts(parts, [i]),
                icon: const Icon(Icons.movie_outlined),
                tooltip: 'MP4 ထုတ်',
              ),
            ]),
          ),
        ),
      _label(Icons.tune, 'MP4'),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<OutRatio>(
            key: ValueKey('sr${_settings.ratio.name}'),
            initialValue: _settings.ratio,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.aspect_ratio, size: 20)),
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
            decoration: const InputDecoration(isDense: true),
            items: const [DropdownMenuItem(value: 480, child: Text('480p')), DropdownMenuItem(value: 720, child: Text('720p')), DropdownMenuItem(value: 1080, child: Text('1080p'))],
            onChanged: _running ? null : (v) => setState(() => _settings = _settings.copyWith(height: v)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        key: ValueKey('sq${_settings.videoKbps}'),
        initialValue: _settings.videoKbps,
        decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.high_quality_outlined, size: 20)),
        items: [for (final k in qualityChoices) DropdownMenuItem(value: k, child: Text(qualityLabel(k)))],
        onChanged: _running ? null : (v) => setState(() => _settings = _settings.copyWith(videoKbps: v)),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(_keepSound ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: DfColors.muted),
        value: _keepSound,
        onChanged: _running ? null : (v) => setState(() => _keepSound = v),
        title: const Text('မူရင်းအသံ'),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.photo_library_outlined, color: DfColors.muted),
        value: _toGallery,
        onChanged: _running ? null : (v) => setState(() => _toGallery = v),
        title: const Text('ပြီးတိုင်း Gallery သိမ်း'),
      ),
      const SizedBox(height: 4),
      if (_running) ...[
        LinearProgressIndicator(value: _runTotal == 0 ? null : (_doneParts + rs.percent / 100) / _runTotal),
        const SizedBox(height: 4),
        Text(_runTotal == 1 ? '$_runLabel ${rs.percent}%' : '${_doneParts + 1}/$_runTotal · ${rs.percent}%', style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          if (_runTotal > 1)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _paused = !_paused),
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
                label: Text(_paused ? 'ဆက်' : 'ခဏရပ်'),
              ),
            ),
          if (_runTotal > 1) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _stop = true;
                  _paused = false;
                });
                rs.cancel();
              },
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('ရပ်'),
            ),
          ),
        ]),
        if (_paused)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('လက်ရှိအပိုင်းပြီးရင် ရပ်ထားမယ်', style: TextStyle(color: DfColors.muted, fontSize: 12)),
          ),
      ] else
        Builder(builder: (_) {
          final left = pendingParts(parts.length, _finished);
          final partly = left.isNotEmpty && left.length < parts.length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: (parts.isEmpty || rs.running) ? null : () => _renderParts(parts, left.isEmpty ? [for (var i = 0; i < parts.length; i++) i] : left),
              icon: const Icon(Icons.movie_creation_outlined, size: 18),
              label: Text(partly ? 'ကျန်တာ MP4 ထုတ် (${left.length}/${parts.length})' : '${parts.length} ခုလုံး MP4 ထုတ်'),
            ),
            if (partly)
              TextButton(
                onPressed: rs.running ? null : () => _renderParts(parts, [for (var i = 0; i < parts.length; i++) i]),
                child: const Text('အစကနေ အကုန်ပြန်ထုတ်'),
              ),
          ]);
        }),
      if (_msg != null)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
      _label(Icons.format_list_bulleted, '${_lines.length}'),
    ]);
  }
}
