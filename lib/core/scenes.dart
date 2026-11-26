import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'segments.dart';
import 'srt.dart';
import 'video_recap.dart';

/// Scene Recap: the phone finds the scenes, picks one picture per scene and
/// puts them on a numbered contact sheet. Gemini then needs only one small
/// picture (and the dialogue text) instead of the whole video. Pure Dart.

/// Bytes of one frame signature: a 16 x 9 picture, 3 colour values per pixel.
const sigBytes = 16 * 9 * 3;

/// Mean absolute difference of two signatures, 0.0 (same) to 1.0 (opposite).
double sigDiff(Uint8List a, int aOff, Uint8List b, int bOff) {
  var sum = 0;
  for (var i = 0; i < sigBytes; i++) {
    final d = a[aOff + i] - b[bOff + i];
    sum += d < 0 ? -d : d;
  }
  return sum / (sigBytes * 255);
}

/// Differences between neighbouring samples. Index 0 is 0.0; index i compares
/// sample i with sample i - 1. [sigs] holds the signatures one after another.
List<double> diffSeries(Uint8List sigs) {
  final n = sigs.length ~/ sigBytes;
  final out = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    out[i] = sigDiff(sigs, (i - 1) * sigBytes, sigs, i * sigBytes);
  }
  return out;
}

class SceneSpan {
  const SceneSpan(this.startMs, this.endMs);
  final int startMs;
  final int endMs;
  int get lengthMs => endMs - startMs;

  /// Time of the picture that stands for the scene: its middle.
  int get keyMs => startMs + lengthMs ~/ 2;

  @override
  bool operator ==(Object o) => o is SceneSpan && o.startMs == startMs && o.endMs == endMs;
  @override
  int get hashCode => Object.hash(startMs, endMs);
  @override
  String toString() => 'Scene($startMs-$endMs)';
}

/// Turns a difference series into scenes inside [rangeStartMs]..[rangeEndMs].
///
/// A cut is a sample whose difference is clearly above the usual one (the
/// average plus two standard deviations, never below [minDiff]). The strongest
/// cuts win when there are more than [maxScenes] - 1, no scene is shorter than
/// [minSceneMs], and a scene longer than [maxSceneMs] (a long talk, a still
/// shot) is split into equal parts so one picture never stands for minutes.
List<SceneSpan> pickScenes({
  required List<int> timesMs,
  required List<double> diffs,
  required int rangeStartMs,
  required int rangeEndMs,
  int minSceneMs = 2500,
  int maxSceneMs = 45000,
  int maxScenes = 40,
  double minDiff = 0.06,
}) {
  if (rangeEndMs <= rangeStartMs) return const [];
  final n = math.min(timesMs.length, diffs.length);
  final cuts = <int>[];
  if (n > 1 && maxScenes > 1) {
    var mean = 0.0;
    for (var i = 1; i < n; i++) {
      mean += diffs[i];
    }
    mean /= (n - 1);
    var v = 0.0;
    for (var i = 1; i < n; i++) {
      v += (diffs[i] - mean) * (diffs[i] - mean);
    }
    final threshold = math.max(minDiff, mean + 2 * math.sqrt(v / (n - 1)));
    final cand = [for (var i = 1; i < n; i++) if (diffs[i] >= threshold) i];
    cand.sort((a, b) => diffs[b].compareTo(diffs[a]));
    for (final i in cand) {
      final t = timesMs[i];
      if (t - rangeStartMs < minSceneMs || rangeEndMs - t < minSceneMs) continue;
      if (cuts.any((c) => (c - t).abs() < minSceneMs)) continue;
      cuts.add(t);
      if (cuts.length >= maxScenes - 1) break;
    }
    cuts.sort();
  }
  final bounds = [rangeStartMs, ...cuts, rangeEndMs];
  final out = <SceneSpan>[];
  for (var i = 0; i + 1 < bounds.length; i++) {
    final s = bounds[i], e = bounds[i + 1];
    final len = e - s;
    final parts = maxSceneMs > 0 ? (len / maxSceneMs).ceil() : 1;
    if (parts <= 1) {
      out.add(SceneSpan(s, e));
    } else {
      for (var k = 0; k < parts; k++) {
        out.add(SceneSpan(s + len * k ~/ parts, k == parts - 1 ? e : s + len * (k + 1) ~/ parts));
      }
    }
  }
  return out;
}

