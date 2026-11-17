import 'dart:convert';

/// Backup file: every project with its notes, subtitles, edit, plans and video
/// index, as one JSON text file. Pure Dart.
///
/// NOT inside the backup: video files, audio files, pictures, finished MP4s
/// (they stay where they are on the phone). After a restore the video link may
/// no longer open, then the video has to be picked again.
const backupFormat = 'dramaflow-backup';
const backupVersion = 1;
const maxBackupProjects = 500;
const maxBackupBytes = 50 * 1024 * 1024;

class BackupProject {
  const BackupProject({required this.project, this.documents = const {}, this.segments = const [], this.handoff = const []});

  /// Row of the projects table without its id.
  final Map<String, Object?> project;

  /// kind -> content
  final Map<String, String> documents;

  /// [{idx, start_ms, end_ms}]
  final List<Map<String, Object?>> segments;

  /// [{task, chunk_idx, result}]
  final List<Map<String, Object?>> handoff;

  Map<String, Object?> toJson() => {'project': project, 'documents': documents, 'segments': segments, 'handoff': handoff};
}

String encodeBackup(List<BackupProject> items, {required int nowMs}) => jsonEncode({
      'format': backupFormat,
      'version': backupVersion,
      'createdAt': nowMs,
      'projects': [for (final i in items) i.toJson()],
    });

class BackupParse {
  const BackupParse({this.projects = const [], this.error, this.skipped = 0});

  final List<BackupProject> projects;
  final String? error;

  /// Projects in the file that were damaged and left out.
  final int skipped;
}

bool _isInt(Object? v) => v is int;

/// Reads a backup. A damaged project is skipped, not guessed; a file from a
/// newer app version is refused.
BackupParse parseBackup(String raw) {
  if (raw.length > maxBackupBytes) return const BackupParse(error: 'ဖိုင် အရမ်းကြီးတယ်');
  Object? m;
  try {
    m = jsonDecode(raw);
  } catch (_) {
    return const BackupParse(error: 'Backup ဖိုင် မဟုတ်ပါ (ဖတ်လို့မရ)');
  }
  if (m is! Map || m['format'] != backupFormat) return const BackupParse(error: 'DramaFlow backup ဖိုင် မဟုတ်ပါ');
  final v = m['version'];
  if (v is! int || v < 1) return const BackupParse(error: 'Backup version မှားနေတယ်');
  if (v > backupVersion) return const BackupParse(error: 'ဒီ backup က app ရဲ့ ပိုအသစ်တဲ့ version နဲ့ လုပ်ထားတာ။ App ကို update လုပ်ပါ');
  final list = m['projects'];
  if (list is! List) return const BackupParse(error: 'Backup ထဲမှာ project မရှိပါ');
  if (list.length > maxBackupProjects) return const BackupParse(error: 'Project အရမ်းများတယ်');

  final out = <BackupProject>[];
  var skipped = 0;
  for (final e in list) {
    final p = e is Map ? e['project'] : null;
    if (p is! Map ||
        p['name'] is! String ||
        p['drama_title'] is! String ||
        !_isInt(p['episode']) ||
        !_isInt(p['created_at']) ||
        !_isInt(p['updated_at'])) {
      skipped++;
      continue;
    }
    final docs = <String, String>{};
    final d = (e as Map)['documents'];
    if (d is Map) {
      d.forEach((k, val) {
        if (k is String && val is String) docs[k] = val;
      });
    }
    final segs = <Map<String, Object?>>[];
    final sg = e['segments'];
    if (sg is List) {
      for (final x in sg) {
        if (x is Map && _isInt(x['idx']) && _isInt(x['start_ms']) && _isInt(x['end_ms'])) {
          segs.add({'idx': x['idx'], 'start_ms': x['start_ms'], 'end_ms': x['end_ms']});
        }
      }
    }
    final hand = <Map<String, Object?>>[];
    final hh = e['handoff'];
    if (hh is List) {
      for (final x in hh) {
        if (x is Map && x['task'] is String && _isInt(x['chunk_idx']) && x['result'] is String) {
          hand.add({'task': x['task'], 'chunk_idx': x['chunk_idx'], 'result': x['result']});
        }
      }
    }
    out.add(BackupProject(project: p.cast<String, Object?>(), documents: docs, segments: segs, handoff: hand));
  }
  if (out.isEmpty) return BackupParse(error: 'ပြန်ယူလို့ရတဲ့ project မရှိပါ', skipped: skipped);
  return BackupParse(projects: out, skipped: skipped);
}

/// Project row columns that are copied on restore. The id, the drama link and
/// the Stage-done mask of finished renders are handled separately.
const projectColumns = [
  'name',
  'drama_title',
  'episode',
  'done_mask',
  'status',
  'source_video_uri',
  'video_name',
  'video_size',
  'video_duration_ms',
  'video_width',
  'video_height',
  'created_at',
  'updated_at',
];
