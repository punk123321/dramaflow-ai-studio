import 'dart:convert';

import 'segments.dart';
import 'srt.dart';

/// The edit decision list of one project: which parts of the original video
/// are kept, which narration and music go with them, and how subtitles are
/// placed. It only DESCRIBES the edit. The original video is never changed,
/// and the render step (Phase 7) turns this description into a new MP4.
/// Pure Dart, no Flutter.

/// Slow zoom on one video piece (framing and emphasis only).
enum ZoomMode { none, zoomIn, zoomOut }

/// A still crop of one video piece: [zoom] 1.0 = whole picture, 2.0 = half the
/// width and height. [cx], [cy] is the centre of the kept area, 0 to 1 from the
/// top-left corner. It only changes framing; the original is never changed.
class CropFrame {
  const CropFrame(this.zoom, this.cx, this.cy);

  static const minZoom = 1.0;
  static const maxZoom = 4.0;

  final double zoom;
  final double cx;
  final double cy;

  /// Zoom limited to the allowed range and the centre pushed inside the
  /// picture so no empty border can show.
  CropFrame get fitted {
    final z = zoom.isNaN ? 1.0 : zoom.clamp(minZoom, maxZoom).toDouble();
    final half = 0.5 / z;
    double c(double v) => (v.isNaN ? 0.5 : v).clamp(half, 1 - half).toDouble();
    return CropFrame(z, c(cx), c(cy));
  }

  List<double> toJson() => [zoom, cx, cy];

  static CropFrame? fromJson(Object? v) {
    if (v is! List || v.length != 3 || v.any((e) => e is! num)) return null;
    return CropFrame((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble()).fitted;
  }

  @override
  bool operator ==(Object other) =>
      other is CropFrame && other.zoom == zoom && other.cx == cx && other.cy == cy;

  @override
  int get hashCode => Object.hash(zoom, cx, cy);
}

class VideoPiece {
  const VideoPiece(this.startMs, this.endMs, [this.zoom = ZoomMode.none, this.crop, this.freeze = false]);

  /// A still frame of the original at [atMs], held for [holdMs]. Only the
  /// render step creates these (from approved Freeze Frame operations); they
  /// are never saved in the timeline.
  const VideoPiece.freezeAt(int atMs, int holdMs, [CropFrame? c])
      : startMs = atMs,
        endMs = atMs + holdMs,
        zoom = ZoomMode.none,
        crop = c,
        freeze = true;

  /// Range inside the ORIGINAL video.
  final int startMs;
  final int endMs;
  final ZoomMode zoom;
  final CropFrame? crop;

  /// Still frame instead of moving video: [startMs] is the frame time and
  /// [lengthMs] how long it is held.
  final bool freeze;

  int get lengthMs => endMs - startMs;

  VideoPiece withRange(int s, int e) => VideoPiece(s, e, zoom, crop, freeze);
  VideoPiece withZoom(ZoomMode z) => VideoPiece(startMs, endMs, z, crop, freeze);
  VideoPiece withCrop(CropFrame? c) => VideoPiece(startMs, endMs, zoom, c, freeze);

  @override
  bool operator ==(Object other) =>
      other is VideoPiece &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.zoom == zoom &&
      other.crop == crop &&
      other.freeze == freeze;

  @override
  int get hashCode => Object.hash(startMs, endMs, zoom, crop, freeze);

  Map<String, Object?> toJson() => {
        's': startMs,
        'e': endMs,
        if (zoom != ZoomMode.none) 'z': zoom.index,
        if (crop != null) 'c': crop!.toJson(),
        if (freeze) 'f': 1,
      };
  static VideoPiece fromJson(Map<String, Object?> m) {
    final z = (m['z'] as int?) ?? 0;
    return VideoPiece(
      m['s'] as int,
      m['e'] as int,
      z >= 0 && z < ZoomMode.values.length ? ZoomMode.values[z] : ZoomMode.none,
      CropFrame.fromJson(m['c']),
      m['f'] == 1,
    );
  }
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

enum Corner { topLeft, topRight, bottomLeft, bottomRight }

Corner _corner(Object? v, Corner d) {
  final i = v is int ? v : -1;
  return i >= 0 && i < Corner.values.length ? Corner.values[i] : d;
}

/// How subtitles look. [size] is a fraction of the video height.
class SubStyle {
  const SubStyle({this.size = 0.05, this.color = 0xFFFFFFFF, this.background = true, this.top = false});

  final double size;

  /// ARGB colour.
  final int color;
  final bool background;
  final bool top;

  SubStyle copyWith({double? size, int? color, bool? background, bool? top}) => SubStyle(
        size: size ?? this.size,
        color: color ?? this.color,
        background: background ?? this.background,
        top: top ?? this.top,
      );

