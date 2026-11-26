import 'dart:convert';

/// Creator Studio (the app side). Everything heavy runs on the user's own
/// backend (a Colab notebook); the phone only sends settings, shows progress
/// and brings finished files back. This file is the pure part: reading the
/// backend's answers and building its requests.

class StudioFile {
  const StudioFile({required this.name, required this.size, required this.kind, required this.mtime});

  final String name;
  final int size;

  /// video | audio | srt | image | zip | other
  final String kind;
  final int mtime;

  bool get isVideo => kind == 'video';
  bool get isSrt => kind == 'srt';
  bool get isImage => kind == 'image';
}

class StudioLibrary {
  const StudioLibrary({this.files = const [], this.freeGb, this.aria2c = false, this.ytSecret = false, this.ytLinked = false});

  final List<StudioFile> files;
  final double? freeGb;
  final bool aria2c;
  final bool ytSecret;
  final bool ytLinked;

  List<StudioFile> ofKind(String kind) => [for (final f in files) if (f.kind == kind) f];
}

Map<String, Object?> _map(String body) {
  try {
    final m = jsonDecode(body);
    if (m is Map) return m.cast<String, Object?>();
  } catch (_) {}
  return const {};
}

StudioLibrary parseStudioLibrary(String body) {
  final m = _map(body);
  final files = <StudioFile>[];
  final raw = m['files'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map && e['name'] is String) {
        files.add(StudioFile(
          name: e['name'] as String,
          size: (e['size'] as num?)?.toInt() ?? 0,
          kind: e['kind'] as String? ?? 'other',
          mtime: (e['mtime'] as num?)?.toInt() ?? 0,
        ));
      }
    }
  }
  final yt = m['youtube'];
  return StudioLibrary(
    files: files,
    freeGb: (m['free_gb'] as num?)?.toDouble(),
    aria2c: m['aria2c'] == true,
    ytSecret: yt is Map && yt['secret'] == true,
    ytLinked: yt is Map && yt['linked'] == true,
  );
}

class StudioLink {
  const StudioLink({required this.title, required this.watch, this.studio = '', this.note = ''});

  final String title;
  final String watch;
  final String studio;
  final String note;
}

enum StudioState { queued, running, done, error, canceled }

class StudioJob {
  const StudioJob({
    required this.state,
    this.op = '',
    this.stage = '',
    this.progress = 0,
    this.error = '',
    this.paused = false,
    this.downloadedMb,
    this.totalMb,
    this.speedMbs,
    this.etaSeconds,
    this.fragment = '',
    this.files = const [],
    this.links = const [],
    this.notes = const [],
    this.errors = const [],
  });

  final StudioState state;
  final String op;
  final String stage;
  final int progress;
  final String error;
  final bool paused;
  final double? downloadedMb;
  final double? totalMb;
  final double? speedMbs;
  final int? etaSeconds;
  final String fragment;
  final List<String> files;
  final List<StudioLink> links;
  final List<String> notes;
  final List<String> errors;

  bool get finished => state == StudioState.done || state == StudioState.error || state == StudioState.canceled;
}

List<String> _strings(Object? v) => v is List ? [for (final e in v) if (e is String) e] : const [];

