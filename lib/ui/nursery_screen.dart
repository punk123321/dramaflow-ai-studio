import 'dart:async';
import 'dart:io';
import 'dart:math';

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
import 'widgets.dart';

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
  int _tab = 0; // 0 setup, 1 scenes, 2 export
  final Map<int, String> _localPics = {}; // scene number -> a picture picked from the phone this session (for the preview only)

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
  NurserySeo get _seo => buildSeo(topic: _topic.text, hero: _hero, cast: _cast, style: _style);

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

  NurseryGenre get _genre => NurseryGenre.values[_d.genre];
  String get _lyricsPrompt => buildLyricsPrompt(
        theme: _theme,
        custom: _topic.text,
        lang: _lang,
        verses: (_d.scenes / 2).round().clamp(1, 4).toInt(),
        character: _heroName,
        genre: _genre,
        tempo: _tempo,
        withStyle: true,
      );
  // The style text the text AI wrote for the song AI, or the one the app builds.
  String get _musicPrompt => _d.songStyle.trim().isNotEmpty ? _d.songStyle.trim() : buildMusicPrompt(lang: _lang, bpm: bpmOf(_tempo), genre: _genre);
  List<NurseryCastSheet> get _castSheets => buildCastSheets(hero: _hero, friend1: _castDesc(_d.friend1), friend2: _castDesc(_d.friend2), style: _style);

  String _allPrompts() {
    final b = StringBuffer();
    b.writeln('=== 1. LYRICS PROMPT (text AI) ===\n$_lyricsPrompt\n');
    b.writeln('=== 2. SONG PROMPT (Suno / Udio) ===\n$_musicPrompt\n');
    for (final c in _castSheets) {
      b.writeln('=== 3. CHARACTER SHEET · ${c.role} · ${c.name} (image AI) ===\n${c.prompt}\n');
    }
    b.writeln('=== NEGATIVE PROMPT (for AIs that have the box) ===\n$nurseryNegativePrompt\n');
    for (final s in _scenes) {
      b.writeln('=== SCENE ${s.number} · IMAGE PROMPT ===\n${s.imagePrompt}\n');
    }
    for (final s in _scenes) {
      b.writeln('=== SCENE ${s.number} · VIDEO PROMPT (${s.line}) ===\n${s.videoPrompt}\n');
    }
    final seo = _seo;
    b.writeln('=== TITLES ===\n${seo.titles.join('\n')}\n\n=== TAGS ===\n${seo.tags}\n\n=== DESCRIPTION ===\n${seo.description}');
    for (final t in seo.thumbs) {
      b.writeln('\n=== THUMBNAIL · ${t.concept} (add the words "${t.overlay}" afterwards) ===\n${t.prompt}');
    }
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
      _applyAnswer(t, quiet: true);
      _say('Gemini က သီချင်းစာသား ရေးပေးပြီး — ဖတ်ပြီး ကိုယ်တိုင်ပြင်ပါ (AI စာသားမို့ မူရင်းမှန်၊ ရှိပြီးသား သီချင်းနဲ့ ဆင်တူမှု မရှိဘူးလို့ အာမမခံဘူး)');
    } on GeminiTtsException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
    if (mounted) setState(() => _writing = false);
  }

  /// An AI's answer to the songwriter prompt (or a plain pasted song): the "SUNO STYLE" part goes to the song prompt and
  /// the lyrics to the Lyrics box. A plain song with no headings is all lyrics.
  void _applyAnswer(String raw, {bool quiet = false}) {
    final a = splitSongAnswer(raw);
    _lyrics.text = a.lyrics;
    _changed(_d.copyWith(songStyle: a.style.isNotEmpty ? a.style : _d.songStyle));
    if (!quiet) _say(a.style.isEmpty ? 'Lyrics ထည့်ပြီး ✓' : 'Song style + Lyrics ခွဲထည့်ပြီး ✓ (style ကို ② Song prompt မှာ ကြည့်ပါ)');
  }

  Future<void> _pasteAnswer() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      _say('Clipboard ထဲ စာ မရှိဘူး — AI ရဲ့ အဖြေကို အရင် Copy လုပ်ပါ', error: true);
      return;
    }
    _applyAnswer(t);
  }

  void _randomIdea() {
    _topic.text = nurserySongIdeas[Random().nextInt(nurserySongIdeas.length)];
    _changed(_d.copyWith(theme: NurseryTheme.custom.index));
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
      style: p.style.index,
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
      _localPics[n] = path;
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
      if (pick != null) {
        _localPics.remove(n);
        _changed(_d.copyWith(sceneFiles: {..._d.sceneFiles, n: pick}));
      }
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

  // ---- layout helpers ----
  static const _gap = SizedBox(height: 14);

  Widget _card(String title, IconData icon, List<Widget> children, {String? hint, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DfColors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DfColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: DfColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          if (trailing != null) trailing,
        ]),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(fontSize: 12, color: DfColors.muted))),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  /// A rounded tonal button with an icon (the one button style of this screen).
  Widget _pill(String label, IconData icon, VoidCallback? onTap, {bool strong = false}) {
    final shape = const StadiumBorder();
    final style = ButtonStyle(shape: WidgetStatePropertyAll(shape), visualDensity: VisualDensity.compact, minimumSize: const WidgetStatePropertyAll(Size(0, 38)));
    final text = Text(label, overflow: TextOverflow.ellipsis);
    return strong
        ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 17), label: text, style: style)
        : FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 17), label: text, style: style);
  }

  Widget _badge(String text, {Color? color, bool filled = false}) {
    final c = color ?? DfColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: filled ? 0 : 0.5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: filled ? DfColors.onAccent : c)),
    );
  }

  Widget _drop<T>(String label, T value, List<DropdownMenuItem<T>> items, void Function(T?) onChanged) => DropdownButtonFormField<T>(
        key: ValueKey('$label$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
        items: items,
        onChanged: onChanged,
      );

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);

  Widget _t(String s) => Text(s, overflow: TextOverflow.ellipsis);

  List<DropdownMenuItem<int>> _castItems(String none) => [
        DropdownMenuItem(value: -1, child: _t(none)),
        for (var i = 0; i < nurseryCharacters.length; i++) DropdownMenuItem(value: i, child: _t(nurseryCharacters[i].label)),
      ];

  Widget _promptPreview(String text) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 110),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: DfColors.raise, borderRadius: BorderRadius.circular(12), border: Border.all(color: DfColors.line)),
        child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 12))),
      );

  static String _two2(int n) => n.toString().padLeft(2, '0');
  static String _mmss(double s) => '${_two2(s ~/ 60)}:${_two2(s.floor() % 60)}';

  /// "00:00 – 00:08" for every scene: the song length (or 8 s a scene before a song is chosen) shared by the same weights the video uses.
  List<String> _sceneTimes(List<NurseryPackScene> sc) {
    if (sc.isEmpty) return const [];
    final total = _d.songMs > 0 ? _d.songMs / 1000 : sc.length * 8.0;
    final ls = _lyricScenes;
    var w = ls.length == sc.length ? sceneWeights(ls) : List<double>.filled(sc.length, 1);
    var sum = w.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) {
      w = List<double>.filled(sc.length, 1);
      sum = sc.length.toDouble();
    }
    var t = 0.0;
    final out = <String>[];
    for (final x in w) {
      final e = t + total * x / sum;
      out.add('${_mmss(t)} – ${_mmss(e)}');
      t = e;
    }
    return out;
  }

  // ---- screen ----
  @override
  Widget build(BuildContext context) {
    if (!_loaded) return Scaffold(appBar: AppBar(title: const Text('Nursery Studio')), body: const Center(child: CircularProgressIndicator()));
    final scenes = _scenes;
    final body = switch (_tab) {
      0 => _setupTab(),
      1 => _scenesTab(scenes),
      _ => _exportTab(scenes),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nursery Studio'),
        actions: [IconButton(tooltip: 'ဒီ screen က ဘာလုပ်ပေးလဲ', icon: const Icon(Icons.info_outline), onPressed: _about)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: ButtonStyle(visualDensity: VisualDensity.comfortable, shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
            segments: const [
              ButtonSegment(value: 0, label: Text('1. Setup')),
              ButtonSegment(value: 1, label: Text('2. Scenes')),
              ButtonSegment(value: 2, label: Text('3. Export')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        if (_msg != null) _banner(),
        Expanded(child: body),
      ]),
    );
  }

  Widget _banner() {
    final c = _err ? DfColors.danger : DfColors.ok;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_err ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: c),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(_msg!, style: TextStyle(fontSize: 12.5, color: c))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _msg = null)),
      ]),
    );
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nursery Studio'),
        content: const Text(
          'ကိုယ်ပိုင် (original) ကလေးသီချင်း ဗီဒီယိုအတွက် prompt တွေ ထုတ်ပေးပြီး၊ ပြီးသား သီချင်း + ပုံတွေကို Colab မှာ karaoke စာတန်းနဲ့ ပေါင်းပေးတယ်။\n\n'
          'သီချင်း / ပုံ / animation ကို App က မဖန်တီးဘူး — Suno၊ Gemini၊ Veo / Kling စတဲ့ AI tool တွေမှာ ကိုယ်တိုင် ဖန်တီးရမယ်။',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  // ---- tab 1: setup ----
  Widget _setupTab() {
    final lyr = _lyricScenes;
    return ListView(
      key: const PageStorageKey('nursery_setup'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _card('Quick presets & topic', Icons.auto_awesome, [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final p in nurseryPresets) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(p.label), onPressed: () => _preset(p))),
            ]),
          ),
          _gap,
          TextField(
            controller: _topic,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: 'သီချင်း ခေါင်းစဉ် / အကြောင်းအရာ',
              hintText: 'English ကောင်း',
              suffixIcon: IconButton(tooltip: 'အကြံ တစ်ခု ရွေးပေး', icon: const Icon(Icons.casino_outlined), onPressed: _randomIdea),
            ),
          ),
          _gap,
          _drop<int>('Theme', _d.theme, [for (final t in NurseryTheme.values) DropdownMenuItem(value: t.index, child: _t(t.label))], (v) => _changed(_d.copyWith(theme: v))),
        ]),
        _card('Character cast', Icons.groups_2_outlined, [
          _drop<int>('⭐ Hero', _d.hero, [const DropdownMenuItem(value: -1, child: Text('— ကိုယ်ပိုင် (အောက်မှာ ရေး) —')), ..._castItems('').skip(1)], (v) => _changed(_d.copyWith(hero: v))),
          if (_d.hero < 0) ...[
            _gap,
            TextField(controller: _heroC, minLines: 1, maxLines: 3, onChanged: (_) => _changed(), decoration: const InputDecoration(labelText: 'Hero ပုံစံ (English)', hintText: 'a cute little fox cub with a green scarf')),
          ],
          _gap,
          _drop<int>('🤝 Friend 1', _d.friend1, _castItems('— မရှိ —'), (v) => _changed(_d.copyWith(friend1: v))),
          _gap,
          _drop<int>('🎈 Friend 2', _d.friend2, _castItems('— မရှိ —'), (v) => _changed(_d.copyWith(friend2: v))),
        ]),
        _card('Style, language & sound', Icons.palette_outlined, [
          _two(
            _drop<int>('ဘာသာစကား', _d.lang, [for (final l in NurseryLang.values) DropdownMenuItem(value: l.index, child: _t(l.label))], (v) => _changed(_d.copyWith(lang: v))),
            _drop<String>('Aspect ratio', _d.ratio, [DropdownMenuItem(value: '16:9', child: _t('16:9 YouTube')), DropdownMenuItem(value: '9:16', child: _t('9:16 Shorts'))], (v) => _changed(_d.copyWith(ratio: v))),
          ),
          _gap,
          _drop<int>('ပုံစံ (style)', _d.style, [for (final s in NurseryStyle.values) DropdownMenuItem(value: s.index, child: _t(s.label))], (v) => _changed(_d.copyWith(style: v))),
          _gap,
          _drop<int>('Music genre', _d.genre, [for (final g in NurseryGenre.values) DropdownMenuItem(value: g.index, child: _t(g.label))], (v) => _changed(_d.copyWith(genre: v))),
          _gap,
          _drop<int>('Tempo', _d.tempo, [for (var i = 0; i < nurseryTempos.length; i++) DropdownMenuItem(value: i, child: _t(nurseryTempos[i]))], (v) => _changed(_d.copyWith(tempo: v))),
          _gap,
          _drop<int>('Video AI tool', _d.tool, [for (var i = 0; i < nurseryVideoTools.length; i++) DropdownMenuItem(value: i, child: _t(nurseryVideoTools[i]))], (v) => _changed(_d.copyWith(tool: v))),
          if (lyr.isEmpty) ...[
            _gap,
            Row(children: [
              _badge('Scene ${_d.scenes}'),
              Expanded(child: Slider(value: _d.scenes.toDouble(), min: 4, max: 12, divisions: 8, onChanged: (v) => _changed(_d.copyWith(scenes: v.round())))),
            ]),
          ] else ...[
            _gap,
            Text('Lyrics ကနေ Scene ${lyr.length} ခု ခွဲပြီးသား (Verse / Chorus တစ်ခုချင်း = ပုံတစ်ပုံ)', style: const TextStyle(fontSize: 12, color: DfColors.ok)),
          ],
        ]),
        GradientButton(label: 'ဆက်သွားမယ် · Scenes', icon: Icons.arrow_forward_rounded, onPressed: () => setState(() => _tab = 1)),
      ],
    );
  }

  // ---- tab 2: lyrics, prompts, scenes ----
  Widget _scenesTab(List<NurseryPackScene> scenes) {
    final times = _sceneTimes(scenes);
    final sheets = _castSheets;
    final lyr = _lyricScenes;
    return ListView(
      key: const PageStorageKey('nursery_scenes'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _card('① Lyrics', Icons.lyrics_outlined, [
          const Text('စာရေး AI (Gemini စသည်) ထဲ ထည့်၊ ရလာတဲ့ အဖြေကို အောက်မှာ paste လုပ်ပါ (Style + Lyrics အလိုလို ခွဲပေးမယ်)။', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          const SizedBox(height: 10),
          _promptPreview(_lyricsPrompt),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('Copy', Icons.copy, () => _copy(_lyricsPrompt, 'Lyrics prompt')),
            _pill('Gemini ဖွင့်', Icons.auto_awesome, () => _gemini(_lyricsPrompt)),
            if (_ai.ready) _pill(_writing ? 'ရေးနေတယ် …' : 'Gemini key နဲ့ ရေး', Icons.bolt, _writing ? null : _writeLyrics, strong: true),
          ]),
          _gap,
          TextField(
            controller: _lyrics,
            minLines: 4,
            maxLines: 12,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Lyrics (AI ရေးတာ paste / ကိုယ်တိုင်ရေး)', hintText: '[Verse 1]\n…', alignLabelWithHint: true),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _pill('Clipboard က paste', Icons.content_paste, _pasteAnswer),
            _pill('Style / Lyrics ခွဲ', Icons.call_split, _lyrics.text.trim().isEmpty ? null : () => _applyAnswer(_lyrics.text)),
            if (_d.songStyle.trim().isNotEmpty) _badge('Song style ✓', color: DfColors.ok),
            if (lyr.isNotEmpty) _badge('${lyr.length} scene', color: DfColors.cyan),
          ]),
        ]),
        _card('② Song prompt', Icons.music_note_outlined, [
          const Text('Suno / Udio ထဲ style အဖြစ် ထည့်၊ lyrics ကို Lyrics ကွက်မှာ ထည့်', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          const SizedBox(height: 10),
          _promptPreview(_musicPrompt),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('Copy', Icons.copy, () => _copy(_musicPrompt, 'Song prompt')),
            if (_d.songStyle.trim().isNotEmpty) _pill('App ရဲ့ style သုံး', Icons.restart_alt, () => _changed(_d.copyWith(songStyle: ''))),
          ]),
        ]),
        _card('③ Character sheets', Icons.face_retouching_natural_outlined, [
          const Text('ပုံထုတ် AI မှာ အရင်လုပ်၊ ရတဲ့ပုံကို scene တိုင်းမှာ reference အဖြစ် ထည့်', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          const SizedBox(height: 10),
          for (final c in sheets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text('${c.role} · ${c.name}', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                _pill('Copy', Icons.copy, () => _copy(c.prompt, '${c.role} sheet')),
              ]),
            ),
          Row(children: [
            const Expanded(child: Text('Negative prompt', style: TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            _pill('Copy', Icons.copy, () => _copy(nurseryNegativePrompt, 'Negative prompt')),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          child: Row(children: [
            const Icon(Icons.movie_filter_outlined, size: 20, color: DfColors.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('Scenes · ${scenes.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            _pill('Prompt အားလုံး', Icons.copy_all, () => _copy(_allPrompts(), 'Prompt အားလုံး')),
          ]),
        ),
        for (var i = 0; i < scenes.length; i++) _sceneCard(scenes[i], i < times.length ? times[i] : ''),
        const SizedBox(height: 6),
        GradientButton(label: 'ဆက်သွားမယ် · Export', icon: Icons.arrow_forward_rounded, onPressed: () => setState(() => _tab = 2)),
      ],
    );
  }

  bool _isVideoName(String n) {
    final l = n.toLowerCase();
    return ['.mp4', '.mov', '.mkv', '.webm', '.m4v'].any(l.endsWith);
  }

  /// The 16:9 picture box of a scene: the picked picture, a name tile for a library file, or a dashed "add" box.
  Widget _mediaBox(NurseryPackScene s, String? file) {
    final local = _localPics[s.number];
    Widget inner;
    if (local != null && File(local).existsSync()) {
      inner = Stack(fit: StackFit.expand, children: [
        Image.file(File(local), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: DfColors.raise)),
        Positioned(left: 8, bottom: 8, child: _badge('✓ ${file ?? ''}', color: DfColors.ok, filled: false)),
      ]);
    } else if (file != null) {
      final video = _isVideoName(file);
      inner = Container(
        color: DfColors.raise,
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(video ? Icons.movie_outlined : Icons.image_outlined, size: 32, color: DfColors.ok),
          const SizedBox(height: 6),
          Text(file, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: DfColors.ok)),
          const Text('Library ထဲက ဖိုင် (preview မပြဘူး)', style: TextStyle(fontSize: 11, color: DfColors.muted)),
        ]),
      );
    } else {
      inner = CustomPaint(
        painter: const _DashedBorderPainter(color: DfColors.muted),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_photo_alternate_outlined, size: 30, color: DfColors.muted),
            SizedBox(height: 6),
            Text('ပုံ / clip ထည့်ရန်', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          ]),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: DfColors.raise.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: _busy ? null : () => _pickScene(s.number), child: inner),
      ),
    );
  }

  Widget _sceneCard(NurseryPackScene s, String time) {
    final file = _d.sceneFiles[s.number];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: DfColors.surface.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(16), border: Border.all(color: DfColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _badge('Scene ${_two2(s.number)}', filled: true),
          const SizedBox(width: 8),
          if (time.isNotEmpty) _badge(time, color: DfColors.cyan),
          const Spacer(),
          Icon(file == null ? Icons.radio_button_unchecked : Icons.check_circle, size: 20, color: file == null ? DfColors.warn : DfColors.ok),
        ]),
        const SizedBox(height: 12),
        _mediaBox(s, file),
        const SizedBox(height: 12),
        Text(s.action, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text('🎵 ${s.line}', style: const TextStyle(fontSize: 12.5, color: DfColors.muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('Image prompt', Icons.image_outlined, () => _copy(s.imagePrompt, 'Scene ${s.number} ပုံ prompt')),
          _pill('Video prompt', Icons.movie_outlined, () => _copy(s.videoPrompt, 'Scene ${s.number} video prompt')),
          _pill('Phone', Icons.phone_android, _busy ? null : () => _pickScene(s.number)),
          _pill('Library', Icons.cloud_outlined, _busy ? null : () => _libScene(s.number)),
        ]),
      ]),
    );
  }

  // ---- tab 3: export ----
  Widget _statusRow(IconData icon, String label, String value, {required bool ok, Widget? badge, List<Widget> actions = const []}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle : icon, size: 20, color: ok ? DfColors.ok : DfColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: DfColors.muted)),
            const SizedBox(height: 2),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: ok ? DfColors.ink : DfColors.warn)),
          ]),
        ),
        if (badge != null) badge,
      ]),
      if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10, left: 30), child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
    ]);
  }

  Widget _exportTab(List<NurseryPackScene> scenes) {
    final have = [for (final s in scenes) if (_d.sceneFiles.containsKey(s.number)) s].length;
    final seo = _seo;
    return ListView(
      key: const PageStorageKey('nursery_export'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _card('Ready to export', Icons.fact_check_outlined, [
          _statusRow(
            Icons.music_note_outlined,
            'Song (.mp3 / .wav, 24 MB အောက်)',
            _d.song.isEmpty ? 'မရွေးရသေးဘူး' : '${_d.song} · ${_dur(_d.songMs)}',
            ok: _d.song.isNotEmpty,
            actions: [_pill(_d.song.isEmpty ? 'သီချင်း ရွေး' : 'ပြောင်း', Icons.upload_file, _busy ? null : _pickSong)],
          ),
          const Divider(height: 28),
          _statusRow(
            Icons.subtitles_outlined,
            'Karaoke စာတန်း',
            _d.karaoke.isEmpty ? 'မရှိသေးဘူး (မလုပ်လည်း ရတယ်၊ စာတန်းမပါဘဲ ထွက်မယ်)' : _d.karaoke,
            ok: _d.karaoke.isNotEmpty,
            actions: [_pill('Karaoke ထုတ်', Icons.lyrics_outlined, (_busy || _d.song.isEmpty) ? null : _karaoke)],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(label: const Text('Lyrics ကနေ'), selected: _mode == 'lyrics', onSelected: (_) => setState(() => _mode = 'lyrics')),
              ChoiceChip(label: const Text('Whisper နားထောင်'), selected: _mode == 'whisper', onSelected: (_) => setState(() => _mode = 'whisper')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 6),
            child: Text(
              _mode == 'lyrics' ? 'စာကြောင်းအရှည်အလိုက် အကြမ်းချိန် (ဘာသာမရွေး)' : 'English / 中文 အတွက်ပဲ ကောင်း၊ မြန်မာစာ မမှန်နိုင်ဘူး',
              style: const TextStyle(fontSize: 12, color: DfColors.muted),
            ),
          ),
          const Divider(height: 28),
          _statusRow(
            Icons.photo_library_outlined,
            'ပုံ / clip',
            have == scenes.length ? 'Scene အားလုံး ပြည့်ပြီ' : 'မရွေးရသေးတဲ့ scene ${scenes.length - have} ခု (Scenes tab မှာ ထည့်ပါ)',
            ok: have == scenes.length && scenes.isNotEmpty,
            badge: _badge('$have / ${scenes.length}', color: have == scenes.length ? DfColors.ok : DfColors.warn),
          ),
        ]),
        if (_busy) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: DfColors.surface.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(16), border: Border.all(color: DfColors.accent)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_what, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null, minHeight: 6, borderRadius: BorderRadius.circular(6)),
              const SizedBox(height: 8),
              Text('$_stage${_pct > 0 ? ' · $_pct%' : ''}', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: _pill('ရပ်မယ်', Icons.stop_circle_outlined, _stop)),
            ]),
          ),
        ] else
          GradientButton(label: 'သီချင်း video ထုတ်မယ်', icon: Icons.movie_creation_outlined, onPressed: _make),
        if (_out != null && !_busy) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: _saving ? null : _toPhone,
              icon: const Icon(Icons.phone_android, size: 20),
              label: Text(_saving ? 'ယူနေတယ် …' : 'ဖုန်းထဲ (Gallery) ယူမယ်'),
            ),
          ),
        ],
        if (_saving) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        const SizedBox(height: 18),
        _card('⑤ Upload text', Icons.upload_outlined, [
          const Text('Title / Tags / Description / Thumbnail ideas — ကိုယ်ပိုင်ပြင်သုံးပါ (view / ဝင်ငွေ မကတိပြုဘူး)', style: TextStyle(fontSize: 12, color: DfColors.muted)),
          const SizedBox(height: 10),
          _promptPreview('${seo.titles.join('\n')}\n\n${seo.tags}'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('Titles + Tags', Icons.copy, () => _copy('${seo.titles.join('\n')}\n\n${seo.tags}', 'Title / Tags')),
            _pill('Description', Icons.notes, () => _copy(seo.description, 'Description')),
          ]),
          if (seo.thumbs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Thumbnail prompts (စာ မပါဘူး — စာကို ပုံရပြီးမှ Editor မှာ ထည့်)', style: TextStyle(fontSize: 12, color: DfColors.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in seo.thumbs) _pill(t.concept, Icons.image_outlined, () => _copy('${t.prompt}\n\nAdd afterwards in an editor: "${t.overlay}"', 'Thumbnail prompt')),
            ]),
          ],
        ]),
        Container(
          decoration: BoxDecoration(color: DfColors.surface.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(16), border: Border.all(color: DfColors.line)),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.checklist_rtl, color: DfColors.accent),
              title: const Text('Upload မတင်ခင် စစ်ရန်စာရင်း', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final c in nurseryChecklist) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $c', style: const TextStyle(fontSize: 12.5)))],
            ),
          ),
        ),
      ],
    );
  }
}

/// A dashed rounded outline for an empty picture box.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
