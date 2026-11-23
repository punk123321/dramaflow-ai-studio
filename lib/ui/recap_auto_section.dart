import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/assembly.dart';
import '../core/backend_kind.dart';
import '../core/news_video.dart';
import '../core/recap_auto.dart';
import '../core/recap_queue.dart' show QStep, qStepLabels;
import '../core/script.dart';
import '../core/source_link.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../core/usage_log.dart';
import '../data/ai_settings_repo.dart';
import '../data/assembly_settings_repo.dart';
import '../data/audio_clip.dart';
import '../data/handoff_repo.dart';
import '../data/recap_backend_repo.dart';
import '../data/usage_repo.dart';
import '../platform/assembly_client.dart';
import '../platform/audio_channel.dart';
import '../platform/gemini_files.dart';
import '../platform/link_ingest.dart';
import '../platform/news_video_client.dart';
import '../platform/recap_client.dart';
import 'recap_step_bar.dart';
import 'widgets.dart';

/// The "Auto" card of Video Recap and Scene Recap. One tap: the user's own
/// backend asks Gemini for every part and makes the voice. The parts are saved
/// like pasted answers, so the screen's own "save as script" button follows.
class RecapAutoSection extends StatefulWidget {
  const RecapAutoSection({
    super.key,
    required this.projectId,
    required this.task,
    required this.mode,
    required this.videoUri,
    required this.buildGroups,
    required this.onTextsSaved,
    required this.onSrtReady,
    this.durationMs = 0,
    this.linkUrl = '',
  });

  final int projectId;
  final String task;

  /// "video" (Gemini watches the whole video) or "scenes" (pictures + dialogue).
  final String mode;
  final String? videoUri;
  final Future<List<RecapGroup>> Function(void Function(String) status) buildGroups;
  final Future<void> Function() onTextsSaved;

  /// Called after the subtitles were made from the sound and saved, so the
  /// screen can read them again before the groups are built.
  final Future<void> Function() onSrtReady;

  /// Length of the video (0 = not known), to say how many minutes of sound
  /// AssemblyAI will get.
  final int durationMs;

  /// The video link of this project ('' = none). When there is one, the
  /// backend puts that video into Gemini and the phone uploads nothing.
  final String linkUrl;

  @override
  State<RecapAutoSection> createState() => _RecapAutoSectionState();
}

class _RecapAutoSectionState extends State<RecapAutoSection> {
  final _repo = RecapBackendRepo();
  final _handoff = HandoffRepo();
  final _connectC = TextEditingController();
  final _modelC = TextEditingController(text: defaultTextModel);
  final _fallbackC = TextEditingController();
  final _usageRepo = UsageRepo();
  UsageLog _usage = const UsageLog();

  NewsVideoSettings _s = const NewsVideoSettings();
  String _geminiKey = '';
  bool _loaded = false;
  AssemblySettings _asr = const AssemblySettings();
  bool _useAsr = true;
  AssemblyClient? _asrClient;
  bool _makeVoice = true;
  String _voice = 'my-MM-ThihaNeural';

  bool _running = false;
  bool _canceled = false;
  String _stage = '';
  int _progress = 0;
  RecapJob? _result;
  // What a retry needs: the groups of the last run and the video already in Gemini.
  List<RecapGroup> _lastGroups = const [];
  String _lastFileUri = '';
  String _lastMime = 'video/mp4';
  String _savedJob = '';

  // Where the run is, for the step bar, and a log to copy when something fails.
  QStep? _qs;
  QStep? _qfail;
  final Set<QStep> _qdone = {};
  final Set<QStep> _qskip = {};
  final List<String> _log = [];
  List<SelfCheck>? _checks;
  bool _testing = false;
  String? _msg;
  bool _err = false;
  RecapClient? _client;