/// Joins scene [i] with the one before it (the user removes a wrong cut).
List<SceneSpan> mergeWithPrevious(List<SceneSpan> scenes, int i) {
  if (i <= 0 || i >= scenes.length) return scenes;
  final out = [...scenes];
  out[i - 1] = SceneSpan(out[i - 1].startMs, out[i].endMs);
  out.removeAt(i);
  return out;
}

/// Scene numbers (1-based) [from]..[to] split into groups of [perSheet].
List<(int, int)> sheetGroups(int count, {int perSheet = 12}) {
  final out = <(int, int)>[];
  for (var s = 1; s <= count; s += perSheet) {
    out.add((s, math.min(count, s + perSheet - 1)));
  }
  return out;
}

/// The subtitle lines that overlap the scene, joined and cut to [maxChars].
String dialogueFor(List<SrtEntry> entries, SceneSpan sc, {int maxChars = 320}) {
  final parts = <String>[];
  for (final e in entries) {
    if (e.endMs <= sc.startMs || e.startMs >= sc.endMs) continue;
    final t = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) parts.add(t);
  }
  final s = parts.join(' / ');
  final runes = s.runes.toList();
  return runes.length <= maxChars ? s : '${String.fromCharCodes(runes.take(maxChars))}…';
}

/// Prompt for scenes [from]..[to] (1-based, inclusive). The contact sheet with
/// those scenes is attached to the same message by the user (or the share).
String buildSceneRecapPrompt({
  required String dramaTitle,
  required int episode,
  required List<SceneSpan> scenes,
  required List<String> dialogue,
  required int from,
  required int to,
  String notes = '',
}) {
  final b = StringBuffer();
  b.writeln('You are writing narration for a drama recap video. The drama is "$dramaTitle", episode $episode.');
  b.writeln('The attached picture is a contact sheet: each tile is one scene, labelled with its scene number and start time. Use the pictures and the dialogue lines below. You cannot hear the audio.');
  b.writeln('For each scene listed below, write the narration for ONLY that scene, in natural spoken Burmese (Myanmar Unicode), as if a storyteller tells the story to a friend.');
  b.writeln();
  b.writeln('SCENES:');
  for (var i = from; i <= to && i <= scenes.length; i++) {
    final s = scenes[i - 1];
    b.writeln('Scene $i: ${formatTime(s.startMs)} - ${formatTime(s.endMs)} (about ${targetChars(s.lengthMs)} Burmese characters)');
    final d = i - 1 < dialogue.length ? dialogue[i - 1] : '';
    b.writeln(d.isEmpty ? '  Dialogue: (none given; describe only what is clearly visible and say less)' : '  Dialogue: $d');
  }
  b.writeln();
  b.writeln('RULES:');
  b.writeln('1. Use only what the pictures and the dialogue show. Do not invent events, characters, names or dialogue. If you cannot tell, say less instead of guessing.');
  b.writeln('2. Keep character names consistent.');
  b.writeln('3. Plain spoken text only: no headings inside a scene, no bullet points, no emoji, no brackets, no timestamps. Short sentences ending with "။".');
  b.writeln('4. Start every scene with exactly this line, with the scene number: === PART n ===');
  b.writeln('5. Output only the scenes. No introduction and no closing remark.');
  b.writeln('6. Put the whole result inside ONE code block so it can be copied in one tap.');
  if (notes.trim().isNotEmpty) {
    b.writeln();
    b.writeln('NAME AND TERM PREFERENCES (follow exactly):');
    b.writeln(notes.trim());
  }
  return b.toString();
}

/// Scenes as the project's Video Index parts.
List<SegmentSpec> toSegments(List<SceneSpan> s) => [for (final x in s) SegmentSpec(x.startMs, x.endMs)];

/// The scene list as saved in the project (DocKind.scenePlan): [[startMs, endMs], ...].
String encodeScenePlan(List<SceneSpan> scenes) => jsonEncode([for (final s in scenes) [s.startMs, s.endMs]]);

/// Reads a saved scene list. Anything unreadable, or a span that is empty or
/// goes backwards, gives an empty list so the caller finds the scenes again.
List<SceneSpan> parseScenePlan(String? text) {
  if (text == null || text.trim().isEmpty) return const [];
  try {
    final l = jsonDecode(text);
    if (l is! List) return const [];
    final out = <SceneSpan>[];
    for (final e in l) {
      if (e is! List || e.length < 2 || e[0] is! num || e[1] is! num) return const [];
      final a = (e[0] as num).toInt(), b = (e[1] as num).toInt();
      if (a < 0 || b <= a) return const [];
      out.add(SceneSpan(a, b));
    }
    return out;
  } catch (_) {
    return const [];
  }
}
