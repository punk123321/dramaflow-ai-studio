import 'dart:convert';

import 'segments.dart';
import 'srt.dart';

/// The edit decision list of one project: which parts of the original video
/// are kept, which narration and music go with them, and how subtitles are
/// placed. It only DESCRIBES the edit. The original video is never changed,
/// and the render step (Phase 7) turns this description into a new MP4.
/// Pure Dart, no Flutter.

class VideoPiece {
  const VideoPiece(this.startMs, this.endMs);

  /// Range inside the ORIGINAL video.
  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;

  @override
  bool operator ==(Object other) => other is VideoPiece && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  Map<String, Object?> toJson() => {'s': startMs, 'e': endMs};
  static VideoPiece fromJson(Map<String, Object?> m) => VideoPiece(m['s'] as int, m['e'] as int);
}

class VoiceItem {
  const VoiceItem({
    required this.source,
    required this.label,
    required this.durationMs,
    required this.offsetMs,
    this.volume = 1.0,
  });

  /// File path (made by the app) or content link (imported by the user).
  final String source;
  final String label;
  final int durationMs;

  /// Where the narration starts on the OUTPUT timeline.
  final int offsetMs;
  final double volume;

  int get endMs => offsetMs + durationMs;

  VoiceItem copyWith({int? offsetMs, double? volume}) => VoiceItem(
        source: source,
        label: label,
        durationMs: durationMs,
        offsetMs: offsetMs ?? this.offsetMs,
        volume: volume ?? this.volume,
      );

  Map<String, Object?> toJson() =>
      {'src': source, 'label': label, 'dur': durationMs, 'off': offsetMs, 'vol': volume};
  static VoiceItem fromJson(Map<String, Object?> m) => VoiceItem(
        source: m['src'] as String,
        label: (m['label'] as String?) ?? '',
        durationMs: m['dur'] as int,
        offsetMs: m['off'] as int,
        volume: (m['vol'] as num?)?.toDouble() ?? 1.0,
      );
}

class MusicTrack {
  const MusicTrack({
    required this.source,
    required this.name,
    required this.durationMs,
    this.volume = 0.25,
    this.loop = true,
  });

  final String source;
  final String name;
  final int durationMs;
  final double volume;

  /// Repeat the music when it is shorter than the video.
  final bool loop;

  MusicTrack copyWith({double? volume, bool? loop}) => MusicTrack(
        source: source,
        name: name,
        durationMs: durationMs,
        volume: volume ?? this.volume,
        loop: loop ?? this.loop,
      );

  Map<String, Object?> toJson() =>
      {'src': source, 'name': name, 'dur': durationMs, 'vol': volume, 'loop': loop};
  static MusicTrack fromJson(Map<String, Object?> m) => MusicTrack(
        source: m['src'] as String,
        name: (m['name'] as String?) ?? '',
        durationMs: m['dur'] as int,
        volume: (m['vol'] as num?)?.toDouble() ?? 0.25,
        loop: (m['loop'] as bool?) ?? true,
      );
}

class Timeline {
  const Timeline({
    this.pieces = const [],
    this.voices = const [],
    this.music,
    this.subtitleOffsetMs = 0,
    this.burnSubtitles = true,
    this.originalVolume = 0.0,
  });

  final List<VideoPiece> pieces;
  final List<VoiceItem> voices;
  final MusicTrack? music;

  /// Shifts every subtitle on the output timeline (positive = later).
  final int subtitleOffsetMs;
  final bool burnSubtitles;

  /// Volume of the original video's own sound, 0 to 1. Recap videos usually
  /// replace it with narration, so the default is silent.
  final double originalVolume;

  int get videoMs => pieces.fold(0, (a, p) => a + p.lengthMs);

  int get voiceEndMs => voices.fold(0, (a, v) => v.endMs > a ? v.endMs : a);

