import 'dart:io';

import '../core/assembly.dart';
import '../core/news_video.dart';
import '../core/recap_auto.dart';
import '../core/recap_queue.dart';
import '../core/scenes.dart' show SceneSpan, dialogueFor;
import '../core/script.dart';
import '../core/segments.dart';
import '../core/srt.dart';
import '../core/video_recap.dart';
import '../data/audio_clip.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../data/segment_repo.dart';
import '../data/usage_repo.dart';
import 'assembly_client.dart';
import 'audio_channel.dart';
import 'gemini_files.dart';
import 'recap_client.dart';

/// Everything one queue run needs, read once when the queue starts.
class QueueSettings {
  const QueueSettings({
    required this.backend,
    required this.geminiKey,
    required this.model,
    required this.fallbackModel,
    required this.voice,
    required this.useAsr,
    required this.asr,
  });

  final NewsVideoSettings backend;
  final String geminiKey;
  final String model;
  final String fallbackModel;

  /// Empty = script only, no voice.
  final String voice;
  final bool useAsr;
  final AssemblySettings asr;
}

/// Runs ONE episode of the queue through the same steps as the Video Recap
/// screen's Auto card, and reports each step to [QueueCtx]:
///   subtitles -> upload -> ask (Gemini + voice on the backend) -> save -> audio.
/// It never changes the original video. It never replaces a script that the
/// project already has; the parts are saved either way.
class RecapEpisodeRunner {
  RecapEpisodeRunner(this.s);

  static const task = 'vrecap';
  static const jobKind = 'recap_job_$task';

  final QueueSettings s;
  final _handoff = HandoffRepo();
  final _segRepo = SegmentRepo();
  final _usage = UsageRepo();
  RecapClient? _client;
  AssemblyClient? _asrClient;

  /// Cuts the network work off now (the queue's cancel button).
  void cancelNow() {
    _client?.cancel();
    _asrClient?.cancel();
  }

  Future<List<SrtEntry>> _loadSrt(int pid) async {
    for (final kind in [DocKind.studioSrt, DocKind.sourceSrt]) {
      final t = await _handoff.getDoc(pid, kind);
      if (t != null && t.trim().isNotEmpty) {
        final e = parseSrt(t).entries;
        if (e.isNotEmpty) return e;
      }
    }
    return const [];
  }

  Future<void> _count({int gemini = 0, int asrSeconds = 0, int voices = 0}) async {
    try {
      await _usage.add(gemini: gemini, asrSeconds: asrSeconds, voices: voices);
    } catch (_) {} // a counter must never fail an episode
  }

