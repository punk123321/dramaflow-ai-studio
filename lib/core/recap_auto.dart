import 'dart:convert';

import 'news_video.dart' show JobState;
import 'scenes.dart';
import 'segments.dart';
import 'video_recap.dart';

/// Automatic Video Recap / Scene Recap through the user's own backend
/// (tools/dramaflow_backend). The app builds the same prompts as the manual
/// flow; the backend asks Gemini, reads the parts and makes the voice.
/// Nothing here touches the network.

/// One request to Gemini: the parts [first]..[last] with their prompt.
class RecapGroup {
  const RecapGroup({required this.first, required this.last, required this.prompt, this.jpegBase64 = '', this.startMs = 0, this.endMs = 0, this.partMs = const []});

  final int first;
  final int last;
  final String prompt;

  /// Scene Recap: the contact sheet of these scenes.
  final String jpegBase64;

  /// Video Recap: the time range Gemini should look at.
  final int startMs;
  final int endMs;

  /// How long the video of each part [first]..[last] is, so the backend can
  /// fit the voice to it. Sent only when there is one entry per part.
  final List<int> partMs;

  Map<String, Object?> toJson() => {
        'first': first,
        'last': last,
        'prompt': prompt,
        if (jpegBase64.isNotEmpty) 'jpeg_b64': jpegBase64,
        if (endMs > startMs) 'start_ms': startMs,
        if (endMs > startMs) 'end_ms': endMs,
        if (partMs.length == last - first + 1 && partMs.any((v) => v > 0)) 'part_ms': partMs,
      };
}

/// Video Recap groups: [perBatch] parts per request, each with its time range.
List<RecapGroup> videoRecapGroups({
  required String dramaTitle,
  required int episode,
  required List<SegmentSpec> parts,
  required String notes,
  int perBatch = 5,
  List<String>? dialogue,
}) {
  final out = <RecapGroup>[];
  for (var from = 1; from <= parts.length; from += perBatch) {
    final to = from + perBatch - 1 > parts.length ? parts.length : from + perBatch - 1;
    out.add(RecapGroup(
      first: from,
      last: to,
      prompt: buildVideoRecapPrompt(dramaTitle: dramaTitle, episode: episode, parts: parts, from: from, to: to, notes: notes, dialogue: dialogue),
      startMs: parts[from - 1].startMs,
      endMs: parts[to - 1].endMs,
      partMs: [for (var i = from; i <= to; i++) parts[i - 1].lengthMs],
    ));
  }
  return out;
}

/// Scene Recap groups: one per contact sheet (see [sheetGroups]); [sheets]
/// gives the sheet picture of the group that starts at that scene number.
List<RecapGroup> sceneRecapGroups({
  required String dramaTitle,
  required int episode,
  required List<SceneSpan> scenes,
  required List<String> dialogue,
  required String notes,
  required Map<int, String> sheets,
}) {
  final out = <RecapGroup>[];
  for (final g in sheetGroups(scenes.length)) {
    out.add(RecapGroup(
      first: g.$1,
      last: g.$2,
      prompt: buildSceneRecapPrompt(dramaTitle: dramaTitle, episode: episode, scenes: scenes, dialogue: dialogue, from: g.$1, to: g.$2, notes: notes),
      jpegBase64: sheets[g.$1] ?? '',
      partMs: [for (var i = g.$1; i <= g.$2; i++) scenes[i - 1].lengthMs],
    ));
  }
  return out;
}

const recapVoices = <String, String>{
  'my-MM-ThihaNeural': 'Thiha (အမျိုးသား)',
  'my-MM-NilarNeural': 'Nilar (အမျိုးသမီး)',
};

/// The body of "create recap job". [voice] empty means script only.
Map<String, Object?> recapRequestJson({
  required String mode,
  required String geminiKey,
  required String model,
  required String voice,
  required List<RecapGroup> groups,
  String fileUri = '',
  String fileMime = 'video/mp4',
  String fallbackModel = '',
}) =>
    {
      'mode': mode == 'video' ? 'video' : 'scenes',
      'gemini_key': geminiKey.trim(),
      if (model.trim().isNotEmpty) 'gemini_model': model.trim(),
      if (fallbackModel.trim().isNotEmpty) 'gemini_fallback': fallbackModel.trim(),
      'voice': voice,
      'file_uri': fileUri,
      'file_mime': fileMime,
      'groups': [for (final g in groups) g.toJson()],
    };

class RecapPart {
  const RecapPart(this.n, this.text, this.audioMs, this.audioUrl, [this.targetMs = 0]);