  Timeline copyWith({
    List<VideoPiece>? pieces,
    List<VoiceItem>? voices,
    MusicTrack? music,
    bool clearMusic = false,
    int? subtitleOffsetMs,
    bool? burnSubtitles,
    double? originalVolume,
  }) =>
      Timeline(
        pieces: pieces ?? this.pieces,
        voices: voices ?? this.voices,
        music: clearMusic ? null : (music ?? this.music),
        subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
        burnSubtitles: burnSubtitles ?? this.burnSubtitles,
        originalVolume: originalVolume ?? this.originalVolume,
      );

  String encode() => jsonEncode({
        'v': 1,
        'pieces': [for (final p in pieces) p.toJson()],
        'voices': [for (final v in voices) v.toJson()],
        'music': music?.toJson(),
        'subOff': subtitleOffsetMs,
        'burn': burnSubtitles,
        'origVol': originalVolume,
      });

  /// Returns an empty timeline when [raw] is empty or damaged, so a broken
  /// save never stops the editor from opening.
  static Timeline decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const Timeline();
    try {
      final m = jsonDecode(raw) as Map<String, Object?>;
      return Timeline(
        pieces: [for (final p in (m['pieces'] as List? ?? const [])) VideoPiece.fromJson((p as Map).cast())],
        voices: [for (final v in (m['voices'] as List? ?? const [])) VoiceItem.fromJson((v as Map).cast())],
        music: m['music'] == null ? null : MusicTrack.fromJson((m['music'] as Map).cast()),
        subtitleOffsetMs: (m['subOff'] as int?) ?? 0,
        burnSubtitles: (m['burn'] as bool?) ?? true,
        originalVolume: (m['origVol'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (_) {
      return const Timeline();
    }
  }
}

// ---- video pieces ----

List<VideoPiece> piecesFromSegments(List<SegmentSpec> segs) =>
    [for (final s in segs) VideoPiece(s.startMs, s.endMs)];

/// Trims piece [i] to [startMs]..[endMs]. Returns null when the range is not
/// valid for a video of [sourceMs] (empty, negative or past the end).
List<VideoPiece>? trimPiece(List<VideoPiece> p, int i, int startMs, int endMs, int sourceMs) {
  if (i < 0 || i >= p.length) return null;
  if (startMs < 0 || endMs <= startMs || endMs > sourceMs) return null;
  final out = [...p];
  out[i] = VideoPiece(startMs, endMs);
  return out;
}

List<VideoPiece> movePiece(List<VideoPiece> p, int i, int delta) {
  final j = i + delta;
  if (i < 0 || i >= p.length || j < 0 || j >= p.length) return p;
  final out = [...p];
  final x = out.removeAt(i);
  out.insert(j, x);
  return out;
}

List<VideoPiece> removePiece(List<VideoPiece> p, int i) {
  if (i < 0 || i >= p.length) return p;
  return [...p]..removeAt(i);
}

/// Cuts piece [i] in two at the ORIGINAL-video time [atMs]. Both halves must
/// keep at least [minMs].
List<VideoPiece> splitPiece(List<VideoPiece> p, int i, int atMs, {int minMs = 500}) {
  if (i < 0 || i >= p.length) return p;
  final x = p[i];
  if (atMs - x.startMs < minMs || x.endMs - atMs < minMs) return p;
  final out = [...p];
  out[i] = VideoPiece(x.startMs, atMs);
  out.insert(i + 1, VideoPiece(atMs, x.endMs));
  return out;
}

/// Where piece [i] starts on the output timeline.
int pieceStartOnTimeline(List<VideoPiece> p, int i) {
  var t = 0;
  for (var k = 0; k < i && k < p.length; k++) {
    t += p[k].lengthMs;
  }
  return t;
}

/// Output time -> (piece number, time inside the original video), or null when
/// the time is outside the edit.
({int piece, int sourceMs})? timelineToSource(List<VideoPiece> p, int timeMs) {
  if (timeMs < 0) return null;
  var t = 0;
  for (var i = 0; i < p.length; i++) {
    final len = p[i].lengthMs;
    if (timeMs < t + len) return (piece: i, sourceMs: p[i].startMs + (timeMs - t));
    t += len;
  }
  return null;
}

// ---- narration ----

/// Places the clips one after another from time zero, no gap. Clips keep the
/// order of [clips].
List<VoiceItem> placeVoicesInSequence(List<VoiceItem> clips, {int gapMs = 0}) {
  var t = 0;
  final out = <VoiceItem>[];
  for (final c in clips) {
    out.add(c.copyWith(offsetMs: t));
    t += c.durationMs + gapMs;
  }
  return out;
}

// ---- subtitles ----

/// Converts subtitles written against the ORIGINAL video into subtitles on the
/// OUTPUT timeline: a subtitle that falls in a kept piece is moved to where
/// that piece sits in the edit, one that crosses a cut is clipped to the piece,
/// one that crosses several pieces is split, and one in a removed part is
/// dropped. [offsetMs] shifts the result. The text is never changed.
List<SrtEntry> remapSubtitles(List<SrtEntry> subs, List<VideoPiece> pieces, {int offsetMs = 0}) {
  final out = <SrtEntry>[];
  var base = 0;
  final parts = <({int start, int end, int base, int pieceStart})>[];
  for (final p in pieces) {
    parts.add((start: p.startMs, end: p.endMs, base: base, pieceStart: p.startMs));
    base += p.lengthMs;
  }
  for (final s in subs) {
    for (final part in parts) {
      final a = s.startMs > part.start ? s.startMs : part.start;
      final b = s.endMs < part.end ? s.endMs : part.end;
      if (b <= a) continue;
      final ns = part.base + (a - part.pieceStart) + offsetMs;
      final ne = part.base + (b - part.pieceStart) + offsetMs;
      if (ne <= 0) continue;
      out.add(SrtEntry(0, ns < 0 ? 0 : ns, ne, s.text));
    }
  }
  out.sort((x, y) => x.startMs.compareTo(y.startMs));
  return [for (var i = 0; i < out.length; i++) SrtEntry(i + 1, out[i].startMs, out[i].endMs, out[i].text)];
}

// ---- checks ----

enum Severity { error, warning }

class TimelineIssue {
  const TimelineIssue(this.severity, this.message);

  final Severity severity;
  final String message;
}

/// Problems that would give a wrong or empty video. Errors must be fixed
/// before rendering; warnings are only worth a look.
List<TimelineIssue> checkTimeline(Timeline t, {required int sourceMs}) {
  final out = <TimelineIssue>[];
  if (t.pieces.isEmpty) {
    out.add(const TimelineIssue(Severity.error, 'ဗီဒီယို အပိုင်း မရှိသေးပါ'));
  }
  for (var i = 0; i < t.pieces.length; i++) {
    final p = t.pieces[i];
    if (p.startMs < 0 || p.endMs <= p.startMs || (sourceMs > 0 && p.endMs > sourceMs)) {
      out.add(TimelineIssue(Severity.error, 'အပိုင်း ${i + 1} အချိန် မမှန်ပါ'));
    }
  }
  final total = t.videoMs;
  if (t.voices.isEmpty) {
    out.add(const TimelineIssue(Severity.warning, 'အသံ (narration) မထည့်ရသေးပါ'));
  } else if (t.voiceEndMs > total && total > 0) {
    out.add(TimelineIssue(Severity.warning, 'အသံက ဗီဒီယိုထက် ${((t.voiceEndMs - total) / 1000).toStringAsFixed(1)} စက္ကန့် ပိုရှည်တယ် (ဗီဒီယိုကို ဖြတ်ထုတ်ပစ်မယ်)'));
  }
  final vs = [...t.voices]..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
  for (var i = 1; i < vs.length; i++) {
    if (vs[i].offsetMs < vs[i - 1].endMs) {
      out.add(TimelineIssue(Severity.warning, '"${vs[i - 1].label}" နဲ့ "${vs[i].label}" အသံ ထပ်နေတယ်'));
    }
  }
  return out;
}
