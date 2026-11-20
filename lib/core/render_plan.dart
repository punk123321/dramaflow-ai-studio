import 'srt.dart';
import 'te_frames.dart';
import 'timeline.dart';

/// Turns the edit description into the job that the native renderer runs, and
/// answers questions like "how big will the file be" and "can we render".
/// Pure Dart, no Flutter.

/// Shape of the finished video.
enum OutRatio {
  original('မူရင်းအတိုင်း', 0),
  r16x9('16:9 (အလျား)', 16 / 9),
  r9x16('9:16 (Shorts / Reels / TikTok)', 9 / 16),
  r1x1('1:1 (လေးထောင့်)', 1),
  r4x5('4:5 (Feed)', 4 / 5);

  const OutRatio(this.label, this.value);
  final String label;

  /// width / height. 0 means "same as the source".
  final double value;
}

/// What to do when the source shape differs from the chosen shape.
enum FillMode {
  /// Whole picture kept, black bars fill the rest.
  bars('အနက်ရောင် အကွက်'),

  /// Picture fills the frame; the edges that do not fit are cut off.
  crop('ဖြတ်ပြီး ပြည့်အောင်'),

  /// Whole picture kept, a blurred, enlarged copy of the same video fills the
  /// rest. Experimental.
  blur('blur နောက်ခံ (စမ်းသပ်)');

  const FillMode(this.label);
  final String label;
}

class RenderSettings {
  const RenderSettings({
    this.height = 720,
    this.fps = 30,
    this.ratio = OutRatio.original,
    this.fill = FillMode.bars,
    this.videoKbps = 0,
    this.sourceBps = 0,
  });

  /// Shorter side of the output in pixels (720 or 1080). For a landscape video
  /// this is the height, for a vertical one the width.
  final int height;
  final int fps;
  final OutRatio ratio;
  final FillMode fill;

  /// Video bitrate in kilobits per second. 0 = automatic: close to the original
  /// file's bitrate, never above the normal value for the chosen size.
  final int videoKbps;

  /// Overall bitrate of the original file in bits per second (file size x 8 /
  /// length), 0 when unknown. Set by the screen, not chosen by the user.
  final int sourceBps;

  RenderSettings copyWith({int? height, int? fps, OutRatio? ratio, FillMode? fill, int? videoKbps, int? sourceBps}) => RenderSettings(
        height: height ?? this.height,
        fps: fps ?? this.fps,
        ratio: ratio ?? this.ratio,
        fill: fill ?? this.fill,
        videoKbps: videoKbps ?? this.videoKbps,
        sourceBps: sourceBps ?? this.sourceBps,
      );
}

/// Choices for the quality menu (kbps). 0 is automatic.
const qualityChoices = [0, 1000, 1500, 2000, 3000, 4000, 6000, 8000];

String qualityLabel(int kbps) => kbps == 0 ? 'Auto (မူရင်းဖိုင်နဲ့ ကပ်)' : '${kbps >= 1000 ? (kbps / 1000).toStringAsFixed(kbps % 1000 == 0 ? 0 : 1) : kbps} Mbps';

/// Original file's overall bitrate from its size and length; 0 when unknown.
int sourceBitsPerSecond(int? sizeBytes, int? durationMs) {
  if (sizeBytes == null || durationMs == null || sizeBytes <= 0 || durationMs <= 0) return 0;
  return (sizeBytes * 8 * 1000 / durationMs).round();
}

int _even(double v) {
  final r = v.round();
  final e = r.isOdd ? r + 1 : r;
  return e < 2 ? 2 : e;
}

/// Output width and height in pixels. [sourceAspect] is width / height of the
/// source and is used only for [OutRatio.original].
({int w, int h}) outputSize(RenderSettings s, double sourceAspect) {
  final short = s.height;
  final r = s.ratio == OutRatio.original ? (sourceAspect > 0.2 && sourceAspect < 5 ? sourceAspect : 16 / 9) : s.ratio.value;
  // "Original" keeps the old behaviour: the height is fixed, the width follows.
  if (s.ratio == OutRatio.original) return (w: _even(short * r), h: _even(short.toDouble()));
  if (r >= 1) return (w: _even(short * r), h: _even(short.toDouble()));
  return (w: _even(short.toDouble()), h: _even(short / r));
}

/// One tap sets shape, size and frame rate. These are common settings, not a
/// promise about what any platform accepts today.
class PlatformPreset {
  const PlatformPreset(this.id, this.label, this.note, this.ratio, this.height, this.fps, this.fill);

  final String id;
  final String label;
  final String note;
  final OutRatio ratio;
  final int height;
  final int fps;
  final FillMode fill;

  RenderSettings get settings => RenderSettings(height: height, fps: fps, ratio: ratio, fill: fill);
}

