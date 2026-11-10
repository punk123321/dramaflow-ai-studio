import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/script.dart';
import '../core/segments.dart';
import '../core/stage.dart';
import '../core/theme.dart';
import '../data/audio_clip.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/audio_channel.dart';
import '../state/project_store.dart';

/// Stage 3: turn the narration script into audio. Three ways, all local:
/// the phone's own text-to-speech (if it has a Burmese voice), the
/// microphone, or an audio file brought back from another app.
class AudioPanel extends StatefulWidget {
  const AudioPanel({super.key, required this.project});

  final Project project;

  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> {
  final _handoff = HandoffRepo();
  final _audio = AudioRepo();

  bool _loading = true;
  TtsStatus? _tts;
  String _script = '';
  List<AudioClip> _clips = [];
  double _rate = 1.0;
  int _maxChars = 1500;

  int? _busy; // chunk that is being synthesized
  int? _recording; // chunk that is being recorded
  int? _playingId;
  String? _msg;
  bool _msgError = false;
  StreamSubscription<void>? _sub;

  int get _pid => widget.project.id!;
  List<String> get _chunks => splitScript(_script, maxChars: _maxChars);

  @override
  void initState() {
    super.initState();
    _sub = AudioChannel.playbackEnded.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    AudioChannel.stop().catchError((_) {});
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgError = error;
    });
  }

  String _explain(Object e) {
    if (e is PlatformException) {
      switch (e.code) {
        case 'no_burmese':
          return 'ဒီဖုန်းမှာ မြန်မာအသံ မထည့်ထားပါ။ Settings → Text-to-speech မှာ မြန်မာအသံ ထည့်ပါ၊ ဒါမှမဟုတ် Mic/ဖိုင်ကို သုံးပါ။';
        case 'no_engine':
          return 'ဖုန်းမှာ Text-to-speech engine မရှိ/မဖွင့်ထားပါ။';
        case 'no_permission':
          return 'မိုက်ခရိုဖုန်း ခွင့်ပြုချက် မပေးထားပါ။ Settings → Apps မှာ ပေးပါ။';
        case 'too_short':
          return 'အသံသွင်းချိန် တိုလွန်းတယ်။ ပြန်စမ်းပါ။';
        case 'busy':
          return 'လုပ်နေဆဲပါ။ ခဏစောင့်ပါ။';
        case 'too_long':
          return 'စာသားရှည်လွန်းတယ်။ Chunk အရွယ်ကို သေးပါ။';
      }
      return '${e.message ?? e.code}';
    }
    return '$e';
  }

  Future<void> _load() async {
    try {
      _script = await _handoff.getDoc(_pid, DocKind.script) ?? '';
      _clips = await _audio.forProject(_pid);
    } catch (e) {
      _say('ဖတ်လို့မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
    try {
      final st = await AudioChannel.ttsStatus();
      if (mounted) setState(() => _tts = st);
    } catch (_) {
      if (mounted) setState(() => _tts = const TtsStatus(engineReady: false, burmese: false));
    }
  }

  AudioClip? _clipOf(int chunk) {
    AudioClip? c;
    for (final x in _clips) {
      if (x.chunkIdx == chunk) c = x;
    }
    return c;
  }

  Future<void> _setScript(String text) async {
    await _handoff.setDoc(_pid, DocKind.script, text);
    if (!mounted) return;
    setState(() {
      _script = text;
      _msg = null;
    });
  }

  Future<String?> _editScriptSheet() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DfColors.surface,
      builder: (_) => _ScriptSheet(initial: _script),
    );
  }

  Future<void> _fromRecap() async {
    final tasks = await _handoff.resultTasks(_pid);
    final recap = {for (final e in tasks.entries) if (!e.key.startsWith('zh_my') && !e.key.startsWith('my_proof') && !e.key.startsWith('ts_translate')) e.key: e.value};
    if (!mounted) return;
    if (recap.isEmpty) {
      _say('Recap ရလဒ် မရှိသေးပါ။ အဆင့် ၂ မှာ Recap/Narration ရေးခိုင်းပြီး ရလဒ်ထည့်ပါ။', error: true);
      return;
    }
    final key = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('ဘယ်ရလဒ်ကို ယူမလဲ'),
        children: [
          for (final e in recap.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.key),
              child: Text('${e.key.split(':').first} · chunk ${e.value} ခု'),
            ),
        ],
      ),
    );
    if (key == null) return;
    final res = await _handoff.results(_pid, key);
    final joined = [for (final k in res.keys.toList()..sort()) res[k]!].join('\n\n');
    await _setScript(joined);
    _say('Script ယူပြီး (${joined.length} လုံး)');
  }

  Future<void> _pasteScript() async {
    final t = await _editScriptSheet();
    if (t != null) await _setScript(t);
  }

  /// Keeps one clip per chunk: adding a new one removes the old one (and its
  /// file, when the app made it).
  Future<void> _storeClip(int chunk, ClipKind kind, AudioFile f, String label) async {
    final old = _clipOf(chunk);
    if (old != null) await _dropClip(old);
    final saved = await _audio.insert(AudioClip(
      projectId: _pid,
      chunkIdx: chunk,
      kind: kind,
      label: label,
      source: f.source,
      durationMs: f.durationMs,
      sizeBytes: f.sizeBytes,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    setState(() => _clips = [..._clips.where((c) => c.chunkIdx != chunk), saved]..sort((a, b) => a.chunkIdx.compareTo(b.chunkIdx)));
    await _maybeDone();
  }

  Future<void> _dropClip(AudioClip c) async {
    if (_playingId == c.id) {
      await AudioChannel.stop();
      _playingId = null;
    }
    if (c.id != null) await _audio.delete(c.id!);
    if (c.ownsFile) {
      try {
        await AudioChannel.deleteFile(c.source);
      } catch (_) {}
    }
    if (mounted) setState(() => _clips = _clips.where((x) => x.id != c.id).toList());
  }

  Future<void> _maybeDone() async {
    final total = _chunks.length;
    if (total == 0) return;
    for (var i = 0; i < total; i++) {
      if (_clipOf(i) == null) return;
    }
    final store = context.read<ProjectStore>();
    final p = store.current;
    if (p != null && !p.isDone(Stage.tts)) await store.setStageDone(p, Stage.tts, true);
  }

  Future<void> _makeTts(int i, String text) async {
    setState(() {
      _busy = i;
      _msg = null;
    });
    try {
      final f = await AudioChannel.synthesize(text, 'p${_pid}_c${i + 1}_${DateTime.now().millisecondsSinceEpoch}', rate: _rate);
      await _storeClip(i, ClipKind.tts, f, 'TTS');
      _say('Chunk ${i + 1} အသံထုတ်ပြီး (${formatTime(f.durationMs)})');
    } catch (e) {
      _say(_explain(e), error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _ttsAll(List<String> chunks) async {
    for (var i = 0; i < chunks.length; i++) {
      if (!mounted) return;
      if (_clipOf(i) != null) continue;
      await _makeTts(i, chunks[i]);
      if (_msgError) return;
    }
  }

  Future<void> _toggleRecord(int i) async {
    if (_recording == i) {
      try {
        final f = await AudioChannel.recordStop();
        setState(() => _recording = null);
        await _storeClip(i, ClipKind.mic, f, 'Mic');
        _say('Chunk ${i + 1} အသံသွင်းပြီး (${formatTime(f.durationMs)})');
      } catch (e) {
        if (mounted) setState(() => _recording = null);
        _say(_explain(e), error: true);
      }
      return;
    }
    if (_recording != null) return;
    try {
      await AudioChannel.recordStart('p${_pid}_c${i + 1}_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) setState(() => _recording = i);
      _say('အသံသွင်းနေတယ်။ ပြီးရင် "ရပ်" ကို နှိပ်ပါ။');
    } catch (e) {
      _say(_explain(e), error: true);
    }
  }

  Future<void> _importAudio(int i) async {
    try {
      final f = await AudioChannel.pickAudio();
      if (f == null) return;
      await _storeClip(i, ClipKind.imported, f, f.name.isEmpty ? 'ဖိုင်' : f.name);
      _say('Chunk ${i + 1} ဖိုင်ထည့်ပြီး (${formatTime(f.durationMs)})');
    } catch (e) {
      _say(_explain(e), error: true);
    }
  }

  Future<void> _togglePlay(AudioClip c) async {
    try {
      if (_playingId == c.id) {
        await AudioChannel.stop();
        if (mounted) setState(() => _playingId = null);
      } else {
        await AudioChannel.play(c.source);
        if (mounted) setState(() => _playingId = c.id);
      }
    } catch (e) {
      _say('ဖွင့်လို့မရပါ။ ဖိုင်ရွှေ့/ဖျက်ထားလား စစ်ပါ။ (${_explain(e)})', error: true);
      if (mounted) setState(() => _playingId = null);
    }
  }

  Future<void> _export(AudioClip c) async {
    final isWav = c.source.endsWith('.wav');
    try {
      final ok = await AudioChannel.export(
        c.source,
        '${widget.project.name}_${c.chunkIdx + 1}.${isWav ? 'wav' : 'm4a'}',
        isWav ? 'audio/wav' : 'audio/mp4',
      );
      if (ok == true) _say('ဖိုင်သိမ်းပြီး');
    } catch (e) {
      _say(_explain(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final chunks = _chunks;
    final haveClips = chunks.indexed.where((e) => _clipOf(e.$1) != null).length;
    final totalMs = [for (var i = 0; i < chunks.length; i++) _clipOf(i)?.durationMs ?? 0].fold<int>(0, (a, b) => a + b);
    final busyAny = _busy != null || _recording != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _status(),
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_msgError ? DfColors.danger : DfColors.ok).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_msg!, style: const TextStyle(fontSize: 13)),
          ),
        _section('၁။ Script (အသံဖတ်ရမယ့်စာ)'),
        Text(
          _script.trim().isEmpty
              ? 'Script မရှိသေးပါ။'
              : '${_script.length} လုံး · ခန့်မှန်း ${formatTime(estimateSpeech(_script).inMilliseconds)}',
          style: TextStyle(color: _script.trim().isEmpty ? DfColors.muted : null, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(onPressed: _fromRecap, icon: const Icon(Icons.auto_stories, size: 18), label: const Text('Recap ရလဒ်ကယူ')),
          OutlinedButton.icon(onPressed: _pasteScript, icon: const Icon(Icons.edit, size: 18), label: const Text('ကူးထည့်/ပြင်')),
        ]),
        if (chunks.isNotEmpty) ...[
          const SizedBox(height: 14),
          _section('၂။ အသံ'),
          Row(children: [
            const Text('အမြန်နှုန်း', style: TextStyle(fontSize: 13)),
            Expanded(
              child: Slider(
                value: _rate,
                min: 0.6,
                max: 1.4,
                divisions: 8,
                label: _rate.toStringAsFixed(1),
                onChanged: (v) => setState(() => _rate = v),
              ),
            ),
            Text('${_rate.toStringAsFixed(1)}×', style: const TextStyle(fontSize: 13)),
          ]),
          DropdownButtonFormField<int>(
            key: ValueKey('mc$_maxChars'),
            initialValue: _maxChars,
            decoration: const InputDecoration(labelText: 'Chunk အရွယ် (စာလုံးရေ)'),
            items: const [
              DropdownMenuItem(value: 500, child: Text('500 (သေး)')),
              DropdownMenuItem(value: 1000, child: Text('1,000')),
              DropdownMenuItem(value: 1500, child: Text('1,500')),
              DropdownMenuItem(value: 3000, child: Text('3,000 (ကြီး)')),
            ],
            onChanged: busyAny ? null : (v) => setState(() => _maxChars = v ?? _maxChars),
          ),
          const SizedBox(height: 6),
          const Text(
            'Chunk အရွယ်ပြောင်းရင် ယခင်ထုတ်ထားတဲ့ အသံတွေက chunk နံပါတ်နဲ့ မကိုက်တော့နိုင်ဘူး။ ပြောင်းမယ်ဆိုရင် အရင်ဖျက်ပါ။',
            style: TextStyle(color: DfColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _section('၃။ Chunk ${chunks.length} ခု · အသံ $haveClips/${chunks.length}${totalMs > 0 ? ' · ${formatTime(totalMs)}' : ''}'),
          if (_tts?.burmese == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonalIcon(
                onPressed: busyAny ? null : () => _ttsAll(chunks),
                icon: const Icon(Icons.record_voice_over, size: 18),
                label: const Text('မရှိသေးတာ အားလုံး TTS ထုတ်'),
              ),
            ),
          for (var i = 0; i < chunks.length; i++) _chunkCard(i, chunks[i]),
        ],
      ],
    );
  }

  Widget _status() {
    final t = _tts;
    final String text;
    final Color color;
    if (t == null) {
      text = 'ဖုန်းရဲ့ TTS ကို စစ်နေတယ်…';
      color = DfColors.muted;
    } else if (!t.engineReady) {
      text = 'ဖုန်းမှာ Text-to-speech engine မရှိ။ Mic သွင်းတာ ဒါမှမဟုတ် ဖိုင်ထည့်တာကို သုံးပါ။';
      color = DfColors.warn;
    } else if (!t.burmese) {
      text = 'TTS engine ရှိပေမယ့် (${t.engine ?? '-'}) မြန်မာအသံ မထည့်ထားပါ။ Settings → Text-to-speech မှာ မြန်မာအသံ ထည့်လို့ရရင် ထည့်ပါ။ မရရင် Mic သို့မဟုတ် ဖိုင်ကို သုံးပါ။';
      color = DfColors.warn;
    } else {
      text = 'ဒီဖုန်းမှာ မြန်မာ TTS အသံ ရှိတယ် (${t.engine ?? '-'})။';
      color = DfColors.ok;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
      );

  Widget _chunkCard(int i, String text) {
    final clip = _clipOf(i);
    final recordingThis = _recording == i;
    final busyThis = _busy == i;
    final otherBusy = (_busy != null && _busy != i) || (_recording != null && _recording != i);
    final canTts = _tts?.burmese == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: recordingThis ? DfColors.danger : (clip != null ? DfColors.ok : DfColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(clip != null ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: clip != null ? DfColors.ok : DfColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Chunk ${i + 1} · ${text.length} လုံး'
                '${clip != null ? ' · ${clip.label} ${formatTime(clip.durationMs)}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            if (busyThis) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 4),
          Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DfColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 2, children: [
            if (canTts)
              TextButton(onPressed: (busyThis || otherBusy || recordingThis) ? null : () => _makeTts(i, text), child: Text(clip?.kind == ClipKind.tts ? 'TTS ပြန်ထုတ်' : 'TTS ထုတ်')),
            TextButton(
              onPressed: (busyThis || otherBusy) ? null : () => _toggleRecord(i),
              child: Text(recordingThis ? '■ ရပ်' : '● Mic'),
            ),
            TextButton(onPressed: (busyThis || recordingThis || otherBusy) ? null : () => _importAudio(i), child: const Text('ဖိုင်ထည့်')),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                _say('Chunk ${i + 1} စာသား ကူးပြီး');
              },
              child: const Text('စာကူး'),
            ),
            if (clip != null) ...[
              TextButton(onPressed: () => _togglePlay(clip), child: Text(_playingId == clip.id ? '■ ရပ်' : '▶ နားထောင်')),
              if (clip.ownsFile) TextButton(onPressed: () => _export(clip), child: const Text('သိမ်း')),
              TextButton(onPressed: () => _dropClip(clip), child: const Text('ဖျက်')),
            ],
          ]),
        ],
      ),
    );
  }
}

class _ScriptSheet extends StatefulWidget {
  const _ScriptSheet({required this.initial});

  final String initial;

  @override
  State<_ScriptSheet> createState() => _ScriptSheetState();
}

class _ScriptSheetState extends State<_ScriptSheet> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && mounted) setState(() => _c.text = d!.text!);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Script', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          TextField(controller: _c, minLines: 6, maxLines: 12, decoration: const InputDecoration(hintText: 'အသံဖတ်ရမယ့် စာသား')),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(onPressed: _paste, child: const Text('Clipboard')),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('သိမ်း')),
          ]),
        ],
      ),
    );
  }
}
