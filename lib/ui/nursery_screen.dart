import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gemini_tts.dart';
import '../core/nursery.dart';
import '../core/studio.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import '../data/handoff_repo.dart';
import '../data/recap_backend_repo.dart';
import '../platform/audio_channel.dart';
import '../platform/background_work.dart';
import '../platform/gemini_open.dart';
import '../platform/gemini_tts_client.dart';
import '../platform/render_channel.dart';
import '../platform/studio_client.dart';

/// Children's song video: writes the prompts for every AI tool (lyrics, song, character picture, scene pictures, scene
/// video clips, upload text), then joins the finished song and pictures into one video on the Colab backend, with
/// karaoke lyrics. The app does not make the song or the pictures itself; those come from the AI tools the person uses.
class NurseryScreen extends StatefulWidget {
  const NurseryScreen({super.key});

  @override
  State<NurseryScreen> createState() => _NurseryScreenState();
}

class _NurseryScreenState extends State<NurseryScreen> {
  static const _pid = -1;
  static const _kind = 'nursery';
  static const _maxMedia = 24 * 1024 * 1024;
  final _docs = HandoffRepo();
  final _topic = TextEditingController();
  final _heroC = TextEditingController();
  final _lyrics = TextEditingController();
  NurseryDraft _d = const NurseryDraft();
  bool _loaded = false;
  Timer? _saveT;
  GeminiTtsSettings _ai = const GeminiTtsSettings();
  String? _msg;
  bool _err = false;