  final int n;
  final String text;
  final int audioMs;
  final String audioUrl;

  /// How long the video of this part is (0 = not known).
  final int targetMs;
}

class RecapJob {
  const RecapJob({
    required this.state,
    this.stage = '',
    this.progress = 0,
    this.error = '',
    this.parts = const [],
    this.warnings = const [],
  });

  final JobState state;
  final String stage;
  final int progress;
  final String error;
  final List<RecapPart> parts;
  final List<String> warnings;
}

/// Reads the reply of "recap job status". Anything unreadable is an error job.
RecapJob parseRecapJob(String body) {
  const bad = RecapJob(state: JobState.error, error: 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
  try {
    final m = jsonDecode(body);
    if (m is! Map) return bad;
    final st = switch (m['status']) {
      'queued' => JobState.queued,
      'running' => JobState.running,
      'done' => JobState.done,
      _ => JobState.error,
    };
    final parts = <RecapPart>[];
    final raw = m['parts'];
    if (raw is List) {
      for (final p in raw) {
        if (p is! Map) continue;
        final n = p['n'];
        final t = p['text'];
        if (n is! num || t is! String || t.trim().isEmpty) continue;
        final ms = p['audio_ms'];
        final tg = p['target_ms'];
        parts.add(RecapPart(n.toInt(), t.trim(), ms is num ? ms.toInt() : 0, p['audio_url'] is String ? p['audio_url'] as String : '', tg is num ? tg.toInt() : 0));
      }
      parts.sort((a, b) => a.n.compareTo(b.n));
    }
    final pr = m['progress'];
    final w = m['warnings'];
    return RecapJob(
      state: st,
      stage: m['stage'] is String ? m['stage'] as String : '',
      progress: pr is num ? pr.clamp(0, 100).round() : 0,
      error: m['error'] is String ? m['error'] as String : (st == JobState.error ? 'ဘာကြောင့်မှန်း မသိ' : ''),
      parts: parts,
      warnings: w is List ? [for (final x in w) if (x is String) x] : const [],
    );
  } catch (_) {
    return bad;
  }
}

/// Part numbers that [groups] ask for but [have] does not hold, ascending.
List<int> missingParts(List<RecapGroup> groups, Iterable<int> have) {
  final h = have.toSet();
  final all = <int>{for (final g in groups) for (var n = g.first; n <= g.last; n++) n};
  return [for (final n in (all.toList()..sort())) if (!h.contains(n)) n];
}

/// The groups that still contain at least one of the [missing] parts. A group
/// is asked again as a whole, because Gemini answers a group in one piece.
List<RecapGroup> groupsFor(List<RecapGroup> groups, Iterable<int> missing) {
  final m = missing.toSet();
  return [
    for (final g in groups)
      if (m.any((n) => n >= g.first && n <= g.last)) g,
  ];
}

/// One line of the backend's self-test.
class SelfCheck {
  const SelfCheck(this.id, this.ok, this.note);

  final String id;
  final bool ok;
  final String note;

  String get label => switch (id) {
        'ffmpeg' => 'ffmpeg (အသံပြောင်း)',
        'edge_tts' => 'Edge TTS (မြန်မာအသံ)',
        'gemini' => 'Gemini (key + model)',
        _ => id,
      };
}

/// The body of "self-test". Unreadable or empty means no checks.
List<SelfCheck> parseSelfTest(String body) {
  try {
    final m = jsonDecode(body);
    final raw = m is Map ? m['checks'] : null;
    if (raw is! List) return const [];
    return [
      for (final c in raw)
        if (c is Map && c['id'] is String) SelfCheck(c['id'] as String, c['ok'] == true, c['note'] is String ? c['note'] as String : ''),
    ];
  } catch (_) {
    return const [];
  }
}

/// Which saved script chunk belongs to which part, or null when they cannot be
/// matched safely. [chunks] are the pieces the audio step makes (the script
/// split), [texts] the saved part texts by part number. They match when there
/// is one chunk per part, in order, and each chunk starts like its part.
List<int>? matchChunksToParts(List<String> chunks, Map<int, String> texts) {
  final keys = texts.keys.toList()..sort();
  if (chunks.length != keys.length) return null;
  String head(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), '');
    return t.length > 12 ? t.substring(0, 12) : t;
  }

  for (var i = 0; i < keys.length; i++) {
    if (head(chunks[i]) != head(texts[keys[i]]!)) return null;
  }
  return keys;
}
