import 'srt.dart';
import 'timeline.dart';

/// Turns the edit description into the job that the native renderer runs, and
/// answers questions like "how big will the file be" and "can we render".
/// Pure Dart, no Flutter.

class RenderSettings {
  const RenderSettings({this.height = 720, this.fps = 30});

  /// 720 or 1080 (output height in pixels; width follows the video).
  final int height;
  final int fps;

  RenderSettings copyWith({int? height, int? fps}) => RenderSettings(height: height ?? this.height, fps: fps ?? this.fps);
}

/// Video bitrate in bits per second for the chosen size and frame rate.
int videoBitrate(RenderSettings s) {
  final base = s.height >= 1080 ? 8000000 : 4000000;
  return s.fps > 30 ? (base * 1.4).round() : base;
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
}) {
  final subs = remapSubtitles(sourceSubtitles, timeline.pieces, offsetMs: timeline.subtitleOffsetMs);
  final lanes = assignVoiceLanes(timeline.voices);
  final dur = outputDurationMs(timeline);
  return {
    'name': name,
    'videoUri': videoUri,
    'height': settings.height,
    'fps': settings.fps,
    'bitrate': videoBitrate(settings),
    'estimateBytes': estimateBytes(dur, settings),
    'originalVolume': timeline.originalVolume,
    'pieces': [for (final p in timeline.pieces) {'s': p.startMs, 'e': p.endMs}],
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
  };
}

/// A file name that is safe on every Android file system.
String safeFileName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
  final s = cleaned.isEmpty ? 'dramaflow' : cleaned;
  return s.length > 60 ? s.substring(0, 60) : s;
}