  Map<String, Object?> toJson() => {'size': size, 'color': color, 'bg': background, 'top': top};
  static SubStyle fromJson(Map<String, Object?> m) => SubStyle(
        size: ((m['size'] as num?)?.toDouble() ?? 0.05).clamp(0.02, 0.12),
        color: (m['color'] as int?) ?? 0xFFFFFFFF,
        background: (m['bg'] as bool?) ?? true,
        top: (m['top'] as bool?) ?? false,
      );
}

/// The user's own text in a corner of the video, such as a channel or credit
/// line. [size] is a fraction of the video height.
class CornerText {
  const CornerText({required this.text, this.corner = Corner.bottomRight, this.size = 0.035, this.color = 0xFFFFFFFF});

  final String text;
  final Corner corner;
  final double size;
  final int color;

  CornerText copyWith({String? text, Corner? corner, double? size, int? color}) => CornerText(
        text: text ?? this.text,
        corner: corner ?? this.corner,
        size: size ?? this.size,
        color: color ?? this.color,
      );

  Map<String, Object?> toJson() => {'t': text, 'c': corner.index, 'size': size, 'color': color};
  static CornerText fromJson(Map<String, Object?> m) => CornerText(
        text: (m['t'] as String?) ?? '',
        corner: _corner(m['c'], Corner.bottomRight),
        size: ((m['size'] as num?)?.toDouble() ?? 0.035).clamp(0.02, 0.12),
        color: (m['color'] as int?) ?? 0xFFFFFFFF,
      );
}

/// The user's own logo picture. [size] is a fraction of the video width.
class LogoItem {
  const LogoItem({required this.path, this.corner = Corner.topRight, this.size = 0.15, this.opacity = 0.9});

  /// A copy of the picture kept inside the app.
  final String path;
  final Corner corner;
  final double size;
  final double opacity;

  LogoItem copyWith({String? path, Corner? corner, double? size, double? opacity}) => LogoItem(
        path: path ?? this.path,
        corner: corner ?? this.corner,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
      );

  Map<String, Object?> toJson() => {'path': path, 'c': corner.index, 'size': size, 'op': opacity};
  static LogoItem fromJson(Map<String, Object?> m) => LogoItem(
        path: m['path'] as String,
        corner: _corner(m['c'], Corner.topRight),
        size: ((m['size'] as num?)?.toDouble() ?? 0.15).clamp(0.05, 0.5),
        opacity: ((m['op'] as num?)?.toDouble() ?? 0.9).clamp(0.1, 1.0),
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
    this.style = const SubStyle(),
    this.corners = const [],
    this.logo,
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

  final SubStyle style;
  final List<CornerText> corners;
  final LogoItem? logo;

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
    SubStyle? style,
    List<CornerText>? corners,
    LogoItem? logo,
    bool clearLogo = false,
  }) =>
      Timeline(
        pieces: pieces ?? this.pieces,
        voices: voices ?? this.voices,
        music: clearMusic ? null : (music ?? this.music),
        subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
        burnSubtitles: burnSubtitles ?? this.burnSubtitles,
        originalVolume: originalVolume ?? this.originalVolume,
        style: style ?? this.style,
        corners: corners ?? this.corners,
        logo: clearLogo ? null : (logo ?? this.logo),
      );

  String encode() => jsonEncode({
        'v': 1,
        'pieces': [for (final p in pieces) p.toJson()],
        'voices': [for (final v in voices) v.toJson()],
        'music': music?.toJson(),
        'subOff': subtitleOffsetMs,
        'burn': burnSubtitles,
        'origVol': originalVolume,
        'style': style.toJson(),
        'corners': [for (final c in corners) c.toJson()],
        'logo': logo?.toJson(),
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
        style: m['style'] == null ? const SubStyle() : SubStyle.fromJson((m['style'] as Map).cast()),
        corners: [for (final c in (m['corners'] as List? ?? const [])) CornerText.fromJson((c as Map).cast())],
        logo: m['logo'] == null ? null : LogoItem.fromJson((m['logo'] as Map).cast()),
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
  out[i] = p[i].withRange(startMs, endMs);
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

List<VideoPiece> setZoom(List<VideoPiece> p, int i, ZoomMode z) {
  if (i < 0 || i >= p.length) return p;
  final out = [...p];
  out[i] = out[i].withZoom(z);
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
  out[i] = x.withRange(x.startMs, atMs);
  out.insert(i + 1, x.withRange(atMs, x.endMs));
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
    // A held still frame shows no original subtitle (it is for commentary).
    if (!p.freeze) parts.add((start: p.startMs, end: p.endMs, base: base, pieceStart: p.startMs));
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
