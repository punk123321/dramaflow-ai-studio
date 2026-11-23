import 'dart:convert';

import 'news_video.dart' show JobState;

/// A video given as a link (YouTube, TikTok, Red Note ...) instead of a file.
/// The user's own backend downloads it, puts it into the user's own Gemini
/// account and answers with the Gemini file address and the length. This file
/// has no network and no Flutter: link reading, cache and answer parsing.

enum LinkKind { youtube, tiktok, rednote, douyin, bilibili, other }

const linkKindLabels = <LinkKind, String>{
  LinkKind.youtube: 'YouTube',
  LinkKind.tiktok: 'TikTok',
  LinkKind.rednote: 'Red Note',
  LinkKind.douyin: 'Douyin',
  LinkKind.bilibili: 'Bilibili',
  LinkKind.other: 'တခြား website',
};

final _url = RegExp('https?://[^\\s<>"‘’“”，。）)】」]+', caseSensitive: false);

/// The first web address in [text]. Share texts from TikTok / Red Note carry
/// words around the link, so the whole text can be pasted. Null when none.
String? extractLink(String text) {
  final m = _url.firstMatch(text);
  if (m == null) return null;
  var u = m.group(0)!;
  while (u.isNotEmpty && '.,;:!?]}\'"'.contains(u[u.length - 1])) {
    u = u.substring(0, u.length - 1);
  }
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty) return null;
  return u;
}

LinkKind linkKindOf(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  bool on(List<String> names) => names.any((n) => host == n || host.endsWith('.$n'));
  if (on(['youtube.com', 'youtu.be'])) return LinkKind.youtube;
  if (on(['tiktok.com'])) return LinkKind.tiktok;
  if (on(['xiaohongshu.com', 'xhslink.com'])) return LinkKind.rednote;
  if (on(['douyin.com', 'iesdouyin.com'])) return LinkKind.douyin;
  if (on(['bilibili.com', 'b23.tv'])) return LinkKind.bilibili;
  return LinkKind.other;
}

/// Gemini keeps an uploaded file for 48 hours; a bit less is trusted here.
const ingestKeepHours = 44;

/// What the backend gave back for a link, kept on the phone so a retry (or the
/// next run) does not download and upload the same video again.
class IngestInfo {
  const IngestInfo({
    required this.url,
    required this.fileUri,
    required this.mime,
    required this.durationMs,
    this.title = '',
    this.source = 'other',
    this.savedAtMs = 0,
  });

  final String url;
  final String fileUri;
  final String mime;
  final int durationMs;
  final String title;
  final String source;
  final int savedAtMs;

  /// True when this is for the same link and Gemini surely still has the file.
  bool usableFor(String link, int nowMs) =>
      url == link.trim() && fileUri.isNotEmpty && durationMs > 0 && nowMs >= savedAtMs && nowMs - savedAtMs < ingestKeepHours * 3600 * 1000;

  Map<String, Object?> toJson() => {
        'url': url,
        'file_uri': fileUri,
        'mime': mime,
        'duration_ms': durationMs,
        'title': title,
        'source': source,
        'saved_at': savedAtMs,
      };

  String encode() => jsonEncode(toJson());

  /// Null when the text is not a complete record.
  static IngestInfo? decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map) return null;
      final uri = m['file_uri'];
      final url = m['url'];
      final dur = m['duration_ms'];
      if (uri is! String || url is! String || uri.isEmpty || dur is! num) return null;
      final mime = m['mime'];
      final at = m['saved_at'];
      return IngestInfo(
        url: url,
        fileUri: uri,
        mime: mime is String && mime.isNotEmpty ? mime : 'video/mp4',
        durationMs: dur.toInt(),
        title: m['title'] is String ? m['title'] as String : '',
        source: m['source'] is String ? m['source'] as String : 'other',
        savedAtMs: at is num ? at.toInt() : 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class IngestJob {
  const IngestJob({required this.state, this.stage = '', this.progress = 0, this.error = '', this.info});

  final JobState state;
  final String stage;
  final int progress;
  final String error;

  /// The backend's answer ({file_uri, mime, duration_ms, title, source}) when done.
  final Map<String, Object?>? info;
}

/// Reads the reply of "ingest job status". Anything unreadable is an error job.
IngestJob parseIngestJob(String body) {
  const bad = IngestJob(state: JobState.error, error: 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
  try {
    final m = jsonDecode(body);
    if (m is! Map) return bad;
    final st = switch (m['status']) {
      'queued' => JobState.queued,
      'running' => JobState.running,
      'done' => JobState.done,
      _ => JobState.error,
    };
    final pr = m['progress'];
    final inf = m['info'];
    return IngestJob(
      state: st,
      stage: m['stage'] is String ? m['stage'] as String : '',
      progress: pr is num ? pr.clamp(0, 100).round() : 0,
      error: m['error'] is String ? m['error'] as String : '',
      info: inf is Map ? inf.map((k, v) => MapEntry('$k', v)) : null,
    );
  } catch (_) {
    return bad;
  }
}

/// Builds the record to keep from a finished job's answer, or null when the
/// answer lacks the file address or the length (then the link cannot be used).
IngestInfo? ingestInfoFrom(String url, Map<String, Object?>? answer, int nowMs) {
  if (answer == null) return null;
  final uri = answer['file_uri'];
  final dur = answer['duration_ms'];
  if (uri is! String || uri.isEmpty || dur is! num || dur <= 0) return null;
  final mime = answer['mime'];
  return IngestInfo(
    url: url.trim(),
    fileUri: uri,
    mime: mime is String && mime.isNotEmpty ? mime : 'video/mp4',
    durationMs: dur.toInt(),
    title: answer['title'] is String ? answer['title'] as String : '',
    source: answer['source'] is String ? answer['source'] as String : 'other',
    savedAtMs: nowMs,
  );
}