StudioJob parseStudioJob(String body) {
  final m = _map(body);
  final state = switch (m['status']) {
    'running' => StudioState.running,
    'done' => StudioState.done,
    'error' => StudioState.error,
    'canceled' => StudioState.canceled,
    _ => StudioState.queued,
  };
  final d = m['detail'] is Map ? (m['detail'] as Map).cast<String, Object?>() : const <String, Object?>{};
  final r = m['result'] is Map ? (m['result'] as Map).cast<String, Object?>() : const <String, Object?>{};
  final links = <StudioLink>[];
  final rawLinks = r['links'];
  if (rawLinks is List) {
    for (final e in rawLinks) {
      if (e is Map && e['watch'] is String) {
        links.add(StudioLink(title: e['title'] as String? ?? '', watch: e['watch'] as String, studio: e['studio'] as String? ?? '', note: e['note'] as String? ?? ''));
      }
    }
  }
  return StudioJob(
    state: state,
    op: m['op'] as String? ?? '',
    stage: m['stage'] as String? ?? '',
    progress: ((m['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
    error: m['error'] as String? ?? '',
    paused: d['paused'] == true,
    downloadedMb: (d['downloaded_mb'] as num?)?.toDouble(),
    totalMb: (d['total_mb'] as num?)?.toDouble(),
    speedMbs: (d['speed_mbs'] as num?)?.toDouble(),
    etaSeconds: (d['eta'] as num?)?.toInt(),
    fragment: d['fragment'] as String? ?? '',
    files: _strings(r['files']),
    links: links,
    notes: _strings(r['notes']),
    errors: _strings(r['errors']),
  );
}

// ---- text helpers ---------------------------------------------------------

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String etaText(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  if (seconds < 60) return '$seconds စက္ကန့်';
  final m = seconds ~/ 60;
  if (seconds < 3600) return '$m မိနစ် ${seconds % 60} စက္ကန့်';
  return '${m ~/ 60} နာရီ ${m % 60} မိနစ်';
}

/// One line for the download card: "12.4 / 80 MB · 3.2 MB/s · ကျန် 21 စက္ကန့်" ("ခဏရပ်ထားတယ်" while paused).
String downloadLine(StudioJob j) {
  if (j.paused) return 'ခဏရပ်ထားတယ် — "ဆက်" နှိပ်ရင် ဆက်ဆွဲမယ်';
  final parts = <String>[];
  if (j.downloadedMb != null) {
    parts.add(j.totalMb != null && j.totalMb! > 0 ? '${j.downloadedMb!.toStringAsFixed(1)} / ${j.totalMb!.toStringAsFixed(0)} MB' : '${j.downloadedMb!.toStringAsFixed(1)} MB');
  }
  if (j.speedMbs != null && j.speedMbs! > 0) parts.add('${j.speedMbs!.toStringAsFixed(1)} MB/s');
  final eta = etaText(j.etaSeconds);
  if (eta.isNotEmpty) parts.add('ကျန် $eta');
  if (j.fragment.isNotEmpty) parts.add('အပိုင်းငယ် ${j.fragment}');
  return parts.join(' · ');
}

// ---- choices (keys are the backend's) -------------------------------------

const studioQualities = <(String, String)>[
  ('best', 'အကောင်းဆုံး (အကြီးဆုံး)'),
  ('1080', '1080p'),
  ('1080hevc', '1080p HEVC (ဖိုင်သေး)'),
  ('720', '720p (အကြံပြု)'),
  ('480', '480p (ဖိုင်အသေးဆုံး)'),
  ('mp3', 'MP3 (အသံပဲ)'),
  ('srt', 'စာတန်းပဲ (.srt)'),
];

const studioSpeeds = <(String, String)>[
  ('native', '1 လိုင်း (ပုံမှန်၊ အလုံခြုံဆုံး)'),
  ('safe2', '2 လိုင်း'),
  ('safe4', '4 လိုင်း'),
  ('fast8', '8 လိုင်း'),
  ('turbo16', '16 လိုင်း'),
];

const studioSubLangs = <(String, String)>[
  ('auto', 'အလိုအလျောက်'),
  ('zh', 'တရုတ်'),
  ('en', 'အင်္ဂလိပ်'),
  ('my', 'မြန်မာ'),
  ('all', 'ရှိသမျှ'),
];

const studioCategories = <(String, String)>[
  ('entertainment', 'Entertainment'),
  ('film', 'Film & Animation'),
  ('people', 'People & Blogs'),
  ('education', 'Education'),
  ('howto', 'How-to & Style'),
  ('news', 'News & Politics'),
  ('music', 'Music'),
  ('gaming', 'Gaming'),
];

const studioPrivacy = <(String, String)>[
  ('private', 'Private (အကြံပြု)'),
  ('unlisted', 'Unlisted'),
  ('public', 'Public'),
];

String labelOf(List<(String, String)> choices, String key) {
  for (final c in choices) {
    if (c.$1 == key) return c.$2;
  }
  return key;
}

// ---- requests -------------------------------------------------------------

Map<String, Object?> studioDownloadRequest({
  required String urls,
  String quality = '720',
  String speed = 'safe4',
  bool playlist = false,
  String playlistItems = '',
  String subLangs = 'auto',
  bool alsoSubtitles = false,
  bool autoSubs = false,
}) =>
    {
      'op': 'download',
      'url': urls,
      'quality': quality,
      'speed': speed,
      'playlist': playlist,
      'playlist_items': playlistItems.trim(),
      'sub_langs': subLangs,
      'subtitles': alsoSubtitles,
      'auto_subs': autoSubs,
    };

Map<String, Object?> studioSplitRequest({
  required String file,
  bool byRanges = false,
  int count = 2,
  String ranges = '',
  String srtFile = '',
  bool reencode = false,
}) =>
    {
      'op': 'split',
      'file': file,
      'split_mode': byRanges ? 'ranges' : 'count',
      'count': count,
      'ranges': ranges,
      'srt_file': srtFile,
      'reencode': reencode,
    };

Map<String, Object?> studioTranslateRequest({required String file, bool gemini = false, String srcLang = 'auto', String geminiKey = '', String geminiModel = ''}) => {
      'op': 'translate',
      'file': file,
      'engine': gemini ? 'gemini' : 'free',
      'src_lang': srcLang,
      if (gemini) 'gemini_key': geminiKey,
      if (gemini && geminiModel.isNotEmpty) 'gemini_model': geminiModel,
    };

Map<String, Object?> studioSubtitleRequest({required String file, required String srtFile, String mode = 'soft', String font = 'Padauk', int fontSize = 22}) => {
      'op': 'subtitle',
      'file': file,
      'srt_file': srtFile,
      'sub_mode': mode,
      'font': font,
      'font_size': fontSize,
    };

Map<String, Object?> studioZipRequest({required List<String> files, String name = ''}) => {'op': 'zip', 'files': files, 'zip_name': name};

/// [confirmRights] must be true; the backend refuses without it, and the app does not offer the button without it.
Map<String, Object?> studioYoutubeRequest({
  required List<String> files,
  required bool confirmRights,
  String privacy = 'private',
  String titleTemplate = '{name}',
  String description = '',
  String tags = '',
  String category = 'entertainment',
  bool kids = false,
  String thumbnail = '',
  bool uploadCc = false,
}) =>
    {
      'op': 'youtube',
      'files': files,
      'confirm_rights': confirmRights,
      'privacy': privacy,
      'title_template': titleTemplate,
      'description': description,
      'tags': tags,
      'category': category,
      'kids': kids,
      'thumbnail': thumbnail,
      'upload_cc': uploadCc,
    };

/// How many links a pasted text holds (what the person typed or shared), for the "N link" hint.
int countLinks(String text) => RegExp(r'https?://[^\s]+', caseSensitive: false).allMatches(text).length;