  // the backend job
  bool _busy = false;
  String _stage = '';
  int _pct = 0;
  String _what = '';
  String? _jobId;
  StudioClient? _client;
  String? _out; // finished video in the backend library
  bool _saving = false;
  String _mode = 'lyrics';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveT?.cancel();
    _flush();
    _topic.dispose();
    _heroC.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _d = NurseryDraft.decode(await _docs.getDoc(_pid, _kind));
      _ai = await AiSettingsRepo().load();
    } catch (_) {}
    _topic.text = _d.topic;
    _heroC.text = _d.heroCustom;
    _lyrics.text = _d.lyrics;
    if (mounted) setState(() => _loaded = true);
  }

  void _flush() {
    if (!_loaded) return;
    _d = _d.copyWith(topic: _topic.text, heroCustom: _heroC.text, lyrics: _lyrics.text);
    _docs.setDoc(_pid, _kind, _d.encode()).catchError((_) {});
  }

  void _changed([NurseryDraft? d]) {
    if (d != null) _d = d;
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 600), _flush);
    setState(() {});
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  // ---- what the prompts are made from ----
  NurseryTheme get _theme => NurseryTheme.values[_d.theme];
  NurseryLang get _lang => NurseryLang.values[_d.lang];
  NurseryStyle get _style => NurseryStyle.values[_d.style];
  String get _tempo => nurseryTempos[_d.tempo];
  String get _tool => nurseryVideoTools[_d.tool];
  String _castDesc(int i) => i >= 0 && i < nurseryCharacters.length ? nurseryCharacters[i].desc : '';
  String get _hero => _d.hero >= 0 ? _castDesc(_d.hero) : _heroC.text.trim();
  String get _cast => castText(_hero, _castDesc(_d.friend1), _castDesc(_d.friend2));
  String get _heroName => _hero.isEmpty ? '' : NurseryCharacter('', _hero).shortName;
  List<NurseryScene> get _lyricScenes => splitScenes(_lyrics.text);

  List<NurseryPackScene> get _scenes {
    final ls = _lyricScenes;
    return buildPackScenes(
      topic: _topic.text,
      hero: _hero,
      friend1: _castDesc(_d.friend1),
      friend2: _castDesc(_d.friend2),
      count: ls.isEmpty ? _d.scenes : ls.length,
      minCount: ls.isEmpty ? 4 : 1,
      maxCount: ls.isEmpty ? 9 : 40,
      style: _style,
      ratio: _d.ratio,
      videoTool: _tool,
      lyricScenes: ls,
    );
  }

  String get _lyricsPrompt => buildLyricsPrompt(
        theme: _theme,
        custom: _topic.text,
        lang: _lang,
        verses: (_d.scenes / 2).round().clamp(1, 4).toInt(),
        character: _heroName,
      );
  String get _musicPrompt => buildMusicPrompt(lang: _lang, bpm: bpmOf(_tempo));
  String get _characterPrompt => buildCharacterPrompt(character: _cast, style: _style);

  String _allPrompts() {
    final b = StringBuffer();
    b.writeln('=== 1. LYRICS PROMPT (text AI) ===\n$_lyricsPrompt\n');
    b.writeln('=== 2. SONG PROMPT (Suno / Udio) ===\n$_musicPrompt\n');
    b.writeln('=== 3. CHARACTER SHEET PROMPT (image AI) ===\n$_characterPrompt\n');
    for (final s in _scenes) {
      b.writeln('=== SCENE ${s.number} · IMAGE PROMPT ===\n${s.imagePrompt}\n');
    }
    for (final s in _scenes) {
      b.writeln('=== SCENE ${s.number} · VIDEO PROMPT (${s.line}) ===\n${s.videoPrompt}\n');
    }
    final seo = buildSeo(topic: _topic.text, hero: _hero);
    b.writeln('=== TITLES ===\n${seo.titles.join('\n')}\n\n=== TAGS ===\n${seo.tags}');
    return b.toString().trim();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('$what ကို Copy လုပ်ပြီး ✓');
  }

  Future<void> _gemini(String prompt) async => _say(await openInGemini(prompt));

  bool _writing = false;
  Future<void> _writeLyrics() async {
    setState(() => _writing = true);
    try {
      final t = await geminiWrite(_ai, _lyricsPrompt);
      _lyrics.text = t.trim();
      _changed();
      _say('Gemini က သီချင်းစာသား ရေးပေးပြီး — ဖတ်ပြီး ကိုယ်တိုင်ပြင်ပါ (AI စာသားမို့ မူရင်းမှန်၊ ရှိပြီးသား သီချင်းနဲ့ ဆင်တူမှု မရှိဘူးလို့ အာမမခံဘူး)');
    } on GeminiTtsException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
    if (mounted) setState(() => _writing = false);
  }

  void _preset(NurseryPreset p) {
    _topic.text = p.topic;
    _heroC.clear();
    _changed(_d.copyWith(
      theme: NurseryTheme.custom.index,
      hero: p.hero,
      friend1: p.friend1 ?? -1,
      friend2: p.friend2 ?? -1,
      lang: p.lang.index,
      tempo: nurseryTempos.contains(p.tempo) ? nurseryTempos.indexOf(p.tempo) : 0,
      tool: nurseryVideoTools.contains(p.videoTool) ? nurseryVideoTools.indexOf(p.videoTool) : 0,
      scenes: p.scenes,
    ));
  }

  // ---- the backend ----
  Future<StudioClient?> _connect() async {
    final s = await RecapBackendRepo().load();
    if (!s.ready) {
      _say('Colab backend ချိတ်ထားတာ မရှိသေးဘူး (Studio ထဲမှာ URL#TOKEN ထည့်ပါ)', error: true);
      return null;
    }
    return StudioClient(s);
  }

  /// Runs one backend job with a progress line. [onDone] gets the finished job.
  Future<void> _run(String title, Map<String, Object?> request, Future<void> Function(StudioJob) onDone) async {
    if (_busy) return;
    final c = await _connect();
    if (c == null) return;
    _client = c;
    setState(() {
      _busy = true;
      _what = title;
      _stage = 'စတင်နေတယ်';
      _pct = 0;
      _jobId = null;
      _msg = null;
    });
    await BackgroundWork.begin('DramaFlow · $title', 'စတင်နေတယ်');
    try {
      final j = await c.run(request, (j) {
        BackgroundWork.update('$title: ${j.stage}', percent: j.progress);
        if (mounted) {
          setState(() {
            _stage = j.stage;
            _pct = j.progress;
          });
        }
      }, onId: (id) => _jobId = id);
      if (j.state == StudioState.done) {
        await onDone(j);
      } else if (j.state == StudioState.canceled) {
        _say('ရပ်လိုက်ပြီ');
      } else {
        _say('မအောင်ဘူး: ${j.error.isEmpty ? j.errors.join('\n') : j.error}', error: true);
      }
    } on StudioCanceled {
      _say('ရပ်လိုက်ပြီ');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      _client = null;
      await BackgroundWork.end();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final c = _client;
    final id = _jobId;
    if (c == null) return;
    try {
      if (id != null) await c.control(id, 'cancel');
    } catch (_) {}
    c.cancel();
  }

  Future<void> _pickSong() async {
    try {
      final f = await AudioChannel.pickAudio();
      if (f == null) return;
      if (f.sizeBytes > _maxMedia) {
        _say('သီချင်းဖိုင်က ${formatBytes(f.sizeBytes)} — ${_maxMedia ~/ 1048576} MB ထက် မကြီးရဘူး (MP3 နဲ့ ပြောင်းပါ)', error: true);
        return;
      }
      final low = (f.name.isEmpty ? f.source : f.name).toLowerCase();
      final ext = ['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.opus'].firstWhere(low.endsWith, orElse: () => '');
      if (ext.isEmpty) {
        _say('သီချင်းက .mp3 / .wav / .m4a / .aac / .ogg / .opus ဖြစ်ရမယ်', error: true);
        return;
      }
      final c = await _connect();
      if (c == null) return;
      _say('သီချင်း တင်နေတယ် (${formatBytes(f.sizeBytes)}) …');
      final stored = await c.upload('nursery_song_${DateTime.now().millisecondsSinceEpoch ~/ 1000}$ext', await File(f.source).readAsBytes());
      _changed(_d.copyWith(song: stored, songMs: f.durationMs, karaoke: ''));
      _say('သီချင်း တင်ပြီး ($stored · ${_dur(f.durationMs)})');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  Future<void> _karaoke() async {
    if (_d.song.isEmpty) return;
    if (_mode == 'lyrics' && _lyrics.text.trim().isEmpty) {
      _say('Karaoke စာတန်းအတွက် သီချင်းစာသား (Lyrics) ကို အပေါ်မှာ ထည့်ပါ', error: true);
      return;
    }
    await _run('Karaoke စာတန်း ထုတ်နေတယ်', studioKaraokeRequest(file: _d.song, lyrics: _lyrics.text, mode: _mode, ratio: _d.ratio), (j) async {
      final ass = j.files.firstWhere((f) => f.toLowerCase().endsWith('.ass'), orElse: () => '');
      if (ass.isEmpty) {
        _say('စာတန်းဖိုင် မထွက်ဘူး', error: true);
        return;
      }
      _changed(_d.copyWith(karaoke: ass));
      _say('Karaoke စာတန်း ပြီး ($ass)${j.notes.isEmpty ? '' : '\n${j.notes.join('\n')}'}');
    });
  }

  Future<void> _pickScene(int n) async {
    try {
      final path = await AudioChannel.pickImage();
      if (path == null) return;
      final c = await _connect();
      if (c == null) return;
      final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final stored = await c.upload('nursery_s${n}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.$ext', await File(path).readAsBytes());
      _changed(_d.copyWith(sceneFiles: {..._d.sceneFiles, n: stored}));
      _say('Scene $n ပုံ တင်ပြီး');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  Future<void> _libScene(int n) async {
    try {
      final c = await _connect();
      if (c == null) return;
      final lib = await c.library();
      final names = [for (final f in lib.files) if (f.isImage || f.isVideo) f.name];
      if (!mounted) return;
      if (names.isEmpty) {
        _say('Library ထဲ ပုံ / clip မရှိသေးဘူး (Drive library ထဲ ထည့်ထားပါ)', error: true);
        return;
      }
      final pick = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Scene $n — Library ကရွေး'),
          children: [for (final f in names) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, f), child: Text(f, overflow: TextOverflow.ellipsis))],
        ),
      );
      if (pick != null) _changed(_d.copyWith(sceneFiles: {..._d.sceneFiles, n: pick}));
    } catch (e) {
      _say('Library ဖတ်မရဘူး: $e', error: true);
    }
  }

  Future<void> _make() async {
    final sc = _scenes;
    final missing = [for (final s in sc) if (!_d.sceneFiles.containsKey(s.number)) s.number];
    if (_d.song.isEmpty) {
      _say('သီချင်း အရင်တင်ပါ', error: true);
      return;
    }
    if (missing.isNotEmpty) {
      _say('ပုံ / clip မရွေးရသေးတဲ့ scene: ${missing.join(', ')}', error: true);
      return;
    }
    final ls = _lyricScenes;
    final weights = ls.length == sc.length ? sceneWeights(ls) : <double>[];
    await _run(
      'သီချင်းဗီဒီယို ထုတ်နေတယ်',
      studioNurseryRequest(
        file: _d.song,
        files: [for (final s in sc) _d.sceneFiles[s.number]!],
        lyricsFile: _d.karaoke,
        durations: weights,
        ratio: _d.ratio,
      ),
      (j) async {
        if (j.files.isEmpty) {
          _say('ဗီဒီယို မထွက်ဘူး', error: true);
          return;
        }
        setState(() => _out = j.files.first);
        _say('ဗီဒီယို ပြီး ✓ (${j.files.first})${j.notes.isEmpty ? '' : '\n${j.notes.join('\n')}'}');
      },
    );
  }

  Future<void> _toPhone() async {
    final name = _out;
    if (name == null || _saving) return;
    final c = await _connect();
    if (c == null) return;
    setState(() => _saving = true);
    await BackgroundWork.begin('DramaFlow · ဖိုင် ဖုန်းထဲ ယူနေတယ်', 'စတင်နေတယ်');
    final tmp = File('${Directory.systemTemp.path}/nursery_${DateTime.now().millisecondsSinceEpoch}.mp4');
    try {
      await c.downloadFile(name, tmp, (got, total) {
        BackgroundWork.update('ဖုန်းထဲ ယူနေတယ်', percent: total > 0 ? (got * 100 / total).round() : 0);
      });
      final base = name.toLowerCase().endsWith('.mp4') ? name.substring(0, name.length - 4) : name;
      try {
        await RenderChannel.saveToGallery(tmp.path, base);
      } on PlatformException catch (e) {
        if (e.code != 'use_export') rethrow;
        await AudioChannel.export(tmp.path, name, 'video/mp4');
      }
      _say('Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး ✓');
    } catch (e) {
      _say('ဖုန်းထဲ မရဘူး: $e', error: true);
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      await BackgroundWork.end();
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _dur(int ms) => '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}';

  // ---- widgets ----
  Widget _promptBox(String title, String hint, String text, {bool gemini = true, List<Widget> extra = const []}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(hint, style: const TextStyle(fontSize: 12, color: DfColors.muted)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: DfColors.raise, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 12))),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: () => _copy(text, title), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
            if (gemini) OutlinedButton.icon(onPressed: () => _gemini(text), icon: const Icon(Icons.auto_awesome, size: 16), label: const Text('Gemini ဖွင့်')),
            ...extra,
          ]),
        ]),
      ),
    );
  }

  Widget _drop<T>(String label, T value, List<DropdownMenuItem<T>> items, void Function(T?) onChanged) => DropdownButtonFormField<T>(
        key: ValueKey('$label$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: onChanged,
      );

  List<DropdownMenuItem<int>> _castItems(String none) => [
        DropdownMenuItem(value: -1, child: Text(none)),
        for (var i = 0; i < nurseryCharacters.length; i++) DropdownMenuItem(value: i, child: Text(nurseryCharacters[i].label, overflow: TextOverflow.ellipsis)),
      ];

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(title: const Text('Nursery Song')), body: const Center(child: CircularProgressIndicator()));
    final scenes = _scenes;
    final lyr = _lyricScenes;
    return Scaffold(
      appBar: AppBar(title: const Text('Nursery Song (ကလေးသီချင်း video)')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        const Text(
          'ကိုယ်ပိုင် (original) ကလေးသီချင်း ဗီဒီယိုအတွက် prompt တွေ ထုတ်ပေးပြီး၊ ပြီးသား သီချင်း + ပုံတွေကို Colab မှာ karaoke စာတန်းနဲ့ ပေါင်းပေးတယ်။ '
          'သီချင်း / ပုံ / animation ကို App က မဖန်တီးဘူး — Suno၊ Gemini၊ Veo / Kling စတဲ့ AI tool တွေမှာ ကိုယ်တိုင် ဖန်တီးရမယ်။',
          style: TextStyle(fontSize: 12.5, color: DfColors.muted),
        ),
        const SizedBox(height: 10),
        const Text('၁ · ပြင်ဆင်', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Wrap(spacing: 8, children: [for (final p in nurseryPresets) ActionChip(label: Text(p.label), onPressed: () => _preset(p))]),
        TextField(controller: _topic, minLines: 1, maxLines: 3, onChanged: (_) => _changed(), decoration: const InputDecoration(labelText: 'သီချင်း ခေါင်းစဉ် / အကြောင်းအရာ (English ကောင်း)')),
        _drop<int>('Theme', _d.theme, [for (final t in NurseryTheme.values) DropdownMenuItem(value: t.index, child: Text(t.label))], (v) => _changed(_d.copyWith(theme: v))),
        _drop<int>('⭐ Hero', _d.hero, [const DropdownMenuItem(value: -1, child: Text('— ကိုယ်ပိုင် (အောက်မှာ ရေး) —')), ..._castItems('').skip(1)], (v) => _changed(_d.copyWith(hero: v))),
        if (_d.hero < 0) TextField(controller: _heroC, minLines: 1, maxLines: 3, onChanged: (_) => _changed(), decoration: const InputDecoration(labelText: 'Hero ပုံစံ (English)', hintText: 'a cute little fox cub with a green scarf')),
        _drop<int>('🤝 Friend 1', _d.friend1, _castItems('— မရှိ —'), (v) => _changed(_d.copyWith(friend1: v))),
        _drop<int>('🎈 Friend 2', _d.friend2, _castItems('— မရှိ —'), (v) => _changed(_d.copyWith(friend2: v))),
        _drop<int>('ဘာသာစကား', _d.lang, [for (final l in NurseryLang.values) DropdownMenuItem(value: l.index, child: Text(l.label))], (v) => _changed(_d.copyWith(lang: v))),
        _drop<int>('ပုံစံ (style)', _d.style, [for (final s in NurseryStyle.values) DropdownMenuItem(value: s.index, child: Text(s.label))], (v) => _changed(_d.copyWith(style: v))),
        _drop<int>('Tempo', _d.tempo, [for (var i = 0; i < nurseryTempos.length; i++) DropdownMenuItem(value: i, child: Text(nurseryTempos[i]))], (v) => _changed(_d.copyWith(tempo: v))),
        _drop<int>('Video AI tool', _d.tool, [for (var i = 0; i < nurseryVideoTools.length; i++) DropdownMenuItem(value: i, child: Text(nurseryVideoTools[i]))], (v) => _changed(_d.copyWith(tool: v))),
        _drop<String>('Aspect ratio', _d.ratio, const [DropdownMenuItem(value: '16:9', child: Text('16:9 (YouTube)')), DropdownMenuItem(value: '9:16', child: Text('9:16 (Shorts)'))], (v) => _changed(_d.copyWith(ratio: v))),
        if (lyr.isEmpty) Row(children: [
          Expanded(child: Text('Scene ${_d.scenes} ခု', style: const TextStyle(fontSize: 13))),
          Expanded(flex: 2, child: Slider(value: _d.scenes.toDouble(), min: 4, max: 9, divisions: 5, onChanged: (v) => _changed(_d.copyWith(scenes: v.round())))),
        ]),
        const SizedBox(height: 14),
        const Text('၂ · Prompt တွေ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        _promptBox('① သီချင်းစာသား prompt', 'စာရေး AI (Gemini စသည်) ထဲ ထည့်၊ ရလာတာကို အောက်က Lyrics ကွက်မှာ paste', _lyricsPrompt, extra: [
          if (_ai.ready) FilledButton.icon(onPressed: _writing ? null : _writeLyrics, icon: const Icon(Icons.bolt, size: 16), label: Text(_writing ? 'ရေးနေတယ် …' : 'Gemini key နဲ့ တိုက်ရိုက်ရေး')),
        ]),
        TextField(
          controller: _lyrics,
          minLines: 4,
          maxLines: 12,
          onChanged: (_) => _changed(),
          decoration: const InputDecoration(labelText: 'Lyrics (AI ရေးတာ paste / ကိုယ်တိုင်ရေး)', hintText: '[Verse 1]\n…', alignLabelWithHint: true),
        ),
        if (lyr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text('Scene ${lyr.length} ခု ခွဲပြီး (Verse / Chorus တစ်ခုချင်း = ပုံတစ်ပုံ)', style: const TextStyle(fontSize: 12, color: DfColors.ok))),
        _promptBox('② သီချင်း prompt (Suno / Udio)', 'သီချင်းဖန်တီးတဲ့ AI ထဲ style အဖြစ် ထည့်၊ lyrics ကို Lyrics ကွက်မှာ ထည့်', _musicPrompt, gemini: false),
        _promptBox('③ ဇာတ်ကောင် ပုံစံ (character sheet) prompt', 'ပုံထုတ် AI မှာ အရင်လုပ်၊ ရတဲ့ပုံကို scene တိုင်းမှာ reference အဖြစ် ထည့်', _characterPrompt),
        Row(children: [
          Expanded(child: Text('④ Scene ${scenes.length} ခု', style: const TextStyle(fontWeight: FontWeight.w600))),
          OutlinedButton.icon(onPressed: () => _copy(_allPrompts(), 'Prompt အားလုံး'), icon: const Icon(Icons.copy_all, size: 16), label: const Text('Prompt အားလုံး Copy')),
        ]),
        const SizedBox(height: 6),
        for (final s in scenes) _sceneCard(s),
        _seoCard(),
        const SizedBox(height: 14),
        const Text('၃ · Video ထုတ် (Colab)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        _makeCard(scenes),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_msg!, style: TextStyle(fontSize: 12.5, color: _err ? DfColors.danger : DfColors.ok))),
        const SizedBox(height: 14),
        Card(
          child: ExpansionTile(
            title: const Text('Upload မတင်ခင် စစ်ရန်စာရင်း', style: TextStyle(fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final c in nurseryChecklist) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $c', style: const TextStyle(fontSize: 12.5)))],
          ),
        ),
      ]),
    );
  }

  Widget _sceneCard(NurseryPackScene s) {
    final file = _d.sceneFiles[s.number];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Scene ${s.number}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(s.action, style: const TextStyle(fontSize: 12.5)),
          Text('🎵 ${s.line}', style: const TextStyle(fontSize: 12.5, color: DfColors.muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 2, children: [
            TextButton.icon(onPressed: () => _copy(s.imagePrompt, 'Scene ${s.number} ပုံ prompt'), icon: const Icon(Icons.image_outlined, size: 16), label: const Text('ပုံ prompt')),
            TextButton.icon(onPressed: () => _copy(s.videoPrompt, 'Scene ${s.number} video prompt'), icon: const Icon(Icons.movie_outlined, size: 16), label: const Text('Video prompt')),
          ]),
          Row(children: [
            Expanded(child: Text(file == null ? 'ပုံ / clip မရွေးရသေးဘူး' : '✓ $file', style: TextStyle(fontSize: 12, color: file == null ? DfColors.warn : DfColors.ok), overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: _busy ? null : () => _pickScene(s.number), child: const Text('ဖုန်းက ပုံ')),
            TextButton(onPressed: _busy ? null : () => _libScene(s.number), child: const Text('Library')),
          ]),
        ]),
      ),
    );
  }

  Widget _seoCard() {
    final seo = buildSeo(topic: _topic.text, hero: _hero);
    final text = '${seo.titles.join('\n')}\n\n${seo.tags}';
    return _promptBox('⑤ Title / Tags ကောင်းမယ့် စာသား', 'Upload မှာ ကိုယ်ပိုင်ပြင်သုံးပါ (view / ဝင်ငွေ မကတိပြုဘူး)', text, gemini: false);
  }

  Widget _makeCard(List<NurseryPackScene> scenes) {
    final have = [for (final s in scenes) if (_d.sceneFiles.containsKey(s.number)) s].length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'ပြီးသား သီချင်း (.mp3 / .wav ၊ 24 MB အောက်) နဲ့ scene တိုင်းရဲ့ ပုံ / clip ကို တင်ပြီး Colab backend မှာ ပေါင်းမယ်။ ဖုန်းက ပုံက ≤1024px အရွယ်ဖြစ်သွားမယ်၊ ပုံကြည်လင်ချင်ရင် Drive library ထဲ ပုံကြီးထည့်ပြီး "Library" က ရွေးပါ။',
            style: TextStyle(fontSize: 12, color: DfColors.muted),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(_d.song.isEmpty ? 'သီချင်း မရွေးရသေးဘူး' : '🎵 ${_d.song} · ${_dur(_d.songMs)}', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            OutlinedButton(onPressed: _busy ? null : _pickSong, child: Text(_d.song.isEmpty ? 'သီချင်း ရွေး' : 'ပြောင်း')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Karaoke:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Lyrics ကနေ'), selected: _mode == 'lyrics', onSelected: (_) => setState(() => _mode = 'lyrics')),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('Whisper နားထောင်'), selected: _mode == 'whisper', onSelected: (_) => setState(() => _mode = 'whisper')),
          ]),
          Text(
            _mode == 'lyrics'
                ? 'ကိုယ့် lyrics ကို သီချင်းအရှည်အတိုင်း စာကြောင်းအရှည်အလိုက် ခွဲမယ် — အကြမ်းချိန်ပဲ၊ ဘာသာမရွေး။'
                : 'Whisper က သီချင်းကို နားထောင်ပြီး စာလုံးအချိန်ယူမယ် — English / 中文 အတွက်ပဲ ကောင်း၊ ဆိုထားတဲ့ မြန်မာစာ မမှန်နိုင်ဘူး။',
            style: const TextStyle(fontSize: 12, color: DfColors.muted),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(_d.karaoke.isEmpty ? 'Karaoke စာတန်း မရှိသေးဘူး (မလုပ်လည်း ရတယ်၊ စာတန်းမပါဘဲ ထွက်မယ်)' : '✓ ${_d.karaoke}', style: TextStyle(fontSize: 12, color: _d.karaoke.isEmpty ? DfColors.muted : DfColors.ok), overflow: TextOverflow.ellipsis)),
            OutlinedButton(onPressed: (_busy || _d.song.isEmpty) ? null : _karaoke, child: const Text('Karaoke ထုတ်')),
          ]),
          const SizedBox(height: 10),
          Text('ပုံ / clip $have / ${scenes.length} scene', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          if (_busy) ...[
            LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null),
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('$_what · $_stage${_pct > 0 ? ' · $_pct%' : ''}', style: const TextStyle(fontSize: 12.5))),
            OutlinedButton(onPressed: _stop, child: const Text('ရပ်မယ်')),
          ] else
            FilledButton.icon(onPressed: _make, icon: const Icon(Icons.movie_creation_outlined, size: 18), label: const Text('သီချင်း video ထုတ်မယ်')),
          if (_out != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(onPressed: _saving ? null : _toPhone, icon: const Icon(Icons.phone_android, size: 18), label: Text(_saving ? 'ယူနေတယ် …' : 'ဖုန်းထဲ (Gallery) ယူမယ်')),
            ),
          if (_saving) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}