  bool get _video => widget.mode == 'video';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await _repo.load();
    final g = await AiSettingsRepo().load();
    final a = await AssemblySettingsRepo().load();
    final fb = await _usageRepo.fallbackModel();
    final u = await _usageRepo.today();
    final job = (await _handoff.getDoc(widget.projectId, _jobKind) ?? '').trim();
    if (!mounted) return;
    setState(() {
      _savedJob = job;
      _asr = a;
      _usage = u;
      _fallbackC.text = fb;
      _s = s;
      _geminiKey = g.apiKey.trim();
      _connectC.text = s.ready ? '${s.url}#${s.token}' : '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _canceled = true;
    _client?.cancel();
    _asrClient?.cancel();
    _connectC.dispose();
    _modelC.dispose();
    _fallbackC.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    _note('${error ? '✗ ' : ''}$m');
    setState(() {
      _msg = m;
      _err = error;
      if (error && _running) _qfail = _qs;
    });
  }

  void _note(String m) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} ${m.replaceAll('\n', ' | ')}');
    if (_log.length > 200) _log.removeAt(0);
  }

  void _stepReset() {
    _qs = null;
    _qfail = null;
    _qdone.clear();
    _qskip.clear();
  }

  /// Enters [s]; the step before it counts as done unless it was skipped.
  void _enter(QStep s) {
    final p = _qs;
    if (p != null && p != s && !_qskip.contains(p)) _qdone.add(p);
    _qs = s;
    _qfail = null;
    _note('▶ ${qStepLabels[s]}');
    if (mounted) setState(() {});
  }

  void _skipStep(QStep s, String why) {
    _qskip.add(s);
    _note('– ${qStepLabels[s]} ကျော်: $why');
    if (mounted) setState(() {});
  }

  void _finishSteps() {
    final p = _qs;
    if (p != null && !_qskip.contains(p)) _qdone.add(p);
    if (mounted) setState(() {});
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    _say('Log ကူးပြီး — error ပေါ်ရင် paste လုပ်ပြီး ပို့ပါ');
  }

  Future<void> _saveBackend() async {
    final c = parseConnect(_connectC.text);
    if (c == null || c.token.isEmpty) {
      _say('Backend လိပ်စာ မမှန်ပါ။ "https://….go.altare.global#APP_TOKEN" ပုံစံ တစ်ကြောင်းလုံး ထည့်ပါ။', error: true);
      return;
    }
    final next = _s.copyWith(url: c.url, token: c.token);
    await _repo.save(next);
    if (!mounted) return;
    setState(() => _s = next);
    _say('သိမ်းပြီး၊ ချိတ်ကြည့်နေတယ် …');
    final svc = await NewsVideoClient(next).healthService();
    if (svc == null) {
      _say('သိမ်းပြီး၊ ဒါပေမဲ့ Backend မဖြေဘူး (Colab Cell ၅ run နေလား၊ URL မှန်လား စစ်ပါ)', error: true);
    } else if (backendKindOf(svc) == BackendKind.news) {
      _say(wrongBackendForRecap, error: true);
    } else {
      _say('Backend နဲ့ ချိတ်မိပြီ ✓${backendKindOf(svc) == BackendKind.unknown ? ' (backend အမည်: ${svc.isEmpty ? 'မသိ' : svc})' : ''}');
    }
  }

  Future<bool> _confirm(bool asr) async {
    final what = _video && widget.linkUrl.isNotEmpty
        ? 'link ကို သင့် Backend ဆီ ပို့မယ် — Backend က ဗီဒီယိုကို ဆွဲပြီး သင့် Gemini account ဆီ တင်မယ် (ဖုန်းက မတင်ဘူး)။ '
            'Gemini key ကို သင့် Backend ဆီ ပို့မယ်။ မူရင်းဗီဒီယိုကို မပြင်ဘူး။ (ဗီဒီယိုရှည်ရင် ၅–၁၅ မိနစ်လောက် ကြာနိုင်တယ်)'
        : _video
        ? 'ဗီဒီယိုတစ်ခုလုံးကို သင့် Gemini account (Google) ဆီ upload လုပ်မယ်။ Gemini key ကို သင့် Backend ဆီ ပို့မယ်။ '
            'မူရင်းဗီဒီယိုကို မပြင်ဘူး၊ ဖုန်း cache ထဲ ယာယီကူးပြီး ပြီးရင် ဖျက်မယ်။ (ဗီဒီယိုကြီးရင် data အများကြီး သုံးမယ် — Wi-Fi သုံးပါ)'
        : 'Scene ပုံတွေ (contact sheet) နဲ့ စာတန်းစာသားကို သင့် Backend နဲ့ Google (Gemini) ဆီ ပို့မယ်။ Gemini key ကိုလည်း Backend ဆီ ပို့မယ်။';
    final mins = asrMinutesFor(widget.durationMs);
    final extra = asr ? '\n\nစာတန်း မရှိသေးလို့ ဗီဒီယိုထဲက အသံကို AssemblyAI ဆီ ပို့မယ် (ပုံမပို့ဘူး၊ credit ကုန်နိုင်တယ်)။${mins > 0 ? ' အသံ ခန့်မှန်း $mins မိနစ်။' : ''}' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Auto စတင်မလား?'),
        content: Text('$what$extra'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('စမယ်')),
        ],
      ),
    );
    return ok == true;
  }

  /// The count is a convenience: a failure here must never spoil a finished job.
  Future<void> _logUsage({int gemini = 0, int asrSeconds = 0, int voices = 0, bool saveFallback = false}) async {
    try {
      if (saveFallback) await _usageRepo.saveFallbackModel(_fallbackC.text);
      final u = await _usageRepo.add(gemini: gemini, asrSeconds: asrSeconds, voices: voices);
      if (mounted) setState(() => _usage = u);
    } catch (_) {}
  }

  Future<bool> _hasSrt() async {
    for (final kind in [DocKind.studioSrt, DocKind.sourceSrt]) {
      final t = await _handoff.getDoc(widget.projectId, kind);
      if (t != null && t.trim().isNotEmpty && parseSrt(t).entries.isNotEmpty) return true;
    }
    return false;
  }

  /// Subtitles from the video's sound (AssemblyAI) when the project has none.
  /// Saved as the project's source subtitles; the video is only read.
  Future<void> _runAsr() async {
    final client = AssemblyClient(_asr.apiKey.trim());
    _asrClient = client;
    File? tmp;
    try {
      setState(() => _stage = 'အသံကို ဗီဒီယိုထဲကနေ ထုတ်နေတယ်');
      final audio = await AssemblyClient.extractAudio(widget.videoUri!);
      tmp = File(audio.path);
      final text = await client.transcribe(tmp, _asr.language, (s) {
        if (mounted) setState(() => _stage = 'AssemblyAI: $s');
      });
      final parsed = parseSrt(text);
      if (parsed.entries.isEmpty) throw const HttpException('အသံထဲက စာ မတွေ့ပါ (Settings မှာ ဘာသာစကား code မှန်လား စစ်ပါ)');
      await _handoff.setDoc(widget.projectId, DocKind.sourceSrt, serializeSrt(parsed.entries));
      await widget.onSrtReady();
      await _logUsage(asrSeconds: widget.durationMs ~/ 1000);
    } on AsrCanceled {
      throw const RecapCanceled();
    } on HttpException catch (e) {
      if (client.canceled) throw const RecapCanceled();
      throw HttpException('AssemblyAI မအောင်မြင်ဘူး: ${e.message} (စာတန်းမလိုဘဲ လုပ်ချင်ရင် "AssemblyAI နဲ့ စာတန်းထုတ်" switch ကို ပိတ်ပါ)');
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
      _asrClient = null;
    }
  }

  /// [retry]: ask again only for the parts that did not come out, reusing the
  /// video that is already in Gemini and the parts that were already saved.
  Future<void> _start({bool retry = false}) async {
    if (!_s.ready) {
      _say('Backend လိပ်စာ + token ကို အရင်သိမ်းပါ', error: true);
      return;
    }
    if (_geminiKey.isEmpty) {
      _say('Gemini API key မထည့်ရသေးဘူး။ Settings မှာ ထည့်ပါ', error: true);
      return;
    }
    if (_video && widget.videoUri == null && widget.linkUrl.isEmpty) {
      _say('ဗီဒီယို မရွေးရသေးဘူး (Stage 1 မှာ ရွေးပါ၊ သို့မဟုတ် အပေါ်မှာ link ထည့်ပါ)', error: true);
      return;
    }
    final needAsr = !retry && _useAsr && _asr.hasKey && widget.videoUri != null && !await _hasSrt();
    if (!mounted) return;
    if (!retry && !await _confirm(needAsr)) return;
    if (!mounted) return;
    final client = RecapClient(_s);
    _client = client;
    File? tmp;
    setState(() {
      _running = true;
      _canceled = false;
      _msg = null;
      _err = false;
      if (!retry) _result = null;
      _progress = 0;
      _stage = 'ပြင်ဆင်နေတယ်';
    });
    if (!retry) _stepReset();
    try {
      if (retry) {
        _enter(QStep.subtitles);
        _skipStep(QStep.subtitles, 'ပြန်လုပ်တာမို့ ကျော်');
      } else if (needAsr) {
        _enter(QStep.subtitles);
        await _runAsr();
      } else {
        _enter(QStep.subtitles);
        _skipStep(QStep.subtitles, 'စာတန်း ရှိပြီးသား / AssemblyAI မသုံးဘူး');
      }
      if (_canceled) throw const RecapCanceled();
      var fileUri = '';
      String? mime;
      if (_video && retry && _lastFileUri.isNotEmpty) {
        fileUri = _lastFileUri;
        mime = _lastMime;
        _enter(QStep.upload);
        _skipStep(QStep.upload, 'Gemini ထဲ ရှိပြီးသား ဗီဒီယိုကို ပြန်သုံး');
      } else if (_video && widget.linkUrl.isNotEmpty) {
        _enter(QStep.upload);
        setState(() => _stage = 'link ကို Backend ဆီ ပို့နေတယ်');
        final info = await LinkIngest(_handoff).ensure(
          projectId: widget.projectId,
          client: client,
          url: widget.linkUrl,
          geminiKey: _geminiKey,
          onStage: (st, pct) {
            if (mounted) {
              setState(() {
                _stage = st;
                _progress = pct;
              });
            }
          },
          reused: (r) => _note(r ? 'link ကနေ ဆွဲပြီးသား Gemini file ကို ပြန်သုံး' : 'link ကို Backend က ဆွဲပြီး Gemini ဆီ တင်မယ် (${linkKindLabels[linkKindOf(widget.linkUrl)]})'),
          onSubs: (n, lang) => _note('ဗီဒီယိုနဲ့အတူ စာတန်း $n ကြောင်း ရပြီး သိမ်းပြီး${lang.isEmpty ? '' : ' ($lang)'}'),
        );
        await widget.onSrtReady(); // so the groups below use the link's own subtitles, if they came
        fileUri = info.fileUri;
        mime = info.mime;
        _lastFileUri = info.fileUri;
        _lastMime = info.mime;
      } else if (_video) {
        _enter(QStep.upload);
        setState(() => _stage = 'Gemini ကို ကြိုစစ်နေတယ် (key နဲ့ တည်နေရာ)');
        await GeminiFiles.preflight(_geminiKey);
        setState(() => _stage = 'ဗီဒီယိုကို ဖုန်း cache ထဲ ကူးနေတယ်');
        tmp = await GeminiFiles.copyToCache(widget.videoUri!);
        final f = await GeminiFiles.upload(
          _geminiKey,
          tmp,
          onStage: (s, _) {
            if (mounted) setState(() => _stage = s);
          },
          canceled: () => _canceled,
        );
        fileUri = f.uri;
        mime = f.mime;
        _lastFileUri = f.uri;
        _lastMime = f.mime;
        try {
          tmp.deleteSync();
          tmp = null;
        } catch (_) {}
      }
      final built = await widget.buildGroups((s) {
        if (mounted) setState(() => _stage = s);
      });
      if (_canceled) throw const RecapCanceled();
      if (built.isEmpty) throw const HttpException('ပို့စရာ အပိုင်း မရှိဘူး');
      if (mounted) setState(() => _lastGroups = built);
      final groups = retry ? groupsFor(built, missingParts(built, _result?.parts.map((p) => p.n) ?? const <int>[])) : built;
      if (groups.isEmpty) throw const HttpException('ပြန်လုပ်စရာ အပိုင်း မရှိတော့ဘူး');
      if (!_video) {
        _enter(QStep.upload);
        _skipStep(QStep.upload, 'Scene mode — ပုံတွေပဲ ပို့တယ်');
      }
      _enter(QStep.ask);
      final job = await client.run(
        recapRequestJson(
          mode: widget.mode,
          geminiKey: _geminiKey,
          model: _modelC.text,
          voice: _makeVoice ? _voice : '',
          groups: groups,
          fileUri: fileUri,
          fileMime: mime ?? 'video/mp4',
          fallbackModel: _fallbackC.text,
        ),
        _onJobUpdate,
        onJobId: _rememberJob,
      );
      await _applyJob(job, retry: retry, groupCount: groups.length);
    } on RecapCanceled {
      _say('ရပ်လိုက်ပြီ (Backend မှာ job က ဆက်လုပ်နေနိုင်တယ်)');
    } on GeminiUploadException catch (e) {
      _say(e.message, error: true);
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      try {
        tmp?.deleteSync();
      } catch (_) {}
      _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  /// Downloads the voice files and stores them as the project's audio, one per
  /// script chunk. Needs the script to be saved first so chunk and part match.
  Future<void> _saveAudio() async {
    final job = _result;
    if (job == null) return;
    final script = await _handoff.getDoc(widget.projectId, DocKind.script) ?? '';
    final chunks = splitScript(script);
    // The script is made from every saved part, so match against those, then
    // use the voice only for parts whose text is still what the backend voiced.
    final texts = await _handoff.results(widget.projectId, widget.task);
    final keys = matchChunksToParts(chunks, texts);
    if (keys == null) {
      _say('Script နဲ့ အသံ အပိုင်း မကိုက်သေးဘူး။ အောက်က "Script အဖြစ် သိမ်း" ကို အရင်နှိပ်ပါ (ပြီးရင် ဒီခလုတ် ပြန်နှိပ်)။', error: true);
      return;
    }
    final client = RecapClient(_s);
    _client = client;
    setState(() {
      _running = true;
      _canceled = false;
      _msg = null;
    });
    _enter(QStep.audio);
    try {
      final repo = AudioRepo();
      final old = await repo.forProject(widget.projectId);
      var done = 0;
      for (var i = 0; i < keys.length; i++) {
        if (_canceled) throw const RecapCanceled();
        final matches = job.parts.where((p) => p.n == keys[i] && p.text.trim() == (texts[keys[i]] ?? '').trim());
        if (matches.isEmpty || matches.first.audioUrl.isEmpty) continue;
        final part = matches.first;
        setState(() => _stage = 'အသံ ဒေါင်းနေတယ် ${i + 1}/${keys.length}');
        final bytes = await client.downloadAudio(part.audioUrl);
        final f = await AudioChannel.saveAudioBytes('p${widget.projectId}_c${i + 1}_r${DateTime.now().millisecondsSinceEpoch}', bytes);
        for (final c in old.where((c) => c.chunkIdx == i)) {
          if (c.id != null) await repo.delete(c.id!);
          if (c.ownsFile) {
            try {
              await AudioChannel.deleteFile(c.source);
            } catch (_) {}
          }
        }
        await repo.insert(AudioClip(
          projectId: widget.projectId,
          chunkIdx: i,
          kind: ClipKind.tts,
          label: 'Edge TTS',
          source: f.source,
          durationMs: f.durationMs,
          sizeBytes: f.sizeBytes,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        done++;
      }
      if (done > 0) _finishSteps();
      _say(done == 0 ? 'ဒီ job ရဲ့ အသံနဲ့ ကိုက်တဲ့ အပိုင်း မရှိဘူး (script ကို ပြင်ထားလား၊ အသံ switch ပိတ်ထားလား)' : 'အသံ $done ခု အဆင့် ၃ (Audio) ထဲ သိမ်းပြီး။');
    } on RecapCanceled {
      _say('ရပ်လိုက်ပြီ');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  void _onJobUpdate(RecapJob j) {
    if (mounted) {
      setState(() {
        _stage = j.stage;
        _progress = j.progress;
      });
    }
  }

  String get _jobKind => 'recap_job_${widget.task}';

  /// The backend's job id is kept, so a job that was running when the screen
  /// or the app was closed can be picked up again.
  Future<void> _rememberJob(String id) async {
    try {
      await _handoff.setDoc(widget.projectId, _jobKind, id);
    } catch (_) {}
    if (mounted) setState(() => _savedJob = id);
  }

  Future<void> _forgetJob() async {
    try {
      await _handoff.setDoc(widget.projectId, _jobKind, '');
    } catch (_) {}
    if (mounted) setState(() => _savedJob = '');
  }

  /// Saves the parts of a finished job like pasted answers and shows them.
  /// [groupCount] is how many Gemini requests this app run made (0 when a job
  /// is picked up again).
  Future<void> _applyJob(RecapJob job, {required bool retry, required int groupCount}) async {
    _enter(QStep.save);
    for (final p in job.parts) {
      await _handoff.saveResult(widget.projectId, widget.task, p.n, p.text);
    }
    await _logUsage(gemini: groupCount, voices: job.parts.where((p) => p.audioUrl.isNotEmpty).length, saveFallback: groupCount > 0);
    await widget.onTextsSaved();
    await _forgetJob();
    if (!mounted) return;
    final prev = retry ? _result : null;
    final merged = <int, RecapPart>{
      if (prev != null) for (final p in prev.parts) p.n: p,
      for (final p in job.parts) p.n: p,
    };
    final all = RecapJob(state: JobState.done, parts: [for (final k in (merged.keys.toList()..sort())) merged[k]!], warnings: job.warnings);
    setState(() => _result = all);
    _finishSteps();
    final w = job.warnings.isEmpty ? '' : '\n⚠ ${job.warnings.join('\n⚠ ')}';
    final miss = missingParts(_lastGroups, all.parts.map((p) => p.n));
    final m = miss.isEmpty ? '' : '\n⚠ မရသေးတဲ့ အပိုင်း: ${miss.join(', ')} — "ပြန်လုပ်" ခလုတ်ကို နှိပ်ပါ';
    _say('အပိုင်း ${job.parts.length} ခု ရပြီး သိမ်းပြီး။ အောက်က "Script အဖြစ် သိမ်း" ကို နှိပ်ပါ၊ ပြီးမှ အသံကို project ထဲ သိမ်းပါ။$w$m');
  }

  /// Picks up the job that was started earlier on this project (the screen or
  /// the app was closed while the backend worked).
  Future<void> _resume() async {
    final id = _savedJob;
    if (id.isEmpty || !_s.ready) return;
    final client = RecapClient(_s);
    _client = client;
    setState(() {
      _running = true;
      _canceled = false;
      _msg = null;
      _err = false;
      _progress = 0;
      _stage = 'Backend ကို မေးနေတယ်';
    });
    _stepReset();
    _enter(QStep.ask);
    try {
      final job = await client.resume(id, _onJobUpdate);
      await _applyJob(job, retry: false, groupCount: 0);
    } on RecapCanceled {
      _say('ရပ်လိုက်ပြီ (job က Backend မှာ ဆက်ရှိနေနိုင်တယ်)');
    } on HttpException catch (e) {
      // A job that is gone cannot be picked up again; one that failed is over too.
      if (e.message.contains('မတွေ့တော့ဘူး')) await _forgetJob();
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  /// Backend check: ffmpeg, Edge TTS and the Gemini key/model, with a Burmese
  /// hint for each thing that fails.
  Future<void> _selfTest() async {
    if (!_s.ready) {
      _say('Backend လိပ်စာ + token ကို အရင်သိမ်းပါ', error: true);
      return;
    }
    setState(() {
      _testing = true;
      _checks = null;
      _msg = null;
    });
    final client = RecapClient(_s);
    try {
      final c = await client.selfTest(_geminiKey, _modelC.text);
      if (mounted) setState(() => _checks = c);
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  void _cancel() {
    setState(() => _canceled = true);
    _client?.cancel();
    _asrClient?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final hasAudio = _result?.parts.any((p) => p.audioUrl.isNotEmpty) ?? false;
    final missing = _lastGroups.isEmpty ? const <int>[] : missingParts(_lastGroups, _result?.parts.map((p) => p.n) ?? const <int>[]);
    return DfCard(
      title: '🤖 Auto (Backend နဲ့ တစ်ချက်တည်း)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _video
              ? 'ဗီဒီယိုကို သင့် Gemini ဆီ upload လုပ်၊ Backend က အပိုင်းတစ်ခုချင်း ကြည့်ခိုင်းပြီး script ရေး၊ မြန်မာအသံပါ ထုတ်ပေးမယ်။ Gemini key (Settings) လိုတယ်။'
              : 'Scene ပုံ + စာတန်းကို Backend က Gemini ကို ပို့ပြီး scene တစ်ခုချင်း script ရေး၊ မြန်မာအသံပါ ထုတ်ပေးမယ်။ Gemini key (Settings) လိုတယ်။',
          style: const TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        if (_qs != null) ...[
          const SizedBox(height: 10),
          RecapStepBar(current: _qs, done: _qdone, skipped: _qskip, failed: _qfail, running: _running),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: !_s.ready,
          title: Text('Backend${_s.ready ? ' ✓ ${Uri.tryParse(_s.url)?.host ?? ''}' : ' (မချိတ်ရသေးဘူး)'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          children: [
            TextField(
              controller: _connectC,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'URL#TOKEN', hintText: 'https://….go.altare.global#APP_TOKEN'),
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: _running ? null : _saveBackend, child: const Text('သိမ်း + စမ်းချိတ်'))),
            const SizedBox(height: 6),
            TextField(controller: _modelC, autocorrect: false, decoration: const InputDecoration(labelText: 'Gemini model (စာရေးဖို့)')),
            const SizedBox(height: 6),
            TextField(
              controller: _fallbackC,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'အရန် model (မထည့်လည်းရ)', helperText: 'ပထမ model မရှိတော့ရင် / quota ပြည့်ရင် ဒီ model နဲ့ ပြန်စမ်းမယ်', helperMaxLines: 2),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('စာတန်းမရှိရင် AssemblyAI နဲ့ ထုတ်'),
          subtitle: Text(
            _asr.hasKey ? 'ဗီဒီယိုထဲက အသံကိုပဲ ပို့မယ်၊ project မှာ စာတန်း ရှိပြီးသားဆိုရင် မထုတ်ဘူး' : 'AssemblyAI key မရှိသေးဘူး (Settings › AssemblyAI)',
            style: const TextStyle(fontSize: 12),
          ),
          value: _useAsr && _asr.hasKey,
          onChanged: (_running || !_asr.hasKey) ? null : (v) => setState(() => _useAsr = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('မြန်မာအသံပါ လုပ် (Edge TTS)'),
          value: _makeVoice,
          onChanged: _running ? null : (v) => setState(() => _makeVoice = v),
        ),
        if (_makeVoice)
          DropdownButton<String>(
            value: _voice,
            items: [for (final e in recapVoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: _running ? null : (v) => setState(() => _voice = v ?? _voice),
          ),
        const SizedBox(height: 6),
        if (_running) ...[
          LinearProgressIndicator(value: _progress > 0 ? _progress / 100 : null),
          const SizedBox(height: 4),
          Text('$_stage${_progress > 0 ? ' · $_progress%' : ''}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          OutlinedButton(onPressed: _cancel, child: const Text('ရပ်မယ်')),
        ] else
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: _start, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Auto လုပ်မယ်')),
            if (_savedJob.isNotEmpty && _s.ready) OutlinedButton.icon(onPressed: _resume, icon: const Icon(Icons.history, size: 18), label: const Text('နောက်ဆုံး job ကို ပြန်ယူ')),
            if (missing.isNotEmpty) OutlinedButton.icon(onPressed: () => _start(retry: true), icon: const Icon(Icons.refresh, size: 18), label: Text('မရတဲ့ အပိုင်း ${missing.length} ခု ပြန်လုပ်')),
            if (hasAudio) OutlinedButton.icon(onPressed: _saveAudio, icon: const Icon(Icons.graphic_eq, size: 18), label: const Text('အသံကို project ထဲ သိမ်း')),
            if (_log.isNotEmpty) OutlinedButton.icon(onPressed: _copyLog, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Log ကူး')),
            OutlinedButton.icon(onPressed: _testing ? null : _selfTest, icon: const Icon(Icons.fact_check_outlined, size: 18), label: Text(_testing ? 'စစ်နေတယ် …' : 'Self-test')),
          ]),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
        if (!_usage.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_usage.summary(), style: const TextStyle(color: DfColors.muted, fontSize: 12))),
        if (_checks != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in _checks!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(c.ok ? Icons.check_circle : Icons.error, size: 16, color: c.ok ? DfColors.ok : DfColors.danger),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${c.label} — ${c.note}', style: const TextStyle(fontSize: 12.5))),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}