const platformPresets = <PlatformPreset>[
  PlatformPreset('shorts', 'YouTube Shorts', '9:16 · 1080 · 30fps', OutRatio.r9x16, 1080, 30, FillMode.blur),
  PlatformPreset('tiktok', 'TikTok / Reels', '9:16 · 720 · 30fps', OutRatio.r9x16, 720, 30, FillMode.blur),
  PlatformPreset('youtube', 'YouTube (ပုံမှန်)', '16:9 · 1080 · 30fps', OutRatio.r16x9, 1080, 30, FillMode.bars),
  PlatformPreset('feed', 'Facebook Feed', '4:5 · 1080 · 30fps', OutRatio.r4x5, 1080, 30, FillMode.blur),
  PlatformPreset('square', 'လေးထောင့် (1:1)', '1:1 · 720 · 30fps', OutRatio.r1x1, 720, 30, FillMode.blur),
];

/// Video bitrate in bits per second for the chosen size and frame rate.
int videoBitrate(RenderSettings s) {
  if (s.videoKbps > 0) return s.videoKbps * 1000;
  final base = s.height >= 1080 ? 8000000 : (s.height >= 720 ? 4000000 : 1800000);
  // Other shapes have more or fewer pixels than 16:9 at the same short side.
  final r = s.ratio == OutRatio.original ? 16 / 9 : s.ratio.value;
  final area = (r >= 1 ? r : 1 / r) / (16 / 9);
  var scaled = (base * area.clamp(0.5, 1.2)).round();
  if (s.fps > 30) scaled = (scaled * 1.4).round();
  if (s.sourceBps > 0) {
    // Stay near the original: a bigger bitrate only makes a bigger file, not a better picture.
    final near = ((s.sourceBps - 128000) * 1.2).round();
    final floor = 800000;
    final target = near < floor ? floor : near;
    return target < scaled ? target : scaled;
  }
  return scaled;
}

const int _audioBitrate = 128000;

/// Rough size of the finished file. Real size varies with the picture, so
/// this is shown as "about". Used before rendering and for the free-space check.
int estimateBytes(int durationMs, RenderSettings s) {
  if (durationMs <= 0) return 0;
  final bits = (videoBitrate(s) + _audioBitrate) * (durationMs / 1000);
  return (bits / 8 * 1.05).round();
}

/// Output length: the video pieces. Narration or music that run longer than
/// the video are cut at the end of the video.
int outputDurationMs(Timeline t) => t.videoMs;

/// Splits narration into lanes so that no lane has two clips at the same time.
/// Clips inside a lane are sorted by start. Most projects need one lane.
List<List<VoiceItem>> assignVoiceLanes(List<VoiceItem> voices) {
  final sorted = [...voices]..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
  final lanes = <List<VoiceItem>>[];
  for (final v in sorted) {
    var placed = false;
    for (final lane in lanes) {
      if (lane.last.endMs <= v.offsetMs) {
        lane.add(v);
        placed = true;
        break;
      }
    }
    if (!placed) lanes.add([v]);
  }
  return lanes;
}

String _uri(String source) => source.startsWith('/') ? 'file://$source' : source;

/// Files named by the edit (narration, music, logo) that [exists] says are
/// gone. Content links (not starting with '/') cannot be checked here.
List<String> missingEditFiles(Timeline t, bool Function(String path) exists) {
  final out = <String>[];
  for (final v in t.voices) {
    if (v.source.startsWith('/') && !exists(v.source)) out.add('အသံဖိုင် ပျောက်နေတယ်: ${v.label}');
  }
  final m = t.music;
  if (m != null && m.source.startsWith('/') && !exists(m.source)) out.add('Background music ဖိုင် ပျောက်နေတယ်: ${m.name}');
  final l = t.logo;
  if (l != null && l.path.startsWith('/') && !exists(l.path)) out.add('Logo ပုံ ပျောက်နေတယ်');
  return out;
}

/// Reasons why rendering cannot start. Empty means it can.
List<String> renderBlockers({required bool hasVideo, required Timeline timeline, required int sourceMs}) {
  final out = <String>[];
  if (!hasVideo) out.add('မူရင်းဗီဒီယို မရွေးရသေးပါ');
  for (final i in checkTimeline(timeline, sourceMs: sourceMs)) {
    if (i.severity == Severity.error) out.add(i.message);
  }
  return out;
}