  Future<void> run(Project p, QueueCtx ctx) async {
    final pid = p.id!;
    final uri = p.sourceVideoUri;
    if (uri == null || !p.hasVideo) throw const HttpException('ဗီဒီယို မရွေးထားဘူး (Stage 1 မှာ ရွေးပါ)');

    // 1. subtitles
    ctx.step(QStep.subtitles);
    var entries = await _loadSrt(pid);
    if (entries.isNotEmpty) {
      ctx.skip(QStep.subtitles, 'စာတန်း ${entries.length} ကြောင်း ရှိပြီးသား');
    } else if (!s.useAsr || !s.asr.hasKey) {
      ctx.skip(QStep.subtitles, 'စာတန်းမရှိ၊ AssemblyAI မသုံးဘူး — စာတန်းမပါဘဲ ဆက်သွားမယ်');
    } else {
      entries = await _asr(p, uri, ctx);
    }
    ctx.check();

    var segs = await _segRepo.load(pid);
    final fromIndex = segs.isNotEmpty;
    if (segs.isEmpty) segs = buildSegments(p.videoDurationMs ?? 0, 60000);
    if (segs.isEmpty) throw const HttpException('ဗီဒီယိုအရှည် မသိလို့ အပိုင်း မခွဲနိုင်ဘူး');
    ctx.log('အပိုင်း ${segs.length} ခု (${fromIndex ? 'Video Index က' : '၁ မိနစ်စီ'})');

    // 2. upload to the user's own Gemini account
    ctx.step(QStep.upload, 'Gemini ကို ကြိုစစ်နေတယ် (key နဲ့ တည်နေရာ)');
    await GeminiFiles.preflight(s.geminiKey);
    ctx.log('Gemini ကြိုစစ်ပြီး (key + တည်နေရာ ပြဿနာမတွေ့ဘူး)');
    ctx.progress(0, 'ဗီဒီယိုကို ဖုန်း cache ထဲ ကူးနေတယ်');
    File? tmp;
    late final GeminiFile file;
    try {
      tmp = await GeminiFiles.copyToCache(uri);
      ctx.log('cache ထဲ ကူးပြီး (${(tmp.lengthSync() / 1048576).toStringAsFixed(1)} MB)');
      file = await GeminiFiles.upload(
        s.geminiKey,
        tmp,
        onStage: (st, f) => ctx.progress(f == null ? 0 : (f * 100).round(), st),
        canceled: () => ctx.canceled,
      );
    } finally {
      try {
        tmp?.deleteSync();
      } catch (_) {}
    }
    ctx.log('Gemini ဆီ ရောက်ပြီး (${file.mime})');
    ctx.check();

    // 3. Gemini writes, the backend makes the voice
    ctx.step(QStep.ask, 'အပိုင်း ${segs.length} ခု');
    final notes = await _handoff.getDoc(pid, DocKind.notes) ?? '';
    final dialogue = [for (final g in segs) dialogueFor(entries, SceneSpan(g.startMs, g.endMs), maxChars: 600)];
    final groups = videoRecapGroups(dramaTitle: p.dramaTitle, episode: p.episode, parts: segs, notes: notes, dialogue: dialogue);
    final client = RecapClient(s.backend);
    _client = client;
    final RecapJob job;
    try {
      job = await client.run(
        recapRequestJson(
          mode: 'video',
          geminiKey: s.geminiKey,
          model: s.model,
          voice: s.voice,
          groups: groups,
          fileUri: file.uri,
          fileMime: file.mime,
          fallbackModel: s.fallbackModel,
        ),
        (j) => ctx.progress(j.progress, j.stage),
        onJobId: (id) {
          ctx.log('Backend job $id');
          _handoff.setDoc(pid, jobKind, id).catchError((_) {});
        },
      );
    } on RecapCanceled {
      throw const QueueCanceled();
    } finally {
      _client = null;
    }
    for (final w in job.warnings) {
      ctx.log('⚠ $w');
    }
    await _count(gemini: groups.length, voices: job.parts.where((x) => x.audioUrl.isNotEmpty).length);
    ctx.check();

    // 4. save the parts (and the script, only when the project has none)
    ctx.step(QStep.save);
    final byPart = <int, String>{};
    for (final part in job.parts) {
      if (part.n > segs.length) continue;
      await _handoff.saveResult(pid, task, part.n, part.text);
      byPart[part.n] = part.text;
    }
    ctx.log('အပိုင်း ${byPart.length}/${segs.length} သိမ်းပြီး');
    final missing = [for (var i = 1; i <= segs.length; i++) if (!byPart.containsKey(i)) i];
    if (missing.isNotEmpty) ctx.log('⚠ မရသေးတဲ့ အပိုင်း: ${missing.join(', ')} (Video Recap စာမျက်နှာက "ပြန်လုပ်" နဲ့ ဖြည့်ပါ)');
    final oldScript = await _handoff.getDoc(pid, DocKind.script);
    var scriptIsNew = false;
    if (byPart.isNotEmpty && (oldScript == null || oldScript.trim().isEmpty)) {
      await _handoff.setDoc(pid, DocKind.script, scriptFromParts(byPart));
      if (!fromIndex) await _segRepo.replaceAll(pid, segs);
      scriptIsNew = true;
      ctx.log('Script အသစ် သိမ်းပြီး');
    } else if (byPart.isNotEmpty) {
      ctx.log('Script ရှိပြီးသားမို့ မထိဘူး (Video Recap စာမျက်နှာမှာ "Script အဖြစ် သိမ်း" နဲ့ ကိုယ်တိုင် အစားထိုးပါ)');
    }
    try {
      await _handoff.setDoc(pid, jobKind, '');
    } catch (_) {}

    // 5. the voice, only for a script this run wrote (so chunks match the parts)
    final voices = job.parts.where((x) => x.audioUrl.isNotEmpty).toList();
    if (!scriptIsNew) {
      ctx.skip(QStep.audio, 'script အသစ် မဟုတ်လို့ ကျော် (အသံကို Video Recap စာမျက်နှာကနေ သိမ်းပါ)');
    } else if (voices.isEmpty) {
      ctx.skip(QStep.audio, 'အသံ မထုတ်ထားဘူး');
    } else {
      await _saveAudio(pid, job, client, ctx);
    }
  }