/// The job sent to the native renderer, as a plain map (encoded to JSON by the
/// caller). Subtitles are converted to the OUTPUT timeline here.
Map<String, Object?> buildRenderJob({
  required String name,
  required String videoUri,
  required Timeline timeline,
  required List<SrtEntry> sourceSubtitles,
  required RenderSettings settings,
  double aspect = 16 / 9,
  List<Map<String, Object?>> overlays = const [],
  List<Map<String, Object?>> splits = const [],
  List<Map<String, Object?>> censors = const [],
}) {
  final subs = remapSubtitles(sourceSubtitles, timeline.pieces, offsetMs: timeline.subtitleOffsetMs);
  final lanes = assignVoiceLanes(timeline.voices);
  final dur = outputDurationMs(timeline);
  final size = outputSize(settings, aspect);
  // Blur background needs the picture to be one continuous stream; freeze
  // frames are separate pictures, so those jobs use black bars instead.
  final hasFreeze = timeline.pieces.any((p) => p.freeze);
  final fill = (settings.fill == FillMode.blur && (hasFreeze || splits.isNotEmpty || censors.isNotEmpty)) ? FillMode.bars : settings.fill;
  return {
    'name': name,
    'videoUri': videoUri,
    'height': size.h,
    'outW': size.w,
    'outH': size.h,
    'fit': settings.ratio == OutRatio.original ? 'orig' : fill.name,
    'fps': settings.fps,
    'bitrate': videoBitrate(settings),
    'estimateBytes': estimateBytes(dur, settings),
    'originalVolume': timeline.originalVolume,
    'pieces': [
      for (final p in timeline.pieces)
        {
          's': p.startMs,
          'e': p.endMs,
          'z': p.zoom.index,
          if (p.crop != null) 'c': p.crop!.toJson(),
          if (p.freeze) 'f': 1,
          if (p.look != null) 'l': p.look!.toJson(),
          if (p.speed != 1.0) 'sp': p.speed,
          if (p.blur != null) 'bl': p.blur,
          if (p.flipH) 'fh': 1,
          if (p.flipV) 'fv': 1,
        }
    ],
    'aspect': aspect,
    'subStyle': timeline.style.toJson(),
    'corners': [for (final c in timeline.corners) if (c.text.trim().isNotEmpty) c.toJson()],
    'logo': timeline.logo?.toJson(),
    'voiceLanes': [
      for (final lane in lanes)
        [
          for (final v in lane) {'uri': _uri(v.source), 'off': v.offsetMs, 'dur': v.durationMs, 'vol': v.volume}
        ]
    ],
    'music': timeline.music == null
        ? null
        : {'uri': _uri(timeline.music!.source), 'vol': timeline.music!.volume, 'loop': timeline.music!.loop},
    'burn': timeline.burnSubtitles,
    'subtitles': [for (final s in subs) {'s': s.startMs, 'e': s.endMs, 't': s.text}],
    if (overlays.isNotEmpty) 'overlays': [for (final o in overlays) _withFramePrims(o, size.w, size.h)],
    if (splits.isNotEmpty) 'splits': splits,
    if (censors.isNotEmpty) 'censors': censors,
  };
}

/// Longest sample, in milliseconds.
const sampleMs = 8000;

/// The first [limitMs] of the finished video: pieces are cut at that point,
/// narration that starts later is dropped. Used for a quick test render.
Timeline sampleTimeline(Timeline t, {int limitMs = sampleMs}) {
  final out = <VideoPiece>[];
  var used = 0;
  for (final p in t.pieces) {
    if (used >= limitMs) break;
    final room = limitMs - used;
    if (p.lengthMs <= room) {
      out.add(p);
      used += p.lengthMs;
    } else {
      if (room >= 200) out.add(p.withRange(p.startMs, p.startMs + (room * p.speed).round()));
      used += room;
    }
  }
  return t.copyWith(
    pieces: out,
    voices: [for (final v in t.voices) if (v.offsetMs < limitMs) v],
  );
}

/// Keeps the windows (maps with 's' and 'e' in output milliseconds) that start
/// before [limitMs] and cuts the rest. Windows left shorter than [minMs] go.
List<Map<String, Object?>> clipWindows(List<Map<String, Object?>> items, int limitMs, {int minMs = 300}) {
  final out = <Map<String, Object?>>[];
  for (final m in items) {
    final s = m['s'] as int;
    final e = m['e'] as int;
    if (s >= limitMs) continue;
    final e2 = e > limitMs ? limitMs : e;
    if (e2 - s < minMs) continue;
    out.add({...m, 'e': e2});
  }
  return out;
}

/// A file name that is safe on every Android file system.
String safeFileName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
  final s = cleaned.isEmpty ? 'dramaflow' : cleaned;
  return s.length > 60 ? s.substring(0, 60) : s;
}

/// A frame overlay with a ready-made template gets its drawing primitives for
/// the real output size, so the render draws exactly the list the preview shows.
Map<String, Object?> _withFramePrims(Map<String, Object?> o, int w, int h) {
  final tpl = o['tpl'];
  if (o['k'] != 'frame' || tpl is! int || tpl <= 0) return o;
  final size = o['size'];
  final color = o['color'];
  final prims = framePrims(tpl, color is int ? color : 0xFFFFFFFF, size is num ? size.toDouble() : 0.012, w.toDouble(), h.toDouble());
  return prims.isEmpty ? o : {...o, 'prims': prims};
}