  Future<List<SrtEntry>> _asr(Project p, String uri, QueueCtx ctx) async {
    final client = AssemblyClient(s.asr.apiKey.trim());
    _asrClient = client;
    File? tmp;
    try {
      ctx.progress(0, 'အသံကို ဗီဒီယိုထဲကနေ ထုတ်နေတယ်');
      final audio = await AssemblyClient.extractAudio(uri);
      tmp = File(audio.path);
      final text = await client.transcribe(tmp, s.asr.language, (st) => ctx.progress(0, 'AssemblyAI: $st'));
      final parsed = parseSrt(text);
      if (parsed.entries.isEmpty) throw const HttpException('အသံထဲက စာ မတွေ့ပါ (Settings မှာ ဘာသာစကား code မှန်လား စစ်ပါ)');
      await _handoff.setDoc(p.id!, DocKind.sourceSrt, serializeSrt(parsed.entries));
      await _count(asrSeconds: (p.videoDurationMs ?? 0) ~/ 1000);
      ctx.log('AssemblyAI စာတန်း ${parsed.entries.length} ကြောင်း သိမ်းပြီး');
      return parsed.entries;
    } on AsrCanceled {
      throw const QueueCanceled();
    } on HttpException catch (e) {
      if (client.canceled) throw const QueueCanceled();
      throw HttpException('AssemblyAI မအောင်မြင်ဘူး: ${e.message}');
    } finally {
      try {
        await tmp?.delete();
      } catch (_) {}
      _asrClient = null;
    }
  }

  Future<void> _saveAudio(int pid, RecapJob job, RecapClient client, QueueCtx ctx) async {
    final script = await _handoff.getDoc(pid, DocKind.script) ?? '';
    final texts = await _handoff.results(pid, task);
    final keys = matchChunksToParts(splitScript(script), texts);
    if (keys == null) {
      ctx.skip(QStep.audio, 'script ခွဲပုံနဲ့ အပိုင်း မကိုက်ဘူး — Video Recap စာမျက်နှာကနေ သိမ်းပါ');
      return;
    }
    ctx.step(QStep.audio, '${keys.length} ပိုင်း');
    final repo = AudioRepo();
    var done = 0;
    for (var i = 0; i < keys.length; i++) {
      ctx.check();
      final m = job.parts.where((x) => x.n == keys[i] && x.text.trim() == (texts[keys[i]] ?? '').trim());
      if (m.isEmpty || m.first.audioUrl.isEmpty) continue;
      ctx.progress(100 * i ~/ keys.length, 'အသံ ဒေါင်းနေတယ် ${i + 1}/${keys.length}');
      final bytes = await client.downloadAudio(m.first.audioUrl);
      final f = await AudioChannel.saveAudioBytes('p${pid}_c${i + 1}_r${DateTime.now().millisecondsSinceEpoch}', bytes);
      await repo.insert(AudioClip(
        projectId: pid,
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
    ctx.log('အသံ $done ခု Audio ထဲ သိမ်းပြီး');
  }
}
